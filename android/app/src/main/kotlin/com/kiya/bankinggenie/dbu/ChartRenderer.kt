package com.kiya.bankinggenie.dbu

import android.graphics.*
import android.util.Base64
import java.io.ByteArrayOutputStream
import kotlin.math.*

object ChartRenderer {

    private const val W = 1000
    private const val H = 560
    private const val PAD_L = 72f
    private const val PAD_T = 50f
    private const val PAD_B_BASE = 60f
    private const val LEGEND_H   = 36f
    private const val PAD_R_CHART = 20f
    private const val PAD_R_PIE   = 240f

    private val COLORS = listOf(
        Color.parseColor("#1565C0"), Color.parseColor("#E53935"),
        Color.parseColor("#43A047"), Color.parseColor("#FB8C00"),
        Color.parseColor("#8E24AA"), Color.parseColor("#00ACC1")
    )

    fun renderToBase64(result: QueryResult): String? {
        val cols      = result.columns ?: return null
        val rows      = result.rows    ?: return null
        val chartType = result.chart?.type ?: return null
        return try {
            when (chartType) {
                "line", "multi_line" -> renderLine(cols, rows, chartType == "multi_line")
                "bar"                -> renderBar(cols, rows)
                "pie"                -> renderPie(cols, rows)
                "scatter"            -> renderScatter(cols, rows)
                "kpi_card"           -> renderKpi(cols, rows)
                "area"               -> renderArea(cols, rows)
                "horizontal_bar"     -> renderHorizontalBar(cols, rows)
                "donut"              -> renderDonut(cols, rows)
                else                 -> null
            }
        } catch (e: Exception) {
            AppLogger.warn("ChartRenderer", "render failed: ${e.message}")
            null
        }
    }

    private val CHART_EXCLUDE_COLS = setOf("id", "account_no", "currency", "reference", "created_at", "value_date")

    private fun isNumericCol(colIdx: Int, rows: List<List<Any?>>): Boolean {
        val nonNull = rows.mapNotNull { it.getOrNull(colIdx) }
        return nonNull.isNotEmpty() && nonNull.all { it is Long || it is Double || it is Int || it is Float }
    }

    private fun isDateLikeCol(colIdx: Int, cols: List<String>, rows: List<List<Any?>>): Boolean {
        val nameHit = cols[colIdx].lowercase().let { "date" in it || "month" in it || "year" in it || "week" in it }
        val sample  = rows.firstOrNull()?.getOrNull(colIdx)?.toString() ?: return nameHit
        val valueHit = sample.matches(Regex("\\d{4}-\\d{2}-\\d{2}")) ||
                       sample.matches(Regex("\\d{4}-\\d{2}")) ||
                       sample.matches(Regex("\\d{4}"))
        return nameHit || valueHit
    }

    private fun classifyCols(cols: List<String>, rows: List<List<Any?>>): Triple<List<String>, List<String>, List<String>> {
        val numCols  = cols.filterIndexed { i, c -> isNumericCol(i, rows) && c.lowercase() !in CHART_EXCLUDE_COLS }
        val dateCols = cols.filterIndexed { i, c -> isDateLikeCol(i, cols, rows) && c.lowercase() !in CHART_EXCLUDE_COLS }.filter { it !in numCols }
        val catCols  = cols.filter { it !in numCols && it !in dateCols && it.lowercase() !in CHART_EXCLUDE_COLS }
        return Triple(numCols, dateCols, catCols)
    }

    private fun drawBottomLegend(c: Canvas, items: List<Pair<String, Int>>) {
        if (items.isEmpty()) return
        val p = labelPaint(22f)
        val swatchSize = 14f; val itemGap = 24f; val rowGap = 28f; val maxW = W - 40f
        data class Row(val entries: MutableList<Pair<String, Int>> = mutableListOf(), var width: Float = 0f)
        val rows = mutableListOf(Row())
        items.forEach { item ->
            val itemW = swatchSize + 6f + p.measureText(item.first.take(14)) + itemGap
            val cur = rows.last()
            if (cur.entries.isNotEmpty() && cur.width + itemW > maxW) rows.add(Row())
            rows.last().entries.add(item); rows.last().width += itemW
        }
        val totalRows = rows.size
        rows.forEachIndexed { rowIdx, row ->
            val rowW = row.width - itemGap
            var x = (W - rowW) / 2f
            val y = H - 14f - (totalRows - 1 - rowIdx) * rowGap
            row.entries.forEach { (lbl, color) ->
                c.drawRect(x, y - swatchSize, x + swatchSize, y, fillPaint(color))
                c.drawText(lbl.take(14), x + swatchSize + 6f, y - 1f, p)
                x += swatchSize + 6f + p.measureText(lbl.take(14)) + itemGap
            }
        }
    }

    private fun legendRowCount(items: List<String>): Int {
        if (items.isEmpty()) return 0
        val p = labelPaint(22f); val swatchSize = 14f; val itemGap = 24f; val maxW = W - 40f
        var rows = 1; var rowW = 0f
        items.forEach { lbl ->
            val itemW = swatchSize + 6f + p.measureText(lbl.take(14)) + itemGap
            if (rowW > 0f && rowW + itemW > maxW) { rows++; rowW = 0f }
            rowW += itemW
        }
        return rows
    }

    private fun renderLine(cols: List<String>, rows: List<List<Any?>>, multiLine: Boolean): String? {
        val (numCols, dateCols, _) = classifyCols(cols, rows)
        val xCol = dateCols.firstOrNull() ?: cols.first()
        val yColList = numCols.take(if (multiLine) 2 else 1)
        if (yColList.isEmpty()) return null
        val padB = PAD_B_BASE + legendRowCount(yColList) * LEGEND_H
        val chartW = W - PAD_L - PAD_R_CHART; val chartH = H - PAD_T - padB
        val xLabels = rows.mapIndexed { i, row -> row[cols.indexOf(xCol)]?.toString() ?: "Row ${i+1}" }
        val bmp = newBitmap(); val cv = Canvas(bmp); drawBackground(cv, padB)
        val allValues = yColList.flatMap { yCol -> rows.map { (it[cols.indexOf(yCol)] as? Number)?.toFloat() ?: 0f } }
        val globalMin = allValues.minOrNull() ?: 0f; val globalMax = allValues.maxOrNull() ?: 1f
        val globalRange = if (globalMax == globalMin) 1f else globalMax - globalMin
        yColList.forEachIndexed { idx, yCol ->
            val values = rows.map { (it[cols.indexOf(yCol)] as? Number)?.toFloat() ?: 0f }
            val paint = linePaint(COLORS[idx % COLORS.size]); val dotPaint = dotPaint(COLORS[idx % COLORS.size])
            val pts = values.mapIndexed { i, v ->
                PointF(PAD_L + i * chartW / (values.size - 1).coerceAtLeast(1),
                       PAD_T + chartH - (v - globalMin) / globalRange * chartH)
            }
            for (i in 0 until pts.size - 1) cv.drawLine(pts[i].x, pts[i].y, pts[i+1].x, pts[i+1].y, paint)
            pts.forEach { cv.drawCircle(it.x, it.y, 5f, dotPaint) }
        }
        drawXLabels(cv, xLabels, chartW, padB); drawYAxisValues(cv, globalMin, globalMax, chartH)
        drawAxes(cv, padB); drawBottomLegend(cv, yColList.mapIndexed { i, lbl -> lbl to COLORS[i % COLORS.size] })
        return encode(bmp)
    }

    private fun renderArea(cols: List<String>, rows: List<List<Any?>>): String? {
        val (numCols, dateCols, _) = classifyCols(cols, rows)
        val xCol = dateCols.firstOrNull() ?: cols.first(); val yCol = numCols.firstOrNull() ?: return null
        val padB = PAD_B_BASE + legendRowCount(listOf(yCol)) * LEGEND_H
        val chartW = W - PAD_L - PAD_R_CHART; val chartH = H - PAD_T - padB
        val xLabels = rows.mapIndexed { i, row -> row[cols.indexOf(xCol)]?.toString() ?: "Row ${i+1}" }
        val values = rows.map { (it[cols.indexOf(yCol)] as? Number)?.toFloat() ?: 0f }
        val minV = values.minOrNull() ?: 0f; val maxV = values.maxOrNull() ?: 1f
        val range = if (maxV == minV) 1f else maxV - minV
        val bmp = newBitmap(); val cv = Canvas(bmp); drawBackground(cv, padB)
        val baseY = PAD_T + chartH
        val pts = values.mapIndexed { i, v ->
            PointF(PAD_L + i * chartW / (values.size - 1).coerceAtLeast(1), PAD_T + chartH - (v - minV) / range * chartH)
        }
        val path = Path().apply {
            moveTo(pts.first().x, baseY); pts.forEach { lineTo(it.x, it.y) }; lineTo(pts.last().x, baseY); close()
        }
        cv.drawPath(path, fillPaint(COLORS[0]).apply { alpha = 80 })
        val lp = linePaint(COLORS[0])
        for (i in 0 until pts.size - 1) cv.drawLine(pts[i].x, pts[i].y, pts[i+1].x, pts[i+1].y, lp)
        drawXLabels(cv, xLabels, chartW, padB); drawYAxisValues(cv, minV, maxV, chartH)
        drawAxes(cv, padB); drawBottomLegend(cv, listOf(yCol to COLORS[0]))
        return encode(bmp)
    }

    private fun renderBar(cols: List<String>, rows: List<List<Any?>>): String? {
        val (numCols, dateCols, catCols) = classifyCols(cols, rows)
        val xCol = dateCols.firstOrNull() ?: catCols.firstOrNull() ?: cols.first()
        val yCol = numCols.firstOrNull() ?: return null
        val displayRows = if (dateCols.isNotEmpty()) rows
            else rows.sortedByDescending { (it[cols.indexOf(yCol)] as? Number)?.toFloat() ?: 0f }.take(12)
        val labels = displayRows.map { it[cols.indexOf(xCol)]?.toString() ?: "" }
        val values = displayRows.map { (it[cols.indexOf(yCol)] as? Number)?.toFloat() ?: 0f }
        val maxV = values.maxOrNull() ?: 1f
        val padB = PAD_B_BASE + legendRowCount(labels) * LEGEND_H
        val chartW = W - PAD_L - PAD_R_CHART; val chartH = H - PAD_T - padB
        val n = values.size.coerceAtLeast(1); val gap = chartW / n; val barW = gap * 0.6f
        val bmp = newBitmap(); val cv = Canvas(bmp); drawBackground(cv, padB)
        values.forEachIndexed { i, v ->
            val barH = (v / maxV) * chartH; val left = PAD_L + i * gap + gap * 0.2f
            val top = PAD_T + chartH - barH; val right = left + barW; val bot = PAD_T + chartH
            cv.drawRoundRect(left, top, right, bot, 4f, 4f, fillPaint(COLORS[i % COLORS.size]))
            val vp = labelPaint(19f).apply { textAlign = Paint.Align.CENTER }
            cv.drawText(formatNum(v), left + barW / 2f, top - 6f, vp)
        }
        drawXLabelsBar(cv, labels, chartW, gap, padB); drawYAxisValues(cv, 0f, maxV, chartH)
        drawAxes(cv, padB); drawBottomLegend(cv, labels.mapIndexed { i, lbl -> lbl to COLORS[i % COLORS.size] })
        return encode(bmp)
    }

    private fun renderHorizontalBar(cols: List<String>, rows: List<List<Any?>>): String? {
        val (numCols, _, catCols) = classifyCols(cols, rows)
        val labelCol = catCols.firstOrNull() ?: cols.first(); val valueCol = numCols.firstOrNull() ?: return null
        val displayRows = rows.sortedByDescending { (it[cols.indexOf(valueCol)] as? Number)?.toFloat() ?: 0f }.take(10)
        val labels = displayRows.map { it[cols.indexOf(labelCol)]?.toString() ?: "" }
        val values = displayRows.map { (it[cols.indexOf(valueCol)] as? Number)?.toFloat() ?: 0f }
        val maxV = values.maxOrNull() ?: 1f
        val padB = PAD_B_BASE + legendRowCount(labels) * LEGEND_H
        val bmp = newBitmap(); val cv = Canvas(bmp); drawBackground(cv, padB)
        val chartW = W - PAD_L - PAD_R_CHART - 20f; val chartH = H - PAD_T - padB
        val rowH = chartH / values.size.coerceAtLeast(1); val barH = rowH * 0.6f
        values.forEachIndexed { i, v ->
            val barW = (v / maxV) * chartW; val top = PAD_T + i * rowH + rowH * 0.2f
            cv.drawRoundRect(PAD_L, top, PAD_L + barW, top + barH, 4f, 4f, fillPaint(COLORS[i % COLORS.size]))
            val lp = labelPaint(22f).apply { textAlign = Paint.Align.RIGHT }
            cv.drawText("${i + 1}", PAD_L - 6f, top + barH / 2f + 8f, lp)
            cv.drawText(formatNum(v), PAD_L + barW + 6f, top + barH / 2f + 8f, labelPaint(20f))
        }
        drawAxes(cv, padB); drawBottomLegend(cv, labels.mapIndexed { i, lbl -> "${i + 1}. $lbl" to COLORS[i % COLORS.size] })
        return encode(bmp)
    }

    private fun renderPie(cols: List<String>, rows: List<List<Any?>>): String? {
        val (numCols, _, catCols) = classifyCols(cols, rows)
        val labelCol = catCols.firstOrNull() ?: cols.first(); val valueCol = numCols.firstOrNull() ?: return null
        val labels = rows.map { it[cols.indexOf(labelCol)]?.toString() ?: "" }
        val values = rows.map { (it[cols.indexOf(valueCol)] as? Number)?.toFloat() ?: 0f }
        val total = values.sum().takeIf { it > 0f } ?: return null
        val bmp = newBitmap(); val cv = Canvas(bmp); drawBackground(cv, PAD_B_BASE)
        val legendX = W - PAD_R_PIE + 10f; val cx = (W - PAD_R_PIE) / 2f + PAD_L / 2f; val cy = H / 2f
        val radius = minOf(W - PAD_R_PIE - PAD_L, H - PAD_T - PAD_B_BASE) / 2f - 10f
        var startAngle = -90f
        values.forEachIndexed { i, v ->
            val sweep = v / total * 360f
            cv.drawArc(cx - radius, cy - radius, cx + radius, cy + radius, startAngle, sweep, true, fillPaint(COLORS[i % COLORS.size]))
            startAngle += sweep
        }
        labels.forEachIndexed { i, lbl ->
            val ly = PAD_T + i * 32f
            cv.drawRect(legendX, ly, legendX + 16f, ly + 16f, fillPaint(COLORS[i % COLORS.size]))
            cv.drawText("${lbl.take(12)} ${"%.1f%%".format(values[i] / total * 100f)}", legendX + 22f, ly + 13f, labelPaint(21f))
        }
        return encode(bmp)
    }

    private fun renderDonut(cols: List<String>, rows: List<List<Any?>>): String? {
        val (numCols, _, catCols) = classifyCols(cols, rows)
        val labelCol = catCols.firstOrNull() ?: cols.first(); val valueCol = numCols.firstOrNull() ?: return null
        val labels = rows.map { it[cols.indexOf(labelCol)]?.toString() ?: "" }
        val values = rows.map { (it[cols.indexOf(valueCol)] as? Number)?.toFloat() ?: 0f }
        val total = values.sum().takeIf { it > 0f } ?: return null
        val bmp = newBitmap(); val cv = Canvas(bmp); drawBackground(cv, PAD_B_BASE)
        val legendX = W - PAD_R_PIE + 10f; val cx = (W - PAD_R_PIE) / 2f + PAD_L / 2f; val cy = H / 2f
        val radius = minOf(W - PAD_R_PIE - PAD_L, H - PAD_T - PAD_B_BASE) / 2f - 10f; val holeR = radius * 0.45f
        var startAngle = -90f
        values.forEachIndexed { i, v ->
            val sweep = v / total * 360f
            cv.drawArc(cx - radius, cy - radius, cx + radius, cy + radius, startAngle, sweep, true, fillPaint(COLORS[i % COLORS.size]))
            startAngle += sweep
        }
        cv.drawCircle(cx, cy, holeR, fillPaint(Color.WHITE))
        labels.forEachIndexed { i, lbl ->
            val ly = PAD_T + i * 32f
            cv.drawRect(legendX, ly, legendX + 16f, ly + 16f, fillPaint(COLORS[i % COLORS.size]))
            cv.drawText("${lbl.take(12)} ${"%.1f%%".format(values[i] / total * 100f)}", legendX + 22f, ly + 13f, labelPaint(21f))
        }
        return encode(bmp)
    }

    private fun renderScatter(cols: List<String>, rows: List<List<Any?>>): String? {
        val (numCols, _, _) = classifyCols(cols, rows)
        if (numCols.size < 2) return null
        val xCol = numCols[0]; val yCol = numCols[1]
        val xs = rows.map { (it[cols.indexOf(xCol)] as? Number)?.toFloat() ?: 0f }
        val ys = rows.map { (it[cols.indexOf(yCol)] as? Number)?.toFloat() ?: 0f }
        val minX = xs.minOrNull() ?: 0f; val maxX = xs.maxOrNull() ?: 1f
        val minY = ys.minOrNull() ?: 0f; val maxY = ys.maxOrNull() ?: 1f
        val rangeX = if (maxX == minX) 1f else maxX - minX; val rangeY = if (maxY == minY) 1f else maxY - minY
        val padB = PAD_B_BASE + LEGEND_H; val chartW = W - PAD_L - PAD_R_CHART; val chartH = H - PAD_T - padB
        val bmp = newBitmap(); val cv = Canvas(bmp); drawBackground(cv, padB)
        val dot = dotPaint(COLORS[0])
        xs.forEachIndexed { i, x ->
            cv.drawCircle(PAD_L + (x - minX) / rangeX * chartW, PAD_T + chartH - (ys[i] - minY) / rangeY * chartH, 6f, dot)
        }
        drawAxes(cv, padB); return encode(bmp)
    }

    private fun renderKpi(cols: List<String>, rows: List<List<Any?>>): String? {
        val value = rows.firstOrNull()?.firstOrNull() ?: return null
        val label = cols.firstOrNull() ?: ""
        val formatted = when (value) { is Double -> "\u20b9%.2f".format(value); is Long -> "\u20b9$value"; else -> value.toString() }
        val bmp = newBitmap(); val cv = Canvas(bmp)
        cv.drawColor(Color.WHITE)
        cv.drawRoundRect(60f, 60f, W - 60f, H - 60f, 24f, 24f, fillPaint(Color.parseColor("#E3F2FD")))
        val vPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLORS[0]; textSize = 96f; typeface = Typeface.DEFAULT_BOLD; textAlign = Paint.Align.CENTER }
        val lPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#546E7A"); textSize = 40f; textAlign = Paint.Align.CENTER }
        cv.drawText(formatted, W / 2f, H / 2f + 30f, vPaint); cv.drawText(label, W / 2f, H / 2f + 90f, lPaint)
        return encode(bmp)
    }

    private fun newBitmap() = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)

    private fun drawBackground(cv: Canvas, padB: Float) {
        cv.drawColor(Color.WHITE)
        val gridPaint = Paint().apply { color = Color.parseColor("#EEEEEE"); strokeWidth = 1f }
        val chartH = H - PAD_T - padB
        for (i in 1..4) cv.drawLine(PAD_L, PAD_T + chartH * i / 4f, W - PAD_R_CHART, PAD_T + chartH * i / 4f, gridPaint)
    }

    private fun drawAxes(cv: Canvas, padB: Float) {
        val p = Paint().apply { color = Color.parseColor("#BDBDBD"); strokeWidth = 2f }
        cv.drawLine(PAD_L, PAD_T, PAD_L, H - padB, p); cv.drawLine(PAD_L, H - padB, W - PAD_R_CHART, H - padB, p)
    }

    private fun drawXLabels(cv: Canvas, labels: List<String>, chartW: Float, padB: Float) {
        val p = labelPaint(20f); val step = chartW / (labels.size - 1).coerceAtLeast(1)
        val maxLabels = (chartW / 55f).toInt().coerceAtLeast(1); val skip = (labels.size / maxLabels).coerceAtLeast(1)
        val baseY = H - padB + 8f
        labels.forEachIndexed { i, lbl ->
            if (i % skip == 0) { val x = PAD_L + i * step; cv.save(); cv.rotate(-45f, x, baseY); cv.drawText(lbl.take(12), x, baseY, p); cv.restore() }
        }
    }

    private fun drawXLabelsBar(cv: Canvas, labels: List<String>, chartW: Float, gap: Float, padB: Float) {
        val p = labelPaint(20f).apply { textAlign = Paint.Align.CENTER }
        val maxLabels = (chartW / 55f).toInt().coerceAtLeast(1); val skip = (labels.size / maxLabels).coerceAtLeast(1)
        val baseY = H - padB + 14f
        labels.forEachIndexed { i, lbl ->
            if (i % skip == 0) { val cx = PAD_L + i * gap + gap * 0.5f; cv.save(); cv.rotate(-40f, cx, baseY); cv.drawText(lbl.take(12), cx, baseY, p); cv.restore() }
        }
    }

    private fun drawYAxisValues(cv: Canvas, minV: Float, maxV: Float, chartH: Float) {
        val p = labelPaint(22f).apply { textAlign = Paint.Align.RIGHT }
        val range = if (maxV == minV) 1f else maxV - minV
        for (i in 0..4) {
            val v = minV + range * i / 4f; val y = PAD_T + chartH - chartH * i / 4f
            cv.drawText(formatNum(v), PAD_L - 6f, y + 8f, p)
        }
    }

    private fun fillPaint(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.FILL }
    private fun linePaint(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.STROKE; strokeWidth = 3f; strokeCap = Paint.Cap.ROUND }
    private fun dotPaint(color: Int)  = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.FILL }
    private fun labelPaint(size: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#424242"); textSize = size }

    private fun formatNum(v: Float): String = when {
        abs(v) >= 1_00_000 -> "\u20b9%.1fL".format(v / 1_00_000)
        abs(v) >= 1_000    -> "\u20b9%.1fK".format(v / 1_000)
        else               -> "\u20b9%.0f".format(v)
    }

    private fun encode(bmp: Bitmap): String {
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 90, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }
}

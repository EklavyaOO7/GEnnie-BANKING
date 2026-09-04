package com.kiya.bankinggenie.dbu

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.regex.Pattern

class SlmEngine(private val context: Context, private val modelsDir: File, private val gemma: GemmaEngine) {

    private val TAG = "SlmEngine"
    private val TABLE_NAME = "TB_Statement"
    private val FORBIDDEN = Pattern.compile("\\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE)\\b", Pattern.CASE_INSENSITIVE)

    private var embedder: SlmEmbedder? = null
    private var summarizer: Summarizer? = null
    private var relevanceChecker: RelevanceChecker? = null
    private var db: SQLiteDatabase? = null

    private var columns: List<String> = emptyList()
    private var descriptions: List<String> = emptyList()
    private var embeddingsMatrix: List<FloatArray> = emptyList()

    private val KNOWN_COLUMNS = setOf(
        "id", "txn_date", "value_date", "description", "reference",
        "type", "amount", "balance", "account_no", "currency", "created_at"
    )
    private val DISPLAY_COLUMNS = listOf("txn_date", "description", "type", "amount", "balance")

    fun init() {
        AppLogger.init(File(context.filesDir, "logs"), context)
        if (embedder == null) {
            AppLogger.info(TAG, "Initialising SlmEmbedder")
            embedder = SlmEmbedder(modelsDir)
            buildVectorstore()
        }
        if (summarizer == null)       summarizer       = Summarizer(gemma)
        if (relevanceChecker == null) relevanceChecker = RelevanceChecker(gemma)
        if (db == null) {
            AppLogger.info(TAG, "Opening mfx_chat.db")
            db = openDb()
        }
    }

    private fun openDb(): SQLiteDatabase {
        val dbFile = File(context.getDatabasePath("mfx_chat.db").absolutePath)
        if (!dbFile.exists()) throw IllegalStateException("mfx_chat.db not found at ${dbFile.absolutePath}")
        AppLogger.info(TAG, "Opening mfx_chat.db — ${dbFile.length()} bytes")
        return SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
    }

    private fun buildVectorstore() {
        val metaFile = File(modelsDir, "TB_Statement_meta.csv")
        if (!metaFile.exists()) { AppLogger.warn(TAG, "TB_Statement_meta.csv not found — vectorstore empty"); return }
        val cols = mutableListOf<String>()
        val descs = mutableListOf<String>()
        val embs = mutableListOf<FloatArray>()
        metaFile.bufferedReader().use { br ->
            br.readLine()
            br.forEachLine { line ->
                val parts = line.split(",", limit = 2)
                if (parts.size == 2) {
                    val col = parts[0].trim(); val desc = parts[1].trim()
                    cols.add(col); descs.add(desc)
                    embs.add(embedder!!.encode("Column: $col\nDescription: $desc"))
                }
            }
        }
        columns = cols; descriptions = descs; embeddingsMatrix = embs
        AppLogger.info(TAG, "Vectorstore built — ${columns.size} columns indexed")
    }

    private fun retrieveColumns(question: String, k: Int = 5): List<Map<String, String>> {
        if (embeddingsMatrix.isEmpty()) return emptyList()
        val qVec = embedder!!.encode(question)
        val scores: List<Float> = embeddingsMatrix.map { embedder!!.cosineSimilarity(it, qVec) }
        val indices = scores.indices.toMutableList()
        indices.sortWith(Comparator { a, b -> scores[b].compareTo(scores[a]) })
        return indices.take(k).map { mapOf("column" to columns[it], "description" to descriptions[it]) }
    }

    private fun extractDateFilter(question: String): String {
        val q = question.lowercase(Locale.US)
        val cal = Calendar.getInstance()
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        if ("last month" in q || "recent month" in q) {
            cal.add(Calendar.MONTH, -1)
            cal.set(Calendar.DAY_OF_MONTH, 1)
            val start = sdf.format(cal.time)
            cal.set(Calendar.DAY_OF_MONTH, cal.getActualMaximum(Calendar.DAY_OF_MONTH))
            return "txn_date >= '$start' AND txn_date <= '${sdf.format(cal.time)}'"
        }
        val monthMatch = Regex("last\\s*(\\d+)\\s*month").find(q)
        if (monthMatch != null) {
            cal.add(Calendar.MONTH, -(monthMatch.groupValues[1].toInt()))
            cal.set(Calendar.DAY_OF_MONTH, 1)
            return "txn_date >= '${sdf.format(cal.time)}'"
        }
        if ("this month" in q) {
            cal.set(Calendar.DAY_OF_MONTH, 1)
            return "txn_date >= '${sdf.format(cal.time)}'"
        }
        val yearMatch = Regex("(\\d+)\\s*year").find(q)
        if (yearMatch != null || "this year" in q) {
            cal.add(Calendar.YEAR, -(yearMatch?.groupValues?.get(1)?.toInt() ?: 0))
            cal.set(Calendar.DAY_OF_YEAR, 1)
            return "txn_date >= '${sdf.format(cal.time)}'"
        }
        val weekMatch = Regex("(\\d+)\\s*week").find(q)
        if (weekMatch != null || "last week" in q || "this week" in q) {
            cal.add(Calendar.WEEK_OF_YEAR, -(weekMatch?.groupValues?.get(1)?.toInt() ?: 1))
            return "txn_date >= '${sdf.format(cal.time)}'"
        }
        return ""
    }

    private fun tryBuildIntentSql(question: String): String? {
        val q = question.lowercase(Locale.US)
        val byMonth   = "by month" in q || "monthly" in q || "per month" in q || "each month" in q
        val byYear    = "by year"  in q || "yearly"  in q || "per year"  in q || "each year"  in q
        val byAccount = "by account" in q || "per account" in q
        val dateFilter = extractDateFilter(question)
        val where   = if (dateFilter.isNotEmpty()) "WHERE $dateFilter" else ""
        val andDate = if (dateFilter.isNotEmpty()) "AND $dateFilter"   else ""
        return when {
            ("average" in q || "avg" in q) && "balance" in q && byMonth ->
                "SELECT strftime('%Y-%m', txn_date) AS month, AVG(balance) AS avg_balance FROM $TABLE_NAME $where GROUP BY month ORDER BY month;"
            ("average" in q || "avg" in q) && "balance" in q ->
                "SELECT AVG(balance) AS avg_balance FROM $TABLE_NAME $where;"
            ("debit" in q || "spend" in q || "spending" in q || "expense" in q) && byMonth ->
                "SELECT strftime('%Y-%m', txn_date) AS month, SUM(amount) AS total_debit FROM $TABLE_NAME WHERE type='DEBIT' $andDate GROUP BY month ORDER BY month;"
            ("credit" in q || "income" in q || "salary" in q) && byMonth ->
                "SELECT strftime('%Y-%m', txn_date) AS month, SUM(amount) AS total_credit FROM $TABLE_NAME WHERE type='CREDIT' $andDate GROUP BY month ORDER BY month;"
            ("debit" in q || "spend" in q || "spending" in q || "expense" in q) && byYear ->
                "SELECT strftime('%Y', txn_date) AS year, SUM(amount) AS total_debit FROM $TABLE_NAME WHERE type='DEBIT' $andDate GROUP BY year ORDER BY year;"
            ("credit" in q || "income" in q || "salary" in q) && byYear ->
                "SELECT strftime('%Y', txn_date) AS year, SUM(amount) AS total_credit FROM $TABLE_NAME WHERE type='CREDIT' $andDate GROUP BY year ORDER BY year;"
            byAccount ->
                "SELECT account_no, MAX(balance) AS latest_balance FROM $TABLE_NAME $where GROUP BY account_no ORDER BY latest_balance DESC;"
            ("compare" in q || "vs" in q || "versus" in q) ->
                "SELECT strftime('%Y-%m', txn_date) AS month, SUM(CASE WHEN type='DEBIT' THEN amount ELSE 0 END) AS total_debit, SUM(CASE WHEN type='CREDIT' THEN amount ELSE 0 END) AS total_credit FROM $TABLE_NAME $where GROUP BY month ORDER BY month;"
            ("top" in q || "highest" in q || "largest" in q) && ("expense" in q || "spend" in q || "debit" in q) -> {
                val n = Regex("top\\s*(\\d+)").find(q)?.groupValues?.get(1)?.toIntOrNull()
                    ?: wordToNumber(q)
                    ?: 5
                "SELECT description, SUM(amount) AS total FROM $TABLE_NAME WHERE type='DEBIT' $andDate GROUP BY description ORDER BY total DESC LIMIT $n;"
            }
            ("total" in q) && ("debit" in q || "spend" in q || "expense" in q) ->
                "SELECT SUM(amount) AS total_debit FROM $TABLE_NAME WHERE type='DEBIT' $andDate;"
            ("total" in q) && ("credit" in q || "income" in q || "salary" in q) ->
                "SELECT SUM(amount) AS total_credit FROM $TABLE_NAME WHERE type='CREDIT' $andDate;"
            ("total" in q) && ("transaction" in q || "txn" in q) ->
                "SELECT SUM(amount) AS total_amount FROM $TABLE_NAME $where;"
            "last transaction" in q || "latest transaction" in q || "recent transaction" in q ->
                "SELECT txn_date, description, type, amount, balance FROM $TABLE_NAME ORDER BY txn_date DESC, id DESC LIMIT 1;"
            Regex("last\\s*(\\d+)\\s*transaction").containsMatchIn(q) -> {
                val n = Regex("last\\s*(\\d+)\\s*transaction").find(q)!!.groupValues[1].toInt()
                "SELECT txn_date, description, type, amount, balance FROM $TABLE_NAME ORDER BY txn_date DESC, id DESC LIMIT $n;"
            }
            ("all transaction" in q || "show all" in q || "list all" in q || "all record" in q) ->
                "SELECT txn_date, type, amount, balance FROM $TABLE_NAME $where ORDER BY txn_date ASC;"
            ("total" in q || "current" in q) && "balance" in q ->
                "SELECT balance FROM $TABLE_NAME ORDER BY txn_date DESC LIMIT 1;"
            else -> null
        }
    }

    private fun buildSqlPrompt(columnsInfo: String, question: String, dateFilter: String, dateRange: String) =
        "SQLite table: $TABLE_NAME (txn_date DATE yyyy-MM-dd, range: $dateRange).\nExact columns (use ONLY these): id, txn_date, value_date, description, reference, type, amount, balance, account_no, currency, created_at\ntype column values: 'DEBIT' or 'CREDIT'. Use WHERE type='DEBIT' for expenses/debits, WHERE type='CREDIT' for income/credits.\nRelevant columns:\n$columnsInfo\n${if (dateFilter.isNotEmpty()) "Required WHERE filter: $dateFilter" else ""}\nRules: SELECT only. No INSERT/UPDATE/DELETE. Use strftime('%m',col) not MONTH(). Use strftime('%Y',col) not YEAR(). Never invent column names.\nQuestion: $question\nSQL:"

    private fun generateSql(question: String, chunks: List<Map<String, String>>): String {
        val intentSql = tryBuildIntentSql(question)
        if (intentSql != null) { AppLogger.info(TAG, "Intent SQL: $intentSql"); return intentSql }

        val columnsInfo = chunks.joinToString("\n") { "  - ${it["column"]}: ${it["description"]}" }
        val dateFilter = extractDateFilter(question)
        val cursor = db!!.rawQuery("SELECT MIN(txn_date), MAX(txn_date) FROM $TABLE_NAME", null)
        val dateRange = if (cursor.moveToFirst()) "${cursor.getString(0)} to ${cursor.getString(1)}" else "unknown"
        cursor.close()

        val prompt = buildSqlPrompt(columnsInfo, question, dateFilter, dateRange)
        var sql = gemma.generate(prompt = prompt, system = "You are a SQL expert.").trim()
        sql = sql.replace(Regex("```\\w*"), "").trim('`').trim()
        sql = sql.lines().joinToString(" ").trim()
        sql = sql.split(";")[0].trim()

        val colAliases = mapOf(
            "transaction_date" to "txn_date", "trans_date" to "txn_date", "tran_date" to "txn_date",
            "transaction_amount" to "amount", "transaction_description" to "description",
            "narration" to "description", "transaction_reference" to "reference",
            "account_number" to "account_no", "acc_no" to "account_no"
        )
        colAliases.forEach { (alias, real) ->
            sql = sql.replace(Regex("(?<![a-zA-Z_])${Regex.escape(alias)}(?![a-zA-Z_0-9])", RegexOption.IGNORE_CASE), real)
        }
        sql = sql.replace(Regex("DATE_SUB\\s*\\([^)]+\\)", RegexOption.IGNORE_CASE), "txn_date")
        sql = sql.replace(Regex("DATE_ADD\\s*\\([^)]+\\)", RegexOption.IGNORE_CASE), "txn_date")
        sql = sql.replace(Regex("NOW\\s*\\(\\s*\\)", RegexOption.IGNORE_CASE), "date('now')")
        sql = sql.replace(Regex("CURDATE\\s*\\(\\s*\\)", RegexOption.IGNORE_CASE), "date('now')")
        sql = sql.replace(Regex("MONTH\\(\\s*(\\w+)\\s*\\)", RegexOption.IGNORE_CASE)) { "strftime('%m', ${it.groupValues[1]})" }
        sql = sql.replace(Regex("YEAR\\(\\s*(\\w+)\\s*\\)", RegexOption.IGNORE_CASE))  { "strftime('%Y', ${it.groupValues[1]})" }
        sql = stripHallucinatedConditions(sql)

        if (!sql.uppercase().startsWith("SELECT")) {
            val base = "SELECT ${DISPLAY_COLUMNS.joinToString(", ")} FROM $TABLE_NAME"
            sql = if (dateFilter.isNotEmpty()) "$base WHERE $dateFilter" else base
        }
        if (sql.uppercase().let { it.startsWith("SELECT *") || it.startsWith("SELECT  *") }) {
            val rest = sql.substring(sql.uppercase().indexOf("FROM"))
            sql = "SELECT ${DISPLAY_COLUMNS.joinToString(", ")} $rest"
        }
        if (!sql.endsWith(";")) sql += ";"
        AppLogger.info(TAG, "Final SQL: $sql")
        return sql
    }

    private fun wordToNumber(q: String): Int? {
        val words = mapOf(
            "one" to 1, "two" to 2, "three" to 3, "four" to 4, "five" to 5,
            "six" to 6, "seven" to 7, "eight" to 8, "nine" to 9, "ten" to 10,
            "eleven" to 11, "twelve" to 12, "thirteen" to 13, "fourteen" to 14,
            "fifteen" to 15, "sixteen" to 16, "seventeen" to 17, "eighteen" to 18,
            "nineteen" to 19, "twenty" to 20
        )
        return words.entries.firstOrNull { it.key in q }?.value
    }

    private fun stripHallucinatedConditions(sql: String): String {
        val whereIdx = sql.uppercase().indexOf("WHERE")
        if (whereIdx < 0) return sql
        val beforeWhere = sql.substring(0, whereIdx)
        val afterWhere  = sql.substring(whereIdx + 5).trim()
        val conditions  = afterWhere.split(Regex("\\bAND\\b", RegexOption.IGNORE_CASE))
        val valid = conditions.filter { cond ->
            val col = cond.trim().split(Regex("[\\s=<>!(.)]+"))[0].trim().lowercase()
            KNOWN_COLUMNS.contains(col) || col.startsWith("strftime")
        }
        return if (valid.isEmpty()) beforeWhere.trimEnd()
        else "$beforeWhere WHERE ${valid.joinToString(" AND ")}"
    }

    private fun executeQuery(sql: String): Pair<List<String>, List<List<Any?>>> {
        if (FORBIDDEN.matcher(sql).find()) throw IllegalArgumentException("Blocked: forbidden SQL operation.")
        val cursor = db!!.rawQuery(sql.trimEnd(';'), null)
        val cols = (0 until cursor.columnCount).map { cursor.getColumnName(it) }
        val rows = mutableListOf<List<Any?>>()
        while (cursor.moveToNext()) {
            rows.add((0 until cursor.columnCount).map { i ->
                when (cursor.getType(i)) {
                    Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(i)
                    Cursor.FIELD_TYPE_FLOAT   -> cursor.getDouble(i)
                    Cursor.FIELD_TYPE_NULL    -> null
                    else                      -> cursor.getString(i)
                }
            })
        }
        cursor.close()
        AppLogger.info(TAG, "Query executed — ${rows.size} row(s), columns: $cols")
        return Pair(cols, rows)
    }

    private fun needsChart(cols: List<String>, rows: List<List<Any?>>): Boolean {
        if (rows.isEmpty() || cols.isEmpty()) return false
        val exclude = setOf("id", "account_no", "currency", "reference", "created_at", "value_date")
        val effectiveCols = cols.filter { it.lowercase() !in exclude }
        val numCols = effectiveCols.filter { c ->
            val i = cols.indexOf(c)
            rows.mapNotNull { it.getOrNull(i) }.let { nn -> nn.isNotEmpty() && nn.all { it is Long || it is Double } }
        }
        if (numCols.isEmpty()) return false
        if (rows.size == 1 && cols.size > 2) return false
        if (rows.size == 1 && numCols.size >= 1) return true
        if (rows.size < 4) return false
        return true
    }

    private fun suggestChart(cols: List<String>, rows: List<List<Any?>>): ChartMeta {
        val exclude = setOf("id", "account_no", "currency", "reference", "created_at", "value_date")
        val effectiveCols = cols.filter { it.lowercase() !in exclude }
        val numCols = effectiveCols.filter { c ->
            val i = cols.indexOf(c)
            rows.mapNotNull { it.getOrNull(i) }.let { nn -> nn.isNotEmpty() && nn.all { it is Long || it is Double } }
        }
        val dateCols = effectiveCols.filter { col ->
            col.lowercase().let { "date" in it || "month" in it || "year" in it || "week" in it } ||
            rows.firstOrNull()?.getOrNull(cols.indexOf(col))?.toString()?.matches(Regex("\\d{4}-\\d{2}(-\\d{2})?")) == true
        }
        val catCols = effectiveCols.filter { it !in numCols && it !in dateCols }
        val hasDebit      = numCols.any { it.lowercase().contains("debit") }
        val hasCredit     = numCols.any { it.lowercase().contains("credit") }
        val hasBalance    = numCols.any { it.lowercase().contains("balance") }
        val hasAmount     = cols.any { it.lowercase() == "amount" }
        val isDualCompare = hasDebit && hasCredit
        val balanceOnly   = hasBalance && !hasDebit && !hasCredit && !hasAmount
        val trendCol = if (isDualCompare) null else numCols.firstOrNull { !it.lowercase().contains("balance") } ?: numCols.firstOrNull()
        return when {
            numCols.size == 1 && rows.size == 1                             -> ChartMeta("kpi_card",       "Single value — KPI card.")
            isDualCompare && rows.size == 1                                 -> ChartMeta("donut",          "Debit vs credit — donut.")
            dateCols.isNotEmpty() && isDualCompare                          -> ChartMeta("multi_line",     "Date + debit vs credit.")
            dateCols.isNotEmpty() && balanceOnly && rows.size > 12          -> ChartMeta("line",           "Date + balance trend.")
            dateCols.isNotEmpty() && balanceOnly && rows.size <= 12         -> ChartMeta("bar",            "Date + balance bar.")
            dateCols.isNotEmpty() && trendCol != null && rows.size > 12     -> ChartMeta("line",           "Date + $trendCol trend.")
            dateCols.isNotEmpty() && trendCol != null && rows.size <= 12    -> ChartMeta("bar",            "Date + $trendCol bar.")
            catCols.isNotEmpty() && numCols.isNotEmpty() && rows.size <= 5  -> ChartMeta("donut",          "${rows.size} categories — donut.")
            catCols.isNotEmpty() && numCols.isNotEmpty() && rows.size <= 8  -> ChartMeta("pie",            "${rows.size} categories — pie.")
            catCols.isNotEmpty() && numCols.isNotEmpty() && rows.size <= 15 -> ChartMeta("horizontal_bar", "Category horizontal bar.")
            catCols.isNotEmpty() && numCols.isNotEmpty()                    -> ChartMeta("horizontal_bar", "Many categories.")
            isDualCompare                                                    -> ChartMeta("multi_line",     "Debit vs credit.")
            numCols.size >= 2                                               -> ChartMeta("bar",            "Multiple values.")
            else                                                            -> ChartMeta("table",          "No suitable chart.")
        }
    }

    private fun toHtmlTable(cols: List<String>, rows: List<List<Any?>>): String? {
        if (rows.isEmpty() || cols.isEmpty()) return null
        val skip = setOf("id", "reference", "currency", "value_date", "account_no", "created_at")
        val displayIdx = cols.indices.filter { cols[it].lowercase() !in skip }
        val displayCols = displayIdx.map { cols[it] }
        val header = displayCols.joinToString("") { "<th>$it</th>" }
        val body = rows.joinToString("") { row ->
            "<tr>" + displayIdx.joinToString("") { i -> "<td>${row.getOrNull(i) ?: ""}</td>" } + "</tr>"
        }
        return "<style>table{border-collapse:collapse;width:100%;font-size:13px;}th{background:#1565C0;color:white;padding:8px;text-align:left;}td{padding:7px 8px;border-bottom:1px solid #ddd;}tr:nth-child(even){background:#f5f5f5;}</style>" +
               "<table><thead><tr>$header</tr></thead><tbody>$body</tbody></table>"
    }

    fun runQuery(question: String): QueryResult {
        AppLogger.info(TAG, "=== runQuery START === question=$question")
        init()
        val relevant = relevanceChecker!!.isSqlRelated(question)
        if (!relevant) {
            AppLogger.info(TAG, "OUT OF SCOPE")
            return QueryResult(null, null, null, "This question is out of scope for the transaction database.", null, null, null)
        }
        val chunks = retrieveColumns(question)
        val sql = generateSql(question, chunks)
        val (cols, rows) = executeQuery(sql)
        val summary = summarizer!!.summarize(question, cols, rows)
        val chart: ChartMeta?
        val tableHtml: String?
        val suggested = if (needsChart(cols, rows)) suggestChart(cols, rows) else null
        if (suggested != null && suggested.type != "table") {
            chart = suggested; tableHtml = null
        } else {
            chart = null; tableHtml = toHtmlTable(cols, rows)
        }
        AppLogger.info(TAG, "=== runQuery END ===")
        return QueryResult(sql, cols, rows, summary, chart, null, tableHtml)
    }

    fun close() {
        db?.close(); db = null
        embedder?.close(); embedder = null
        AppLogger.info(TAG, "SlmEngine closed")
    }
}

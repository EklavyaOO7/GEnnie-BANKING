package com.kiya.bankinggenie

import android.util.Log
import com.kiya.bankinggenie.dbu.AppLogger
import com.kiya.bankinggenie.dbu.ChartRenderer
import com.kiya.bankinggenie.dbu.GemmaEngine
import com.kiya.bankinggenie.dbu.SlmEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.util.concurrent.Executors

class SlmPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "SlmPlugin"
        private const val CHANNEL = "com.kiya.bankinggenie/slm"
        val MODEL_FILES = arrayOf(
            "all-MiniLM-L12-v2_quantized.onnx",
            "vocab.txt",
            "gemma-4-E2B-it.litertlm",
            "TB_Statement_meta.csv"
        )
    }

    private lateinit var channel: MethodChannel
    private lateinit var modelsDir: File
    private var gemmaEngine: GemmaEngine? = null
    private var slmEngine: SlmEngine? = null
    private val executor = Executors.newSingleThreadExecutor()
    private var appContext: android.content.Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        modelsDir = File(
            binding.applicationContext.getExternalFilesDir(null) ?: binding.applicationContext.filesDir,
            "models"
        )
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        slmEngine?.close()
        gemmaEngine?.close()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.i(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "checkModel"     -> executor.execute { checkModel(result) }
            "downloadModels" -> executor.execute { downloadModels(call, result) }
            "init"           -> executor.execute { doInit(result) }
            "initSlm"        -> executor.execute { doInitSlm(result) }
            "querySlm"       -> executor.execute { doQuerySlm(call, result) }
            "closeSlm"       -> executor.execute { doCloseSlm(result) }
            else             -> result.notImplemented()
        }
    }

    // ── checkModel ────────────────────────────────────────────────────────────

    private fun checkModel(result: MethodChannel.Result) {
        for (name in MODEL_FILES) {
            val f = File(modelsDir, name)
            if (!f.exists() || f.length() == 0L) {
                Log.w(TAG, "checkModel: MISSING $name")
                runOnMain { result.success(false) }
                return
            }
        }
        Log.i(TAG, "checkModel: all present")
        runOnMain { result.success(true) }
    }

    // ── downloadModels ────────────────────────────────────────────────────────

    private fun downloadModels(call: MethodCall, result: MethodChannel.Result) {
        modelsDir.mkdirs()
        val urls = call.argument<Map<String, String>>("urls") ?: run {
            runOnMain { result.error("NO_URLS", "urls argument missing", null) }
            return
        }
        val total = MODEL_FILES.size
        try {
            MODEL_FILES.forEachIndexed { i, name ->
                val url = urls[name] ?: run {
                    runOnMain { result.error("MISSING_URL", "No URL for $name", null) }
                    return
                }
                Log.i(TAG, "Downloading [${i + 1}/$total] $name")
                downloadFile(url, File(modelsDir, name)) { filePct ->
                    val totalPct = ((i * 100 + filePct) / total.toDouble()).toInt()
                    runOnMain {
                        channel.invokeMethod("onProgress", mapOf(
                            "file" to name, "fileProgress" to filePct, "totalProgress" to totalPct
                        ))
                    }
                }
                Log.i(TAG, "Done [${i + 1}/$total] $name")
            }
            runOnMain { result.success(true) }
        } catch (e: Exception) {
            Log.e(TAG, "downloadModels error: ${e.message}", e)
            runOnMain { result.error("DOWNLOAD_ERROR", e.message, null) }
        }
    }

    private fun downloadFile(urlStr: String, dest: File, onProgress: (Int) -> Unit) {
        val tmp = File(dest.parent, dest.name + ".tmp")
        try {
            val conn = java.net.URI.create(urlStr).toURL().openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 30_000
            conn.readTimeout    = 120_000
            conn.instanceFollowRedirects = true
            conn.setRequestProperty("User-Agent", "BankingGenie/1.0")
            conn.connect()
            if (conn.responseCode !in 200..299) {
                conn.errorStream?.use { Log.e(TAG, "download error: ${it.readBytes().toString(Charsets.UTF_8)}\n") }
                throw Exception("HTTP ${conn.responseCode} for ${dest.name}")
            }
            val fileTotal = conn.contentLengthLong
            var downloaded = 0L; var lastPct = -1
            conn.inputStream.use { input ->
                FileOutputStream(tmp).use { out ->
                    val buf = ByteArray(65536); var n: Int
                    while (input.read(buf).also { n = it } != -1) {
                        out.write(buf, 0, n); downloaded += n
                        if (fileTotal > 0) {
                            val pct = (downloaded * 100 / fileTotal).toInt()
                            if (pct != lastPct) { lastPct = pct; onProgress(pct) }
                        }
                    }
                }
            }
            if (fileTotal > 0 && tmp.length() != fileTotal) {
                tmp.delete()
                throw Exception("Size mismatch for ${dest.name}: expected=$fileTotal got=${tmp.length()}")
            }
            Log.i(TAG, "✔ downloaded ${dest.name} bytes=$downloaded")
            tmp.renameTo(dest)
        } catch (e: Exception) {
            tmp.delete(); throw e
        }
    }

    // ── init — load GemmaEngine only ─────────────────────────────────────────

    private fun doInit(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "init() — loading GemmaEngine from ${modelsDir.absolutePath}")
            if (gemmaEngine == null) gemmaEngine = GemmaEngine(modelsDir)
            val gemmaReady = gemmaEngine!!.isReady()
            Log.i(TAG, "init() SUCCESS | gemmaReady=$gemmaReady")
            runOnMain { result.success(mapOf("gemmaReady" to gemmaReady)) }
        } catch (e: Exception) {
            Log.e(TAG, "init() FAILED: ${e.message}", e)
            runOnMain { result.error("INIT_ERROR", e.message, null) }
        }
    }

    // ── initSlm ───────────────────────────────────────────────────────────────

    private fun doInitSlm(result: MethodChannel.Result) {
        try {
            val eng = gemmaEngine ?: run {
                runOnMain { result.error("NOT_INIT", "Call init() before initSlm()", null) }
                return
            }
            AppLogger.init(File(appContext!!.filesDir, "logs"), appContext)
            if (slmEngine == null) slmEngine = SlmEngine(appContext!!, modelsDir, eng)
            slmEngine!!.init()
            Log.i(TAG, "initSlm() SUCCESS")
            runOnMain { result.success(null) }
        } catch (e: Exception) {
            Log.e(TAG, "initSlm() FAILED: ${e.message}", e)
            runOnMain { result.error("INIT_SLM_ERROR", e.message, null) }
        }
    }

    // ── querySlm ──────────────────────────────────────────────────────────────

    private fun doQuerySlm(call: MethodCall, result: MethodChannel.Result) {
        val engine = slmEngine ?: run {
            runOnMain { result.error("SLM_NOT_INIT", "SLM not initialized", null) }
            return
        }
        val question = call.arguments as? String ?: run {
            runOnMain { result.error("BAD_ARGS", "Expected string question", null) }
            return
        }
        Log.i(TAG, "querySlm() question=\"$question\"")
        try {
            val qr = engine.runQuery(question)
            val chartImage = if (qr.chart != null) ChartRenderer.renderToBase64(qr) else null
            val map = mutableMapOf<String, Any?>(
                "sql"        to qr.sql,
                "summary"    to qr.summary,
                "tableHtml"  to qr.tableHtml,
                "chartImage" to chartImage,
                "columns"    to qr.columns,
                "rows"       to qr.rows?.map { row -> row.map { it?.toString() } }
            )
            Log.i(TAG, "querySlm() done | summary=${qr.summary}")
            runOnMain { result.success(map) }
        } catch (e: Exception) {
            Log.e(TAG, "querySlm() FAILED: ${e.message}", e)
            runOnMain { result.error("QUERY_ERROR", e.message, null) }
        }
    }

    // ── closeSlm ──────────────────────────────────────────────────────────────

    private fun doCloseSlm(result: MethodChannel.Result) {
        slmEngine?.close(); slmEngine = null
        Log.i(TAG, "closeSlm() done")
        runOnMain { result.success(null) }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun runOnMain(block: () -> Unit) {
        android.os.Handler(android.os.Looper.getMainLooper()).post(block)
    }
}

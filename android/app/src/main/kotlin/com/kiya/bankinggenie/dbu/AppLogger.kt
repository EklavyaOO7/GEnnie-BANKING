package com.kiya.bankinggenie.dbu

import android.util.Log
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object AppLogger {

    private const val MAX_BYTES = 5 * 1024 * 1024L
    private const val MAX_BACKUPS = 3
    private val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
    private var logFile: File? = null
    lateinit var appContext: android.content.Context

    fun init(logDir: File, context: android.content.Context? = null) {
        logDir.mkdirs()
        logFile = File(logDir, "app.log")
        if (context != null) appContext = context.applicationContext
    }

    fun debug(tag: String, msg: String) { Log.d(tag, msg); write("DEBUG", tag, msg) }
    fun info(tag: String, msg: String)  { Log.i(tag, msg); write("INFO ", tag, msg) }
    fun warn(tag: String, msg: String)  { Log.w(tag, msg); write("WARN ", tag, msg) }
    fun error(tag: String, msg: String) { Log.e(tag, msg); write("ERROR", tag, msg) }

    private fun write(level: String, tag: String, msg: String) {
        val f = logFile ?: return
        rotate(f)
        FileWriter(f, true).use { it.write("${fmt.format(Date())} | $level | $tag | $msg\n") }
    }

    private fun rotate(f: File) {
        if (!f.exists() || f.length() < MAX_BYTES) return
        for (i in MAX_BACKUPS - 1 downTo 1) {
            val old = File(f.parent, "app.log.$i")
            val new = File(f.parent, "app.log.${i + 1}")
            if (old.exists()) old.renameTo(new)
        }
        f.renameTo(File(f.parent, "app.log.1"))
    }
}

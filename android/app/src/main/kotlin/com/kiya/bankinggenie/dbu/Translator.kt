package com.kiya.bankinggenie.dbu

import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

object Translator {
    private const val TAG     = "Translator"
    private const val API_URL = "https://uatgenai.kiya.ai/process_request/translation"

    fun translate(text: String, inputLanguage: String, outputLanguage: String): String? {
        return try {
            val payload = JSONObject().apply {
                put("operationobject", JSONObject().apply {
                    put("operation", "translate")
                    put("channeltype", "dbu")
                    put("instancepreferred", "CPU")
                })
                put("inputobject", JSONObject().apply {
                    put("inputtext", text)
                    put("inputtype", "text")
                    put("inputlanguage", inputLanguage)
                    put("outputlanguage", outputLanguage)
                })
            }
            val conn = URL(API_URL).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true
            OutputStreamWriter(conn.outputStream).use { it.write(payload.toString()) }
            if (conn.responseCode == 200)
                JSONObject(conn.inputStream.bufferedReader().readText()).getJSONObject("results").getString("translated_text")
            else null
        } catch (e: Exception) {
            Log.e(TAG, "translate error: ${e.message}"); null
        }
    }
}

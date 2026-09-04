package com.kiya.bankinggenie.dbu

import android.util.Log
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.SamplerConfig
import java.io.File

private const val TAG = "GemmaEngine"
private const val MODEL_FILENAME = "gemma-4-E2B-it.litertlm"

class GemmaEngine(modelsDir: File) {

    private var engine: Engine? = null

    init {
        val modelFile = File(modelsDir, MODEL_FILENAME)
        Log.i(TAG, "LiteRT model path: ${modelFile.absolutePath} | exists=${modelFile.exists()} | size=${if (modelFile.exists()) modelFile.length() else 0}")
        if (!modelFile.exists()) {
            Log.w(TAG, "✘ Model file not found — GemmaEngine disabled")
        } else {
            try {
                val cfg = EngineConfig(modelPath = modelFile.absolutePath, maxNumTokens = 1024)
                engine = Engine(cfg).also { it.initialize() }
                Log.i(TAG, "✔ LiteRT engine loaded")
            } catch (e: Exception) {
                Log.e(TAG, "✘ LiteRT load failed: ${e.message}", e)
            }
        }
    }

    fun isReady(): Boolean = engine != null

    fun generate(prompt: String, system: String = "", maxTokens: Int = 300): String {
        val eng = engine ?: return ""
        val fullPrompt = if (system.isNotBlank())
            "<start_of_turn>user\n$system\n\n$prompt<end_of_turn>\n<start_of_turn>model\n"
        else
            "<start_of_turn>user\n$prompt<end_of_turn>\n<start_of_turn>model\n"
        val samplerConfig = SamplerConfig(topK = 40, topP = 0.95, temperature = 0.8)
        val conv = eng.createConversation(ConversationConfig(samplerConfig = samplerConfig))
        return try {
            conv.sendMessage(fullPrompt).contents?.toString()?.trim() ?: ""
        } finally {
            conv.close()
        }
    }

    fun chat(system: String, userMessage: String): String = generate(prompt = userMessage, system = system)

    fun close() { engine?.close(); engine = null }
}

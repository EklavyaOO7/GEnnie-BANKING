package com.kiya.bankinggenie.dbu

import android.content.Context
import android.util.Log
import java.io.File

class RagEngine(context: Context, modelsDir: File, private val onnx: OnnxInferenceEngine, private val gemma: GemmaEngine) {
    companion object { private const val TAG = "RagEngine" }

    private val chunks: List<String> = try {
        val f = File(modelsDir, "rag_documents.txt")
        if (!f.exists()) emptyList()
        else f.readText().split("\n---\n").map { it.trim() }.filter { it.isNotBlank() }
    } catch (e: Exception) { emptyList() }

    fun askQuestion(question: String, k: Int = 3): String {
        if (chunks.isEmpty()) return "I don't know."
        val queryEmb = onnx.encodeMiniLM(question)
        val topChunks = chunks
            .map { Pair(it, onnx.cosineSimilarity(queryEmb, onnx.encodeMiniLM(it))) }
            .sortedByDescending { it.second }.take(k).map { it.first }
        val ctx = topChunks.joinToString("\n\n")
        return gemma.chat(
            system      = "You are a helpful assistant. Answer ONLY from the provided context. If the answer is not in the context, say 'I don't know.'",
            userMessage = "Context:\n$ctx\n\nQuestion:\n$question"
        )
    }
}

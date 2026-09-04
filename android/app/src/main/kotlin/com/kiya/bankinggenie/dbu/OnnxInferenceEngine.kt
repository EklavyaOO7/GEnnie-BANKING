package com.kiya.bankinggenie.dbu

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.util.Log
import java.io.File
import java.nio.LongBuffer

class OnnxInferenceEngine(context: android.content.Context, modelsDir: File) {

    companion object {
        const val MAX_SEQ_LEN = 128
        private const val PAD_ID = 0L
        private const val UNK_ID = 100L
        private const val CLS_ID = 101L
        private const val SEP_ID = 102L
        private const val TAG    = "OnnxInferenceEngine"

        val NER_LABELS = mapOf(
            0 to "O", 1 to "B-MISC", 2 to "I-MISC",
            3 to "B-PER", 4 to "I-PER",
            5 to "B-ORG", 6 to "I-ORG",
            7 to "B-LOC", 8 to "I-LOC"
        )
    }

    private val env           = OrtEnvironment.getEnvironment()
    private val miniLMSession : OrtSession
    private val mpnetSession  : OrtSession
    private val nerSession    : OrtSession
    private val vocab         : Map<String, Long>

    init {
        fun load(name: String): OrtSession {
            val f = File(modelsDir, name)
            Log.i(TAG, "Loading ONNX: ${f.absolutePath} (${f.length()} bytes)")
            return env.createSession(f.readBytes(), OrtSession.SessionOptions())
        }
        miniLMSession = load("all-MiniLM-L12-v2_quantized.onnx")
        mpnetSession  = load("multi-qa-mpnet-base-dot-v1_quantized.onnx")
        nerSession    = load("bert-base-NER_quantized.onnx")
        vocab         = loadVocab(modelsDir)
        Log.i(TAG, "✔ All ONNX models loaded | vocab size=${vocab.size}")
    }

    private fun loadVocab(modelsDir: File): Map<String, Long> {
        val map = mutableMapOf<String, Long>()
        File(modelsDir, "vocab.txt").bufferedReader().useLines { lines ->
            lines.forEachIndexed { i, token -> map[token] = i.toLong() }
        }
        return map
    }

    private data class Encoding(val inputIds: LongArray, val attentionMask: LongArray, val tokenTypeIds: LongArray)

    private fun tokenize(text: String): Encoding {
        val words = text.lowercase().trim().split(Regex("\\s+"))
        val ids = mutableListOf(CLS_ID)
        for (w in words) {
            if (ids.size >= MAX_SEQ_LEN - 1) break
            ids.add(vocab[w] ?: UNK_ID)
        }
        ids.add(SEP_ID)
        val seqLen = ids.size
        return Encoding(
            inputIds      = LongArray(MAX_SEQ_LEN) { if (it < seqLen) ids[it] else PAD_ID },
            attentionMask = LongArray(MAX_SEQ_LEN) { if (it < seqLen) 1L else 0L },
            tokenTypeIds  = LongArray(MAX_SEQ_LEN) { 0L }
        )
    }

    private fun makeTensor(ids: LongArray): OnnxTensor =
        OnnxTensor.createTensor(env, LongBuffer.wrap(ids), longArrayOf(1L, MAX_SEQ_LEN.toLong()))

    private fun embed(session: OrtSession, text: String): FloatArray {
        val enc = tokenize(text)
        val inputs = mapOf(
            "input_ids"      to makeTensor(enc.inputIds),
            "attention_mask" to makeTensor(enc.attentionMask),
            "token_type_ids" to makeTensor(enc.tokenTypeIds)
        )
        val output = session.run(inputs)
        @Suppress("UNCHECKED_CAST")
        val tensor = (output.get(0).value as Array<Array<FloatArray>>)[0]
        val hidden = tensor[0].size
        val result = FloatArray(hidden)
        var count = 0
        for (i in 0 until MAX_SEQ_LEN) {
            if (enc.attentionMask[i] == 1L) {
                for (j in 0 until hidden) result[j] += tensor[i][j]
                count++
            }
        }
        if (count > 0) { val cf = count.toFloat(); for (j in 0 until hidden) result[j] /= cf }
        inputs.values.forEach { it.close() }
        output.close()
        return result
    }

    fun encodeMiniLM(text: String): FloatArray = embed(miniLMSession, text)
    fun encodeMpnet(text: String): FloatArray  = embed(mpnetSession, text)

    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        var dot = 0f; var normA = 0f; var normB = 0f
        for (i in a.indices) { dot += a[i] * b[i]; normA += a[i] * a[i]; normB += b[i] * b[i] }
        val denom = Math.sqrt(normA.toDouble()) * Math.sqrt(normB.toDouble())
        return if (denom == 0.0) 0f else (dot / denom).toFloat()
    }

    data class NerToken(val word: String, val label: String, val score: Float)

    fun runNer(text: String): List<NerToken> {
        val words = text.lowercase().trim().split(Regex("\\s+"))
        val enc = tokenize(text)
        val inputs = mapOf(
            "input_ids"      to makeTensor(enc.inputIds),
            "attention_mask" to makeTensor(enc.attentionMask),
            "token_type_ids" to makeTensor(enc.tokenTypeIds)
        )
        val output = nerSession.run(inputs)
        @Suppress("UNCHECKED_CAST")
        val logits = (output.get(0).value as Array<Array<FloatArray>>)[0]
        val results = mutableListOf<NerToken>()
        for (i in words.indices) {
            val pos = i + 1
            if (pos >= MAX_SEQ_LEN - 1) break
            val sm = softmax(logits[pos])
            val maxIdx = sm.indices.maxByOrNull { sm[it] } ?: 0
            results.add(NerToken(words[i], NER_LABELS[maxIdx] ?: "O", sm[maxIdx]))
        }
        inputs.values.forEach { it.close() }
        output.close()
        return results
    }

    private fun softmax(logits: FloatArray): FloatArray {
        val max = logits.maxOrNull() ?: 0f
        val exp = FloatArray(logits.size) { Math.exp((logits[it] - max).toDouble()).toFloat() }
        val sum = exp.sum()
        return FloatArray(exp.size) { exp[it] / sum }
    }

    fun close() { miniLMSession.close(); mpnetSession.close(); nerSession.close(); env.close() }
}

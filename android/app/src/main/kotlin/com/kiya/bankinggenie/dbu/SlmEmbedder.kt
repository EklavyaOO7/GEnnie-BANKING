package com.kiya.bankinggenie.dbu

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.nio.LongBuffer
import kotlin.math.sqrt

class SlmEmbedder(private val modelsDir: File) {

    private val TAG = "SlmEmbedder"
    private val vocab: Map<String, Int>
    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private val session: OrtSession

    companion object {
        private const val MAX_SEQ_LEN = 128
        private const val UNK_ID = 100L
        private const val CLS_ID = 101L
        private const val SEP_ID = 102L
        private const val PAD_ID = 0L
    }

    init {
        AppLogger.info(TAG, "Loading vocab from $modelsDir/vocab.txt")
        vocab = loadVocab()
        AppLogger.info(TAG, "Vocab loaded — ${vocab.size} tokens")
        AppLogger.info(TAG, "Loading ONNX model from $modelsDir/all-MiniLM-L12-v2_quantized.onnx")
        val modelBytes = File(modelsDir, "all-MiniLM-L12-v2_quantized.onnx").readBytes()
        session = env.createSession(modelBytes, OrtSession.SessionOptions())
        AppLogger.info(TAG, "ONNX session created")
    }

    fun encode(text: String): FloatArray {
        val tokens = tokenize(text)
        val inputIds      = LongArray(MAX_SEQ_LEN) { PAD_ID }
        val attentionMask = LongArray(MAX_SEQ_LEN) { 0L }
        val tokenTypeIds  = LongArray(MAX_SEQ_LEN) { 0L }

        inputIds[0] = CLS_ID; attentionMask[0] = 1L
        val len = minOf(tokens.size, MAX_SEQ_LEN - 2)
        for (i in 0 until len) { inputIds[i + 1] = tokens[i]; attentionMask[i + 1] = 1L }
        inputIds[len + 1] = SEP_ID; attentionMask[len + 1] = 1L

        val shape = longArrayOf(1, MAX_SEQ_LEN.toLong())
        val tIds  = OnnxTensor.createTensor(env, LongBuffer.wrap(inputIds),      shape)
        val tMask = OnnxTensor.createTensor(env, LongBuffer.wrap(attentionMask), shape)
        val tType = OnnxTensor.createTensor(env, LongBuffer.wrap(tokenTypeIds),  shape)

        val output = session.run(mapOf("input_ids" to tIds, "attention_mask" to tMask, "token_type_ids" to tType))
        @Suppress("UNCHECKED_CAST")
        val hidden = (output.get(0).value as Array<Array<FloatArray>>)[0]

        val embedding = FloatArray(hidden[0].size)
        var count = 0
        for (i in 0 until MAX_SEQ_LEN) {
            if (attentionMask[i] == 1L) {
                val row = hidden[i]
                for (j in embedding.indices) embedding[j] = embedding[j] + row[j]
                count++
            }
        }
        if (count > 0) { val c = count.toFloat(); for (j in embedding.indices) embedding[j] = embedding[j] / c }

        val norm = sqrt(embedding.map { it * it }.sum()).toDouble()
        if (norm > 1e-10) { val n = norm.toFloat(); for (j in embedding.indices) embedding[j] = embedding[j] / n }

        tIds.close(); tMask.close(); tType.close(); output.close()
        return embedding
    }

    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        var dot = 0f
        for (i in a.indices) dot += a[i] * b[i]
        return dot
    }

    private fun tokenize(text: String): LongArray {
        val words = text.lowercase().split(Regex("\\s+|(?=[^a-z0-9])|(?<=[^a-z0-9])")).filter { it.isNotEmpty() }
        val ids = mutableListOf<Long>()
        for (word in words) ids.addAll(wordPieceTokenize(word))
        return ids.toLongArray()
    }

    private fun wordPieceTokenize(word: String): List<Long> {
        if (word in vocab) return listOf(vocab[word]!!.toLong())
        val pieces = mutableListOf<Long>()
        var start = 0
        while (start < word.length) {
            var end = word.length; var found = false
            while (start < end) {
                val sub = if (start == 0) word.substring(start, end) else "##${word.substring(start, end)}"
                if (sub in vocab) { pieces.add(vocab[sub]!!.toLong()); start = end; found = true; break }
                end--
            }
            if (!found) { pieces.add(UNK_ID); break }
        }
        return pieces
    }

    private fun loadVocab(): Map<String, Int> {
        val map = mutableMapOf<String, Int>()
        BufferedReader(InputStreamReader(File(modelsDir, "vocab.txt").inputStream())).use { br ->
            var idx = 0
            br.forEachLine { line -> map[line.trim()] = idx++ }
        }
        return map
    }

    fun close() { session.close(); env.close() }
}

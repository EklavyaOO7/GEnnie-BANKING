package com.kiya.bankinggenie.dbu

import android.util.Log

class MenuValidator(private val gemma: GemmaEngine) {

    companion object {
        private const val TAG = "MenuValidator"
    }

    fun llmValidate(query: String, intent: String?): String {
        if (intent == null) { Log.w(TAG, "--- llmValidate: intent is null → False"); return "False" }
        Log.i(TAG, "--- llmValidate | query=$query | intent=$intent")

        val prompt = """Does "$intent" match the intent of: "$query"? Answer YES or NO only.""".trimIndent()

        val answer = gemma.chat(system = "", userMessage = prompt).trim().uppercase()
        Log.d(TAG, "--- LLM raw output: $answer")

        // Gemma 2B often outputs verbose text instead of plain YES/NO.
        // Accept as True if the answer contains YES or does NOT contain NO.
        val hasYes = "YES" in answer
        val hasNo  = Regex("\\bNO\\b").containsMatchIn(answer)
        val result = if (hasYes || (!hasNo && answer.isNotEmpty())) "True" else "False"
        Log.i(TAG, "--- llmValidate result: $result (hasYes=$hasYes hasNo=$hasNo)")
        return result
    }
}

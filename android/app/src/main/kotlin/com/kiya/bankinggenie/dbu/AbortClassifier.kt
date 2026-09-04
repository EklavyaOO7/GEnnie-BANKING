package com.kiya.bankinggenie.dbu

import android.util.Log

class AbortClassifier(private val gemma: GemmaEngine) {
    companion object { private const val TAG = "AbortClassifier" }

    fun classifyAbort(userInput: String, flowName: String = "general"): Map<String, String> {
        if (userInput.isBlank()) return mapOf("action" to "continue")
        val prompt = """
You are a strict intent classifier. A user is in the middle of a "$flowName" process.
Reply with ONLY one word: "abort" or "continue" or "switch" or "undetermined".
Current flow: "$flowName"
User: "$userInput"
Answer:""".trimIndent()
        val result = gemma.generate(prompt = prompt).lowercase().trim()
        val action = when {
            "abort"    in result -> "abort"
            "switch"   in result -> "switch"
            "continue" in result -> "continue"
            else                 -> "undetermined"
        }
        return mapOf("action" to action)
    }
}

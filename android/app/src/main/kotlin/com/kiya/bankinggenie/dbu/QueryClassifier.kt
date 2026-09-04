package com.kiya.bankinggenie.dbu

import android.util.Log
import org.json.JSONObject

class QueryClassifier(private val gemma: GemmaEngine) {

    companion object {
        private const val TAG = "QueryClassifier"
    }

    private val systemPrompt = """
Classify the banking query. Reply ONLY with JSON: {"category": "<cat>", "product": "<product or null>"}
Categories: actionable, informational, actionable_with_information, form_fill
Rules: "I want to send money"→actionable | "What is X"→informational | "Can I do X"→actionable_with_information | providing field values→form_fill
""".trimIndent()

    fun classify(query: String): Map<String, String?> {
        val raw = gemma.generate(prompt = "Classify this query: \"$query\"", system = systemPrompt)
        return try {
            val start = raw.indexOf("{"); val end = raw.lastIndexOf("}") + 1
            if (start == -1 || end <= start) return fallbackClassify(query)
            val obj = JSONObject(raw.substring(start, end))
            val category = obj.optString("category", "").lowercase().trim()
            val validCategories = setOf("actionable", "informational", "actionable_with_information", "form_fill")
            val finalCategory = if (category in validCategories) category else fallbackClassify(query)["category"]
            mapOf("category" to finalCategory, "product" to obj.optString("product").takeIf { it.isNotBlank() && it != "null" })
        } catch (e: Exception) {
            fallbackClassify(query)
        }
    }

    private fun fallbackClassify(query: String): Map<String, String?> {
        val lower = query.lowercase().trim()
        val category = when {
            lower.all { it.isDigit() || it.isWhitespace() } -> "form_fill"
            Regex("\\b(name|amount|address|number|account|phone|email|city|pin|dob|date)\\s+is\\b").containsMatchIn(lower) -> "form_fill"
            Regex("\\b(i want to|transfer|send|pay|open|block|apply|check|close|activate|update)\\b").containsMatchIn(lower) -> "actionable"
            Regex("\\b(can i|how do i|is it possible|what is my|show my)\\b").containsMatchIn(lower) -> "actionable_with_information"
            else -> "informational"
        }
        return mapOf("category" to category, "product" to null)
    }

    data class IntentResult(val intent: String, val sentenceDict: Map<String, String>, val product: String?)

    fun intentClassifier(userText: String): IntentResult {
        if (userText.trim().all { it.isDigit() }) return IntentResult("form_fill", mapOf(userText to "form_fill"), null)

        val sentenceDict = mutableMapOf<String, String>()
        val productList  = mutableListOf<String>()
        val initialResult  = classify(userText)
        val initialIntent  = initialResult["category"] ?: "informational"
        val initialProduct = initialResult["product"]

        if (initialIntent == "form_fill") {
            sentenceDict[userText] = "form_fill"
            return IntentResult("form_fill", sentenceDict, initialProduct)
        }

        val hasSplit = listOf(',', '.', '?').any { it in userText } || "and" in userText
        if (hasSplit) {
            val sentences = userText.split(Regex("[,.?]|\\band\\b")).map { it.trim() }.filter { it.isNotBlank() }
            if (sentences.size > 1) {
                val intents = mutableListOf<String>(); var formFillCount = 0
                for (sentence in sentences) {
                    val res = classify(sentence); val intent = res["category"] ?: "informational"
                    sentenceDict[sentence] = intent
                    res["product"]?.let { productList.add(it) }
                    if (intent == "form_fill") formFillCount++
                    else if (intent in listOf("actionable", "informational", "actionable_with_information")) intents.add(intent)
                }
                if (formFillCount > 0) return IntentResult("form_fill", sentenceDict, null)
                val combinedProduct = productList.joinToString(", ").takeIf { it.isNotBlank() }
                val finalIntent = when {
                    intents.count { it == "actionable_with_information" } > 0 -> "actionable_with_information"
                    intents.count { it == "actionable" } > 0 && intents.count { it == "informational" } > 0 -> "actionable_with_information"
                    intents.count { it == "actionable" } > 0 -> "actionable"
                    else -> "informational"
                }
                return IntentResult(finalIntent, sentenceDict, combinedProduct)
            }
        }

        sentenceDict[userText] = initialIntent
        return IntentResult(initialIntent, sentenceDict, initialProduct)
    }
}

package com.kiya.bankinggenie.dbu

import android.util.Log
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

class FieldExtractor(private val gemma: GemmaEngine) {
    companion object { private const val TAG = "FieldExtractor" }

    private val nullValues = setOf("none", "null", "no answer", "n/a", "", "not present", "not mentioned", "not provided", "not specified")

    private fun humanizeFieldName(fieldName: String): String =
        fieldName.replace("_", " ").replace(Regex("(?<!^)(?=[A-Z])"), " ").trim()

    private fun getFieldVariants(fieldName: String): Set<String> {
        val lower = fieldName.lowercase()
        return setOf(
            lower.replace("_", " "),
            fieldName.replace(Regex("(?<!^)(?=[A-Z])"), " ").lowercase().trim(),
            lower,
            lower.replace(Regex("(name|address|number|date|id|type|mail|code|status)$"), " $1").trim()
        )
    }

    fun detectFieldsToUpdate(payload: MutableMap<String, Any?>): List<Map<String, String>> {
        val textLower = (payload["text"] as? String ?: "").lowercase()
        val formField = payload["form_field"] as? Map<*, *> ?: return emptyList()
        return formField.entries.filter { (k, v) ->
            v != null && getFieldVariants(k.toString()).any { variant ->
                variant.isNotBlank() && Regex("\\b${Regex.escape(variant)}\\b").containsMatchIn(textLower)
            }
        }.map { (k, _) -> mapOf("fieldName" to k.toString(), "fieldType" to "String") }
    }

    fun fieldIdentifierNew(response: MutableMap<String, Any?>): MutableMap<String, Any?> {
        val originalText = response["text"] as? String ?: return response
        val reqFields    = response["mandatory_field"] as? List<*> ?: return response
        val formField    = (response["form_field"] as? MutableMap<String, Any?>) ?: mutableMapOf()

        val mandatoryFieldNames = reqFields.mapNotNull { (it as? Map<*, *>)?.get("fieldName") as? String }.toSet()
        val textLower   = originalText.lowercase()
        val extraFields = formField.keys.filter { k ->
            k !in mandatoryFieldNames &&
            (formField[k] == null || Regex("\\b${Regex.escape(k.lowercase().replace("_", " "))}\\b").containsMatchIn(textLower))
        }.toSet()

        val allFieldNames = mandatoryFieldNames + extraFields
        if (allFieldNames.isEmpty()) return response

        val fieldListStr = allFieldNames.joinToString("\n") { "- ${humanizeFieldName(it)}" }
        val jsonKeysStr  = allFieldNames.joinToString(", ") { "\"$it\": \"value or null\"" }

        val prompt = """
You are a form-filling assistant. Extract values for each field from the text below.
Text: "$originalText"
Fields:
$fieldListStr
Respond ONLY with JSON: {$jsonKeysStr}
""".trimIndent()

        return try {
            val answer = gemma.chat(system = "", userMessage = prompt)
            val jsonMatch = Regex("\\{[^{}]*\\}", RegexOption.DOT_MATCHES_ALL).find(answer)
            val extracted = if (jsonMatch != null) try { JSONObject(jsonMatch.value) } catch (e: Exception) { JSONObject() } else JSONObject()
            val originalTextClean = originalText.lowercase().replace(Regex("[^\\w\\s@.]"), "")

            for (fieldName in allFieldNames) {
                val value = extracted.optString(fieldName, "null")
                if (value.isBlank() || value.lowercase().trim('.').trim() in nullValues) continue
                val valueClean = value.lowercase().replace(Regex("[^\\w\\s@.]"), "").trim()
                val coreValue  = valueClean.replace(Regex("^(rs|inr|usd|gbp)\\s*"), "").trim()
                if (coreValue.isNotBlank() && coreValue !in originalTextClean) continue
                val finalValue = if ("date" in fieldName.lowercase() || "dob" in fieldName.lowercase())
                    convertToYyyyMmDd(value) ?: value else value
                formField[fieldName] = finalValue
            }
            response["form_field"] = formField
            response
        } catch (e: Exception) {
            Log.e(TAG, "fieldIdentifierNew error: ${e.message}"); response
        }
    }

    private fun convertToYyyyMmDd(dateInput: String): String? {
        val cleaned = dateInput.replace(Regex("(\\d+)(st|nd|rd|th)"), "$1").trim()
        val formats = listOf("dd MMMM yyyy", "dd/MM/yyyy", "dd-MM-yyyy", "yyyy-MM-dd", "MMMM dd, yyyy")
        for (fmt in formats) {
            try {
                val sdf = SimpleDateFormat(fmt, Locale.ENGLISH).also { it.isLenient = false }
                val date = sdf.parse(cleaned) ?: continue
                return SimpleDateFormat("yyyy-MM-dd", Locale.ENGLISH).format(date)
            } catch (e: Exception) { continue }
        }
        return null
    }
}

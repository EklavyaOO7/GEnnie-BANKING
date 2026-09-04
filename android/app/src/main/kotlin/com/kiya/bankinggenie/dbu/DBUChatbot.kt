package com.kiya.bankinggenie.dbu

import android.content.Context
import android.util.Log
import java.io.File

class DBUChatbot(context: Context, modelsDir: File) {
    companion object { private const val TAG = "DBUChatbot" }

    private val gemma           = GemmaEngine(modelsDir)
    private val onnx            = OnnxInferenceEngine(context, modelsDir)
    private val menuMatcher     = MenuMatcher(context, modelsDir, onnx)
    private val menuValidator   = MenuValidator(gemma)
    private val queryClassifier = QueryClassifier(gemma)
    private val flowSwitcher    = FlowSwitcher(queryClassifier, menuMatcher, menuValidator)
    private val fieldExtractor  = FieldExtractor(gemma)
    private val formFieldMgr    = FormFieldManager(fieldExtractor)
    private val abortClassifier = AbortClassifier(gemma)
    private val ragEngine       = RagEngine(context, modelsDir, onnx, gemma)
    private val genAiEngine     = GenAiEngine(ragEngine, gemma)

    fun isGemmaReady(): Boolean = gemma.isReady()
    fun getGemma(): GemmaEngine = gemma

    fun osLogic(payload: MutableMap<String, Any?>): MutableMap<String, Any?> {
        payload.keys.forEach { if (payload[it] == "null") payload[it] = null }

        val inputLang = payload["inputlanguage"] as? String ?: "en"
        if (inputLang != "en") {
            payload["text"] = Translator.translate(payload["text"] as? String ?: "", inputLang, "en") ?: payload["text"]
        }

        val text = payload["text"] as? String ?: ""

        val ctx = payload["context"] as? String
        if (ctx != null) {
            val abortResult = abortClassifier.classifyAbort(text, ctx)
            when (abortResult["action"]) {
                "abort"        -> { payload["abort"] = "Yes"; return translateOutput(payload) }
                "undetermined" -> { payload["abort"] = "undetermined"; return translateOutput(payload) }
                else           -> payload["abort"] = null
            }
        }

        val question = payload["question"] as? String
        val mandatoryField = payload["mandatory_field"]
        val mandatoryEmpty = mandatoryField == null || (mandatoryField is List<*> && mandatoryField.isEmpty())

        if (question == null && mandatoryEmpty) {
            val fieldsToUpdate = fieldExtractor.detectFieldsToUpdate(payload)
            if (fieldsToUpdate.isNotEmpty()) {
                val fieldsStr = fieldsToUpdate.joinToString(" , ") { it["fieldName"] ?: "" }
                payload["mandatory_field"] = fieldsToUpdate
                payload["question"] = "Can you please specify the $fieldsStr to complete this transaction?"
            } else {
                payload["mandatory_field"] = null
                payload["form_field"] = mutableMapOf<String, Any?>()
            }
        }

        val tokens = text.lowercase().split(Regex("\\s+")).toSet()
        when {
            tokens.intersect(setOf("thank", "thanks", "thanking", "grateful", "happy")).isNotEmpty() -> {
                payload["response"] = "You are Welcome."; return translateOutput(payload)
            }
            tokens.intersect(setOf("ok", "okay")).isNotEmpty() -> {
                payload["response"] = "Do you have any other queries so that I can help you?"; return translateOutput(payload)
            }
            tokens.intersect(setOf("hi", "hello")).isNotEmpty() -> {
                payload["response"] = "Hello, How may I help you?"; return translateOutput(payload)
            }
        }

        val tempContext = payload["temporary_context"] as? String
        if (tempContext != null) {
            val lower    = text.lowercase().trim()
            val positive = listOf("yes", "y", "ok", "okay", "sure", "proceed", "continue", "start", "go ahead")
            val negative = listOf("no", "n", "nope", "cancel", "stop", "deny", "reject", "don't", "not")
            val isPositive = positive.any { it in lower }
            val isNegative = negative.any { it in lower }
            if (isPositive && !isNegative) {
                payload["context"] = tempContext; payload["temporary_context"] = null
                return translateOutput(formFieldMgr.fullJsonOneGoRenew(payload))
            } else if (isNegative) {
                payload["temporary_context"] = null
                val c = payload["context"] as? String; val q = payload["question"] as? String
                payload["response"] = if (c != null && q != null) "Continuing with $c. $q" else "Ok, How can I help you?"
                return translateOutput(payload)
            }
        }

        if (payload["query_type"] == "default") {
            val result = formFieldMgr.fullJsonOneGoRenew(payload)
            result["query_type"] = null
            return translateOutput(result)
        }

        val switchResult = flowSwitcher.finalCheck1(payload)
        val flowType = switchResult.flowType
        val bestMenu = switchResult.bestMenu
        val intent   = switchResult.intent

        val genaiEnabled    = payload["genai_flow"]?.toString()?.lowercase() in listOf("yes", "true", "1")
        val assistedEnabled = payload["assisted_flow"]?.toString()?.lowercase() in listOf("yes", "true", "1")
        val genaiPath       = payload["genai_path"] as? String ?: ""
        val assistedPath    = payload["assisted_flow_path"] as? String ?: ""

        when (flowType) {
            "Context Not In Option" -> {
                payload["context"] = null; payload["mandatory_field"] = null
                payload["response"] = if (genaiEnabled) {
                    "Sorry, We don't have any service related to this. ${genAiEngine.getResponseFromGenAi(text, genaiPath)["content"]}"
                } else "Sorry, We don't have any service related to this. You may visit nearest branch."
            }
            "dbu flow" -> {
                val currentContext = payload["context"] as? String
                if (currentContext == null) {
                    payload["form_field"] = mutableMapOf<String, Any?>()
                    if ((intent == "actionable" || intent == "form_fill") && bestMenu != null && bestMenu != "Context not found") {
                        payload["context"] = bestMenu
                        formFieldMgr.fullJsonOneGoRenew(payload).also { payload.putAll(it) }
                    } else {
                        payload["response"] = "Sorry, We don't have any service related to this"
                    }
                } else {
                    when {
                        currentContext == bestMenu && intent != "form_fill" -> {
                            formFieldMgr.fullJsonOneGoRenew(payload).also { payload.putAll(it) }
                            payload["response"] = "You are already in $currentContext flow. ${payload["question"]}"
                        }
                        intent == "form_fill" -> formFieldMgr.fullJsonOneGoRenew(payload).also { payload.putAll(it) }
                        intent == "actionable" -> {
                            if (bestMenu != null && bestMenu != "Context not found") {
                                payload["context"] = bestMenu; payload["mandatory_field"] = null
                                payload["form_field"] = mutableMapOf<String, Any?>()
                                payload["response"] = null; payload["question"] = null
                            } else {
                                payload["response"] = "Sorry, We don't have any service related to this."
                            }
                        }
                        else -> {
                            payload["mandatory_field"] = null; payload["form_field"] = mutableMapOf<String, Any?>()
                            payload["response"] = null; payload["question"] = null
                            formFieldMgr.fullJsonOneGoRenew(payload).also { payload.putAll(it) }
                        }
                    }
                }
            }
            "Assistant Flow" -> {
                payload["response"] = when {
                    assistedEnabled -> genAiEngine.getResponseFromGenAi(text, assistedPath)["content"]
                    genaiEnabled    -> "I don't have an exact answer but: ${genAiEngine.getResponseFromGenAi(text, genaiPath)["content"]}"
                    else            -> "I am not trained for assisted flow."
                }
            }
            "Gen_AI Flow" -> {
                payload["context"] = null; payload["mandatory_field"] = null
                payload["response"] = if (genaiEnabled) genAiEngine.getResponseFromGenAi(text, genaiPath)["content"]
                                      else "I am not trained for GenAI flow."
            }
            "Combine Flow" -> {
                val currentContext = payload["context"] as? String
                if ((currentContext == null || currentContext != bestMenu) && bestMenu != null && bestMenu != "Context not found") {
                    payload["temporary_context"] = bestMenu
                    payload["response"] = if (genaiEnabled)
                        "${genAiEngine.getResponseFromGenAi(text, genaiPath)["content"]} Do you want me to proceed with $bestMenu?"
                    else "Do you want me to proceed with $bestMenu?"
                } else if (currentContext == bestMenu) {
                    payload["response"] = if (genaiEnabled)
                        "${genAiEngine.getResponseFromGenAi(text, genaiPath)["content"]} ${payload["question"] ?: ""}"
                    else "You are already in $currentContext flow. ${payload["question"]}"
                } else {
                    payload["response"] = "Sorry, We don't have any service related to this"
                }
            }
            else -> {
                payload["context"] = null; payload["mandatory_field"] = null
                payload["response"] = if (genaiEnabled) genAiEngine.getResponseFromGenAi(text, genaiPath)["content"]
                                      else "Sorry, I could not process your request."
            }
        }

        if (payload["context"] == "Life Insurance") payload["context"] = "Insurance Premium"
        return translateOutput(payload)
    }

    private fun translateOutput(payload: MutableMap<String, Any?>): MutableMap<String, Any?> {
        val outputLang = payload["outputlanguage"] as? String ?: "en"
        if (outputLang != "en") {
            val response = payload["response"] as? String
            if (response != null) payload["response"] = Translator.translate(response, "en", outputLang) ?: response
        }
        return payload
    }

    fun close() { onnx.close(); gemma.close() }
}

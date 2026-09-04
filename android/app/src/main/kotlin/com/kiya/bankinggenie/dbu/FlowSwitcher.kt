package com.kiya.bankinggenie.dbu

import android.util.Log

class FlowSwitcher(
    private val queryClassifier: QueryClassifier,
    private val menuMatcher: MenuMatcher,
    private val menuValidator: MenuValidator
) {

    companion object {
        private const val TAG = "FlowSwitcher"
    }

    data class SwitchResult(val flowType: String, val bestMenu: String?, val intent: String)

    fun finalCheck1(payload: Map<String, Any?>): SwitchResult {
        val query = payload["text"] as? String ?: ""

        Log.i(TAG, "--- Intent_Classifier input: $query")
        val intentResult   = queryClassifier.intentClassifier(query)
        val answer         = intentResult.intent
        val sentenceDict   = intentResult.sentenceDict
        val initialProduct = intentResult.product

        Log.i(TAG, "--- Intent_Classifier result: answer=$answer | product=$initialProduct")
        Log.d(TAG, "--- Sentence dict: $sentenceDict")

        val actionableQuery = sentenceDict.entries
            .filter { it.value == "actionable" || it.value == "actionable_with_information" }
            .map { it.key }

        Log.i(TAG, "--- Actionable query parts: $actionableQuery")

        val bestMenu: String? = if (actionableQuery.isNotEmpty()) {
            val modifiedQuery = if (initialProduct == null || initialProduct == "Not found")
                actionableQuery[0]
            else
                "$initialProduct - ${actionableQuery[0]}"

            Log.i(TAG, "--- Modified actionable query: $modifiedQuery")
            val ctx = menuMatcher.resolveContext(modifiedQuery)
            Log.i(TAG, "--- Context resolved: $ctx")

            val validator = menuValidator.llmValidate(modifiedQuery, ctx)
            Log.i(TAG, "--- Validator result: $validator")

            if (validator == "False") { Log.w(TAG, "--- Validator returned False → bestMenu=null"); null }
            else ctx
        } else {
            Log.i(TAG, "--- No actionable query parts → bestMenu=null"); null
        }

        Log.i(TAG, "--- Final answer=$answer | bestMenu=$bestMenu")

        return when (answer) {
            "actionable" -> if (bestMenu != null) {
                Log.i(TAG, "--- Routing to: dbu flow")
                SwitchResult("dbu flow", bestMenu, answer)
            } else {
                Log.w(TAG, "--- Routing to: Context Not In Option")
                SwitchResult("Context Not In Option", null, answer)
            }
            "form_fill" -> {
                Log.i(TAG, "--- Routing to: dbu flow (form_fill)")
                SwitchResult("dbu flow", bestMenu, answer)
            }
            "informational" -> {
                val context      = payload["context"] as? String
                val assistedFlow = payload["assisted_flow"]?.toString()
                if (context != null && assistedFlow?.lowercase() in listOf("yes", "true")) {
                    Log.i(TAG, "--- Routing to: Assistant Flow")
                    SwitchResult("Assistant Flow", null, answer)
                } else {
                    Log.i(TAG, "--- Routing to: Gen_AI Flow")
                    SwitchResult("Gen_AI Flow", null, answer)
                }
            }
            "actionable_with_information" -> {
                Log.i(TAG, "--- Routing to: Combine Flow")
                SwitchResult("Combine Flow", bestMenu, answer)
            }
            "Context_Not_In_Option" -> {
                Log.i(TAG, "--- Routing to: Context Not In Option")
                SwitchResult("Context Not In Option", null, answer)
            }
            else -> {
                Log.w(TAG, "--- Unknown answer=$answer → Gen_AI Flow")
                SwitchResult("Gen_AI Flow", null, answer)
            }
        }
    }
}

package com.kiya.bankinggenie.dbu

import android.util.Log

class FormFieldManager(private val fieldExtractor: FieldExtractor) {
    companion object { private const val TAG = "FormFieldManager" }

    fun cleanMandatoryFields(payload: MutableMap<String, Any?>): MutableMap<String, Any?> {
        val mandatory = payload["mandatory_field"] as? List<*> ?: return payload
        val formField = payload["form_field"] as? Map<*, *> ?: return payload
        payload["mandatory_field"] = mandatory.filter { field ->
            val name = (field as? Map<*, *>)?.get("fieldName") as? String ?: return@filter true
            formField[name] == null
        }
        return payload
    }

    private fun newAccountFlow1(response: MutableMap<String, Any?>): MutableMap<String, Any?> {
        val requiredFields = (response["mandatory_field"] as? List<*>)
            ?.mapNotNull { (it as? Map<*, *>)?.get("fieldName") as? String } ?: return response
        val updated   = fieldExtractor.fieldIdentifierNew(response)
        val formField = updated["form_field"] as? Map<*, *> ?: mapOf<String, Any?>()
        val questionList = requiredFields.filter { formField[it] == null }
        if (questionList.isNotEmpty()) {
            val fieldsStr = questionList.joinToString(" , ")
            val question  = if (fieldsStr == "Account_Type")
                "Which account do you want to open, Saving Account or Current Account?"
            else "Can you please specify the $fieldsStr to complete this transaction?"
            updated["question"] = question
            updated["response"] = question
        } else {
            updated["question"] = null
            updated["response"] = null
        }
        return updated
    }

    fun fullJsonOneGoRenew(response: MutableMap<String, Any?>): MutableMap<String, Any?> {
        response["mandatory_field"] ?: return response
        val updated = newAccountFlow1(response)
        cleanMandatoryFields(updated)
        return updated
    }
}

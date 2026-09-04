package com.kiya.bankinggenie.dbu

class GenAiEngine(private val ragEngine: RagEngine, private val gemma: GemmaEngine) {
    fun getResponseFromGenAi(userQuery: String, botName: String = ""): Map<String, String?> {
        val ragAnswer = ragEngine.askQuestion(userQuery)
            .takeIf { it.isNotBlank() && it != "I don't know." }
            ?: gemma.chat(
                system      = "You are a helpful banking assistant. Answer the user's query clearly and concisely.",
                userMessage = userQuery
            )
        return mapOf("msgType" to "quickReply", "content" to ragAnswer, "msgid" to "text")
    }
}

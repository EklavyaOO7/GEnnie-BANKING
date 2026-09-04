package com.kiya.bankinggenie.dbu

import java.util.Locale

class RelevanceChecker(private val gemma: GemmaEngine) {

    private val TAG = "RelevanceChecker"

    private val CONCEPT_PATTERNS = mapOf(
        "transaction" to listOf(
            "transaction", "transactions", "txn", "txns", "statement", "history",
            "record", "records", "activity", "activities", "movement", "movements",
            "show", "list", "display", "get", "fetch", "find", "give me", "tell me"
        ),
        "debit" to listOf(
            "spent", "spend", "spending", "expense", "expenses", "expenditure",
            "paid", "pay", "payment", "payments", "withdraw", "withdrawal", "withdrawals",
            "debit", "debits", "purchase", "purchases", "cost", "costs", "charged",
            "outflow", "outgoing", "money out", "bill", "bills", "fee", "fees"
        ),
        "credit" to listOf(
            "income", "received", "receive", "deposit", "deposits", "salary", "salaries",
            "wages", "refund", "refunds", "dividend", "dividends", "credited", "credit",
            "credits", "earnings", "earning", "inflow", "incoming", "money in",
            "transfer in", "allowance", "bonus", "commission"
        ),
        "balance" to listOf(
            "balance", "balances", "current balance", "remaining balance",
            "available balance", "closing balance", "opening balance", "net"
        ),
        "date" to listOf(
            "today", "yesterday", "date", "daily", "week", "weekly", "month", "monthly",
            "year", "yearly", "annual", "annually", "last month", "this month",
            "last year", "this year", "last week", "this week", "recent", "latest",
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december",
            "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
            "q1", "q2", "q3", "q4", "quarter", "quarterly", "past", "previous", "prior"
        ),
        "account" to listOf(
            "account", "accounts", "account number", "bank account", "my account"
        ),
        "analytics" to listOf(
            "total", "sum", "how much", "how many", "count", "average", "avg",
            "highest", "lowest", "top", "most", "least", "maximum", "minimum",
            "max", "min", "compare", "comparison", "breakdown", "summary",
            "report", "analysis", "trend", "trends", "chart", "graph",
            "percentage", "percent", "ratio", "more than", "less than", "between"
        )
    )

    private val UNRELATED_PATTERNS = listOf(
        "weather", "football score", "cricket score", "movie review", "song lyrics",
        "write a poem", "write a story", "joke", "recipe", "python code", "java code",
        "capital of", "president of", "politics", "news today",
        "who is", "what is the meaning", "translate", "define ", "how to cook",
        "sports", "stock market", "cryptocurrency", "bitcoin"
    )

    fun isSqlRelated(question: String): Boolean {
        AppLogger.info(TAG, "Relevance check: $question")
        val normalized = question.trim().replace(Regex("\\s+"), " ")
        if (normalized.length < 2) return false
        val lowered = normalized.lowercase(Locale.US)
        for (pattern in UNRELATED_PATTERNS) {
            if (pattern in lowered) {
                AppLogger.warn(TAG, "Unrelated pattern matched: $pattern")
                return false
            }
        }
        for ((_, patterns) in CONCEPT_PATTERNS) {
            if (patterns.any { it in lowered }) {
                AppLogger.info(TAG, "Schema concept matched — RELEVANT")
                return true
            }
        }
        // Fallback to LLM only if no concept matched
        val prompt = "Banking app. Does this question relate to bank transactions, balance, spending, income, or account history? Answer YES or NO only.\nQuestion: $normalized\nAnswer:"
        val result = gemma.generate(prompt = prompt, maxTokens = 5).trim().uppercase(Locale.US)
        AppLogger.info(TAG, "LLM relevance: $result")
        if (result.startsWith("YES")) return true
        if (result.startsWith("NO"))  return false
        val match = Regex("\\b(YES|NO)\\b").find(result)
        return match?.groupValues?.get(1) != "NO"
    }
}

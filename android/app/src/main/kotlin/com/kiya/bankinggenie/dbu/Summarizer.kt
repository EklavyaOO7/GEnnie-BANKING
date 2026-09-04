package com.kiya.bankinggenie.dbu

class Summarizer(private val gemma: GemmaEngine) {

    private val TAG = "Summarizer"

    fun summarize(question: String, columns: List<String>, rows: List<List<Any?>>): String {
        if (rows.isEmpty()) return "No matching transaction data was found."
        val total = rows.size

        if (total == 1 && columns.size == 1) {
            val col = columns[0].lowercase()
            val value = rows[0].getOrNull(0)?.toString() ?: ""
            return when {
                col.contains("balance")      -> "Current balance: \u20b9$value"
                col.contains("total_debit")  -> "Total debits: \u20b9$value"
                col.contains("total_credit") -> "Total credits: \u20b9$value"
                col.contains("total_amount") -> "Total amount: \u20b9$value"
                col.contains("avg")          -> "Average balance: \u20b9$value"
                else                         -> "${columns[0]}: $value"
            }
        }

        if (total > 20) return buildStaticSummary(columns, rows, total)

        val tableText = buildString {
            appendLine(columns.joinToString(" | "))
            appendLine(columns.joinToString("-+-") { "-".repeat(it.length) })
            rows.forEach { row -> appendLine(columns.indices.joinToString(" | ") { i -> row.getOrNull(i)?.toString() ?: "" }) }
        }

        val prompt = buildString {
            appendLine("You are a bank statement assistant. Answer the question using ONLY the exact numbers in the table below.")
            appendLine("Rules: 1) Use only values from the table. 2) No advice or tips. 3) No extra explanation. 4) 1-3 sentences max. 5) Use \u20b9 for amounts.")
            appendLine()
            appendLine("Question: ${question.trim()}")
            appendLine()
            appendLine("Data:")
            append(tableText)
            appendLine()
            appendLine("Answer:")
        }

        AppLogger.info(TAG, "Generating LLM summary | rows=$total")
        return try {
            gemma.generate(prompt = prompt)
                .replace("$", "\u20b9")
                .replace(Regex("^(Sure[,.]?|Here is|Here's|Certainly[,.]?|Of course[,.]?|Based on)[^\n]*\n?", RegexOption.IGNORE_CASE), "")
                .trim()
                .also { AppLogger.debug(TAG, "LLM summary: $it") }
        } catch (e: Exception) {
            AppLogger.warn(TAG, "Summary LLM failed: ${e.message}")
            buildStaticSummary(columns, rows, total)
        }
    }

    private fun buildStaticSummary(columns: List<String>, rows: List<List<Any?>>, total: Int): String {
        val idx = { col: String -> columns.indexOfFirst { it.equals(col, true) } }
        val get = { col: String -> rows.firstOrNull()?.getOrNull(idx(col))?.toString() }

        val debitIdx  = columns.indexOfFirst { it.lowercase().contains("total_debit") }
        val creditIdx = columns.indexOfFirst { it.lowercase().contains("total_credit") }
        if (debitIdx >= 0 && creditIdx >= 0) {
            val totalDebit  = rows.sumOf { it.getOrNull(debitIdx)?.toString()?.toDoubleOrNull()  ?: 0.0 }
            val totalCredit = rows.sumOf { it.getOrNull(creditIdx)?.toString()?.toDoubleOrNull() ?: 0.0 }
            return "Total debits: \u20b9${String.format("%.2f", totalDebit)} | Total credits: \u20b9${String.format("%.2f", totalCredit)}"
        }

        val periodIdx = columns.indexOfFirst { it.lowercase() == "month" || it.lowercase() == "year" }
        if (periodIdx >= 0) {
            val numCol = columns.firstOrNull { c ->
                c.lowercase() != "month" && c.lowercase() != "year" &&
                rows.mapNotNull { it.getOrNull(columns.indexOf(c)) }.all { it is Long || it is Double }
            }
            val numIdx = if (numCol != null) columns.indexOf(numCol) else -1
            val first  = rows.firstOrNull()?.getOrNull(periodIdx)?.toString() ?: ""
            val last   = rows.lastOrNull()?.getOrNull(periodIdx)?.toString() ?: ""
            val period = if (first == last) first else "$first to $last"
            val grandTotal = if (numIdx >= 0) rows.sumOf { it.getOrNull(numIdx)?.toString()?.toDoubleOrNull() ?: 0.0 } else 0.0
            val label = numCol?.replace("_", " ") ?: ""
            return "${rows.size} months | Period: $period | Total $label: \u20b9${String.format("%.2f", grandTotal)}"
        }

        val descIdx  = idx("description")
        val totalIdx = idx("total")
        if (descIdx >= 0 && totalIdx >= 0) {
            val top3 = rows.take(3).joinToString(", ") { row ->
                val desc = row.getOrNull(descIdx)?.toString() ?: ""
                val amt  = row.getOrNull(totalIdx)?.toString()?.toDoubleOrNull()
                if (amt != null) "$desc (\u20b9${String.format("%.0f", amt)})" else desc
            }
            return "Top ${rows.size} results. Leading: $top3"
        }

        val parts = mutableListOf<String>()
        if (total > 1) parts.add("$total transactions found.")
        get("txn_date")?.let    { parts.add("Date: $it") }
        get("description")?.let { parts.add("Description: $it") }
        get("type")?.let        { parts.add("Type: $it") }
        get("amount")?.let      { parts.add("Amount: \u20b9$it") }
        get("balance")?.let     { parts.add("Balance: \u20b9$it") }
        return parts.joinToString(" | ")
    }
}

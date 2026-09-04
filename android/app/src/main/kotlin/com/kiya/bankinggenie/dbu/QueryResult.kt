package com.kiya.bankinggenie.dbu

data class QueryResult(
    val sql: String?,
    val columns: List<String>?,
    val rows: List<List<Any?>>?,
    val summary: String,
    val chart: ChartMeta?,
    val figure: Any?,
    val tableHtml: String?
)

data class ChartMeta(
    val type: String,
    val reason: String
)

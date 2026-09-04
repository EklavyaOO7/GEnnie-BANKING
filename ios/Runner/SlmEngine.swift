import Foundation
import SQLite3

private let TAG = "SlmEngine"

struct QueryResult {
    let sql: String?
    let summary: String
    let tableHtml: String?
    let columns: [String]?
    let rows: [[String?]?]?
}

final class SlmEngine {

    private let modelsDir: URL
    private let gemma: GemmaEngine
    private var embedder: SlmEmbedder?
    private var db: OpaquePointer?
    private var metaRows: [(question: String, sql: String, embedding: [Float])] = []
    private let log = AppLogger.shared

    private static let FORBIDDEN = ["insert", "update", "delete", "drop", "alter", "create"]

    init(modelsDir: URL, gemma: GemmaEngine) throws {
        self.modelsDir = modelsDir
        self.gemma = gemma
    }

    func initialize() throws {
        embedder = try SlmEmbedder(modelsDir: modelsDir)
        try loadMeta()
        try openDb()
        log.info(TAG, "SlmEngine initialized | meta=\(metaRows.count) rows")
    }

    func runQuery(question: String) throws -> QueryResult {
        guard let embedder = embedder else {
            throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "Not initialized"])
        }

        let qEmb = try embedder.encode(question)
        let best = metaRows.max(by: { embedder.cosineSimilarity($0.embedding, qEmb) < embedder.cosineSimilarity($1.embedding, qEmb) })

        let systemPrompt = "You are a SQL expert. Return only valid SQLite SELECT SQL. No explanation."
        let userPrompt = best.map { "Example: \($0.question) → \($0.sql)\n\nQuestion: \(question)" } ?? question
        var sql = gemma.chat(system: systemPrompt, userMessage: userPrompt)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if sql.isEmpty {
            return QueryResult(sql: nil, summary: "Model not ready. Please download models.", tableHtml: nil, columns: nil, rows: nil)
        }

        let lower = sql.lowercased()
        for word in SlmEngine.FORBIDDEN {
            if lower.contains(word) {
                return QueryResult(sql: sql, summary: "Query blocked: contains forbidden keyword '\(word)'.", tableHtml: nil, columns: nil, rows: nil)
            }
        }

        return try executeSQL(sql: sql)
    }

    private func executeSQL(sql: String) throws -> QueryResult {
        guard let db = db else {
            throw NSError(domain: TAG, code: 2, userInfo: [NSLocalizedDescriptionKey: "Database not open"])
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: TAG, code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }

        let colCount = Int(sqlite3_column_count(stmt))
        var columns: [String] = []
        for i in 0..<colCount {
            columns.append(String(cString: sqlite3_column_name(stmt, Int32(i))))
        }

        var rows: [[String?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String?] = []
            for i in 0..<colCount {
                if sqlite3_column_type(stmt, Int32(i)) == SQLITE_NULL {
                    row.append(nil)
                } else {
                    row.append(String(cString: sqlite3_column_text(stmt, Int32(i))))
                }
            }
            rows.append(row)
        }

        let summary = rows.isEmpty ? "No results found." : "\(rows.count) row(s) returned."
        return QueryResult(sql: sql, summary: summary, tableHtml: nil, columns: columns, rows: rows)
    }

    private func loadMeta() throws {
        let csvPath = modelsDir.appendingPathComponent("TB_Statement_meta.csv")
        guard FileManager.default.fileExists(atPath: csvPath.path) else { return }
        guard let embedder = embedder else { return }
        let content = try String(contentsOf: csvPath, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").dropFirst()
        for line in lines {
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 2 else { continue }
            let question = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let sql = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if question.isEmpty || sql.isEmpty { continue }
            if let emb = try? embedder.encode(question) {
                metaRows.append((question: question, sql: sql, embedding: emb))
            }
        }
    }

    private func openDb() throws {
        let dbPath = modelsDir.appendingPathComponent("banking.db").path
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw NSError(domain: TAG, code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot open database"])
        }
    }

    func close() {
        embedder?.close()
        if let db = db { sqlite3_close(db) }
        db = nil
    }
}

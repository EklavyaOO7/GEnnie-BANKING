import Foundation
import os.log

/// Mirrors AppLogger.kt — file-based rotating logger.
/// Logs go to <AppSupport>/logs/app.log
final class AppLogger {

    static let shared = AppLogger()
    private init() {}

    private let maxBytes: Int64 = 5 * 1024 * 1024
    private let maxBackups = 3
    private lazy var logFile: URL? = {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app.log")
    }()

    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func debug(_ tag: String, _ msg: String) { write("DEBUG", tag, msg) }
    func info(_ tag: String, _ msg: String)  { write("INFO ", tag, msg) }
    func warn(_ tag: String, _ msg: String)  { write("WARN ", tag, msg) }
    func error(_ tag: String, _ msg: String) { write("ERROR", tag, msg) }

    private func write(_ level: String, _ tag: String, _ msg: String) {
        guard let url = logFile else { return }
        rotate(url)
        let line = "\(fmt.string(from: Date())) | \(level) | \(tag) | \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func rotate(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64, size >= maxBytes else { return }
        let dir = url.deletingLastPathComponent()
        for i in stride(from: maxBackups - 1, through: 1, by: -1) {
            let old = dir.appendingPathComponent("app.log.\(i)")
            let new = dir.appendingPathComponent("app.log.\(i + 1)")
            if FileManager.default.fileExists(atPath: old.path) {
                try? FileManager.default.moveItem(at: old, to: new)
            }
        }
        try? FileManager.default.moveItem(at: url, to: dir.appendingPathComponent("app.log.1"))
    }
}

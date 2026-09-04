import Flutter
import Foundation

private let TAG = "SlmPlugin"
private let CHANNEL = "com.kiya.bankinggenie/slm"

/// iOS implementation of the SLM MethodChannel.
/// Mirrors SlmPlugin.kt — handles checkModel, downloadModels, init, initSlm, querySlm, closeSlm.
final class SlmPlugin: NSObject {

    private var channel: FlutterMethodChannel?
    private var modelsDir: URL
    private var gemmaEngine: GemmaEngine?
    private var slmEngine: SlmEngine?
    private let queue = DispatchQueue(label: "com.kiya.bankinggenie.slm", qos: .userInitiated)
    private let log = AppLogger.shared

    static let modelFiles = [
        "all-MiniLM-L12-v2_quantized.onnx",
        "vocab.txt",
        "gemma-4-E2B-it.litertlm",
        "TB_Statement_meta.csv",
    ]

    // MARK: - Registration

    static func register(with messenger: FlutterBinaryMessenger) {
        let instance = SlmPlugin()
        let ch = FlutterMethodChannel(name: CHANNEL, binaryMessenger: messenger)
        instance.channel = ch
        ch.setMethodCallHandler { [weak instance] call, result in
            instance?.handle(call, result: result)
        }
    }

    // MARK: - Init

    override init() {
        // Store models in <AppSupport>/models/
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDir = support.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        super.init()
    }

    // MARK: - Method dispatch

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        log.info(TAG, "onMethodCall: \(call.method)")
        switch call.method {
        case "checkModel":     queue.async { self.checkModel(result: result) }
        case "downloadModels": queue.async { self.downloadModels(call: call, result: result) }
        case "init":           queue.async { self.doInit(result: result) }
        case "initSlm":        queue.async { self.doInitSlm(result: result) }
        case "querySlm":       queue.async { self.doQuerySlm(call: call, result: result) }
        case "closeSlm":       queue.async { self.doCloseSlm(result: result) }
        default:               result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - checkModel

    private func checkModel(result: @escaping FlutterResult) {
        for name in SlmPlugin.modelFiles {
            let f = modelsDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: f.path),
                  (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 else {
                log.warn(TAG, "checkModel: MISSING \(name)")
                DispatchQueue.main.async { result(false) }
                return
            }
        }
        log.info(TAG, "checkModel: all present")
        DispatchQueue.main.async { result(true) }
    }

    // MARK: - downloadModels

    private func downloadModels(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urls = args["urls"] as? [String: String] else {
            DispatchQueue.main.async { result(FlutterError(code: "NO_URLS", message: "urls argument missing", details: nil)) }
            return
        }
        let total = SlmPlugin.modelFiles.count
        do {
            for (i, name) in SlmPlugin.modelFiles.enumerated() {
                guard let urlStr = urls[name] else {
                    DispatchQueue.main.async { result(FlutterError(code: "MISSING_URL", message: "No URL for \(name)", details: nil)) }
                    return
                }
                log.info(TAG, "Downloading [\(i+1)/\(total)] \(name)")
                try downloadFile(urlStr: urlStr, dest: modelsDir.appendingPathComponent(name)) { filePct in
                    let totalPct = Int((Double(i * 100 + filePct) / Double(total)))
                    DispatchQueue.main.async {
                        self.channel?.invokeMethod("onProgress", arguments: [
                            "file": name,
                            "fileProgress": filePct,
                            "totalProgress": totalPct,
                        ])
                    }
                }
                log.info(TAG, "Done [\(i+1)/\(total)] \(name)")
            }
            DispatchQueue.main.async { result(true) }
        } catch {
            log.error(TAG, "downloadModels error: \(error)")
            DispatchQueue.main.async { result(FlutterError(code: "DOWNLOAD_ERROR", message: error.localizedDescription, details: nil)) }
        }
    }

    private func downloadFile(urlStr: String, dest: URL, onProgress: @escaping (Int) -> Void) throws {
        guard let url = URL(string: urlStr) else { throw NSError(domain: TAG, code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]) }
        let tmp = dest.deletingLastPathComponent().appendingPathComponent(dest.lastPathComponent + ".tmp")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let semaphore = DispatchSemaphore(value: 0)
        var downloadError: Error?

        let session = URLSession(configuration: .default)
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue("BankingGenie/1.0", forHTTPHeaderField: "User-Agent")

        let task = session.downloadTask(with: request) { tmpUrl, response, error in
            defer { semaphore.signal() }
            if let error = error { downloadError = error; return }
            guard let tmpUrl = tmpUrl else { downloadError = NSError(domain: TAG, code: 1, userInfo: nil); return }
            try? FileManager.default.moveItem(at: tmpUrl, to: tmp)
        }
        task.resume()
        semaphore.wait()

        if let error = downloadError { throw error }
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.moveItem(at: tmp, to: dest)
        onProgress(100)
    }

    // MARK: - init (load GemmaEngine)

    private func doInit(result: @escaping FlutterResult) {
        do {
            log.info(TAG, "init() — loading GemmaEngine from \(modelsDir.path)")
            if gemmaEngine == nil { gemmaEngine = GemmaEngine(modelsDir: modelsDir) }
            let gemmaReady = gemmaEngine?.isReady ?? false
            log.info(TAG, "init() SUCCESS | gemmaReady=\(gemmaReady)")
            DispatchQueue.main.async { result(["gemmaReady": gemmaReady]) }
        }
    }

    // MARK: - initSlm

    private func doInitSlm(result: @escaping FlutterResult) {
        guard let gemma = gemmaEngine else {
            DispatchQueue.main.async { result(FlutterError(code: "NOT_INIT", message: "Call init() before initSlm()", details: nil)) }
            return
        }
        do {
            if slmEngine == nil { slmEngine = try SlmEngine(modelsDir: modelsDir, gemma: gemma) }
            try slmEngine?.initialize()
            log.info(TAG, "initSlm() SUCCESS")
            DispatchQueue.main.async { result(nil) }
        } catch {
            log.error(TAG, "initSlm() FAILED: \(error)")
            DispatchQueue.main.async { result(FlutterError(code: "INIT_SLM_ERROR", message: error.localizedDescription, details: nil)) }
        }
    }

    // MARK: - querySlm

    private func doQuerySlm(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let engine = slmEngine else {
            DispatchQueue.main.async { result(FlutterError(code: "SLM_NOT_INIT", message: "SLM not initialized", details: nil)) }
            return
        }
        guard let question = call.arguments as? String else {
            DispatchQueue.main.async { result(FlutterError(code: "BAD_ARGS", message: "Expected string question", details: nil)) }
            return
        }
        log.info(TAG, "querySlm() question=\"\(question)\"")
        do {
            let qr = try engine.runQuery(question: question)
            var map: [String: Any?] = [
                "sql":       qr.sql as Any?,
                "summary":   qr.summary,
                "tableHtml": qr.tableHtml as Any?,
                "chartImage": nil,
                "columns":   qr.columns as Any?,
                "rows":      qr.rows?.map { row in row.map { $0.map { "\($0)" } } } as Any?,
            ]
            log.info(TAG, "querySlm() done | summary=\(qr.summary)")
            DispatchQueue.main.async { result(map) }
        } catch {
            log.error(TAG, "querySlm() FAILED: \(error)")
            DispatchQueue.main.async { result(FlutterError(code: "QUERY_ERROR", message: error.localizedDescription, details: nil)) }
        }
    }

    // MARK: - closeSlm

    private func doCloseSlm(result: @escaping FlutterResult) {
        slmEngine?.close()
        slmEngine = nil
        log.info(TAG, "closeSlm() done")
        DispatchQueue.main.async { result(nil) }
    }
}

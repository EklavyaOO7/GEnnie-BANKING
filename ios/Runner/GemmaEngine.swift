import Foundation

// LiteRT-LM iOS SDK is added via Swift Package Manager:
// https://github.com/google-ai-edge/LiteRT-LM  (package: LiteRTLM)
// After adding the SPM package, uncomment the import below.
// import LiteRTLM

private let TAG = "GemmaEngine"
private let MODEL_FILENAME = "gemma-4-E2B-it.litertlm"

/// Wraps the LiteRT-LM Engine for Gemma inference on iOS.
/// Mirrors GemmaEngine.kt 1:1.
final class GemmaEngine {

    // MARK: - Private state
    // Typed as Any? so the file compiles before the SPM package is added.
    // Replace with `private var engine: Engine?` once LiteRTLM is imported.
    private var engine: Any?
    private let log = AppLogger.shared

    // MARK: - Init
    init(modelsDir: URL) {
        let modelFile = modelsDir.appendingPathComponent(MODEL_FILENAME)
        log.info(TAG, "LiteRT model path: \(modelFile.path) | exists=\(FileManager.default.fileExists(atPath: modelFile.path))")

        guard FileManager.default.fileExists(atPath: modelFile.path) else {
            log.warn(TAG, "✘ Model file not found — GemmaEngine disabled")
            return
        }

        // ── Uncomment after adding LiteRTLM via SPM ──────────────────────
        // do {
        //     let cfg = EngineConfig(modelPath: modelFile.path, maxNumTokens: 1024)
        //     let eng = try Engine(config: cfg)
        //     try eng.initialize()
        //     engine = eng
        //     log.info(TAG, "✔ LiteRT engine loaded")
        // } catch {
        //     log.error(TAG, "✘ LiteRT load failed: \(error)")
        // }
        // ─────────────────────────────────────────────────────────────────

        log.warn(TAG, "LiteRTLM SPM package not yet linked — add via Xcode > File > Add Package Dependencies")
    }

    // MARK: - Public API

    var isReady: Bool { engine != nil }

    /// Generates a response for the given prompt.
    /// Mirrors GemmaEngine.generate(prompt:system:maxTokens:)
    func generate(prompt: String, system: String = "", maxTokens: Int = 300) -> String {
        guard engine != nil else { return "" }

        // ── Uncomment after adding LiteRTLM via SPM ──────────────────────
        // guard let eng = engine as? Engine else { return "" }
        // let fullPrompt: String
        // if !system.isEmpty {
        //     fullPrompt = "<start_of_turn>user\n\(system)\n\n\(prompt)<end_of_turn>\n<start_of_turn>model\n"
        // } else {
        //     fullPrompt = "<start_of_turn>user\n\(prompt)<end_of_turn>\n<start_of_turn>model\n"
        // }
        // let samplerConfig = SamplerConfig(topK: 40, topP: 0.95, temperature: 0.8)
        // let conv = try? eng.createConversation(config: ConversationConfig(samplerConfig: samplerConfig))
        // defer { try? conv?.close() }
        // return (try? conv?.sendMessage(fullPrompt))?.contents?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // ─────────────────────────────────────────────────────────────────
        return ""
    }

    func chat(system: String, userMessage: String) -> String {
        return generate(prompt: userMessage, system: system)
    }

    func close() {
        // engine?.close()
        engine = nil
    }
}

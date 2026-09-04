import Foundation

#if canImport(onnxruntime_objc)
import onnxruntime_objc
#endif

private let TAG = "SlmEmbedder"
private let MAX_SEQ_LEN = 128
private let UNK_ID: Int64 = 100
private let CLS_ID: Int64 = 101
private let SEP_ID: Int64 = 102
private let PAD_ID: Int64 = 0

final class SlmEmbedder {

    private let vocab: [String: Int]
    private let log = AppLogger.shared

#if canImport(onnxruntime_objc)
    private let env: ORTEnv
    private let session: ORTSession

    init(modelsDir: URL) throws {
        log.info(TAG, "Loading vocab from \(modelsDir.path)/vocab.txt")
        vocab = try SlmEmbedder.loadVocab(modelsDir: modelsDir)
        log.info(TAG, "Vocab loaded — \(vocab.count) tokens")

        let modelPath = modelsDir.appendingPathComponent("all-MiniLM-L12-v2_quantized.onnx").path
        log.info(TAG, "Loading ONNX model from \(modelPath)")

        env = try ORTEnv(loggingLevel: .warning)
        let opts = try ORTSessionOptions()
        try opts.setIntraOpNumThreads(2)
        session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: opts)
        log.info(TAG, "ONNX session created")
    }

    func encode(_ text: String) throws -> [Float] {
        let tokens = tokenize(text)

        var inputIds      = [Int64](repeating: PAD_ID, count: MAX_SEQ_LEN)
        var attentionMask = [Int64](repeating: 0,      count: MAX_SEQ_LEN)
        var tokenTypeIds  = [Int64](repeating: 0,      count: MAX_SEQ_LEN)

        inputIds[0] = CLS_ID; attentionMask[0] = 1
        let len = min(tokens.count, MAX_SEQ_LEN - 2)
        for i in 0..<len {
            inputIds[i + 1] = tokens[i]
            attentionMask[i + 1] = 1
        }
        inputIds[len + 1] = SEP_ID; attentionMask[len + 1] = 1

        let shape: [NSNumber] = [1, NSNumber(value: MAX_SEQ_LEN)]
        let tIds  = try makeTensor(inputIds,      shape: shape)
        let tMask = try makeTensor(attentionMask, shape: shape)
        let tType = try makeTensor(tokenTypeIds,  shape: shape)

        let inputs: [String: ORTValue] = [
            "input_ids":      tIds,
            "attention_mask": tMask,
            "token_type_ids": tType,
        ]

        let outputs = try session.run(
            withInputs: inputs,
            outputNames: ["last_hidden_state"],
            runOptions: nil
        )

        guard let hiddenValue = outputs["last_hidden_state"] else {
            throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing last_hidden_state output"])
        }

        let tensorData = try hiddenValue.tensorData() as Data
        let hiddenSize = tensorData.count / MemoryLayout<Float>.size / MAX_SEQ_LEN
        var floats = [Float](repeating: 0, count: MAX_SEQ_LEN * hiddenSize)
        _ = floats.withUnsafeMutableBytes { tensorData.copyBytes(to: $0) }

        var embedding = [Float](repeating: 0, count: hiddenSize)
        var count = 0
        for i in 0..<MAX_SEQ_LEN {
            guard attentionMask[i] == 1 else { continue }
            let offset = i * hiddenSize
            for j in 0..<hiddenSize { embedding[j] += floats[offset + j] }
            count += 1
        }
        if count > 0 {
            let cf = Float(count)
            for j in 0..<hiddenSize { embedding[j] /= cf }
        }

        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 1e-10 {
            for j in 0..<hiddenSize { embedding[j] /= norm }
        }
        return embedding
    }

    private func makeTensor(_ ids: [Int64], shape: [NSNumber]) throws -> ORTValue {
        let data = ids.withUnsafeBytes { Data($0) }
        return try ORTValue(
            tensorData: NSMutableData(data: data),
            elementType: .int64,
            shape: shape
        )
    }

#else
    // ONNX runtime not available — stub for compilation only
    init(modelsDir: URL) throws {
        log.warn(TAG, "onnxruntime_objc not available — SlmEmbedder disabled")
        vocab = try SlmEmbedder.loadVocab(modelsDir: modelsDir)
    }

    func encode(_ text: String) throws -> [Float] {
        throw NSError(domain: TAG, code: 99, userInfo: [NSLocalizedDescriptionKey: "ONNX runtime not available"])
    }
#endif

    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i] }
        return dot
    }

    func close() {}

    // MARK: - Tokenisation (BERT WordPiece)

    private func tokenize(_ text: String) -> [Int64] {
        let lower = text.lowercased()
        var words: [String] = []
        var current = ""
        for ch in lower {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else {
                if !current.isEmpty { words.append(current); current = "" }
                let s = String(ch)
                if !s.trimmingCharacters(in: .whitespaces).isEmpty { words.append(s) }
            }
        }
        if !current.isEmpty { words.append(current) }
        var ids: [Int64] = []
        for word in words { ids.append(contentsOf: wordPieceTokenize(word)) }
        return ids
    }

    private func wordPieceTokenize(_ word: String) -> [Int64] {
        if let id = vocab[word] { return [Int64(id)] }
        var pieces: [Int64] = []
        var start = word.startIndex
        while start < word.endIndex {
            var end = word.endIndex
            var found = false
            while start < end {
                let sub = start == word.startIndex
                    ? String(word[start..<end])
                    : "##" + String(word[start..<end])
                if let id = vocab[sub] {
                    pieces.append(Int64(id))
                    start = end
                    found = true
                    break
                }
                end = word.index(before: end)
            }
            if !found { return [UNK_ID] }
        }
        return pieces
    }

    private static func loadVocab(modelsDir: URL) throws -> [String: Int] {
        let vocabPath = modelsDir.appendingPathComponent("vocab.txt")
        let content = try String(contentsOf: vocabPath, encoding: .utf8)
        var map: [String: Int] = [:]
        var idx = 0
        for line in content.components(separatedBy: "\n") {
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { map[token] = idx }
            idx += 1
        }
        return map
    }
}

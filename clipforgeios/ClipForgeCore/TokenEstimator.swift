import Foundation

// MARK: - 费用 / Token 估算

enum TokenEstimator {

    struct Rate {
        let priceValue: Double
        let priceUnit: String
        let tokenPerUnit: Double
        let billedBy: Billable
    }

    enum Billable {
        case chars(Int)
        case videoSeconds(Int, String)
        case voiceClone(Double?)
    }

    struct Estimate {
        let model: String
        let action: String
        let tokenMin: Int
        let tokenEst: Int
        let tokenMax: Int
        let amount: String
        let detail: String

        var tokenRangeText: String { "\(fmt(tokenMin))–\(fmt(tokenMax)) token" }
        var tokenEstText: String { fmt(tokenEst) }

        private func fmt(_ n: Int) -> String {
            if n >= 1_000_000 { return String(format: "%.1f万", Double(n) / 1_000_000) }
            if n >= 10_000   { return String(format: "%.1f万", Double(n) / 10_000) }
            return "\(n)"
        }
    }

    private static let costTable: [String: Rate] = [
        FixedModel.tts: Rate(
            priceValue: 1.5, priceUnit: "元/万字符",
            tokenPerUnit: 15_000,
            billedBy: .chars(0)),
        FixedModel.voiceEnrollment: Rate(
            priceValue: 0, priceUnit: "随训练/合成出账",
            tokenPerUnit: 0,
            billedBy: .voiceClone(nil)),
        FixedModel.videoI2V: Rate(
            priceValue: 0.6, priceUnit: "元/秒(720P)",
            tokenPerUnit: 120_000,
            billedBy: .videoSeconds(0, "720P")),
        FixedModel.embedding: Rate(
            priceValue: 0.000125, priceUnit: "元/千token",
            tokenPerUnit: 1_000,
            billedBy: .chars(0)),
    ]

    private static let videoRates: [String: [Double]] = [
        "wan2.6-i2v":       [0.6, 1.0, 0.6, 1.0],
        "wan2.7-i2v":       [0.6, 1.0, 0.6, 1.0],
        "wan2.6-t2v":       [0.6, 1.0, 0.6, 1.0],
        "wan2.7-t2v":       [0.6, 1.0, 0.6, 1.0],
        "wan2.6-i2v-flash": [0.3, 0.5, 0.15, 0.25],
    ]

    static func videoRate(model: String, resolution: String, audio: Bool) -> Double {
        let t = videoRates[model] ?? [0.6, 1.0, 0.6, 1.0]
        let idx = (resolution == "1080P" ? 1 : 0) + (audio ? 0 : 2)
        return t[idx]
    }

    static func estimateTTS(text: String) -> Estimate {
        let chars = text.count
        let amount = Double(chars) / 10000.0 * (costTable[FixedModel.tts]?.priceValue ?? 1.5)
        let tokenEst = Int(Double(chars) / 10000.0 * (costTable[FixedModel.tts]?.tokenPerUnit ?? 15_000))
        return makeEstimate(model: FixedModel.tts, action: "语音合成",
                            tokenEst: tokenEst, amount: amount,
                            detail: "输入 \(chars) 字符 · ¥1.5/万字符")
    }

    static func estimateVideo(model: String, prompt: String, resolution: String,
                              duration: Int, audio: Bool) -> Estimate {
        let rate = videoRate(model: model, resolution: resolution, audio: audio)
        let amount = rate * Double(duration)
        let tokenPerSecond = Int(120_000 * rate / 0.6)
        let tokenEst = tokenPerSecond * duration
        let audioText = audio ? "有声" : "无声"
        return makeEstimate(model: model, action: FixedModel.videoKindName(model),
                            tokenEst: tokenEst, amount: amount,
                            detail: "\(resolution) · \(duration)s · \(audioText) · ¥\(rateTrunc(rate))/秒")
    }

    static func estimateVoiceClone() -> Estimate {
        makeEstimate(model: FixedModel.voiceEnrollment, action: "声音克隆",
                     tokenEst: nil, amount: nil,
                     detail: "费用随样本训练与首次合成出账，金额波动较大")
    }

    private static func imageRate(forModel model: String) -> Double {
        switch model {
        case "qwen-image-2.0-pro", "wan2.7-image-pro": return 0.5
        default: return 0.2
        }
    }

    static func estimateImage(model: String, size: String, n: Int) -> Estimate {
        let rate = imageRate(forModel: model)
        let amount = rate * Double(n)
        let tokenPerImage = 120_000
        let tokenEst = tokenPerImage * n
        return makeEstimate(model: model, action: "文生图",
                            tokenEst: tokenEst, amount: amount,
                            detail: "\(model) · \(size) · \(n) 张 · ¥\(rateTrunc(rate))/张")
    }

    static let llmInputPricePerK = 0.00096
    static let llmOutputPricePerK = 0.0024

    static func estimateProTotal(kind: PromptKind, embedTokens: Int, genTokens: Int) -> Estimate {
        let rate = costTable[FixedModel.embedding]?.priceValue ?? 0.000125
        let embedAmount = Double(embedTokens) / 1000.0 * rate
        let genIn = 600
        let genAmount = Double(genIn) / 1000.0 * llmInputPricePerK
            + Double(genTokens) / 1000.0 * llmOutputPricePerK
        let amount = embedAmount + genAmount
        let total = embedTokens + genTokens
        return makeEstimate(model: FixedModel.textGeneration, action: "试试手气 Pro",
                            tokenEst: total, amount: amount,
                            detail: "向量选句 ≈\(embedTokens) token（¥0.000125/千）+ "
                                     + "扩写 \(kind.label) ≤\(genTokens) token（输入 ¥0.00096/千 · 输出 ¥0.0024/千）")
    }

    static func embeddingTokens(for texts: [String]) -> Int {
        var n = 0
        for t in texts {
            let scalars = Array(t.unicodeScalars)
            let cjk = scalars.filter { $0.value > 0x2E80 }.count
            n += cjk + (scalars.count - cjk) / 4
        }
        return max(1, n)
    }

    static func estimateEmbedding(tokens: Int, texts: Int = 0) -> Estimate {
        let rate = costTable[FixedModel.embedding]?.priceValue ?? 0.000125
        let amount = Double(tokens) / 1000.0 * rate
        var detail = "输入 ≈\(tokens) token · ¥0.000125/千token"
        if texts > 0 { detail = "\(texts) 条文本 · " + detail }
        return makeEstimate(model: FixedModel.embedding, action: "试试手气 Pro",
                            tokenEst: tokens, amount: amount, detail: detail)
    }

    // MARK: - 内部

    private static func rateTrunc(_ v: Double) -> String {
        v == Double(Int(v)) ? String(Int(v)) : String(v)
    }

    private static func makeEstimate(model: String, action: String,
                                     tokenEst: Int?, amount: Double?, detail: String) -> Estimate {
        let est = tokenEst ?? 0
        let lower = max(0, Int(Double(est) * 0.7))
        let upper = Int(Double(est) * 1.3)

        var amountText: String
        if let a = amount {
            if a >= 0.005 {
                amountText = String(format: "预估金额 ≈ ¥%.2f", a)
            } else if a > 0 {
                amountText = "预估金额 ≈ <¥0.01"
            } else {
                amountText = "预估金额 ≈ ¥0"
            }
        } else {
            amountText = "费用随出账波动（约 ¥0.3–¥2）"
        }
        if est == 0 {
            amountText = "此操作将产生费用，随出账扣除"
        }
        return Estimate(model: model, action: action,
                        tokenMin: lower, tokenEst: est, tokenMax: upper,
                        amount: amountText, detail: detail)
    }
}

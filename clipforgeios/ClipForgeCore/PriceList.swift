import Foundation

// MARK: - 价目表（设置页展示，华北2北京按量付费，仅供参考，以官方账单为准）

struct PriceRow: Identifiable {
    let id = UUID()
    let model: String
    let name: String
    let unit: String
    let price: String
}

enum PriceList {

    static let video: [PriceRow] = [
        PriceRow(model: "wan2.6-t2v",       name: "文生视频", unit: "元/秒",
                 price: "720P ¥0.6 · 1080P ¥1.0"),
        PriceRow(model: "wan2.7-t2v",       name: "文生视频", unit: "元/秒",
                 price: "720P ¥0.6 · 1080P ¥1.0"),
        PriceRow(model: "wan2.6-i2v",       name: "图生视频", unit: "元/秒",
                 price: "720P ¥0.6 · 1080P ¥1.0"),
        PriceRow(model: "wan2.7-i2v",       name: "图生视频", unit: "元/秒",
                 price: "720P ¥0.6 · 1080P ¥1.0"),
        PriceRow(model: "wan2.6-i2v-flash", name: "图生视频·Flash", unit: "元/秒",
                 price: "有声 0.3/0.5 · 无声 0.15/0.25"),
    ]

    static let image: [PriceRow] = [
        PriceRow(model: "qwen-image-2.0",     name: "文生图", unit: "元/张", price: "¥0.20"),
        PriceRow(model: "qwen-image-2.0-pro", name: "文生图", unit: "元/张", price: "¥0.50"),
        PriceRow(model: "wan2.7-image",       name: "文生图", unit: "元/张", price: "¥0.20"),
        PriceRow(model: "wan2.7-image-pro",   name: "文生图", unit: "元/张", price: "¥0.50"),
    ]

    static let audio: [PriceRow] = [
        PriceRow(model: "cosyvoice-v3.5-plus", name: "语音合成", unit: "元/万字符", price: "¥1.50"),
        PriceRow(model: "voice-enrollment",     name: "声音克隆", unit: "按出账",
                 price: "随训练/合成出账"),
    ]

    static let vector: [PriceRow] = [
        PriceRow(model: "qwen3.7-text-embedding-flash", name: "文本向量", unit: "元/千token",
                 price: "¥0.000125"),
        PriceRow(model: "qwen-plus", name: "文本生成", unit: "元/千token",
                 price: "输入 ¥0.00096 · 输出 ¥0.0024"),
    ]
}

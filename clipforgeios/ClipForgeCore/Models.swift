import Foundation
import SwiftUI
import Combine

// MARK: - 固定模型标识（不可更换）

enum FixedModel {
    static let tts = "cosyvoice-v3.5-plus"
    static let voiceEnrollment = "voice-enrollment"
    static let videoI2V = "wan2.6-i2v"
    static let imageDefault = "qwen-image-2.0"
    static let imageModels = ["qwen-image-2.0", "qwen-image-2.0-pro", "wan2.7-image", "wan2.7-image-pro"]

    /// 文本向量化模型（「试试手气 Pro」阶段一：语义选句，按输入 token 计费）
    static let embedding = "qwen3.7-text-embedding-flash"

    /// 文本生成模型（「试试手气 Pro」阶段二：把选中的词库句子扩充成 ~500 字的新提示词）
    static let textGeneration = "qwen-plus"

    /// 视频生成模型
    static let videoModels = ["wan2.6-i2v", "wan2.7-i2v", "wan2.6-i2v-flash", "wan2.7-t2v", "wan2.6-t2v"]

    /// 是否为文生视频（不需要首帧图片）
    static func isTextToVideo(_ m: String) -> Bool { m.hasSuffix("-t2v") }

    /// 中文能力名
    static func videoKindName(_ m: String) -> String {
        isTextToVideo(m) ? "文生视频" : "图生视频"
    }
}

enum DashScope {
    static let httpBase = "https://dashscope.aliyuncs.com/api/v1"
    static let wsBase = "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
}

// MARK: - 应用设置（API Key 可换，存 Keychain）

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var apiKey: String = ""
    @Published var voicePrefix: String = "myvoice"
    @Published var lastSaved: Date? = nil

    private let keyAccount = "clipforge.dashscope.apikey"
    private let serviceName = "ClipForge"

    private init() {
        apiKey = Keychain.read(service: serviceName, account: keyAccount) ?? ""
    }

    func save() {
        Keychain.write(service: serviceName, account: keyAccount, value: apiKey)
        lastSaved = Date()
    }

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
}

enum Keychain {
    /// iOS 适配：afterFirstUnlock（非 ThisDeviceOnly，允许恢复/迁移）+ synchronizable=false（不外泄到 iCloud）
    static func read(service: String, account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(service: String, account: String, value: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

// MARK: - 素材库

struct MediaClip: Identifiable, Hashable {
    enum Kind: String { case video, audio, image
        var symbol: String {
            switch self {
            case .video: return "film"
            case .audio: return "waveform"
            case .image: return "photo"
            }
        }
        var label: String {
            switch self {
            case .video: return "视频"
            case .audio: return "音频"
            case .image: return "图片"
            }
        }
    }
    let id: UUID
    var kind: Kind
    var name: String
    var url: URL
    var addedAt: Date

    init(id: UUID = UUID(), kind: Kind, name: String, url: URL, addedAt: Date = Date()) {
        self.id = id; self.kind = kind; self.name = name; self.url = url; self.addedAt = addedAt
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()
    @Published var clips: [MediaClip] = []
    @Published var order: [UUID] = []

    private init() {}

    func add(_ clip: MediaClip) {
        clips.insert(clip, at: 0)
        order.append(clip.id)
    }

    func remove(_ id: UUID) {
        clips.removeAll { $0.id == id }
        order.removeAll { $0 == id }
    }

    func clip(_ id: UUID) -> MediaClip? { clips.first { $0.id == id } }
}

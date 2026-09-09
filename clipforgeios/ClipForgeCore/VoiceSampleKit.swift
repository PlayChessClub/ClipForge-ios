import Foundation

// MARK: - 音色素材（Voice Samples，纯 Foundation，iOS/mac 通用）
//
// 来源两类：
//   1) 内置样例：随 App 打进 Bundle（Contents/Resources/VoiceSamples/），只读，可试听 / 克隆；
//   2) 素材文件夹：iOS 默认 Documents/VoiceSamples（设置页可改）。
//      「保存副本」把内置样例按用户昵称拷贝到这里；手动放入的 wav/mp3/m4a 作为「用户素材」列出。
// 规则：Bundle 永不写盘；写盘一律走素材文件夹拷贝；文件名净化 + 重名自动 -1。

struct VoiceSample: Identifiable, Equatable {
    let id: String
    let name: String
    let tags: [String]
    let source: String
    let bundleFile: String?

    var isBuiltin: Bool { bundleFile != nil }
    var builtinKey: String? {
        guard id.hasPrefix("builtin-") else { return nil }
        return String(id.dropFirst("builtin-".count))
    }
}

struct ResolvedSample: Identifiable {
    let sample: VoiceSample
    let fileURL: URL
    var materialized: Bool
    var id: String { sample.id }
}

enum VoiceSampleKit {

    // MARK: - 内置样例定义（bundleFile 必须与 App 包内 VoiceSamples/ 下的文件一致）

    struct BuiltinDef {
        let key: String
        let bundleFile: String
        let name: String
        let tags: [String]
        let source: String
    }

    /// 内置样音（mac/iOS 共用）：macOS 系统 say TTS 本机合成素材，无第三方版权。
    static let builtinDefs: [BuiltinDef] = [
        BuiltinDef(key: "zh-male-broadcast",
                   bundleFile: "zh-male-broadcast-reed.wav",
                   name: "沉稳播音男声",
                   tags: ["中文", "男声", "播音"],
                   source: "macOS 系统 TTS（say · Reed）本机合成，可自由作配音/克隆参考"),
        BuiltinDef(key: "zh-female-broadcast",
                   bundleFile: "zh-female-broadcast-sandy.wav",
                   name: "标准播音女声",
                   tags: ["中文", "女声", "播音"],
                   source: "macOS 系统 TTS（say · Sandy）本机合成，可自由作配音/克隆参考"),
    ]

    // MARK: - 持久化 key

    private static let rootKey = "clipforge.voiceMaterialRoot"
    private static let namePrefix = "clipforge.voiceSampleName."
    private static let copyPrefix = "clipforge.voiceSampleCopy."

    // MARK: - 素材文件夹（整体可自定义；只影响将来写入位置，不搬移旧文件）

    static var defaultMaterialRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceSamples", isDirectory: true)
    }

    static var materialRoot: URL {
        if let s = UserDefaults.standard.string(forKey: rootKey), !s.isEmpty {
            return URL(fileURLWithPath: (s as NSString).expandingTildeInPath, isDirectory: true)
        }
        return defaultMaterialRoot
    }

    static var isMaterialRootDefault: Bool {
        materialRoot.standardizedFileURL.path == defaultMaterialRoot.standardizedFileURL.path
    }

    static func setMaterialRoot(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        UserDefaults.standard.set(url.path, forKey: rootKey)
    }

    static func resetMaterialRoot() {
        UserDefaults.standard.removeObject(forKey: rootKey)
    }

    static func materialRootDisplay() -> String {
        abbrev(materialRoot.path)
    }

    static func ensureMaterialDir() {
        try? FileManager.default.createDirectory(at: materialRoot, withIntermediateDirectories: true)
    }

    // MARK: - 昵称

    static func nickname(for sample: VoiceSample) -> String {
        guard let k = sample.builtinKey else { return sample.name }
        let s = UserDefaults.standard.string(forKey: namePrefix + k)
        return (s?.isEmpty ?? true) ? sample.name : s!
    }

    static func setNickname(_ nick: String, for sample: VoiceSample) {
        guard let k = sample.builtinKey else { return }
        let t = nick.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            UserDefaults.standard.removeObject(forKey: namePrefix + k)
            return
        }
        UserDefaults.standard.set(t, forKey: namePrefix + k)
        if let mapped = mappedFileName(for: sample) {
            renameMaterialized(sample, from: mapped, to: t)
        }
    }

    private static func mappedFileName(for sample: VoiceSample) -> String? {
        guard let k = sample.builtinKey else { return nil }
        guard let f = UserDefaults.standard.string(forKey: copyPrefix + k) else { return nil }
        let url = materialRoot.appendingPathComponent(f)
        return FileManager.default.fileExists(atPath: url.path) ? f : nil
    }

    private static func renameMaterialized(_ sample: VoiceSample, from old: String, to newName: String) {
        let fm = FileManager.default
        let oldURL = materialRoot.appendingPathComponent(old)
        guard fm.fileExists(atPath: oldURL.path) else { return }
        let ext = (old as NSString).pathExtension
        let target = uniqueURL(in: materialRoot, base: newName, ext: ext)
        try? fm.moveItem(at: oldURL, to: target)
        if let k = sample.builtinKey {
            UserDefaults.standard.set(target.lastPathComponent, forKey: copyPrefix + k)
        }
    }

    // MARK: - 解析：内置（含落盘状态）+ 素材文件夹里的用户素材

    static func loadSamples() -> [ResolvedSample] {
        ensureMaterialDir()
        let fm = FileManager.default
        var out: [ResolvedSample] = []
        var mappedNames = Set<String>()

        for def in builtinDefs {
            let sample = VoiceSample(id: "builtin-\(def.key)", name: def.name,
                                     tags: def.tags, source: def.source,
                                     bundleFile: def.bundleFile)
            if let mapped = mappedFileName(for: sample) {
                mappedNames.insert(mapped)
                let url = materialRoot.appendingPathComponent(mapped)
                out.append(ResolvedSample(sample: sample, fileURL: url, materialized: true))
                continue
            }
            guard let bundleURL = bundleURL(def.bundleFile) else { continue }
            out.append(ResolvedSample(sample: sample, fileURL: bundleURL, materialized: false))
        }

        if let files = try? fm.contentsOfDirectory(at: materialRoot, includingPropertiesForKeys: nil) {
            let exts: Set<String> = ["wav", "mp3", "m4a", "aac", "caf"]
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard exts.contains(f.pathExtension.lowercased()),
                      !mappedNames.contains(f.lastPathComponent) else { continue }
                let base = f.deletingPathExtension().lastPathComponent
                let sample = VoiceSample(id: "user-\(f.lastPathComponent)", name: base,
                                         tags: ["本地"], source: "用户自备",
                                         bundleFile: nil)
                out.append(ResolvedSample(sample: sample, fileURL: f, materialized: true))
            }
        }
        return out
    }

    private static func bundleURL(_ file: String) -> URL? {
        Bundle.main.url(forResource: file, withExtension: nil)
            ?? Bundle.main.url(forResource: (file as NSString).deletingPathExtension,
                               withExtension: (file as NSString).pathExtension,
                               subdirectory: "VoiceSamples")
    }

    // MARK: - 保存副本到素材文件夹

    @discardableResult
    static func materialize(_ resolved: ResolvedSample) -> URL? {
        let fm = FileManager.default
        ensureMaterialDir()
        let sample = resolved.sample
        guard let k = sample.builtinKey else { return resolved.fileURL }
        if resolved.materialized, let mapped = mappedFileName(for: sample) {
            return materialRoot.appendingPathComponent(mapped)
        }
        let ext = resolved.fileURL.pathExtension.isEmpty ? "wav" : resolved.fileURL.pathExtension
        let target = uniqueURL(in: materialRoot, base: nickname(for: sample), ext: ext)
        do {
            try fm.copyItem(at: resolved.fileURL, to: target)
            UserDefaults.standard.set(target.lastPathComponent, forKey: copyPrefix + k)
            return target
        } catch {
            return nil
        }
    }

    @discardableResult
    static func renameUserFile(_ resolved: ResolvedSample, to newName: String) -> Bool {
        guard !resolved.sample.isBuiltin else { return false }
        let fm = FileManager.default
        let src = resolved.fileURL
        guard fm.fileExists(atPath: src.path) else { return false }
        let ext = src.pathExtension
        let target = uniqueURL(in: materialRoot, base: newName, ext: ext)
        return (try? fm.moveItem(at: src, to: target)) != nil
    }

    // MARK: - 工具

    private static func abbrev(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private static func uniqueURL(in dir: URL, base rawBase: String, ext: String) -> URL {
        let base = sanitize(rawBase)
        let fm = FileManager.default
        var url = dir.appendingPathComponent(base + "." + ext)
        var n = 1
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        return url
    }

    static func sanitize(_ name: String) -> String {
        var t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/:\\")
            .union(.controlCharacters)
        t = t.components(separatedBy: forbidden).joined()
        return t.isEmpty ? "素材" : t
    }
}

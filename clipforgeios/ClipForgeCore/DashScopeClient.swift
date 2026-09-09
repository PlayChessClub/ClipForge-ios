import Foundation

@MainActor
final class DashScopeClient {
    static let shared = DashScopeClient()
    private let session: URLSession
    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 3600
        session = URLSession(configuration: cfg)
    }

    private func key() throws -> String {
        let k = AppSettings.shared.apiKey.trimmingCharacters(in: .whitespaces)
        if k.isEmpty { throw APIError("请先在「设置」中填写 DashScope API Key") }
        return k
    }

    private func authHeaders(extra: [String: String] = [:]) throws -> [String: String] {
        var h = ["Authorization": "Bearer \(try key())"]
        for (k, v) in extra { h[k] = v }
        return h
    }

    // MARK: - OSS 临时上传（供 img_url / audio_url 使用）

    /// 上传本地文件到 DashScope 临时 OSS，返回 oss:// 形式的 URL
    func uploadToOSS(model: String, fileURL: URL) async throws -> String {
        var comp = URLComponents(string: "\(DashScope.httpBase)/uploads")
        comp?.queryItems = [URLQueryItem(name: "action", value: "getPolicy"),
                            URLQueryItem(name: "model", value: model)]
        guard let policyURL = comp?.url else { throw APIError("uploads URL 无效") }
        var req = URLRequest(url: policyURL)
        req.httpMethod = "GET"
        for (k, v) in try authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (pdata, presp) = try await session.data(for: req)
        guard let http = presp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError("获取上传凭证失败：\(String(data: pdata, encoding: .utf8) ?? "HTTP \( (presp as? HTTPURLResponse)?.statusCode ?? -1 )")")
        }
        let policyJson = try JSONSerialization.jsonObject(with: pdata) as? [String: Any] ?? [:]
        guard let output = policyJson["data"] as? [String: Any] ?? policyJson["output"] as? [String: Any] else {
            throw APIError("上传凭证响应缺少 data 字段")
        }
        guard let host = output["upload_host"] as? String,
              let dir = output["upload_dir"] as? String,
              let policy = output["policy"] as? String,
              let sig = output["signature"] as? String,
              let ak = output["oss_access_key_id"] as? String else {
            throw APIError("上传凭证字段不完整")
        }

        let fileName = fileURL.lastPathComponent
        let key = dir + "/" + fileName
        guard let ossURL = URL(string: host) else { throw APIError("upload_host 无效") }
        let boundary = "----ClipForge\(UUID().uuidString)"
        let mime = mimeFor(fileURL)

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("OSSAccessKeyId", ak)
        field("Signature", sig)
        field("policy", policy)
        field("key", key)
        field("x-oss-object-acl", (output["x_oss_object_acl"] as? String) ?? "private")
        field("x-oss-forbid-overwrite", (output["x_oss_object_acl"] as? String) ?? "true")
        field("success_action_status", "200")
        field("x-oss-content-type", mime)
        let fileData = try Data(contentsOf: fileURL)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mime)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        _ = boundary

        var oreq = URLRequest(url: ossURL)
        oreq.httpMethod = "POST"
        oreq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        oreq.setValue("application/json", forHTTPHeaderField: "Accept")
        let (oBody, oResp) = try await session.upload(for: oreq, from: body)
        guard let ohttp = oResp as? HTTPURLResponse, (200..<300).contains(ohttp.statusCode) else {
            throw APIError("上传 OSS 失败：\(String(data: oBody, encoding: .utf8) ?? "HTTP \( (oResp as? HTTPURLResponse)?.statusCode ?? -1 )")")
        }
        return "oss://" + key
    }

    private func mimeFor(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "mp4": return "video/mp4"
        default: return "application/octet-stream"
        }
    }

    // MARK: - 声音复刻 enrollment

    func createVoice(targetModel: String, prefix: String, url: String) async throws -> String {
        let body: [String: Any] = [
            "model": FixedModel.voiceEnrollment,
            "input": ["action": "create_voice", "target_model": targetModel,
                      "prefix": prefix, "url": url],
        ]
        var extra: [String: String] = [:]
        if url.hasPrefix("oss://") { extra["X-DashScope-OssResourceResolve"] = "enable" }
        let json = try await postJSON("\(DashScope.httpBase)/services/audio/tts/customization",
                                      body: body, extra: extra)
        guard let vid = JSONValue.string(json["output"], ["voice_id"]) else {
            throw APIError("创建音色失败：\(json["code"] ?? "") \(json["message"] ?? "")")
        }
        return vid
    }

    func queryVoice(voiceId: String) async throws -> [String: Any] {
        let body: [String: Any] = [
            "model": FixedModel.voiceEnrollment,
            "input": ["action": "query_voice", "voice_id": voiceId],
        ]
        let json = try await postJSON("\(DashScope.httpBase)/services/audio/tts/customization", body: body)
        return json["output"] as? [String: Any] ?? [:]
    }

    func listVoices(prefix: String) async throws -> [[String: Any]] {
        let body: [String: Any] = [
            "model": FixedModel.voiceEnrollment,
            "input": ["action": "list_voice", "prefix": prefix, "page_index": 0, "page_size": 50],
        ]
        let json = try await postJSON("\(DashScope.httpBase)/services/audio/tts/customization", body: body)
        return (json["output"] as? [String: Any])?["voice_list"] as? [[String: Any]] ?? []
    }

    func deleteVoice(voiceId: String) async throws {
        let body: [String: Any] = [
            "model": FixedModel.voiceEnrollment,
            "input": ["action": "delete_voice", "voice_id": voiceId],
        ]
        _ = try await postJSON("\(DashScope.httpBase)/services/audio/tts/customization", body: body)
    }

    // MARK: - 视频生成任务 (wan2.6-i2v)

    struct VideoRequest {
        var model: String = FixedModel.videoI2V
        var prompt: String
        var imageURL: String?          // 文生视频(t2v)不需要首帧图
        var audioURL: String?
        var resolution: String = "720P"
        var duration: Int = 10
        var promptExtend: Bool = true
        var audioEnabled: Bool = true
        var shotType: String = "multi"
    }

    func submitVideoTask(_ r: VideoRequest) async throws -> String {
        var input: [String: Any] = ["prompt": r.prompt]
        if let img = r.imageURL, !img.isEmpty { input["img_url"] = img }
        if let a = r.audioURL { input["audio_url"] = a }
        var params: [String: Any] = [
            "resolution": r.resolution,
            "prompt_extend": r.promptExtend,
            "duration": r.duration,
            "audio": r.audioEnabled,
        ]
        if r.shotType == "multi" { params["shot_type"] = "multi" }
        let body: [String: Any] = ["model": r.model, "input": input, "parameters": params]
        let json = try await postJSON(
            "\(DashScope.httpBase)/services/aigc/video-generation/video-synthesis",
            body: body,
            extra: ["X-DashScope-Async": "enable", "X-DashScope-OssResourceResolve": "enable"])
        guard let tid = JSONValue.string(json["output"], ["task_id"]) else {
            throw APIError("提交视频任务失败：\(json["code"] ?? "") \(json["message"] ?? "")")
        }
        return tid
    }

    struct VideoStatus {
        var state: String
        var videoUrl: String?
        var message: String?
        var raw: [String: Any]
    }

    func pollVideoTask(_ taskId: String) async throws -> VideoStatus {
        let url = URL(string: "\(DashScope.httpBase)/tasks/\(taskId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in try authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        let (data, _) = try await Net.data(req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let out = json["output"] as? [String: Any] ?? [:]
        let state = (out["task_status"] as? String) ?? "UNKNOWN"
        let vurl = JSONValue.string(out, ["video_url"]) ?? JSONValue.string(out, ["results", "0", "url"])
        let msg = out["message"] as? String ?? json["message"] as? String
        return VideoStatus(state: state, videoUrl: vurl, message: msg, raw: json)
    }

    // MARK: - 文生图（同步 multimodal-generation）

    struct ImageRequest {
        var prompt: String
        var model: String = FixedModel.imageDefault
        var size: String = "1024*1024"
        var n: Int = 1
        var promptExtend: Bool = true
        var watermark: Bool = false
    }

    /// 同步生成图片，返回图片 URL 数组
    func submitImage(_ r: ImageRequest) async throws -> [String] {
        let params: [String: Any] = [
            "size": r.size,
            "n": r.n,
            "watermark": r.watermark,
            "prompt_extend": r.promptExtend,
        ]
        let body: [String: Any] = [
            "model": r.model,
            "input": [
                "messages": [
                    ["role": "user", "content": [["text": r.prompt]]]
                ]
            ],
            "parameters": params,
        ]
        let json = try await postJSON(
            "\(DashScope.httpBase)/services/aigc/multimodal-generation/generation",
            body: body)

        var urls: [String] = []
        if let out = json["output"] as? [String: Any],
           let choices = out["choices"] as? [[String: Any]] {
            for ch in choices {
                guard let msg = ch["message"] as? [String: Any],
                      let content = msg["content"] as? [[String: Any]] else { continue }
                for item in content {
                    if let u = item["image"] as? String, !u.isEmpty { urls.append(u) }
                }
            }
        }
        if urls.isEmpty {
            if let out = json["output"] as? [String: Any],
               let results = out["results"] as? [[String: Any]] {
                for item in results {
                    if let u = item["url"] as? String, !u.isEmpty { urls.append(u) }
                }
            }
        }
        if urls.isEmpty {
            throw APIError("生成失败：未返回图片地址 \(json["code"] ?? "") \(json["message"] ?? "")")
        }
        return urls
    }

    // MARK: - 下载远端资源到本地

    func download(_ remote: URL, to dest: URL) async throws {
        let (tmp, _) = try await Net.download(URLRequest(url: remote))
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    // MARK: - 文本向量化（qwen3.7-text-embedding-flash）

    func embed(texts: [String]) async throws -> (vectors: [[Double]], tokens: Int) {
        guard !texts.isEmpty else { return ([], 0) }
        let body: [String: Any] = [
            "model": FixedModel.embedding,
            "input": ["texts": texts],
            "parameters": ["dimension": 1024],
        ]
        let json = try await postJSON(
            "\(DashScope.httpBase)/services/embeddings/text-embedding/text-embedding",
            body: body)
        let out = JSONValue.dict(json, "output") ?? json
        guard let list = out["embeddings"] as? [[String: Any]] else {
            throw APIError("向量接口响应异常：缺少 output.embeddings")
        }
        let sorted = list.sorted { a, b in
            (JSONValue.int(a, ["text_index"]) ?? 0) < (JSONValue.int(b, ["text_index"]) ?? 0)
        }
        let vectors = sorted.map { d -> [Double] in
            if let v = d["embedding"] as? [Double] { return v }
            if let v = d["embedding"] as? [NSNumber] { return v.map { $0.doubleValue } }
            return []
        }
        let tokens = JSONValue.int(json, ["usage", "total_tokens"]) ?? estimateTokens(texts)
        return (vectors, tokens)
    }

    // MARK: - 文本生成（qwen-plus，「试试手气 Pro」阶段二：扩充生成）

    /// 文本生成：系统指令 + 用户提示 → 正文，返回文本 + 本次总 token
    func generateText(model: String, system: String, user: String,
                      maxTokens: Int, temperature: Double = 0.9) async throws -> (text: String, tokens: Int) {
        let body: [String: Any] = [
            "model": model,
            "input": [
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user],
                ],
            ],
            "parameters": [
                "result_format": "message",
                "max_tokens": maxTokens,
                "temperature": temperature,
            ],
        ]
        let json = try await postJSON(
            "\(DashScope.httpBase)/services/aigc/text-generation/generation", body: body)
        var text = ""
        if let out = json["output"] as? [String: Any],
           let t = JSONValue.string(out, ["text"]), !t.isEmpty {
            text = t
        } else if let out = json["output"] as? [String: Any],
                  let choices = out["choices"] as? [[String: Any]] {
            for ch in choices {
                if let msg = ch["message"] as? [String: Any],
                   let c = msg["content"] as? String, !c.isEmpty {
                    text += c
                }
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let usage = JSONValue.dict(json, "usage")
            ?? JSONValue.dict(JSONValue.dict(json, "output"), "usage") ?? [:]
        let inputTokens = JSONValue.int(usage, ["input_tokens"]) ?? 0
        let outputTokens = JSONValue.int(usage, ["output_tokens"]) ?? 0
        let total = JSONValue.int(usage, ["total_tokens"]) ?? 0
        let tokens = total > 0 ? total : (inputTokens + outputTokens > 0 ? inputTokens + outputTokens
                                                                         : estimateTokens([system, user]) + maxTokens)
        return (text, tokens)
    }

    /// 粗略估算 token 数（中文按字、其他按 4 字符 ≈ 1 token）
    private func estimateTokens(_ texts: [String]) -> Int {
        var n = 0
        for t in texts {
            for ch in t {
                if let v = ch.unicodeScalars.first, v.value > 0x2E80 { n += 1 }
            }
            let ascii = t.unicodeScalars.filter { $0.value <= 0x2E80 }.count
            n += ascii / 4
        }
        return max(1, n)
    }

    func postJSON(_ urlString: String, body: [String: Any], extra: [String: String] = [:]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw APIError("URL 无效") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in try authHeaders(extra: extra) { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await Net.data(req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if !(200..<300).contains(status) {
            let code = json["code"] as? String ?? ""
            let msg = json["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
            throw APIError("HTTP \(status) \(code) \(msg)".trimmingCharacters(in: .whitespaces))
        }
        return json
    }
}

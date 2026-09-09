import Foundation

/// CosyVoice 全双工 WebSocket 语音合成（model=cosyvoice-v3.5-plus + voice_id）
enum CosyVoiceTTS {
    struct Result {
        let audio: Data
        let format: String
    }

    /// 合成一段文本，返回 mp3 数据。
    static func synthesize(text: String, voiceId: String, apiKey: String,
                           speechRate: Double = 1.0, volume: Int = 50, pitch: Double = 1.0,
                           instruction: String? = nil) async throws -> Result {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { throw APIError("请先在「设置」中填写 DashScope API Key") }
        guard let url = URL(string: DashScope.wsBase) else { throw APIError("WS URL 无效") }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        req.setValue("clipforge", forHTTPHeaderField: "user-agent")

        let task = URLSession.shared.webSocketTask(with: req)
        task.maximumMessageSize = 8 * 1024 * 1024
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        let taskId = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        var parameters: [String: Any] = [
            "voice": voiceId,
            "volume": volume,
            "text_type": "PlainText",
            "sample_rate": 22050,
            "rate": speechRate,
            "format": "mp3",
            "pitch": pitch,
            "seed": 0,
            "type": 0,
            "enable_ssml": true,
        ]
        if let instruction, !instruction.isEmpty { parameters["instruction"] = instruction }

        let runTask: [String: Any] = [
            "header": ["action": "run-task", "task_id": taskId, "streaming": "duplex"],
            "payload": [
                "model": FixedModel.tts,
                "task_group": "audio",
                "task": "tts",
                "function": "SpeechSynthesizer",
                "input": [String: Any](),
                "parameters": parameters,
            ],
        ]
        try await send(task, runTask)

        try await waitForEvent(task, taskId: taskId, expect: "task-started")

        let cont: [String: Any] = [
            "header": ["action": "continue-task", "task_id": taskId, "streaming": "duplex"],
            "payload": [
                "model": FixedModel.tts, "task_group": "audio", "task": "tts",
                "function": "SpeechSynthesizer", "input": ["text": text],
            ],
        ]
        try await send(task, cont)

        let fin: [String: Any] = [
            "header": ["action": "finish-task", "task_id": taskId, "streaming": "duplex"],
            "payload": ["input": [String: Any]()],
        ]
        try await send(task, fin)

        var audio = Data()
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            let msg = try await receive(task)
            switch msg {
            case .data(let chunk):
                audio.append(chunk)
            case .string(let s):
                guard let j = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
                      let header = j["header"] as? [String: Any],
                      let event = header["event"] as? String else { continue }
                if event == "task-finished" {
                    if audio.isEmpty { throw APIError("合成返回空音频") }
                    return Result(audio: audio, format: "mp3")
                } else if event == "task-failed" {
                    let code = header["error_code"] as? String ?? j["code"] as? String ?? ""
                    let em = header["error_message"] as? String ?? j["message"] as? String ?? s
                    throw APIError("合成失败：\(code) \(em)")
                }
            @unknown default:
                continue
            }
        }
        if audio.isEmpty { throw APIError("合成超时且未收到音频") }
        return Result(audio: audio, format: "mp3")
    }

    // MARK: helpers

    private enum Msg { case data(Data); case string(String) }

    private static func send(_ task: URLSessionWebSocketTask, _ obj: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: obj)
        guard let str = String(data: data, encoding: .utf8) else { throw APIError("JSON 编码失败") }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            task.send(.string(str)) { err in
                if let err = err { c.resume(throwing: err) } else { c.resume() }
            }
        }
    }

    private static func receive(_ task: URLSessionWebSocketTask) async throws -> Msg {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Msg, Error>) in
            task.receive { result in
                switch result {
                case .success(.data(let d)): c.resume(returning: .data(d))
                case .success(.string(let s)): c.resume(returning: .string(s))
                case .success: c.resume(throwing: APIError("未知 WS 消息"))
                case .failure(let e): c.resume(throwing: e)
                @unknown default: c.resume(throwing: APIError("未知"))
                }
            }
        }
    }

    private static func waitForEvent(_ task: URLSessionWebSocketTask, taskId: String, expect: String) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let msg = try await receive(task)
            guard case .string(let s) = msg else { continue }
            guard let j = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
                  let header = j["header"] as? [String: Any],
                  let event = header["event"] as? String else { continue }
            if event == expect { return }
            if event == "task-failed" {
                let em = (header["error_message"] as? String) ?? s
                throw APIError("任务启动失败：\(em)")
            }
        }
        throw APIError("等待 \(expect) 超时")
    }
}

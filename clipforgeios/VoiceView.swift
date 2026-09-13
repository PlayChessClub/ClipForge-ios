import SwiftUI
import Combine
import AVFoundation
import UniformTypeIdentifiers

// MARK: - 语音页（TTS 合成 / 试听 / 素材 / 声音克隆，迁移整合 macOS VoiceStudioView.swift）
//
// · 合成：CosyVoice TTS，用云端 voice_id（克隆得到或内置样音克隆）
// · 声音克隆：录音 / 本地音频 / 公网 URL → 上传 OSS → voice-enrollment → 轮询就绪
// · 所有消耗性操作先弹 Token 确认

@MainActor
final class VoiceCloneModel: ObservableObject {
    @Published var cloningURL: String = ""
    @Published var ttsModel: String = FixedModel.ttsDefault
    @Published var myVoices: [[String: Any]] = []
    @Published var busy = false
    @Published var status = "就绪"
    @Published var newVoiceId: String = ""
    @Published var error: String? = nil
    @Published var isRecording = false
    @Published var recordSeconds: Int = 0

    let confirm = TokenConfirmModel()
    private let client = DashScopeClient.shared
    private var recorder: AVAudioRecorder?
    private var tick: Task<Void, Never>? = nil

    private var prefix: String { AppSettings.shared.voicePrefix }

    // MARK: 录音

    func toggleRecord() {
        if isRecording { stopRecord() } else { startRecord() }
    }

    private func startRecord() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard granted else {
                    self?.error = "未授权麦克风，请在系统设置中开启"
                    return
                }
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default)
                    try session.setActive(true)
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("clone_ref_\(Int(Date().timeIntervalSince1970)).wav")
                    let rec = try AVAudioRecorder(url: url, settings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 16000,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                    ])
                    rec.record()
                    self?.recorder = rec
                    self?.isRecording = true
                    self?.recordSeconds = 0
                    self?.status = "录音中…（再点一次停止）"
                    self?.tick = Task { [weak self] in
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            self?.recordSeconds += 1
                        }
                    }
                } catch {
                    self?.error = "录音初始化失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func stopRecord() {
        recorder?.stop()
        tick?.cancel()
        isRecording = false
        if let url = recorder?.url, recordSeconds >= 2 {
            status = "已录 \(recordSeconds)s"
            cloneFromLocal(url)
        } else {
            status = "录音太短（至少 2 秒）"
        }
        recorder = nil
    }

    // MARK: 克隆

    /// 用音色素材（本地文件）发起克隆
    func cloneFromSample(_ rs: ResolvedSample) {
        cloneFromLocal(rs.fileURL)
    }

    /// 从 URL 创建克隆音色（先确认再执行）
    func createVoiceFromURL() {
        let url = cloningURL.trimmingCharacters(in: .whitespaces)
        if url.isEmpty { error = "请填写公网可访问的音频 URL"; return }
        confirm.confirmAndRun(TokenEstimator.estimateVoiceClone()) { [weak self] in
            await self?.performCreateVoice(url: url)
        }
    }

    func cloneFromLocal(_ f: URL) {
        guard FileManager.default.fileExists(atPath: f.path) else {
            error = "素材文件不存在"
            return
        }
        confirm.confirmAndRun(TokenEstimator.estimateVoiceClone()) { [weak self] in
            await self?.performCloneFromLocal(f)
        }
    }

    private func performCreateVoice(url: String) async {
        error = nil
        recordCloneBill()
        busy = true; status = "提交音色克隆请求…"
        defer { busy = false }
        do {
            let vid = try await client.createVoice(targetModel: ttsModel, prefix: prefix, url: url)
            newVoiceId = vid
            status = "已提交，正在轮询状态…"
            await pollUntilReady(vid: vid)
        } catch {
            self.error = error.localizedDescription
            status = "克隆失败"
        }
    }

    private func performCloneFromLocal(_ f: URL) async {
        error = nil; busy = true
        recordCloneBill()
        status = "上传参考音频到临时 OSS…"
        defer { busy = false }
        do {
            let oss = try await client.uploadToOSS(model: ttsModel, fileURL: f)
            cloningURL = oss
            status = "提交音色克隆请求…"
            let vid = try await client.createVoice(targetModel: ttsModel, prefix: prefix, url: oss)
            newVoiceId = vid
            status = "已提交，正在轮询状态…"
            await pollUntilReady(vid: vid)
        } catch {
            self.error = error.localizedDescription
            status = "克隆失败"
        }
    }

    private func pollUntilReady(vid: String) async {
        for attempt in 1...30 {
            do {
                let info = try await client.queryVoice(voiceId: vid)
                let st = info["status"] as? String ?? "UNKNOWN"
                status = "轮询 \(attempt)/30 · 状态 \(st)"
                if st == "OK" {
                    status = "音色已就绪：\(vid)"
                    await refreshVoices()
                    return
                } else if st == "UNDEPLOYED" || st == "FAILED" {
                    error = "音色处理失败（\(st)），请检查音频质量后重试"
                    return
                }
            } catch {
                self.error = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
        error = "轮询超时，音色仍未就绪"
    }

    private func recordCloneBill() {
        let est = TokenEstimator.estimateVoiceClone()
        BillStore.shared.add(BillEntry(
            action: "声音克隆", model: FixedModel.voiceEnrollment,
            summary: "prefix=\(prefix)",
            unitName: "次", unitCount: 1,
            tokenMin: est.tokenMin, tokenMax: est.tokenMax,
            amountText: est.amount, detail: est.detail))
    }

    // MARK: 音色列表

    func refreshVoices() async {
        do {
            myVoices = try await client.listVoices(prefix: prefix)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteVoice(_ vid: String) async {
        do {
            try await client.deleteVoice(voiceId: vid)
            if newVoiceId == vid { newVoiceId = "" }
            await refreshVoices()
        } catch { self.error = error.localizedDescription }
    }
}

struct VoiceView: View {
    @StateObject private var clone = VoiceCloneModel()
    @ObservedObject private var settings = AppSettings.shared

    @State private var text = "夜色渐深，城市慢慢安静下来。远处的灯火一盏盏熄灭，只剩下风穿过树梢的声音。"
    @State private var voiceId = ""
    @State private var instruction = ""
    @State private var samples: [ResolvedSample] = []
    @State private var audioData: Data?
    @State private var isPlaying = false
    @State private var busy = false
    @State private var log = "粘贴云端 voice_id 或点「我的音色」选择，输入文案后合成。"
    @State private var player: AVAudioPlayer?
    @State private var showAudioImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !settings.hasKey {
                            Label("尚未配置 API Key，请前往「设置」填写。", systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(.orange)
                        }

                        // MARK: 合成
                        Group {
                            Text("合成模型").font(.headline)
                            Picker("模型", selection: $clone.ttsModel) {
                                ForEach(FixedModel.ttsModels) { mo in
                                    Text("\(mo.id) · \(mo.priceText)").tag(mo.id)
                                }
                            }
                            .pickerStyle(.menu)
                            if let info = FixedModel.modelInfo(clone.ttsModel) {
                                Text(info.merits).font(.caption).foregroundStyle(.secondary)
                            }

                            Text("文案 / 旁白").font(.headline)
                            TextEditor(text: $text)
                                .frame(minHeight: 100)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

                            HStack {
                                Button(action: { Task { await synth() } }) {
                                    Label("合成并试听", systemImage: "waveform")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(busy || voiceId.trimmingCharacters(in: .whitespaces).isEmpty)

                                Button(action: { Task { await proNarration() } }) {
                                    Label("Pro 旁白", systemImage: "sparkles")
                                }
                                .buttonStyle(.bordered)
                                .disabled(busy || !settings.hasKey)
                            }

                            if busy { ProgressView("合成中…") }
                            if audioData != nil, isPlaying {
                                Label("播放中…", systemImage: "speaker.wave.2.fill").font(.footnote)
                            }
                        }

                        // MARK: 我的音色（云端）
                        myVoicesSection

                        // MARK: 声音克隆
                        cloneSection

                        // MARK: 素材
                        materialsSection

                        if let e = clone.error {
                            Text(e).font(.caption).foregroundStyle(.red)
                        }
                        Text(log).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding()
                }

                TokenConfirmOverlay(model: clone.confirm, title: "声音克隆")
            }
            .navigationTitle("语音")
            .onAppear {
                samples = VoiceSampleKit.loadSamples()
                Task { await clone.refreshVoices() }
            }
            .onDisappear { player?.stop() }
            .fileImporter(isPresented: $showAudioImporter,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    clone.cloneFromLocal(url)
                }
            }
        }
    }

    // MARK: 我的音色

    private var myVoicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("我的音色（\(clone.myVoices.count)）").font(.headline)
                Spacer()
                Button { Task { await clone.refreshVoices() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(clone.busy)
            }
            if clone.myVoices.isEmpty {
                Text("还没有云端音色 —— 用下方「声音克隆」创建一个。").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(clone.myVoices.indices, id: \.self) { vi in
                    let v = clone.myVoices[vi]
                    let vid = (v["voice_id"] as? String) ?? ""
                    let st = (v["status"] as? String) ?? ""
                    Button {
                        voiceId = vid
                        log = "已选音色：\(vid)"
                    } label: {
                        HStack {
                            Image(systemName: vid == voiceId ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(vid == voiceId ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vid).font(.footnote.monospaced()).lineLimit(1)
                                Text(st == "OK" || st == "available" ? "可用" : st)
                                    .font(.caption2)
                                    .foregroundStyle(st == "OK" || st == "available" ? Color.green : Color.secondary)
                            }
                            Spacer()
                            Image(systemName: "waveform").foregroundStyle(.teal)
                        }
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await clone.deleteVoice(vid) }
                        } label: { Label("删除音色", systemImage: "trash") }
                    }
                }
            }
        }
    }

    // MARK: 克隆区

    private var cloneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("声音克隆").font(.headline)

            HStack(spacing: 10) {
                Button {
                    clone.toggleRecord()
                } label: {
                    Label(clone.isRecording ? "停止(\(clone.recordSeconds)s)" : "录音 10 秒以上",
                          systemImage: clone.isRecording ? "stop.circle.fill" : "mic.circle")
                        .foregroundStyle(clone.isRecording ? .red : .primary)
                }
                .buttonStyle(.bordered)

                Button { showAudioImporter = true } label: {
                    Label("本地音频", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            HStack {
                TextField("或填公网音频 URL", text: $clone.cloningURL)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button("克隆") { clone.createVoiceFromURL() }
                    .buttonStyle(.bordered)
                    .disabled(clone.busy || clone.cloningURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("参考音频要求：单一说话人、清晰无噪音、10-20 秒最佳。克隆按次计费。")
                .font(.caption2).foregroundStyle(.secondary)

            if clone.busy || clone.isRecording {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.8)
                    Text(clone.status).font(.caption).foregroundStyle(.orange)
                }
            } else if !clone.newVoiceId.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text(clone.status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 素材

    private var materialsSection: some View {
        DisclosureGroup("音色素材（\(samples.count)）— 点 ↗ 克隆为云端音色") {
            ForEach(samples) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(VoiceSampleKit.nickname(for: s.sample)).font(.subheadline)
                        Text(s.sample.isBuiltin ? "内置样音" : "用户素材")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: { playLocal(s) }) {
                        Image(systemName: "play.circle").imageScale(.large)
                    }
                    Button {
                        clone.cloneFromSample(s)
                    } label: {
                        Image(systemName: "arrowshape.turn.up.right").imageScale(.large)
                    }
                    .disabled(clone.busy)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: 合成

    private func synth() async {
        guard settings.hasKey else { log = "请先在「设置」填写 API Key"; return }
        let vid = voiceId.trimmingCharacters(in: .whitespaces)
        guard !vid.isEmpty else { log = "请选择或填写云端 voice_id"; return }
        busy = true; defer { busy = false }
        do {
            log = "调用 CosyVoice 合成…"
            let r = try await CosyVoiceTTS.synthesize(text: text, voiceId: vid, apiKey: settings.apiKey,
                                                      model: clone.ttsModel,
                                                      instruction: instruction.isEmpty ? nil : instruction)
            audioData = r.audio
            await saveAudio(r.audio)
            play(data: r.audio)
            let est = TokenEstimator.estimateTTS(text: text, model: clone.ttsModel)
            BillStore.shared.add(BillEntry(
                action: "语音合成", model: clone.ttsModel, summary: String(text.prefix(40)),
                unitName: "字符", unitCount: text.count,
                tokenMin: est.tokenMin, tokenMax: est.tokenMax,
                amountText: est.amount, detail: est.detail, taskId: nil))
            log = "合成成功（\(r.format)，已试听并保存到文档）"
        } catch {
            log = "合成失败：\(error.localizedDescription)"
        }
    }

    private func proNarration() async {
        guard settings.hasKey else { log = "请先填写 API Key"; return }
        busy = true; defer { busy = false }
        let pro = await PromptBank.pro(kind: .audio, purpose: "")
        text = pro.prompt
        log = "Pro 已生成旁白文案（≈\(pro.embedTokens)+\(pro.genTokens) token）"
        busy = false
        if !voiceId.trimmingCharacters(in: .whitespaces).isEmpty {
            await synth()
        }
    }

    private func play(data: Data) {
        do {
            player = try AVAudioPlayer(data: data)
            player?.play()
            isPlaying = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let p = player, !p.isPlaying { isPlaying = false }
            }
        } catch { log = "播放失败：\(error.localizedDescription)" }
    }

    private func playLocal(_ s: ResolvedSample) {
        do {
            player = try AVAudioPlayer(contentsOf: s.fileURL)
            player?.play()
            isPlaying = true
        } catch { log = "试听失败：\(error.localizedDescription)" }
    }

    private func saveAudio(_ data: Data) async {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipForge/voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("tts_\(Int(Date().timeIntervalSince1970)).mp3")
        try? data.write(to: url)
    }
}

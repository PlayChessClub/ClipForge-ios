import SwiftUI
import Combine
import PhotosUI
import AVKit
import UniformTypeIdentifiers

// MARK: - 视频页（迁移自 macOS VideoStudioView.swift）
//
// wan 系列视频生成：图生视频(i2v 需首帧图) / 文生视频(t2v 仅 Prompt)
// 首帧图：PhotosPicker 选相册 或 fileImporter 选文件 或填 URL
// 配音：fileImporter 选音频 或填 URL；生成走异步任务 + 轮询，完成后自动下载并入库

@MainActor
final class VideoStudioModel: ObservableObject {
    @Published var prompt: String = "一幅都市奇幻艺术的场景。一个由喷漆画成的少年从混凝土墙上活过来，边 rap 边摆出充满活力的说唱姿势，夜晚铁路桥下，街灯孤照，电影感氛围。"
    @Published var imageURL: String = ""
    @Published var audioURL: String = ""
    @Published var model: String = FixedModel.videoI2V
    @Published var resolution: String = "720P"
    @Published var duration: Int = 10
    @Published var shotType: String = "single"
    @Published var promptExtend: Bool = true
    @Published var audioEnabled: Bool = true

    @Published var localImage: URL? = nil
    @Published var localAudio: URL? = nil

    @Published var busy = false
    @Published var status = "就绪"
    @Published var taskId: String = ""
    @Published var error: String? = nil
    @Published var videoLocalURL: URL? = nil
    @Published var elapsed: Int = 0

    /// 生成前 token 消耗确认
    let confirm = TokenConfirmModel()

    private let client = DashScopeClient.shared

    func useLibraryAudio(_ url: URL) { localAudio = url }

    var isTextToVideo: Bool { FixedModel.isTextToVideo(model) }
    var actionName: String { FixedModel.videoKindName(model) }

    private func currentEstimate() -> TokenEstimator.Estimate {
        TokenEstimator.estimateVideo(model: model, prompt: prompt,
                                     resolution: resolution,
                                     duration: duration, audio: audioEnabled)
    }

    /// 入口：先弹 token 消耗确认，用户点「继续生成」后才真正执行
    func submit() {
        confirm.confirmAndRun(currentEstimate()) { [weak self] in await self?.performSubmit() }
    }

    private func recordBill() {
        let est = currentEstimate()
        let entry = BillEntry(
            action: actionName, model: model,
            summary: String(prompt.prefix(60)),
            unitName: "秒", unitCount: duration,
            tokenMin: est.tokenMin, tokenMax: est.tokenMax,
            amountText: est.amount, detail: est.detail)
        BillStore.shared.add(entry)
        lastBillId = entry.id
    }

    private var lastBillId: UUID?

    func performSubmit() async {
        error = nil; videoLocalURL = nil; busy = true; elapsed = 0
        defer { busy = false }
        recordBill()
        do {
            var img = imageURL.trimmingCharacters(in: .whitespaces)
            if img.isEmpty, let f = localImage {
                status = "上传图片到临时 OSS…"
                img = try await client.uploadToOSS(model: model, fileURL: f)
            }
            if img.isEmpty && !isTextToVideo {
                throw APIError("请提供首帧图片（相册/文件选择或填 URL），或改用文生视频模型")
            }

            var aud = audioURL.trimmingCharacters(in: .whitespaces)
            if aud.isEmpty, let f = localAudio {
                status = "上传配音到临时 OSS…"
                aud = try await client.uploadToOSS(model: model, fileURL: f)
            }

            let req = DashScopeClient.VideoRequest(
                model: model,
                prompt: prompt, imageURL: img,
                audioURL: aud.isEmpty ? nil : aud,
                resolution: resolution, duration: duration,
                promptExtend: promptExtend, audioEnabled: audioEnabled,
                shotType: shotType)

            status = "提交视频生成任务…"
            let tid = try await client.submitVideoTask(req)
            taskId = tid
            if let bid = lastBillId {
                BillStore.shared.update(id: bid, taskId: tid, status: "生成中")
            }
            status = "任务已提交，生成中（通常 1-5 分钟）…"
            try await poll(tid)
        } catch {
            self.error = error.localizedDescription
            status = "失败"
        }
    }

    private func poll(_ tid: String) async throws {
        let deadline = Date().addingTimeInterval(60 * 15)
        while Date() < deadline {
            let s = try await client.pollVideoTask(tid)
            switch s.state {
            case "SUCCEEDED":
                status = "生成成功，下载中…"
                guard let vurl = s.videoUrl, let u = URL(string: vurl) else {
                    throw APIError("返回中没有视频地址")
                }
                let dest = outputDir()
                    .appendingPathComponent("视频_\(Int(Date().timeIntervalSince1970)).mp4")
                try await client.download(u, to: dest)
                videoLocalURL = dest
                LibraryStore.shared.add(MediaClip(kind: .video, name: dest.lastPathComponent, url: dest))
                status = "完成 ✓"
                return
            case "FAILED", "CANCELED", "UNKNOWN":
                throw APIError("任务\(s.state)：\(s.message ?? "无详情")")
            default:
                status = "生成中 · \(s.state)（已等待 \(elapsed)s）"
                for _ in 0..<5 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    elapsed += 1
                }
            }
        }
        throw APIError("轮询超时（15 分钟）")
    }

    private func outputDir() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipForge/video", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

struct VideoView: View {
    @StateObject private var m = VideoStudioModel()
    @ObservedObject private var lib = LibraryStore.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var showImageImporter = false
    @State private var showAudioImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !settings.hasKey {
                            Label("尚未配置 API Key，请前往「设置」填写。", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        modelSection
                        promptSection
                        firstFrameSection
                        audioSection
                        paramsSection
                        submitSection
                        if let v = m.videoLocalURL {
                            resultSection(v).padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }

                TokenConfirmOverlay(model: m.confirm, title: "视频生成")
            }
            .navigationTitle("视频")
            .onChange(of: photoItem) { item in
                Task { await loadPhoto(item) }
            }
            .fileImporter(isPresented: $showImageImporter,
                          allowedContentTypes: [.png, .jpeg, .image],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    m.localImage = url
                }
            }
            .fileImporter(isPresented: $showAudioImporter,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    m.localAudio = url
                }
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("生成模型").font(.subheadline)
            Picker("模型", selection: $m.model) {
                ForEach(FixedModel.videoModels, id: \.self) { mo in
                    Text("\(mo) · \(FixedModel.videoKindName(mo))").tag(mo)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal)
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt").font(.subheadline)
            TextEditor(text: $m.prompt)
                .frame(minHeight: 84)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            LuckyPromptButtons(kind: .video, confirm: m.confirm, text: $m.prompt)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var firstFrameSection: some View {
        if m.isTextToVideo {
            Label("文生视频模型：仅凭 Prompt 生成，无需首帧图片。", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("首帧图片（必填）").font(.subheadline)
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoItem,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        Label("相册", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)

                    Button { showImageImporter = true } label: {
                        Label("文件", systemImage: "doc")
                    }
                    .buttonStyle(.bordered)

                    TextField("或填图片 URL", text: $m.imageURL)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                if let img = m.localImage {
                    Text("已选：\(img.lastPathComponent)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("配音音频（可选）").font(.subheadline)
            HStack(spacing: 10) {
                Button { showAudioImporter = true } label: {
                    Label(m.localAudio?.lastPathComponent ?? "选择本地音频", systemImage: "music.note.list")
                }
                .buttonStyle(.bordered)

                TextField("或填音频 URL", text: $m.audioURL)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            if !lib.clips.filter({ $0.kind == .audio }).isEmpty {
                Menu {
                    ForEach(lib.clips.filter { $0.kind == .audio }) { c in
                        Button(c.name) { m.useLibraryAudio(c.url) }
                    }
                } label: {
                    Label("使用素材库配音", systemImage: "waveform.path")
                        .font(.footnote)
                }
            }
        }
        .padding(.horizontal)
    }

    private var paramsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("分辨率", selection: $m.resolution) {
                Text("720P").tag("720P"); Text("1080P").tag("1080P")
            }
            .pickerStyle(.segmented)

            Picker("时长", selection: $m.duration) {
                ForEach([5, 10, 15], id: \.self) { Text("\($0)s").tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("镜头", selection: $m.shotType) {
                Text("单镜头").tag("single"); Text("多镜头").tag("multi")
            }
            .pickerStyle(.segmented)

            Toggle("智能扩写 prompt_extend", isOn: $m.promptExtend)
            Toggle("生成音频轨 audio", isOn: $m.audioEnabled)
            if m.model == "wan2.6-i2v-flash" {
                Text(m.audioEnabled
                     ? "flash 有声：¥0.3/s(720P) · ¥0.5/s(1080P)"
                     : "flash 无声更省：¥0.15/s(720P) · ¥0.25/s(1080P)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var submitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { m.submit() } label: {
                Label("开始生成视频", systemImage: "video.fill.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(m.busy)

            if m.busy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(m.status).font(.footnote).foregroundStyle(.orange)
                }
            } else {
                statusText
            }
            if !m.taskId.isEmpty {
                Text("task_id: \(m.taskId)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if let e = m.error {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var statusText: some View {
        if m.error != nil {
            Text(m.status).font(.footnote).foregroundStyle(Color.red)
        } else {
            Text(m.status).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func resultSection(_ v: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text(v.lastPathComponent).font(.caption).lineLimit(1)
                Spacer()
                ShareLink(item: v) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            VideoPlayer(player: AVPlayer(url: v))
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: 相册选图 → 临时文件

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            m.error = "读取相册图片失败"
            return
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("firstframe_\(Int(Date().timeIntervalSince1970)).jpg")
        do {
            try data.write(to: tmp)
            m.localImage = tmp
            m.error = nil
        } catch {
            m.error = "写入临时文件失败：\(error.localizedDescription)"
        }
    }
}

import SwiftUI
import AVKit
import UniformTypeIdentifiers

// MARK: - 时间线页（迁移自 macOS TimelineView.swift + 素材库）
//
// · 素材库：生成的视频/音频自动收录，也可手动导入；可删除
// · 时间线：按素材库顺序拼接视频轨（拼接保留原声 / 配音替换音轨）
// · 导出 mp4 后可分享 / 预览

struct StudioView: View {
    @ObservedObject private var lib = LibraryStore.shared
    @State private var mode: ExportEngine.Mode = .concat
    @State private var dubAudio: URL? = nil
    @State private var busy = false
    @State private var progress: Double = 0
    @State private var status = "就绪"
    @State private var error: String? = nil
    @State private var outputURL: URL? = nil
    @State private var showImporter = false
    @State private var showDubImporter = false

    private var videoClips: [MediaClip] {
        lib.order.compactMap { lib.clip($0) }.filter { $0.kind == .video }
    }
    private var audioClips: [MediaClip] {
        lib.clips.filter { $0.kind == .audio }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 素材库
                    Group {
                        HStack {
                            Text("素材库（\(lib.clips.count)）").font(.headline)
                            Spacer()
                            Button { showImporter = true } label: { Label("导入", systemImage: "plus") }
                                .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                lib.clips.removeAll(); lib.order.removeAll()
                            } label: { Label("清空", systemImage: "trash") }
                                .buttonStyle(.bordered)
                        }
                        if lib.clips.isEmpty {
                            Text("暂无素材 —— 去「视频/语音」生成，或点「导入」。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(lib.clips) { c in
                                HStack(spacing: 10) {
                                    Image(systemName: c.kind.symbol)
                                        .foregroundStyle(c.kind == .video ? .purple : (c.kind == .audio ? .teal : .orange))
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(c.name).font(.footnote).lineLimit(1)
                                        Text(c.kind.label).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if c.kind == .video {
                                        NavigationLink {
                                            VideoPlayer(player: AVPlayer(url: c.url))
                                                .frame(height: 300)
                                                .padding()
                                                .navigationTitle(c.name)
                                                .navigationBarTitleDisplayMode(.inline)
                                        } label: {
                                            Image(systemName: "play.circle")
                                        }
                                    }
                                    Button { withAnimation { lib.remove(c.id) } } label: {
                                        Image(systemName: "xmark.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    Divider()

                    // 时间线
                    Group {
                        Text("时间线").font(.headline)
                        if videoClips.isEmpty {
                            Text("还没有视频片段 —— 去「视频生成」产出一段，或导入本地 mp4/mov。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(Array(videoClips.enumerated()), id: \.element.id) { i, c in
                                        VStack(spacing: 4) {
                                            Text("\(i + 1)").font(.caption2.bold())
                                            Image(systemName: "film")
                                            Text(c.name).font(.caption2).lineLimit(1).frame(width: 80)
                                        }
                                        .frame(width: 96, height: 76)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }

                        Picker("模式", selection: $mode) {
                            ForEach(ExportEngine.Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)

                        if mode == .dub {
                            HStack {
                                Button { showDubImporter = true } label: {
                                    Label(dubAudio?.lastPathComponent ?? "选择配音音频", systemImage: "music.note")
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                if !audioClips.isEmpty {
                                    Menu {
                                        ForEach(audioClips) { c in
                                            Button(c.name) { dubAudio = c.url }
                                        }
                                    } label: {
                                        Label("用素材库配音", systemImage: "waveform.path")
                                    }
                                }
                            }
                        }

                        Button {
                            Task { await export() }
                        } label: {
                            Label("按时间线导出 mp4", systemImage: "square.and.arrow.down.on.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || videoClips.isEmpty || (mode == .dub && dubAudio == nil))

                        if busy {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: progress)
                                Text(status).font(.caption).foregroundStyle(.orange)
                            }
                        } else {
                            Text(status).font(.caption).foregroundStyle(.secondary)
                        }
                        if let e = error {
                            Text(e).font(.caption).foregroundStyle(.red)
                        }

                        if let out = outputURL {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                    Text(out.lastPathComponent).font(.caption).lineLimit(1)
                                    Spacer()
                                    ShareLink(item: out) {
                                        Label("分享", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                VideoPlayer(player: AVPlayer(url: out))
                                    .frame(height: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("时间线")
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.movie, .audio, .image],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        let kind: MediaClip.Kind = url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov" ? .video
                            : ["mp3", "wav", "m4a"].contains(url.pathExtension.lowercased()) ? .audio : .image
                        lib.add(MediaClip(kind: kind, name: url.lastPathComponent, url: url))
                    }
                }
            }
            .fileImporter(isPresented: $showDubImporter,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    dubAudio = url
                }
            }
        }
    }

    private func export() async {
        error = nil; outputURL = nil; busy = true; progress = 0
        defer { busy = false }
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ClipForge/export", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let out = dir.appendingPathComponent("合成_\(Int(Date().timeIntervalSince1970)).mp4")
            let plan = ExportEngine.Plan(videos: videoClips.map(\.url), mode: mode, dubAudio: dubAudio)
            try await ExportEngine.export(plan, to: out) { p in
                progress = p
                status = "导出中… \(Int(p * 100))%"
            }
            outputURL = out
            LibraryStore.shared.add(MediaClip(kind: .video, name: out.lastPathComponent, url: out))
            status = "完成 ✓（已收录进素材库）"
        } catch {
            self.error = error.localizedDescription
            status = "导出失败"
        }
    }
}

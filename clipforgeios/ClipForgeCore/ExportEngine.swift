import Foundation
import AVFoundation

/// 时间线导出引擎：AVFoundation 原生实现（迁移自 macOS ExportEngine.swift，iOS 适配）
/// - 拼接模式：多段视频顺序拼接，保留各自音轨
/// - 配音模式：多段视频顺序拼接，整体替换为一条音轨
@MainActor
enum ExportEngine {
    enum Mode: String, CaseIterable, Identifiable {
        case concat = "拼接（保留原声）"
        case dub = "配音（替换音轨）"
        var id: String { rawValue }
    }

    struct Plan {
        var videos: [URL]
        var mode: Mode
        var dubAudio: URL?
    }

    enum ExportError: LocalizedError {
        case noVideo, badVideo, exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .noVideo: return "时间线里还没有视频片段"
            case .badVideo: return "存在无法读取的视频文件，请检查素材库"
            case .exportFailed(let m): return "导出失败：\(m)"
            }
        }
    }

    private struct Segment {
        let start: CMTime
        let duration: CMTime
        let normalizedSize: CGSize
    }

    // iOS 适配：同步轨道读取（iOS 16 目标下无需 macOS 版的 async AVCompat 包装）
    private static func videoTrack(_ asset: AVAsset) -> AVAssetTrack? {
        asset.tracks(withMediaType: .video).first
    }
    private static func audioTrack(_ asset: AVAsset) -> AVAssetTrack? {
        asset.tracks(withMediaType: .audio).first
    }

    static func export(_ plan: Plan, to output: URL,
                       progress: ((Double) -> Void)? = nil) async throws {
        if plan.videos.isEmpty { throw ExportError.noVideo }
        progress?(0.05)

        let composition = AVMutableComposition()
        guard let trackV = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.badVideo }
        let trackA = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var segments: [Segment] = []
        var cursor = CMTime.zero
        var renderSize: CGSize? = nil

        for (i, url) in plan.videos.enumerated() {
            let asset = AVURLAsset(url: url)
            guard let v = videoTrack(asset) else { throw ExportError.badVideo }
            let a = audioTrack(asset)

            let size = v.naturalSize.applying(v.preferredTransform)
            let norm = CGSize(width: abs(size.width), height: abs(size.height))
            let dur = asset.duration
            if renderSize == nil { renderSize = norm }

            let range = CMTimeRange(start: .zero, duration: dur)
            try trackV.insertTimeRange(range, of: v, at: cursor)
            if plan.mode == .concat, let a {
                try? trackA?.insertTimeRange(range, of: a, at: cursor)
            }
            segments.append(Segment(start: cursor, duration: dur, normalizedSize: norm))
            cursor = CMTimeAdd(cursor, dur)
            progress?(0.05 + 0.4 * Double(i + 1) / Double(plan.videos.count))
        }
        let total = cursor
        let canvas = renderSize ?? CGSize(width: 1280, height: 720)

        // 配音模式：插入替换音轨
        if plan.mode == .dub, let audioURL = plan.dubAudio {
            let audioAsset = AVURLAsset(url: audioURL)
            if let a = audioTrack(audioAsset) {
                let ad = audioAsset.duration
                let d = min(ad.seconds, CMTimeGetSeconds(total))
                let r = CMTimeRange(start: .zero, duration: CMTime(seconds: max(d, 0.1), preferredTimescale: 600))
                try? trackA?.insertTimeRange(r, of: a, at: .zero)
            }
        }

        // 视频合成：每段一条指令，等比缩放居中到统一画布
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        var cover: [AVMutableVideoCompositionInstruction] = []
        var needsComposition = false
        for seg in segments {
            if CMTimeGetSeconds(seg.duration) <= 0 { continue }
            let ins = AVMutableVideoCompositionInstruction()
            ins.timeRange = CMTimeRange(start: seg.start, duration: seg.duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: trackV)
            if seg.normalizedSize != canvas {
                needsComposition = true
                let sx = canvas.width / max(seg.normalizedSize.width, 1)
                let sy = canvas.height / max(seg.normalizedSize.height, 1)
                let s = min(sx, sy)
                let tx = (canvas.width - seg.normalizedSize.width * s) / 2
                let ty = (canvas.height - seg.normalizedSize.height * s) / 2
                layer.setTransform(CGAffineTransform(translationX: tx, y: ty).scaledBy(x: s, y: s),
                                   at: seg.start)
            } else {
                layer.setTransform(.identity, at: seg.start)
            }
            ins.layerInstructions = [layer]
            cover.append(ins)
        }
        if needsComposition { videoComposition.instructions = cover }
        progress?(0.5)

        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw ExportError.exportFailed("无法创建导出会话") }

        try? FileManager.default.removeItem(at: output)
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        if needsComposition { exporter.videoComposition = videoComposition }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { c.resume() }
        }
        progress?(1.0)

        switch exporter.status {
        case .completed: return
        case .failed, .cancelled:
            throw ExportError.exportFailed(exporter.error?.localizedDescription ?? "未知错误")
        default:
            throw ExportError.exportFailed("导出状态异常")
        }
    }
}

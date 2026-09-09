import SwiftUI
import Combine

// MARK: - Token 消耗确认弹层（iOS 版，迁移自 macOS TokenConfirmOverlay.swift）
//
// 在真正发起生成（图/视频/克隆）前弹出，展示预计消耗的 token 区间（±30%）与金额，
// 用户确认后再执行。估算仅供量级参考，实际以 DashScope 账单为准。

/// 供 ViewModel 持有的确认弹层状态
@MainActor
final class TokenConfirmModel: ObservableObject {
    @Published var estimate: TokenEstimator.Estimate? = nil

    var isPresented: Bool { estimate != nil }

    /// 弹出确认；用户确认后回调 confirm
    func confirmAndRun(_ e: TokenEstimator.Estimate, _ action: @escaping () async -> Void) {
        estimate = e
        pending = action
    }

    func dismiss() { estimate = nil; pending = nil }

    private var pending: (() async -> Void)?

    /// 用户点「继续」→ 收起弹层并执行
    func proceed() {
        let p = pending
        estimate = nil; pending = nil
        if let p { Task { await p() } }
    }
}

/// 通用确认浮层：叠加在内容之上，点击遮罩/取消可关闭
struct TokenConfirmOverlay: View {
    @ObservedObject var model: TokenConfirmModel
    var title: String = "确认生成"

    var body: some View {
        ZStack {
            if let e = model.estimate {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { model.dismiss() }
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(.orange)
                        Text("\(title) · 预计消耗")
                            .font(.headline)
                        Spacer()
                        Button { model.dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(e.action)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if e.tokenEst > 0 {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(e.tokenEstText)
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(.purple)
                                Text("token")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Text("区间 ±30%").font(.caption).foregroundStyle(.tertiary)
                                Text(e.tokenRangeText).font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("将消耗模型推理额度")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "yensign.circle")
                            .foregroundStyle(.teal)
                        Text(e.amount)
                            .font(.callout)
                            .foregroundStyle(.teal)
                        Spacer()
                    }
                    .padding(10)
                    .background(.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

                    Text("计费口径：" + e.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("以上为预估值，仅供参考，实际以 DashScope 账单为准。")
                        .font(.caption2)
                        .foregroundStyle(.orange)

                    HStack {
                        Spacer()
                        Button("取消") { model.dismiss() }
                            .buttonStyle(.bordered)
                        Button("继续生成") { model.proceed() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 2)
                }
                .padding(20)
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(24)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: model.isPresented)
    }
}

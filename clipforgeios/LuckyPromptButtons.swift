import SwiftUI

// MARK: - 「试试手气」+「试试手气 Pro」按钮组（iOS 竖排紧凑版，迁移自 macOS LuckyPromptButtons.swift）
//
// · 试试手气：从本地整句词库随机取一条，不联网、不计费
// · 试试手气 Pro：两阶段（向量选句 + qwen-plus 扩写），先弹合并的消耗确认

struct LuckyPromptButtons: View {
    let kind: PromptKind
    /// 所在页的确认弹层（复用，保证与其它生成一致的确认体验）
    var confirm: TokenConfirmModel
    @Binding var text: String

    @State private var purpose: String = ""
    @State private var theme: String = ""
    @State private var busy = false
    @State private var note: String? = nil

    private var themes: [String] { PromptBank.purposeSeeds[kind] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("目的 / 关键词（可留空）", text: $purpose)
                    .textFieldStyle(.roundedBorder)

                Menu {
                    Button("自动（随机主题）") { theme = "" }
                    Divider()
                    ForEach(themes, id: \.self) { t in
                        Button(t) { theme = t; purpose = t }
                    }
                } label: {
                    Label(theme.isEmpty ? "主题" : theme, systemImage: "tag")
                        .font(.footnote)
                }
            }

            HStack(spacing: 10) {
                Button { text = PromptBank.random(kind) } label: {
                    Label("试试手气", systemImage: "dice")
                }
                .buttonStyle(.bordered)

                Button { askThenRun() } label: {
                    HStack(spacing: 6) {
                        if busy {
                            ProgressView().scaleEffect(0.7)
                            Text("生成中…")
                        } else {
                            Image(systemName: "sparkles")
                            Text("试试手气 Pro")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)

                Spacer()
            }

            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 流程

    private func askThenRun() {
        guard !busy else { return }
        let seedPurpose = theme.isEmpty ? purpose : theme
        let texts = PromptBank.plannedTexts(kind: kind, purpose: seedPurpose)
        let embedTokens = TokenEstimator.embeddingTokens(for: texts)
        let est = TokenEstimator.estimateProTotal(kind: kind,
                                                  embedTokens: embedTokens,
                                                  genTokens: kind.maxGenTokens)
        confirm.confirmAndRun(est) { await runPro(purpose: seedPurpose) }
    }

    private func runPro(purpose seedPurpose: String) async {
        busy = true
        note = nil
        defer { busy = false }

        let result = await PromptBank.pro(kind: kind, purpose: seedPurpose)
        text = result.prompt

        guard result.usedPro else {
            note = "Pro 调用失败，已改用普通随机（未计费）"
            return
        }

        // 两阶段实际 token 合并记一条账
        let est = TokenEstimator.estimateProTotal(kind: kind,
                                                  embedTokens: result.embedTokens,
                                                  genTokens: result.genTokens)
        let entry = BillEntry(
            action: "试试手气 Pro",
            model: "\(FixedModel.textGeneration)+\(FixedModel.embedding)",
            summary: String(result.prompt.prefix(60)),
            unitName: "token",
            unitCount: result.totalTokens,
            tokenMin: est.tokenMin,
            tokenMax: est.tokenMax,
            amountText: est.amount,
            detail: "向量选句 \(result.embedTokens) + 扩写 \(result.genTokens) token",
            status: "成功"
        )
        BillStore.shared.add(entry)
        note = "已扩写 ~\(result.prompt.count) 字 · \(est.tokenRangeText)"
    }
}

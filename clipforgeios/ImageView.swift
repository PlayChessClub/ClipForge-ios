import SwiftUI

// MARK: - 图片页（基础生成 + 试试手气 Pro 两阶段）

struct ImageView: View {
    @State private var prompt = ""
    @State private var keyword = ""
    @State private var model = FixedModel.imageDefault
    @State private var size = "1024*1024"
    @State private var n = 1
    @State private var images: [URL] = []
    @State private var log = "填写提示词或目的关键词，点生成。"
    @State private var busy = false
    @State private var lastPro: PromptBank.ProResult?
    @StateObject private var confirm = TokenConfirmModel()

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("提示词").font(.headline)
                        TextEditor(text: $prompt)
                            .frame(minHeight: 88)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        Text("目的 / 关键词（试试手气 Pro 用，留空则随机）").font(.subheadline)
                        TextField("如：静谧江南", text: $keyword)
                            .textFieldStyle(.roundedBorder)

                        Picker("模型", selection: $model) {
                            ForEach(FixedModel.imageModels, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Picker("尺寸", selection: $size) {
                                Text("1:1").tag("1024*1024")
                                Text("16:9").tag("1664*928")
                                Text("9:16").tag("928*1664")
                            }
                            .pickerStyle(.menu)
                            Picker("张数", selection: $n) {
                                ForEach([1, 2, 4], id: \.self) { Text("\($0)张").tag($0) }
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Button(action: { askImageConfirm(usePro: false) }) {
                                Label("试试手气", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy)

                            Button(action: { askProConfirm() }) {
                                Label("试试手气 Pro", systemImage: "sparkles")
                            }
                            .buttonStyle(.bordered)
                            .disabled(busy || !AppSettings.shared.hasKey)
                        }

                    if busy { ProgressView("生成中…") }

                    if let pro = lastPro, pro.usedPro {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pro 扩写结果（已用于生成）").font(.footnote.bold())
                            Text(pro.prompt).font(.footnote)
                            Text("向量选句 ≈\(pro.embedTokens) token · 扩写 \(pro.genTokens) token")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }

                    if !images.isEmpty {
                        Text("结果").font(.headline)
                        ForEach(images, id: \.absoluteString) { url in
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty: ProgressView()
                                    case .success(let img): img.resizable().scaledToFit()
                                    case .failure: Color.gray.frame(height: 120)
                                    @unknown default: EmptyView()
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .background(.quaternary)
                                .cornerRadius(10)
                                Button(action: { Task { await save(url) } }) {
                                    Label("保存到相簿/文档", systemImage: "square.and.arrow.down")
                                        .font(.footnote)
                                }
                            }
                        }
                    }

                    Text(log).font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                }

                TokenConfirmOverlay(model: confirm, title: "文生图")
            }
            .navigationTitle("图片")
        }
    }

    // MARK: 确认流程（先弹消耗确认，再执行）

    private func askImageConfirm(usePro: Bool) {
        let est = TokenEstimator.estimateImage(model: model, size: size, n: n)
        confirm.confirmAndRun(est) { Task { await generate(usePro: usePro) } }
    }

    private func askProConfirm() {
        let texts = PromptBank.plannedTexts(kind: .image, purpose: keyword)
        let est = TokenEstimator.estimateProTotal(
            kind: .image,
            embedTokens: TokenEstimator.embeddingTokens(for: texts),
            genTokens: PromptKind.image.maxGenTokens)
        confirm.confirmAndRun(est) { Task { await generate(usePro: true) } }
    }

    private func generate(usePro: Bool) async {
        guard AppSettings.shared.hasKey else {
            log = "请先在「设置」填写 DashScope API Key"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let usedPrompt: String
            if usePro {
                let pro = await PromptBank.pro(kind: .image, purpose: keyword)
                lastPro = pro
                usedPrompt = pro.prompt
                recordPro(pro)
                log = "Pro 已生成扩写提示词（≈\(pro.embedTokens)+\(pro.genTokens) token），提交文生图…"
            } else {
                usedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? PromptBank.random(.image) : prompt
                log = "提交文生图…"
            }
            let req = DashScopeClient.ImageRequest(prompt: usedPrompt, model: model, size: size, n: n)
            let urls = try await DashScopeClient.shared.submitImage(req)
            images = urls.compactMap { URL(string: $0) }
            let est = TokenEstimator.estimateImage(model: model, size: size, n: req.n)
            BillStore.shared.add(BillEntry(
                action: "文生图", model: model, summary: String(usedPrompt.prefix(40)),
                unitName: "张", unitCount: req.n,
                tokenMin: est.tokenMin, tokenMax: est.tokenMax,
                amountText: est.amount, detail: est.detail, taskId: nil))
            log = "生成成功：\(urls.count) 张"
        } catch {
            log = "失败：\(error.localizedDescription)"
        }
    }

    private func recordPro(_ pro: PromptBank.ProResult) {
        let est = TokenEstimator.estimateProTotal(kind: .image, embedTokens: pro.embedTokens, genTokens: pro.genTokens)
        BillStore.shared.add(BillEntry(
            action: "试试手气 Pro", model: FixedModel.textGeneration,
            summary: "图片扩写", unitName: "次", unitCount: 1,
            tokenMin: est.tokenMin, tokenMax: est.tokenMax,
            amountText: est.amount, detail: est.detail, taskId: nil))
    }

    private func save(_ url: URL) async {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipForge/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("img_\(Int(Date().timeIntervalSince1970)).png")
        do {
            try await DashScopeClient.shared.download(url, to: dest)
            log = "已保存：\(dest.lastPathComponent)"
        } catch {
            log = "保存失败：\(error.localizedDescription)"
        }
    }
}

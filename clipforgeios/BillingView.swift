import SwiftUI
import UIKit

// MARK: - 账本页（BillStore + CSV 导出分享）

struct BillingView: View {
    @StateObject private var store = BillStore.shared

    @State private var showShare = false
    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            List {
                summarySection
                ForEach(store.entries) { e in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(e.action).font(.subheadline.bold())
                            Spacer()
                            Text(e.status).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(e.model).font(.footnote).foregroundStyle(.secondary)
                        Text(e.summary).font(.footnote)
                            .lineLimit(2)
                        HStack {
                            Text("≈\(e.tokenMin)–\(e.tokenMax) token")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text(e.amountText).font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("账本")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: exportCSV) {
                        Label("导出 CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.entries.isEmpty)
                }
            }
            .overlay {
                if store.entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "receipt").font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("还没有账单").font(.headline)
                        Text("生成图片 / 语音 / 视频时自动记账")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = csvURL { ShareSheet(url: url) }
            }
        }
    }

    private var summarySection: some View {
        Section {
            let today = store.summary(of: store.todayEntries)
            let month = store.summary(of: store.monthEntries)
            HStack {
                Text("今日"); Spacer()
                Text("\(today.count) 笔 · ¥\(String(format: "%.2f", today.amount))")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("本月"); Spacer()
                Text("\(month.count) 笔 · ¥\(String(format: "%.2f", month.amount))")
                    .foregroundStyle(.secondary)
            }
        } header: { Text("汇总") }
    }

    private func delete(at offsets: IndexSet) {
        let removed = offsets.map { store.entries[$0] }
        for r in removed { BillStore.shared.remove(id: r.id) }
    }

    private func exportCSV() {
        let text = store.csvText(store.entries)
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("clipforge_bill_\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            csvURL = url
            showShare = true
        } catch {
            csvURL = nil
        }
    }
}

// UIActivityViewController 封装（CSV 分享）
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

import Foundation
import Combine

// MARK: - 生成账单（纯 Foundation，去 AppKit 化；写时 flush + 由宿主在场景切换/退后台时调用 flush()）

struct BillEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var time: Date = Date()
    var action: String
    var model: String
    var summary: String
    var unitName: String
    var unitCount: Int
    var tokenMin: Int
    var tokenMax: Int
    var amountText: String
    var detail: String
    var taskId: String?
    var status: String = "已提交"

    enum CodingKeys: String, CodingKey {
        case id, time, action, model, summary, unitName, unitCount
        case tokenMin, tokenMax, amountText, detail, taskId, status
    }
}

@MainActor
final class BillStore: ObservableObject {
    static let shared = BillStore()

    @Published private(set) var entries: [BillEntry] = []

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("bill.jsonl")
    }()

    private var pending: [BillEntry] = []
    private let flushThreshold = 5

    private init() {
        load()
    }

    // MARK: - 读写

    func add(_ e: BillEntry) {
        entries.insert(e, at: 0)
        pending.append(e)
        if pending.count >= flushThreshold { flush() }
    }

    /// 把缓冲中的条目一次性追加写入磁盘；不足一批时由宿主（scenePhase 退后台/失活）兜底 flush
    func flush() {
        guard !pending.isEmpty else { return }
        var text = ""
        for e in pending {
            guard let data = try? JSONEncoder().encode(e),
                  let line = String(data: data, encoding: .utf8) else { continue }
            text += line + "\n"
        }
        appendRaw(text)
        pending.removeAll()
    }

    func update(id: UUID, taskId: String? = nil, status: String? = nil) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        if let t = taskId { entries[idx].taskId = t }
        if let s = status { entries[idx].status = s }
        rewriteDisk()
        pending.removeAll()
    }

    private func rewriteDisk() {
        var text = ""
        for e in entries.reversed() {
            guard let data = try? JSONEncoder().encode(e),
                  let line = String(data: data, encoding: .utf8) else { continue }
            text += line + "\n"
        }
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func appendRaw(_ text: String) {
        guard !text.isEmpty else { return }
        let row = text.hasSuffix("\n") ? text : text + "\n"
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(Data(row.utf8))
            handle.closeFile()
        } else {
            try? row.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        var list: [BillEntry] = []
        for line in text.split(separator: "\n") {
            if let d = line.data(using: .utf8),
               let e = try? JSONDecoder().decode(BillEntry.self, from: d) {
                list.append(e)
            }
        }
        entries = list.reversed()
    }

    func clear() {
        entries = []
        pending.removeAll()
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// 按 id 删除一条账单并回写磁盘
    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        pending.removeAll { $0.id == id }
        rewriteDisk()
    }

    // MARK: - 汇总

    struct Summary {
        var count: Int
        var amount: Double
        var tokenMin: Int
        var tokenMax: Int
    }

    func summary(of list: [BillEntry]) -> Summary {
        var amount = 0.0, tMin = 0, tMax = 0
        for e in list {
            amount += parseAmount(e.amountText)
            tMin += e.tokenMin
            tMax += e.tokenMax
        }
        return Summary(count: list.count, amount: amount, tokenMin: tMin, tokenMax: tMax)
    }

    private func parseAmount(_ s: String) -> Double {
        let digits = s.replacingOccurrences(
            of: "[^0-9.]", with: "", options: .regularExpression)
        return Double(digits) ?? 0
    }

    var todayEntries: [BillEntry] {
        let cal = Calendar.current
        return entries.filter { cal.isDateInToday($0.time) }
    }

    var monthEntries: [BillEntry] {
        let cal = Calendar.current
        let now = Date()
        return entries.filter {
            cal.isDate($0.time, equalTo: now, toGranularity: .month)
                && cal.isDate($0.time, equalTo: now, toGranularity: .year)
        }
    }

    // MARK: - CSV 导出

    func csvText(_ list: [BillEntry]) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var out = "\u{FEFF}时间,操作,模型,内容摘要,计量单位,数量,token下限,token上限,预估金额,任务ID,状态,计费口径\n"
        for e in list {
            out += csvRow([
                df.string(from: e.time),
                e.action,
                e.model,
                e.summary,
                e.unitName,
                String(e.unitCount),
                String(e.tokenMin),
                String(e.tokenMax),
                e.amountText,
                e.taskId ?? "",
                e.status,
                e.detail,
            ])
        }
        return out
    }

    private func csvRow(_ fields: [String]) -> String {
        fields.map { f in
            let needsQuote = f.contains(",") || f.contains("\"") || f.contains("\n")
            let escaped = f.replacingOccurrences(of: "\"", with: "\"\"")
            return needsQuote ? "\"\(escaped)\"" : escaped
        }.joined(separator: ",") + "\n"
    }
}

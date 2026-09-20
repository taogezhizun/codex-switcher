import SwiftUI
import AccountsCore

/// Read-only projection, including caches written before bucket metadata was stored.
enum QuotaPresentation {
    struct Group: Identifiable {
        let id: String
        let title: String
        let windows: [QuotaWindow]
        let unidentified: Bool
    }
    static func bucketID(_ window: QuotaWindow) -> String {
        if let id = window.bucketID, !id.isEmpty { return id }
        if let dot = window.id.lastIndex(of: ".") { return String(window.id[..<dot]) }
        return window.id
    }
    static func duration(_ window: QuotaWindow) -> String {
        window.label.components(separatedBy: " · ").last ?? window.label
    }
    static func friendlyName(_ window: QuotaWindow) -> String? {
        let id = bucketID(window)
        if let name = window.bucketName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty, name.caseInsensitiveCompare(id) != .orderedSame, !name.contains("_") {
            return name
        }
        return id == "codex" ? "Codex" : nil
    }
    static func groups(_ windows: [QuotaWindow]) -> [Group] {
        let buckets = Dictionary(grouping: windows, by: bucketID)
        let ids = buckets.keys.sorted { lhs, rhs in
            if (lhs == "codex") != (rhs == "codex") { return lhs == "codex" }
            return lhs < rhs
        }
        var unknown = 0
        return ids.map { id in
            let rows = buckets[id]!
            let name = rows.compactMap(friendlyName).first
            if name == nil { unknown += 1 }
            return Group(id: id, title: name ?? "其他额度 \(unknown)", windows: rows, unidentified: name == nil)
        }
    }
    /// Do not mistake a full, unrelated pool for the account's available Codex quota.
    static func summary(_ windows: [QuotaWindow]) -> QuotaWindow? {
        windows.filter { bucketID($0) == "codex" }.min { $0.remaining < $1.remaining }
    }
}

struct QuotaGroupsView: View {
    let windows: [QuotaWindow]
    private var groups: [QuotaPresentation.Group] { QuotaPresentation.groups(windows) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(groups.filter { !$0.unidentified }) { group in QuotaGroupView(group: group) }
            let other = groups.filter(\.unidentified)
            if !other.isEmpty {
                DisclosureGroup("其他额度（\(other.count) 组）") {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("接口未提供可识别的名称，暂不推测对应模型。这些额度不能与 Codex 额度相加。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ForEach(other) { group in QuotaGroupView(group: group) }
                    }.padding(.top, 12)
                }.font(.callout)
            }
            Text("百分比表示剩余额度；同组不同周期分别计算。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct QuotaGroupView: View {
    let group: QuotaPresentation.Group
    @State private var showingDetails = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text(group.title).font(.callout.weight(.medium))
                Button { showingDetails.toggle() } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .accessibilityLabel("\(group.title)的额度说明")
                    .popover(isPresented: $showingDetails) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title).font(.headline)
                            Text(group.unidentified ? "暂未确认这组额度对应的模型或功能。" : "名称来自接口显示名或已识别的 Codex 额度编号。")
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                            Text("接口编号").font(.caption).foregroundStyle(.secondary)
                            Text(group.id).font(.caption.monospaced()).textSelection(.enabled)
                            Text("不同额度组不能合并，也不保证可互相替代。").font(.caption).foregroundStyle(.secondary)
                        }.padding(18).frame(width: 300)
                    }
                Spacer()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 190), spacing: 14), count: min(2, group.windows.count)), spacing: 14) {
                ForEach(group.windows) { window in QuotaCard(window: window) }
            }.frame(maxWidth: group.windows.count == 1 ? 440 : .infinity, alignment: .leading)
        }
    }
}

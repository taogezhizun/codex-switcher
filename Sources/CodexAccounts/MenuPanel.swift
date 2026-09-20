import SwiftUI
import AppKit
import AccountsCore

struct MenuPanel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var menuBar: MenuBarController
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var contentHeight: CGFloat = 0
    @State private var pending: Account?
    @State private var recovering = false
    var accounts: [Account] { AccountPresentation.ordered(model.accounts, current: model.currentIdentity, query: query) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pending != nil || recovering {
                SwitchConfirmation(target: pending, compact: true, cancel: { pending = nil; recovering = false }) {
                    let target = pending; pending = nil; recovering = false
                    if let target { model.switchTo(target.id) } else { model.restore() }
                }.padding(20)
            } else {
                HStack(spacing: 10) {
                    BrandMark(size: 32)
                    VStack(alignment: .leading, spacing: 3) { Text("Codex Switcher").font(.headline); Text("选择账号，快速切换").font(.system(size: 10)).foregroundStyle(.secondary) }
                    Spacer()
                    Button { model.hideEmails.toggle() } label: { Image(systemName: model.hideEmails ? "eye.slash" : "eye").frame(width: 24, height: 24) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(model.hideEmails ? "显示邮箱" : "隐藏邮箱")
                }.padding(18)
                if let error = model.error { ErrorBanner(message: error) { model.error = nil }.padding([.horizontal, .bottom], 14) }
                if model.needsMigration { MigrationBanner().padding([.horizontal, .bottom], 14) }
                if model.awaitingConfirmation {
                    VStack(alignment: .leading, spacing: 9) {
                        Label(model.recoveryNeedsUnlock ? "恢复记录需要检查" : "请先核对上次切换", systemImage: "clock.badge.checkmark").font(.callout.weight(.medium))
                        Text(model.recoveryNeedsUnlock ? "重新检查本地恢复记录。" : "检查桌面 App 的账号，确认后才能继续切换。").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            if model.recoveryNeedsUnlock { Button("检查恢复记录…") { model.unlockRecoveryRecord() } }
                            else { Button("已核对") { model.confirmDesktopAccount() }; Button("恢复…") { recovering = true } }
                        }.disabled(model.busy || model.demo)
                    }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).padding([.horizontal, .bottom], 14)
                }
                if !model.accounts.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索账号", text: $query).textFieldStyle(.plain).accessibilityLabel("搜索账号")
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).accessibilityLabel("清除搜索") }
                    }.padding(10).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 14).padding(.bottom, 8)
                    if accounts.isEmpty {
                        VStack(spacing: 7) { Text("没有匹配的账号").font(.callout); Button("清除搜索") { query = "" }.font(.caption) }.frame(maxWidth: .infinity).padding(24)
                    } else {
                        ScrollView {
                            VStack(spacing: 3) {
                                ForEach(accounts) { account in
                                    QuickAccountRow(account: account) {
                                        model.selection = account.id
                                        if account.id == model.currentIdentity { model.openDesktop() }
                                        else { pending = account }
                                    }
                                    .disabled(model.busy || (account.id != model.currentIdentity && model.switchBlockReason(account.id) != nil))
                                }
                            }.padding(.horizontal, 8)
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: MenuRowsHeight.self, value: geometry.size.height)
                                })
                        }.frame(height: min(contentHeight > 0 ? contentHeight : CGFloat(accounts.count) * 88, 340))
                            .onPreferenceChange(MenuRowsHeight.self) { height in
                                if abs(height - contentHeight) > 0.5 { contentHeight = height }
                            }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("先保存你正在使用的账号").font(.callout.weight(.medium))
                        Text("以后切换时，不必重复登录。").font(.caption).foregroundStyle(.secondary)
                        Button("保存当前账号") { model.importCurrent() }.buttonStyle(.borderedProminent).disabled(model.busy || model.demo)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.busy || model.demo {
                    HStack(spacing: 7) {
                        if model.busy { ProgressView().controlSize(.small) }
                        Text(model.demo ? "演示模式 · 所有账号操作均不会执行" : model.status).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if model.busy && model.canCancel { Button("取消") { model.cancel() } }
                    }.padding(.horizontal, 18).padding(.vertical, 10)
                }
                if !model.demo { RefreshStatusView().padding(.horizontal, 18).padding(.bottom, 10) }
                MenuUpdateNotice(updates: model.updates).padding(.horizontal, 14)
                Divider()
                HStack {
                    Button { menuBar.openAccounts() } label: { Label("管理账号", systemImage: "sidebar.left") }
                    Spacer()
                    Menu {
                        Button("刷新全部账号额度") { model.refreshAll() }.disabled(model.busy || model.demo || model.awaitingConfirmation)
                        Button("恢复上次认证…") { recovering = true }
                            .disabled((!model.hasBackup && !model.recoveryNeedsUnlock) || model.credentialActionsBlocked)
                        CheckForAppUpdates(updates: model.updates)
                    } label: { Image(systemName: "ellipsis") }.help("更多操作")
                    Button { menuBar.openSettings() } label: { Image(systemName: "gearshape") }.help("设置")
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("退出 Codex Switcher").disabled(model.busy)
                }.buttonStyle(.borderless).padding(15)
            }
        }.frame(width: 368).fixedSize(horizontal: false, vertical: true)
            .background((colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color(red: 0.97, green: 0.97, blue: 0.98)).ignoresSafeArea())
            .onAppear { model.checkCurrentIdentity() }
            .sheet(isPresented: $model.showMigration) { MigrationView().environmentObject(model) }
    }
}

private struct QuickAccountRow: View {
    @EnvironmentObject var model: AppModel
    let account: Account
    let action: () -> Void
    @State private var hovered = false
    var current: Bool { account.id == model.currentIdentity }
    var summary: MenuQuotaSummary { MenuQuotaSummary.make(account: account, now: model.quotaDisplayDate) }
    var daily: DailyUsagePresentation { DailyUsagePresentation.make(account: account, now: model.quotaDisplayDate) }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                AccountAvatar(account: account, hideEmails: model.hideEmails, size: 36)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(model.title(account)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        if current { Text("当前认证").font(.system(size: 9, weight: .medium)).foregroundStyle(.tint).fixedSize() }
                        Spacer(minLength: 0)
                        Text(daily.text).font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary).fixedSize().help(daily.help)
                    }
                    Text(summary.text)
                        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if account.quotaNeedsLogin == true {
                        Text("需要重新登录").font(.system(size: 10)).foregroundStyle(.orange)
                    }
                    if let quota = QuotaPresentation.summary(account.quotas) { QuotaMeter(window: quota, height: 3) }
                }
                Image(systemName: current ? "arrow.up.forward" : "arrow.right").font(.caption.weight(.medium)).foregroundStyle(hovered ? .primary : .tertiary)
            }.padding(.horizontal, 11).padding(.vertical, 12)
                .background(current ? Color.accentColor.opacity(hovered ? 0.13 : 0.08) : hovered ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .help("\(summary.help)\n\(daily.help)\n\(current ? "打开桌面 App" : "查看切换确认")")
            .accessibilityLabel("\(model.title(account))，\(current ? "当前认证，打开桌面 App" : "切换账号")")
            .accessibilityValue("\(summary.text)\n\(daily.text)\n\(summary.help)\n\(daily.help)\(account.quotaNeedsLogin == true ? "\n需要重新登录" : "")")
    }
}

private struct MenuRowsHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

import SwiftUI
import AccountsCore

struct AccountsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var search = ""
    @State private var sidebarVisible = true
    @FocusState private var searchFocused: Bool
    @State private var pendingSwitch: Account?
    @State private var pendingRename: Account?
    @State private var pendingDelete: Account?
    @State private var showRestore = false
    var filtered: [Account] { AccountPresentation.ordered(model.accounts, current: model.currentIdentity, query: search) }

    var body: some View {
        HSplitView {
            if sidebarVisible {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索备注或邮箱", text: $search).textFieldStyle(.plain)
                            .focused($searchFocused).accessibilityLabel("搜索备注或邮箱")
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).accessibilityLabel("清除搜索")
                        }
                    }.padding(7).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7)).padding(10)
                    List(selection: $model.selection) {
                        Section {
                            ForEach(filtered) { account in
                                AccountSidebarRow(account: account).tag(account.id)
                                    .contextMenu {
                                        Button("切换至此账号…") { pendingSwitch = account }.disabled(model.switchBlockReason(account.id) != nil)
                                        Button("刷新额度") { model.refresh(account.id) }.disabled(!model.canRefresh(account.id))
                                        Divider()
                                        Button("编辑备注…") { pendingRename = account }.disabled(model.busy || model.demo)
                                        Button("移除账号…", role: .destructive) { pendingDelete = account }.disabled(model.busy || model.demo)
                                    }
                            }
                        } header: {
                            HStack { Text(search.isEmpty ? "已保存的账号" : "搜索结果"); Spacer(); Text("\(filtered.count)").monospacedDigit() }
                        }
                    }.listStyle(.sidebar)
                    Divider().padding(.horizontal, 14)
                    HStack(spacing: 7) {
                        Image(systemName: model.demo ? "play.rectangle" : "lock.shield")
                        Text(model.demo ? "虚构账号 · 安全演示" : "本机文件存储").font(.caption)
                        Spacer()
                    }.foregroundStyle(.secondary).padding(16)
                }
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
                .background(.regularMaterial, ignoresSafeAreaEdges: [])
            }
            VStack(spacing: 0) {
                if model.needsMigration { MigrationBanner().padding([.top, .horizontal], 24) }
                if model.awaitingConfirmation {
                    RecoveryBanner { showRestore = true }.padding([.top, .horizontal], 24)
                }
                if let error = model.error {
                    ErrorBanner(message: error) { model.error = nil }.padding([.top, .horizontal], 24)
                }
                if model.accounts.isEmpty {
                    WelcomeView()
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("没有匹配的账号", systemImage: "magnifyingglass")
                    } description: { Text("试试账号备注或邮箱，或者清除搜索条件。") }
                    actions: { Button("清除搜索") { search = "" } }
                } else if let account = model.selected {
                    AccountDetail(account: account, switchAction: { pendingSwitch = account }, renameAction: { pendingRename = account }, deleteAction: { pendingDelete = account })
                } else {
                    ContentUnavailableView("选择一个账号", systemImage: "sidebar.left", description: Text("在左侧选择账号，查看额度或进行切换。"))
                }
                StatusFooter()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor), ignoresSafeAreaEdges: [])
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    sidebarVisible.toggle()
                } label: { Image(systemName: "sidebar.left") }
                    .accessibilityLabel(sidebarVisible ? "收起侧栏" : "显示侧栏")
                    .help(sidebarVisible ? "收起侧栏" : "显示侧栏")
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }
            ToolbarItemGroup {
                if model.demo {
                    Text("DEMO").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    Button("预览菜单栏", systemImage: "menubar.rectangle") { openWindow(id: "menu-preview") }.help("打开使用同一组件的菜单栏预览")
                }
                Button {
                    model.hideEmails.toggle()
                } label: { Image(systemName: model.hideEmails ? "eye.slash" : "eye") }
                    .help(model.hideEmails ? "显示邮箱（⇧⌘P）" : "隐藏邮箱（⇧⌘P）")
                    .accessibilityLabel(model.hideEmails ? "显示邮箱" : "隐藏邮箱")
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                AddAccountMenu().disabled(model.credentialActionsBlocked)
                Menu {
                    Button("刷新全部账号额度") { model.refreshAll() }.disabled(model.busy || model.demo || model.awaitingConfirmation)
                    Button("打开桌面 App") { model.openDesktop() }.disabled(model.busy || model.demo)
                    Button("恢复上次认证…") { showRestore = true }.disabled((!model.hasBackup && !model.recoveryNeedsUnlock) || model.busy || model.demo)
                    Divider()
                    Button("搜索账号") { sidebarVisible = true; searchFocused = true }.keyboardShortcut("f")
                    SettingsLink { Text("设置…") }
                } label: { Label("更多操作", systemImage: "ellipsis.circle") }.help("更多操作")
            }
        }
        .sheet(isPresented: $model.showMigration) { MigrationView().environmentObject(model) }
        .sheet(item: $pendingSwitch) { account in RestartSheet(target: account) }
        .sheet(isPresented: $showRestore) { RestartSheet(target: nil) }
        .sheet(item: $pendingRename) { account in RenameSheet(account: account) }
        .alert("移除这个账号？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("移除", role: .destructive) { if let id = pendingDelete?.id { model.delete(id) }; pendingDelete = nil }
        } message: { Text("仅移除本工具保存的账号。桌面 App 当前登录和恢复备份会保留。") }
        .onAppear { model.checkCurrentIdentity() }
        .onChange(of: search) { _, _ in
            if !filtered.contains(where: { $0.id == model.selection }) {
                model.selection = filtered.first?.id
            }
        }
    }
}

struct AccountSidebarRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.controlActiveState) private var activeState
    let account: Account
    private var highlighted: Bool { model.selection == account.id && activeState != .inactive }
    private var secondaryColor: Color { highlighted ? .white.opacity(0.85) : .secondary }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AccountAvatar(account: account, hideEmails: model.hideEmails, highlighted: highlighted)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(model.title(account)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    if account.id == model.currentIdentity { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(highlighted ? .white : Color.accentColor).accessibilityLabel("当前认证") }
                }
                HStack(spacing: 5) {
                    Text(account.plan.uppercased()).font(.system(size: 10, weight: .medium))
                    if account.id == model.currentIdentity { Text("· 当前认证").font(.system(size: 10)) }
                }.foregroundStyle(secondaryColor)
                if let first = QuotaPresentation.summary(account.quotas) {
                    HStack(spacing: 7) {
                        QuotaMeter(window: first, height: 3, highlighted: highlighted).frame(maxWidth: 74)
                        Text("\(Int(first.remaining))% 剩余").font(.system(size: 10)).monospacedDigit().foregroundStyle(secondaryColor)
                        if AccountPresentation.needsRefresh(account) { Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(secondaryColor).help("缓存可能已过期，请刷新额度") }
                    }.padding(.top, 2).help("Codex \(QuotaPresentation.duration(first))：剩余 \(Int(first.remaining))%。摘要显示 Codex 各周期中的最低值。")
                } else { Text("Codex 额度未读取").font(.system(size: 10)).foregroundStyle(secondaryColor) }
            }
        }.padding(.vertical, 9)
    }
}

struct AddAccountMenu: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Menu {
            Button("保存当前账号", systemImage: "square.and.arrow.down") { model.importCurrent() }
            Button("浏览器添加账号…", systemImage: "globe") { model.addViaLogin() }
            Button("设备码添加账号…", systemImage: "key.horizontal") { model.addViaLogin(device: true) }
            Divider()
            Button("从 JSON 导入…", systemImage: "doc.badge.plus") { model.importFile() }
        } label: { Label("添加账号", systemImage: "plus") }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer(minLength: 12)
            BrandMark(size: 70)
            VStack(alignment: .leading, spacing: 10) {
                Text("你的账号，随时切换。").font(.system(size: 27, weight: .semibold))
                Text("先保存正在使用的账号。以后从菜单栏选择账号，\n就能完成切换并重新打开 Codex。")
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            }
            VStack(spacing: 0) {
                OnboardingRow(number: "1", title: "保存当前账号", detail: "保留现在的登录，方便随时切回来。")
                Divider().padding(.leading, 52)
                OnboardingRow(number: "2", title: "添加另一个账号", detail: "通过 OpenAI 官方浏览器页面登录。")
                Divider().padding(.leading, 52)
                OnboardingRow(number: "3", title: "从菜单栏快速切换", detail: "切换前备份，遇到问题可以恢复。")
            }.padding(.horizontal, 16).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
            HStack(spacing: 14) {
                Button { model.importCurrent() } label: { Label("保存当前账号", systemImage: "square.and.arrow.down").padding(.horizontal, 4) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy || model.demo)
                Button("浏览器添加…") { model.addViaLogin() }.controlSize(.large).disabled(model.busy || model.demo)
            }
            if !model.configured && !model.demo {
                HStack { Image(systemName: "info.circle"); Text("没有找到桌面 App。"); SettingsLink { Text("前往设置") } }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
        }.padding(.horizontal, 40).padding(.vertical, 20).frame(maxWidth: 600, maxHeight: .infinity, alignment: .leading)
    }
}

struct OnboardingRow: View {
    let number: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            Text(number).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).frame(width: 28, height: 28).background(.quaternary.opacity(0.5), in: Circle())
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 13, weight: .medium)); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(.vertical, 15)
    }
}

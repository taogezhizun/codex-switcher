import SwiftUI
import AccountsCore

struct RestartSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: Account?
    var body: some View {
        SwitchConfirmation(target: target, compact: false, cancel: { dismiss() }) { terminateImmediately in
            dismiss()
            if let target { model.switchTo(target.id, terminateImmediately: terminateImmediately) }
            else { model.restore(terminateImmediately: terminateImmediately) }
        }.padding(28).frame(width: 480)
    }
}

struct SwitchConfirmation: View {
    @EnvironmentObject var model: AppModel
    let target: Account?
    var compact = false
    let cancel: () -> Void
    let perform: (_ terminateImmediately: Bool) -> Void
    @State private var ready = false
    private var actionsDisabled: Bool {
        !ready || model.busy || model.demo || (target.map { model.switchBlockReason($0.id) != nil } ?? false)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 22) {
            HStack(spacing: 11) {
                BrandMark(size: compact ? 34 : 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(target == nil ? "恢复上次认证" : "确认切换账号").font(compact ? .headline : .title2.weight(.semibold))
                    Text("桌面 App 将退出并重新打开").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 13) {
                HStack(spacing: 10) {
                    if let source = model.currentAccount { AccountAvatar(account: source, hideEmails: model.hideEmails, size: 34) }
                    else { Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(.secondary).frame(width: 34) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前认证").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(model.currentAccount.map { model.title($0) } ?? "未保存的当前账号").font(.callout.weight(.medium)).lineLimit(1)
                    }
                    Spacer()
                }
                HStack { Image(systemName: "arrow.down").font(.caption).foregroundStyle(.tertiary).frame(width: 34); Rectangle().fill(.quaternary).frame(height: 1) }
                HStack(spacing: 10) {
                    if let target { AccountAvatar(account: target, hideEmails: model.hideEmails, size: 34) }
                    else { Image(systemName: "clock.arrow.circlepath").font(.title2).foregroundStyle(.tint).frame(width: 34) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(target == nil ? "恢复为" : "切换为").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(target.map { model.title($0) } ?? "上一次保存的认证").font(.callout.weight(.semibold)).lineLimit(2)
                    }
                    Spacer()
                }
            }.padding(16).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 12) {
                Toggle("我已暂停任务，可以重开桌面 App", isOn: $ready).toggleStyle(.checkbox).font(.callout)
                Text("本工具无法判断所有运行中的任务。请先保存编辑，并暂停共享此账号的 CLI。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("切换前会保存原认证备份，供操作失败时恢复。账号与备份保存在本机私有文件。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.demo { Label("演示模式：不会更改账号或重开 App", systemImage: "play.rectangle").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 10) {
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(target == nil ? "恢复并重开" : "切换并重开") { perform(false) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(actionsDisabled)
            }.controlSize(.large)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Button(role: .destructive) { perform(true) } label: {
                    Text(target == nil ? "结束 Codex 并恢复" : "结束 Codex 并切换").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).controlSize(.large).disabled(actionsDisabled)
                Text("跳过正常退出等待，直接结束当前 Codex 及已确认的后台进程；仍无响应时强制结束。未完成任务会中断。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ShutdownConfirmationView: View {
    @EnvironmentObject var model: AppModel
    let prompt: DesktopShutdownPrompt
    @State private var ready = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(prompt.title, systemImage: "exclamationmark.triangle").font(.headline)
            Text(prompt.mainAppRunning
                 ? "请先查看 Codex 是否正在等待退出确认。若仍无法退出，可以结束该实例后继续切换。"
                 : "Codex 主程序已退出，但本次检测到的后台程序仍在运行，可以结束残留进程后继续。")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("已确认 \(prompt.processCount) 个相关进程。继续会先请求结束，仍无响应时强制结束，未完成的任务会中断。原登录凭据尚未更改。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("任务已保存，允许结束这些进程", isOn: $ready).toggleStyle(.checkbox).font(.callout)
            HStack {
                Button("取消切换") { model.answerShutdown(terminate: false) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("结束进程并继续", role: .destructive) { model.answerShutdown(terminate: true) }
                    .disabled(!ready || model.demo)
            }
        }.padding(18).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RenameSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @State private var name = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("编辑账号备注").font(.title2.weight(.semibold))
            Text("用你熟悉的名字区分账号，例如“日常工作”。").font(.callout).foregroundStyle(.secondary)
            TextField("账号备注", text: $name).textFieldStyle(.roundedBorder).focused($focused).onSubmit(save)
            HStack { Text("最多 80 个字符").font(.caption).foregroundStyle(.secondary); Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存", action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || model.demo) }
        }.padding(26).frame(width: 410).onAppear { name = account.nickname; focused = true }
    }
    private func save() { model.rename(account.id, nickname: name); dismiss() }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("外观与隐私") {
                Picker("外观", selection: $model.appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                Toggle("隐藏账号邮箱", isOn: $model.hideEmails)
                Toggle("在状态栏显示剩余额度", isOn: $model.showMenuBarQuota)
                Text("隐藏邮箱不会隐藏你填写的备注。公开截图请始终使用演示模式。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("额度刷新") {
                Toggle("自动刷新所有已保存账号的额度", isOn: $model.automaticRefresh).disabled(model.demo)
                RefreshStatusView()
                Text("每 5 分钟刷新已保存账号，最多同时查询 2 个。失败保留缓存并延后重试；凭据失效时提示重新登录，不自动打开登录页面。后台刷新不访问钥匙串、不切换桌面账号。旧数据迁移前仅刷新当前账号。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("本地存储") {
                if model.needsMigration { MigrationBanner() }
                else { Text("账号与恢复备份保存在本机私有文件，正常账号操作不访问钥匙串。").font(.callout) }
                Text("凭据未经过应用层加密，不会主动上传。迁移前的旧钥匙串记录保留但不再使用；系统备份是否包含文件取决于你的备份设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("应用更新") {
                UpdateSettingsView(updates: model.updates)
            }
            Section("桌面 App") {
                LabeledContent("已选择", value: model.application?.lastPathComponent ?? "未找到")
                Button("选择桌面 App…") { model.chooseApplication() }.disabled(model.demo || model.busy || model.updates.sessionInProgress)
            }
            Section("认证目录") {
                Text(model.demo ? "演示目录" : model.home.path).font(.caption.monospaced()).textSelection(.enabled)
                Button("选择目录…") { model.chooseHome() }.disabled(model.demo || model.busy || model.updates.sessionInProgress)
                Text("应与桌面 App 的 CODEX_HOME 一致。支持文件认证；其他认证存储方式和共享守护进程仍不支持。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("关于") {
                HStack(spacing: 12) { BrandMark(size: 38); VStack(alignment: .leading, spacing: 4) { Text("Codex Switcher").font(.headline); Text("\(AppUpdates.version) · macOS 原生 · MIT License").font(.caption).foregroundStyle(.secondary) } }
                Link("开发与维护：\(AppUpdates.author)", destination: AppUpdates.profileURL)
                Link("项目主页 · 源码与反馈", destination: AppUpdates.projectURL)
                Link("灵感来源：codex-account-switcher", destination: URL(string: "https://github.com/cjg1995/codex-account-switcher")!)
                Link("自动刷新设计参考：OpenUsage", destination: URL(string: "https://github.com/robinebers/openusage")!)
                Link("菜单交互参考：liuzhao1225/codex-account-switcher", destination: URL(string: "https://github.com/liuzhao1225/codex-account-switcher")!)
                Link("应用更新组件：Sparkle", destination: URL(string: "https://sparkle-project.org")!)
                Text("独立开发，与 OpenAI 及原项目作者无隶属或背书关系。凭据保存在本机私有文件，登录和额度查询连接 OpenAI。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(10).disabled(model.busy && !model.refreshingAutomatically)
            .sheet(isPresented: $model.showMigration) { MigrationView().environmentObject(model) }
    }
}

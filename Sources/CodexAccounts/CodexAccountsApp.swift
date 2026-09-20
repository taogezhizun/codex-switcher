import SwiftUI
import AppKit

@main struct CodexAccountsApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @StateObject private var model = AppModel(demo: PreviewConfiguration.enabled)
    @StateObject private var menuBar = MenuBarController()
    var body: some Scene {
        Window("Codex Switcher", id: "accounts") {
            AccountsView().environmentObject(model).environmentObject(menuBar)
                .frame(minWidth: 820, minHeight: 590)
                .preferredColorScheme(model.preferredColorScheme)
        }
        .defaultSize(width: 900, height: 620)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("管理账号") { menuBar.openAccounts() }.keyboardShortcut("0")
                CheckForAppUpdates(updates: model.updates).environmentObject(model)
            }
            CommandGroup(replacing: .newItem) {
                Button("浏览器添加账号…") { model.addViaLogin() }.keyboardShortcut("n").disabled(model.credentialActionsBlocked)
            }
        }
        Settings { SettingsView().environmentObject(model).preferredColorScheme(model.preferredColorScheme).frame(width: 540) }
    }
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

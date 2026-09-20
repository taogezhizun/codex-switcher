import SwiftUI
import AppKit

@main struct CodexAccountsApp: App {
    @StateObject private var model = AppModel(demo: PreviewConfiguration.enabled)
    var body: some Scene {
        WindowGroup("Codex Switcher", id: "accounts") {
            AccountsView().environmentObject(model)
                .frame(minWidth: 820, minHeight: 590)
                .preferredColorScheme(model.preferredColorScheme)
        }
        .defaultSize(width: 900, height: 620)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForAppUpdates(updates: model.updates).environmentObject(model)
            }
            CommandGroup(replacing: .newItem) {
                Button("浏览器添加账号…") { model.addViaLogin() }.keyboardShortcut("n").disabled(model.credentialActionsBlocked)
            }
        }
        MenuBarExtra {
            MenuPanel().environmentObject(model).preferredColorScheme(model.preferredColorScheme)
        } label: {
            StatusBarLabel().environmentObject(model)
        }.menuBarExtraStyle(.window)
        Settings { SettingsView().environmentObject(model).preferredColorScheme(model.preferredColorScheme).frame(width: 540) }
        Window("快速切换", id: "menu-preview") {
            MenuPanel().environmentObject(model).preferredColorScheme(model.preferredColorScheme)
        }.windowResizability(.contentSize)
    }
}

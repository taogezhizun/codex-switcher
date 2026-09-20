import AppKit
import Combine
import SwiftUI

/// One status item and one native popover, shared by production and UI acceptance.
@MainActor final class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private weak var model: AppModel?
    private var observation: AnyCancellable?
    private var renderingScheduled = false
    private var lastLabel: StatusBarQuota?
    private var lastShowsQuota: Bool?
    private var manageAction: () -> Void = {}
    private var settingsAction: () -> Void = {}

    func start(model: AppModel, manage: @escaping () -> Void, settings: @escaping () -> Void) {
        manageAction = manage; settingsAction = settings
        guard statusItem == nil else { return }
        self.model = model
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.image = SwitchGlyph.menuBarImage
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.animates = false
        observation = model.objectWillChange.sink { [weak self] _ in
            guard let self, !self.renderingScheduled else { return }
            self.renderingScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.renderingScheduled = false
                self?.renderLabel()
            }
        }
        renderLabel()

    }

    private func renderLabel() {
        guard let model, let button = statusItem?.button else { return }
        let label = StatusBarQuota.make(account: model.currentAccount, pending: model.awaitingConfirmation,
                                       hideEmails: model.hideEmails, now: model.quotaDisplayDate)
        // Do not redraw the system status item on every model clock tick.
        if label != lastLabel || model.showMenuBarQuota != lastShowsQuota {
            button.title = model.showMenuBarQuota ? " \(label.text)" : ""
            button.toolTip = label.help
            button.setAccessibilityLabel("Codex Switcher，\(label.help)")
            lastLabel = label; lastShowsQuota = model.showMenuBarQuota
        }
        let appearance: NSAppearance? = model.appearance == "dark" ? NSAppearance(named: .darkAqua)
            : model.appearance == "light" ? NSAppearance(named: .aqua) : nil
        popover.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { show() }
    }

    func show() {
        guard let model, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            return
        }
        // Activating the application here can switch back to its management-window
        // Space. Only the popover takes keyboard focus; explicit management and
        // settings actions below still activate the application.
        let host = MenuHostingController(rootView: MenuPanel().environmentObject(model).environmentObject(self))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        renderLabel()
        host.view.layoutSubtreeIfNeeded()
        popover.contentSize = host.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)

    }

    func openAccounts() {
        popover.performClose(nil)
        manageAction()
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettings() {
        popover.performClose(nil)
        settingsAction()
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class MenuHostingController<Content: View>: NSHostingController<Content> {
    override func viewWillAppear() {
        super.viewWillAppear()
        guard let window = view.window else { return }
        // Apply to the popup window, never the management window. Preserve the
        // native popover's transient/nonactivating behavior and dismissal rules.
        window.collectionBehavior.subtract([.moveToActiveSpace, .fullScreenPrimary, .fullScreenNone, .primary, .auxiliary])
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications])
    }
}

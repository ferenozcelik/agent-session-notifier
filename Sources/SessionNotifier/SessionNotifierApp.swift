import AppKit
import ServiceManagement
import SwiftUI

@main
struct SessionNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: delegate.store, hooks: delegate.hooks)
        } label: {
            MenuBarLabel(store: delegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: SessionStore
    let hooks: HookInstaller
    private var inbox: EventInbox!

    override init() {
        Prefs.registerDefaults()
        store = SessionStore()
        hooks = HookInstaller()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.setup()
        Notifier.shared.onOpen = { [weak self] id in
            guard let session = self?.store.session(id: id) else { return }
            TerminalApp.focus(session)
        }

        inbox = EventInbox { [weak self] event in self?.store.apply(event) }
        inbox.start()

        // Enable launch at login on first launch (can be turned off from the menu).
        if !UserDefaults.standard.bool(forKey: "didSetupLoginItem") {
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
            try? SMAppService.mainApp.register()
        }
    }
}

struct MenuBarLabel: View {
    let store: SessionStore

    var body: some View {
        if store.waitingCount > 0 {
            Image(nsImage: MenuBarIcon.image(.waiting))
            Text("\(store.waitingCount)")
        } else if store.runningCount > 0 {
            Image(nsImage: MenuBarIcon.image(.running))
        } else if store.doneCount > 0 {
            Image(nsImage: MenuBarIcon.image(.done))
        } else {
            Image(nsImage: MenuBarIcon.image(.idle))
        }
    }
}

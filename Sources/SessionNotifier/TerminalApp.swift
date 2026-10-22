import AppKit

/// Finds the terminal / editor app the session runs in and brings it to the front.
@MainActor
enum TerminalApp {
    /// Fallback guess from TERM_PROGRAM when `__CFBundleIdentifier` is missing.
    private static let termPrograms: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "vscode": "com.microsoft.VSCode",
        "ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm",
    ]

    private static var iconCache: [String: NSImage] = [:]

    static func bundleID(for session: Session) -> String? {
        session.appBundleID ?? session.termProgram.flatMap { termPrograms[$0] }
    }

    static func icon(for session: Session) -> NSImage? {
        guard let id = bundleID(for: session) else { return nil }
        if let cached = iconCache[id] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[id] = icon
        return icon
    }

    static func isFrontmost(_ session: Session) -> Bool {
        guard let id = bundleID(for: session) else { return false }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id
    }

    static func focus(_ session: Session) {
        if let id = bundleID(for: session),
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            app.activate()
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd))
        }
    }
}

import Foundation
import Observation

/// Adds / removes the global hooks in `~/.claude/settings.json`.
/// The hooks run a small shell script that writes the event to the `events/` folder.
@Observable
@MainActor
final class HookInstaller {
    static let events = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    private(set) var isInstalled = false
    private(set) var lastError: String?

    private let settingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    /// The command in settings.json. Quoted because the path contains a space.
    private var command: String { "\"\(AppPaths.hookScript.path)\"" }
    private let marker = "SessionNotifier/hook.sh"

    init() {
        writeScript()
        refresh()
    }

    func refresh() {
        let hooks = readSettings()?["hooks"] as? [String: Any] ?? [:]
        isInstalled = Self.events.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains(where: containsOurs)
        }
    }

    func install() {
        update { hooks in
            for event in Self.events {
                var groups = (hooks[event] as? [[String: Any]] ?? []).filter { !containsOurs($0) }
                groups.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
                hooks[event] = groups
            }
        }
    }

    func uninstall() {
        update { hooks in
            for (event, value) in hooks {
                guard let groups = value as? [[String: Any]] else { continue }
                let kept = groups.filter { !containsOurs($0) }
                if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
            }
        }
    }

    // MARK: - Helpers

    private func containsOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains {
            ($0["command"] as? String)?.contains(marker) == true
        }
    }

    private func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func update(_ change: (inout [String: Any]) -> Void) {
        lastError = nil
        let fm = FileManager.default
        var settings: [String: Any] = [:]

        if fm.fileExists(atPath: settingsURL.path) {
            guard let existing = readSettings() else {
                lastError = "Couldn't read settings.json (invalid JSON?). The file was left untouched."
                return
            }
            settings = existing
            // Back up before every change.
            let backup = settingsURL.appendingPathExtension("sessionnotifier-backup")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: settingsURL, to: backup)
        } else {
            try? fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        change(&hooks)
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }

        do {
            let data = try JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            lastError = "Couldn't write settings.json: \(error.localizedDescription)"
        }
        refresh()
    }

    /// Writes the latest hook script on every launch.
    private func writeScript() {
        let script = #"""
        #!/bin/sh
        # SessionNotifier hook: drops the Claude Code event into the folder the app reads.
        # Events are kept even if the app is closed. Always exits 0 so it never blocks Claude.
        dir="$HOME/Library/Application Support/SessionNotifier/events"
        mkdir -p "$dir" 2>/dev/null || exit 0
        tmp=$(mktemp "$dir/.evt.XXXXXXXX" 2>/dev/null) || exit 0
        app=$(printf '%s' "${__CFBundleIdentifier:-}" | tr -cd 'A-Za-z0-9._-')
        term=$(printf '%s' "${TERM_PROGRAM:-}" | tr -cd 'A-Za-z0-9._-')
        { printf '{"app":"%s","term":"%s","payload":' "$app" "$term"; cat; printf '}\n'; } > "$tmp" 2>/dev/null
        mv "$tmp" "$dir/${tmp##*/.}.json" 2>/dev/null || rm -f "$tmp"
        exit 0
        """#
        let url = AppPaths.hookScript
        try? script.appending("\n").write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

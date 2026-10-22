import Foundation

enum SessionStatus: String, Codable {
    case waiting   // waiting for permission / approval
    case running   // working
    case done      // finished responding, your turn
    case idle      // open, nothing asked yet

    /// Sort priority in the list (lower comes first).
    var sortOrder: Int {
        switch self {
        case .waiting: 0
        case .running: 1
        case .done: 2
        case .idle: 3
        }
    }

    var label: String {
        switch self {
        case .waiting: "Needs approval"
        case .running: "Running"
        case .done: "Done"
        case .idle: "Idle"
        }
    }
}

struct Session: Codable, Identifiable {
    let id: String
    var cwd: String
    var status: SessionStatus
    var lastMessage: String?
    var lastPrompt: String?
    var transcriptPath: String?
    var customTitle: String?   // name set with /rename
    var aiTitle: String?       // Claude's automatic title
    var appBundleID: String?
    var termProgram: String?
    var startedAt: Date
    var updatedAt: Date

    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    /// Name shown in the list and in notifications.
    var name: String { customTitle ?? aiTitle ?? project }

    /// If the name isn't the folder name, show the folder next to it.
    var hasOwnName: Bool { customTitle != nil || aiTitle != nil }

    /// Text shown on the second line of the row.
    var detail: String? {
        switch status {
        case .waiting, .done: lastMessage ?? lastPrompt
        case .running: lastPrompt
        case .idle: nil
        }
    }
}

/// A single Claude Code event written by the hook script.
struct HookEvent {
    let name: String
    let sessionID: String
    let date: Date
    let cwd: String?
    let transcriptPath: String?
    let message: String?
    let notificationType: String?
    let prompt: String?
    let lastAssistantMessage: String?
    let appBundleID: String?
    let termProgram: String?

    init?(data: Data, date: Date) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              let name = payload["hook_event_name"] as? String,
              let sessionID = payload["session_id"] as? String
        else { return nil }

        func nonEmpty(_ value: Any?) -> String? {
            guard let s = value as? String, !s.isEmpty else { return nil }
            return s
        }

        self.name = name
        self.sessionID = sessionID
        self.date = date
        cwd = nonEmpty(payload["cwd"])
        transcriptPath = nonEmpty(payload["transcript_path"])
        message = nonEmpty(payload["message"])
        notificationType = nonEmpty(payload["notification_type"])
        prompt = nonEmpty(payload["prompt"])
        lastAssistantMessage = nonEmpty(payload["last_assistant_message"])
        appBundleID = nonEmpty(root["app"])
        termProgram = nonEmpty(root["term"])
    }
}

enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SessionNotifier", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let events = support.appendingPathComponent("events", isDirectory: true)
    static let hookScript = support.appendingPathComponent("hook.sh")
    static let sessions = support.appendingPathComponent("sessions.json")
}

/// User preferences (UserDefaults keys, also used with @AppStorage in views).
enum Prefs {
    static let notifyWaiting = "notifyWaiting"
    static let notifyDone = "notifyDone"
    static let sound = "sound"
    static let quietWhenFrontmost = "quietWhenFrontmost"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            notifyWaiting: true,
            notifyDone: true,
            sound: true,
            quietWhenFrontmost: false,
        ])
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
}

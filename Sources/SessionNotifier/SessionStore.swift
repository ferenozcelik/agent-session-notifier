import Foundation
import Observation

@Observable
@MainActor
final class SessionStore {
    private(set) var sessions: [Session] = []

    /// No notification for events older than this (those queued while the app was closed).
    private let notifyWindow: TimeInterval = 120
    /// Sessions with no events for this long are dropped from the list
    /// (for terminals closed without a SessionEnd).
    private let staleAfter: TimeInterval = 24 * 3600

    private var pruneTimer: Timer?
    private let titleReader = TitleReader()

    init() {
        load()
        prune()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
    }

    var waitingCount: Int { sessions.filter { $0.status == .waiting }.count }
    var runningCount: Int { sessions.filter { $0.status == .running }.count }
    var doneCount: Int { sessions.filter { $0.status == .done }.count }

    // MARK: - Events

    func apply(_ event: HookEvent) {
        if event.name == "SessionEnd" {
            remove(event.sessionID)
            return
        }

        var session = sessions.first { $0.id == event.sessionID } ?? Session(
            id: event.sessionID,
            cwd: event.cwd ?? "?",
            status: .idle,
            startedAt: event.date,
            updatedAt: event.date
        )
        if let cwd = event.cwd { session.cwd = cwd }
        if let path = event.transcriptPath { session.transcriptPath = path }
        if let titles = titleReader.titles(at: session.transcriptPath) {
            if let custom = titles.custom { session.customTitle = custom }
            if let ai = titles.ai { session.aiTitle = ai }
        }
        if let app = event.appBundleID { session.appBundleID = app }
        if let term = event.termProgram { session.termProgram = term }
        session.updatedAt = event.date

        let fresh = Date().timeIntervalSince(event.date) < notifyWindow

        switch event.name {
        case "SessionStart":
            session.status = .idle
            session.lastMessage = nil

        case "UserPromptSubmit":
            session.status = .running
            session.lastPrompt = event.prompt.flatMap { Transcript.condense($0, limit: 200) }
            session.lastMessage = nil
            Notifier.shared.clear(sessionID: session.id)

        case "PostToolUse":
            // If permission was granted the tool ran; go back to "running".
            session.status = .running
            Notifier.shared.clear(sessionID: session.id)

        case "Notification":
            switch NotificationKind(event) {
            case .needsApproval:
                session.status = .waiting
                session.lastMessage = event.message
                if fresh && Prefs.bool(Prefs.notifyWaiting) {
                    notify(session, title: "\(session.name) · needs approval",
                           body: event.message ?? "Claude is waiting for your approval")
                }
            case .idleReminder:
                // Usually arrives after Stop, which already notified. Catch it here if Stop was missed.
                if session.status == .running {
                    session.status = .done
                    if fresh && Prefs.bool(Prefs.notifyDone) {
                        notify(session, title: "\(session.name) · waiting for you",
                               body: event.message ?? "Claude finished responding")
                    }
                }
            case .other:
                break
            }

        case "Stop":
            session.status = .done
            session.lastMessage = event.lastAssistantMessage.flatMap { Transcript.condense($0) }
                ?? Transcript.lastAssistantText(at: session.transcriptPath)
            if fresh && Prefs.bool(Prefs.notifyDone) {
                notify(session, title: "\(session.name) · done",
                       body: session.lastMessage ?? session.lastPrompt ?? "Claude finished responding")
            }

        default:
            break
        }

        upsert(session)
    }

    private func notify(_ session: Session, title: String, body: String) {
        if Prefs.bool(Prefs.quietWhenFrontmost) && TerminalApp.isFrontmost(session) { return }
        Notifier.shared.post(sessionID: session.id, title: title,
                             subtitle: session.hasOwnName ? session.project : nil, body: body)
    }

    // MARK: - List

    /// Waiting first, then running, then done; newest first within each group.
    var sorted: [Session] {
        sessions.sorted {
            if $0.status.sortOrder != $1.status.sortOrder { return $0.status.sortOrder < $1.status.sortOrder }
            return $0.updatedAt > $1.updatedAt
        }
    }

    func session(id: String) -> Session? {
        sessions.first { $0.id == id }
    }

    func remove(_ id: String) {
        sessions.removeAll { $0.id == id }
        Notifier.shared.clear(sessionID: id)
        save()
    }

    /// Removes done and idle sessions from the list.
    func clearFinished() {
        let ids = sessions.filter { $0.status == .done || $0.status == .idle }.map(\.id)
        ids.forEach { Notifier.shared.clear(sessionID: $0) }
        sessions.removeAll { ids.contains($0.id) }
        save()
    }

    private func upsert(_ session: Session) {
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[i] = session
        } else {
            sessions.append(session)
        }
        save()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        let before = sessions.count
        sessions.removeAll { $0.updatedAt < cutoff }
        if sessions.count != before { save() }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.sessions),
              let decoded = try? JSONDecoder().decode([Session].self, from: data)
        else { return }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: AppPaths.sessions, options: .atomic)
    }
}

private enum NotificationKind {
    case needsApproval, idleReminder, other

    init(_ event: HookEvent) {
        switch event.notificationType {
        case "permission_prompt", "elicitation_dialog":
            self = .needsApproval
        case "idle_prompt":
            self = .idleReminder
        case .some:
            self = .other
        case nil:
            // Older Claude Code versions don't send notification_type; guess from the message.
            let message = event.message?.lowercased() ?? ""
            if message.contains("permission") || message.contains("approval") {
                self = .needsApproval
            } else if message.contains("waiting for your input") {
                self = .idleReminder
            } else {
                self = .other
            }
        }
    }
}

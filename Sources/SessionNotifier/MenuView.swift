import ServiceManagement
import SwiftUI

struct MenuView: View {
    let store: SessionStore
    let hooks: HookInstaller

    @Environment(\.dismiss) private var dismiss
    @State private var listHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if !hooks.isInstalled {
                hooksBanner
                Divider()
            }

            if store.sessions.isEmpty {
                emptyState
            } else {
                // ScrollView has no natural height in a MenuBarExtra window (it collapses to 0),
                // so measure the content and set the height manually.
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.sorted) { session in
                            SessionRow(session: session) {
                                TerminalApp.focus(session)
                                dismiss()
                            }
                            .contextMenu { contextMenu(for: session) }
                        }
                    }
                    .padding(6)
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { listHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, height in listHeight = height }
                    })
                }
                .frame(height: min(max(listHeight, 60), 420))
            }

            Divider()
            footer
        }
        .frame(width: 360)
        .onAppear { hooks.refresh() }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(spacing: 10) {
            Text("Claude Sessions").font(.headline)
            Spacer()
            if store.waitingCount > 0 { CountBadge(count: store.waitingCount, color: .orange) }
            if store.runningCount > 0 { CountBadge(count: store.runningCount, color: .blue) }
            if store.doneCount > 0 { CountBadge(count: store.doneCount, color: .green) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var hooksBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Hooks not installed", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("To track sessions, global hooks will be added to ~/.claude/settings.json. The existing file is backed up first.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = hooks.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button("Install Hooks") { hooks.install() }
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No active sessions")
                .foregroundStyle(.secondary)
            if hooks.isInstalled {
                Text("New Claude Code sessions will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack {
            SettingsMenu(hooks: hooks)
            Spacer()
            Button("Clear Finished") { store.clearFinished() }
                .disabled(!store.sessions.contains { $0.status == .done || $0.status == .idle })
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func contextMenu(for session: Session) -> some View {
        Button("Switch to Terminal") { TerminalApp.focus(session) }
        Button("Show in Finder") {
            NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd))
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.cwd, forType: .string)
        }
        Divider()
        Button("Remove from List") { store.remove(session.id) }
    }
}

// MARK: - Row

private struct SessionRow: View {
    let session: Session
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                StatusIndicator(status: session.status)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.name)
                            .font(.system(.body, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text(relative(session.updatedAt))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if let icon = TerminalApp.icon(for: session) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 14, height: 14)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(session.status.label)
                            .foregroundStyle(session.status.color)
                        if session.hasOwnName {
                            Text("·").foregroundStyle(.tertiary)
                            Label(session.project, systemImage: "folder")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption.weight(.medium))
                    if let detail = session.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.07) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(session.cwd)
    }

    private func relative(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "en_US")
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct StatusIndicator: View {
    let status: SessionStatus

    var body: some View {
        switch status {
        case .running:
            ProgressView().controlSize(.small).scaleEffect(0.7)
        case .waiting:
            Image(systemName: "hand.raised.circle.fill").foregroundStyle(.orange)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .idle:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }
}

private struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(color))
    }
}

extension SessionStatus {
    var color: Color {
        switch self {
        case .waiting: .orange
        case .running: .blue
        case .done: .green
        case .idle: .secondary
        }
    }
}

// MARK: - Settings

private struct SettingsMenu: View {
    let hooks: HookInstaller

    @AppStorage(Prefs.notifyWaiting) private var notifyWaiting = true
    @AppStorage(Prefs.notifyDone) private var notifyDone = true
    @AppStorage(Prefs.sound) private var sound = true
    @AppStorage(Prefs.quietWhenFrontmost) private var quietWhenFrontmost = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            Toggle("Notify When Approval Is Needed", isOn: $notifyWaiting)
            Toggle("Notify When Done", isOn: $notifyDone)
            Toggle("Notification Sound", isOn: $sound)
            Toggle("Mute While Terminal Is Active", isOn: $quietWhenFrontmost)
            Divider()
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    if enabled { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                }
            Divider()
            if hooks.isInstalled {
                Button("Uninstall Hooks") { hooks.uninstall() }
            } else {
                Button("Install Hooks") { hooks.install() }
            }
            Button("Open Notification Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

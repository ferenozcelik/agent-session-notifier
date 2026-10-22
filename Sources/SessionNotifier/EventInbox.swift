import Foundation

/// Reads and deletes the files the hook script drops into the `events/` folder.
/// Events that arrive while the app is closed are not lost; they are processed in order on launch.
@MainActor
final class EventInbox {
    private let handler: (HookEvent) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?

    init(handler: @escaping (HookEvent) -> Void) {
        self.handler = handler
    }

    func start() {
        let dir = AppPaths.events
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fd = open(dir.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            src.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.drain() }
            }
            src.setCancelHandler { close(fd) }
            src.resume()
            source = src
        }

        // Fallback: periodic scan in case a folder notification is missed.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drain() }
        }
        drain()
    }

    private func drain() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: AppPaths.events,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]  // temp files still being written start with "."
        ) else { return }

        let files = urls
            .filter { $0.pathExtension == "json" }
            .map { url in (url, (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()) }
            .sorted { $0.1 < $1.1 }

        for (url, date) in files {
            if let data = try? Data(contentsOf: url), let event = HookEvent(data: data, date: date) {
                handler(event)
            }
            try? fm.removeItem(at: url)
        }
    }
}

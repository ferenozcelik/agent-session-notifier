import AppKit

/// Menu bar icon. build.sh copies the PNGs into Resources (AppIcons/*.imageset).
/// Loaded as a template image, so it adapts to light and dark menu bars.
///
/// - idle:     empty ring
/// - running:  filled circle
/// - waiting:  half-filled ring
/// - done:     checkmark in a ring
enum MenuBarIcon {
    enum State { case idle, running, waiting, done }

    private static var cache: [State: NSImage] = [:]

    static func image(_ state: State) -> NSImage {
        if let cached = cache[state] { return cached }
        let image = NSImage(named: name(state)) ?? NSImage()
        image.isTemplate = true
        cache[state] = image
        return image
    }

    private static func name(_ state: State) -> String {
        switch state {
        case .idle: "MenuBarIconIdle"
        case .running: "MenuBarIcon"
        case .waiting: "MenuBarIconWaiting"
        case .done: "MenuBarIconDone"
        }
    }
}

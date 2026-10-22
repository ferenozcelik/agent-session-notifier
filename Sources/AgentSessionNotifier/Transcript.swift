import Foundation

/// Reads Claude's last text response from the session transcript (JSONL).
enum Transcript {
    static func lastAssistantText(at path: String?) -> String? {
        guard let path, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        // Only read the end of the file; transcripts can get large.
        let tail: UInt64 = 512 * 1024
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > tail ? size - tail : 0)
        guard let data = try? handle.readToEnd() else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n").reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { continue }

            let joined = content
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: " ")
            if let summary = condense(joined) { return summary }
        }
        return nil
    }

    /// Collapses whitespace and truncates for notifications.
    static func condense(_ text: String, limit: Int = 300) -> String? {
        let flat = text
            .replacingOccurrences(of: "[*`#>]", with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}

/// Reads the session name from the transcript: the one set with `/rename` (`custom-title`)
/// and the title Claude generates automatically (`ai-title`).
/// Resumes each file where it left off instead of rescanning on every event.
final class TitleReader {
    struct Titles {
        var custom: String?
        var ai: String?
    }

    private static let customPrefix = Array(#"{"type":"custom-title""#.utf8)
    private static let aiPrefix = Array(#"{"type":"ai-title""#.utf8)

    private var offsets: [String: UInt64] = [:]
    private var cache: [String: Titles] = [:]

    func titles(at path: String?) -> Titles? {
        guard let path, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let offset = offsets[path] ?? 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return cache[path] }

        // Leave an incomplete last line for the next read.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return cache[path] }
        let complete = data[data.startIndex...lastNewline]
        offsets[path] = offset + UInt64(complete.count)

        var titles = cache[path] ?? Titles()
        for line in complete.split(separator: UInt8(ascii: "\n")) {
            // Quick pre-filter: only decode title lines as JSON.
            guard line.count < 4096,
                  line.starts(with: Self.customPrefix) || line.starts(with: Self.aiPrefix),
                  let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            switch obj["type"] as? String {
            case "custom-title":
                titles.custom = (obj["customTitle"] as? String).flatMap { Transcript.condense($0, limit: 80) }
            case "ai-title":
                titles.ai = (obj["aiTitle"] as? String).flatMap { Transcript.condense($0, limit: 80) }
            default:
                break
            }
        }
        cache[path] = titles
        return titles
    }
}

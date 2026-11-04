import Foundation

public struct StatusStamp: Codable, Equatable, Sendable {
    public var phase: Phase
    public var time: Date
    public init(_ phase: Phase, _ time: Date) { self.phase = phase; self.time = time }
}

/// Matches only the envelope and payload type at the start of a JSONL record.
/// Anchoring prevents quoted or embedded messages from masquerading as events.
public enum HeaderScanner {
    private static let header = try! NSRegularExpression(pattern:
        #"^\s*\{\s*"timestamp"\s*:\s*"([^"]+)"\s*,\s*(?:"ordinal"\s*:\s*\d+\s*,\s*)?"type"\s*:\s*"([^"]+)"\s*,\s*"payload"\s*:\s*\{\s*"type"\s*:\s*"([^"]+)""#)

    public static func stamp(_ prefix: Data) -> StatusStamp? {
        let text = String(decoding: prefix.prefix(512), as: UTF8.self)
        guard let match = header.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let t = Range(match.range(at: 1), in: text), let date = ClockText.date(String(text[t])),
              let e = Range(match.range(at: 2), in: text), let p = Range(match.range(at: 3), in: text) else { return nil }
        let envelope = String(text[e]), kind = String(text[p])
        if envelope == "event_msg" {
            if ["task_started", "turn_started", "token_count"].contains(kind) { return StatusStamp(.working, date) }
            if ["task_complete", "task_completed", "turn_aborted", "task_aborted", "turn_complete"].contains(kind) {
                return StatusStamp(.finished, date)
            }
        }
        if envelope == "response_item", ["reasoning", "function_call", "custom_tool_call"].contains(kind) {
            return StatusStamp(.working, date)
        }
        return nil
    }
}

import Foundation

public enum Client: String, Codable, CaseIterable, Sendable {
    case codex, claude
    public var label: String { self == .codex ? "Codex" : "Claude Code" }
}

public struct ChatID: Hashable, Codable, Sendable {
    public var client: Client
    public var rawValue: String
    public init(_ client: Client, _ rawValue: String) { self.client = client; self.rawValue = rawValue }
    public var link: URL? {
        var url = URLComponents()
        switch client {
        case .codex:
            url.scheme = "codex"; url.host = "threads"; url.path = "/" + rawValue
        case .claude:
            url.scheme = "claude"; url.host = "code"; url.path = "/continue"
            url.queryItems = [URLQueryItem(name: "session", value: rawValue)]
        }
        return url.url
    }
}

public enum Phase: String, Codable, Sendable { case working, finished }

/// Metadata only. No messages, prompts, tool arguments, or usage records.
public struct Reading: Equatable, Sendable {
    public let id: ChatID
    public var title: String
    public var phase: Phase?
    public var eventTime: Date?
    public var unread: Bool?
    public var archived: Bool
    public init(id: ChatID, title: String, phase: Phase?, eventTime: Date? = nil, unread: Bool? = nil, archived: Bool = false) {
        self.id = id; self.title = title; self.phase = phase
        self.eventTime = eventTime; self.unread = unread; self.archived = archived
    }
}

public struct Indicator: Codable, Equatable, Sendable {
    public let id: ChatID
    // Hidden records keep event history after a batch ends, with 0 meaning that
    // the next activation needs a new number. Visible indicators are always > 0.
    public internal(set) var ordinal: Int
    public var title: String
    public var phase: Phase
    public var eventTime: Date?
    public var visible: Bool
    public var finishedObservedAt: Date?
    public var text: String { phase == .working ? "运行中" : "已完成" }
    public var marker: String {
        guard id.client == .claude else { return String(ordinal) }
        let alphabet = Array("αβγδεζηθικλμνξοπρστυφχψω")
        let index = max(0, ordinal - 1)
        let letter = String(alphabet[index % alphabet.count])
        return index < alphabet.count ? letter : letter + String(index / alphabet.count + 1)
    }
}

/// Numbering stays stable within each client's nonempty batch. Finished history
/// remains after a reset so old log events cannot reappear as newly completed work.
public struct ActivityLedger: Codable, Sendable {
    private var records: [Indicator] = []
    private var baseline: Date?
    public init() {}
    public var visible: [Indicator] {
        records.filter(\.visible).sorted {
            if $0.id.client != $1.id.client { return $0.id.client == .codex }
            return $0.ordinal < $1.ordinal
        }
    }
    public var watched: Set<ChatID> { Set(records.filter(\.visible).map(\.id)) }

    public mutating func apply(_ readings: [Reading], at now: Date = Date()) {
        if baseline == nil { baseline = now }
        // Also normalizes persisted, already-empty lists from older app versions.
        resetEmptyClients()
        let ordered = readings.sorted(by: { $0.id.rawValue < $1.id.rawValue })
        var activating = Set<ChatID>()
        var discoveries: [Reading] = []
        // Deterministic numbering for simultaneous discoveries.
        for reading in ordered {
            if let i = records.firstIndex(where: { $0.id == reading.id }) {
                records[i].title = reading.title
                if reading.archived { records[i].visible = false; continue }
                if let incoming = reading.phase,
                   reading.eventTime == nil || records[i].eventTime == nil || reading.eventTime! >= records[i].eventTime! {
                    if incoming == .working { activating.insert(reading.id); records[i].finishedObservedAt = nil }
                    if incoming == .finished && records[i].phase == .working { records[i].finishedObservedAt = now }
                    records[i].phase = incoming
                    records[i].eventTime = reading.eventTime
                }
                if records[i].phase == .finished, reading.unread == false,
                   now.timeIntervalSince(records[i].finishedObservedAt ?? .distantPast) > 1.5 {
                    records[i].visible = false
                }
            } else if !reading.archived, let phase = reading.phase,
                      phase == .working || (reading.eventTime ?? .distantPast) > baseline! {
                discoveries.append(reading)
            }
        }
        // Retire old rows before assigning new numbers: clearing the last old
        // row and discovering new work in the same poll starts a fresh batch.
        resetEmptyClients()
        let discoveredIDs = Set(discoveries.map(\.id))
        for reading in ordered {
            if activating.contains(reading.id), let i = records.firstIndex(where: { $0.id == reading.id }) {
                if records[i].ordinal == 0 { records[i].ordinal = nextOrdinal(for: reading.id.client) }
                records[i].visible = true
            } else if discoveredIDs.contains(reading.id), !records.contains(where: { $0.id == reading.id }), let phase = reading.phase {
                records.append(Indicator(id: reading.id, ordinal: nextOrdinal(for: reading.id.client), title: reading.title, phase: phase,
                                         eventTime: reading.eventTime, visible: true, finishedObservedAt: phase == .finished ? now : nil))
            }
        }
    }

    private func nextOrdinal(for client: Client) -> Int {
        (records.filter { $0.id.client == client }.map(\.ordinal).max() ?? 0) + 1
    }

    private mutating func resetEmptyClients() {
        for client in Client.allCases where !records.contains(where: { $0.id.client == client && $0.visible }) {
            for i in records.indices where records[i].id.client == client { records[i].ordinal = 0 }
        }
    }
}

public enum ClockText {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let plain = ISO8601DateFormatter()
    private static let lock = NSLock()
    public static func date(_ value: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return fractional.date(from: value) ?? plain.date(from: value)
    }
}

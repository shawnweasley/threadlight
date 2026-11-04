import Foundation
import Testing
@testable import ThreadlightCore

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private func sample(_ name: String = "a", _ phase: Phase?, _ offset: Double = 0, unread: Bool? = nil, client: Client = .codex) -> Reading {
    Reading(id: ChatID(client, name), title: "合成任务 \(name)", phase: phase, eventTime: start.addingTimeInterval(offset), unread: unread)
}

@Suite struct StateTests {
    @Test func independentAlphabetsAndStableOrdinals() throws {
        var ledger = ActivityLedger()
        ledger.apply([sample("b", .working), sample("a", .working), sample("z", .working, client: .claude)], at: start)
        #expect(ledger.visible.map(\.marker) == ["1", "2", "α"])
        ledger.apply([sample("a", .finished, 1, unread: true)], at: start.addingTimeInterval(1))
        #expect(ledger.visible[0].phase == .finished)
        ledger.apply([sample("a", .finished, 1, unread: false)], at: start.addingTimeInterval(4))
        #expect(ledger.visible.map(\.marker) == ["2", "α"])
        ledger.apply([sample("a", .working, 5)], at: start.addingTimeInterval(5))
        #expect(ledger.visible.map(\.marker) == ["1", "2", "α"])
        let restored = try JSONDecoder().decode(ActivityLedger.self, from: JSONEncoder().encode(ledger))
        #expect(restored.visible == ledger.visible)
    }

    @Test func doesNotImportHistoricFinishedConversations() {
        var ledger = ActivityLedger()
        ledger.apply([sample("old", .finished, -100, unread: true)], at: start)
        #expect(ledger.visible.isEmpty)
        ledger.apply([sample("fast", .finished, 1, unread: true)], at: start.addingTimeInterval(2))
        #expect(ledger.visible.count == 1)
    }

    @Test func codexEmptyBatchRestartsAtOneWhileClaudeContinues() {
        var ledger = ActivityLedger()
        ledger.apply([sample("c1", .working), sample("c2", .working),
                      sample("h1", .working, client: .claude)], at: start)
        ledger.apply([sample("c1", .finished, 1, unread: true), sample("c2", .finished, 1, unread: true)], at: start.addingTimeInterval(1))
        ledger.apply([sample("c1", .finished, 1, unread: false), sample("c2", .finished, 1, unread: false)], at: start.addingTimeInterval(4))
        #expect(ledger.visible.map(\.marker) == ["α"])
        ledger.apply([sample("c3", .working, 5), sample("h2", .working, 5, client: .claude)], at: start.addingTimeInterval(5))
        #expect(ledger.visible.map(\.marker) == ["1", "α", "β"])
    }

    @Test func claudeEmptyBatchRestartsAtAlphaWhileCodexContinues() {
        var ledger = ActivityLedger()
        ledger.apply([sample("c1", .working), sample("h1", .working, client: .claude),
                      sample("h2", .working, client: .claude)], at: start)
        ledger.apply([sample("h1", .finished, 1, unread: true, client: .claude),
                      sample("h2", .finished, 1, unread: true, client: .claude)], at: start.addingTimeInterval(1))
        ledger.apply([sample("h1", .finished, 1, unread: false, client: .claude),
                      sample("h2", .finished, 1, unread: false, client: .claude)], at: start.addingTimeInterval(4))
        ledger.apply([sample("c2", .working, 5), sample("h3", .working, 5, client: .claude)], at: start.addingTimeInterval(5))
        #expect(ledger.visible.map(\.marker) == ["1", "2", "α"])
    }

    @Test func oneUnreadConversationKeepsTheBatchAndDoesNotFillGaps() {
        var ledger = ActivityLedger()
        ledger.apply([sample("a", .working), sample("b", .working)], at: start)
        ledger.apply([sample("a", .finished, 1, unread: false), sample("b", .finished, 1, unread: true)], at: start.addingTimeInterval(1))
        ledger.apply([sample("a", .finished, 1, unread: false), sample("b", .finished, 1, unread: true)], at: start.addingTimeInterval(4))
        ledger.apply([sample("c", .working, 5)], at: start.addingTimeInterval(5))
        #expect(ledger.visible.map(\.marker) == ["2", "3"])
    }

    @Test func clearingLastRowAndDiscoveringNewWorkInSamePollStartsNewBatch() {
        var ledger = ActivityLedger()
        ledger.apply([sample("z-old", .working)], at: start)
        ledger.apply([sample("z-old", .finished, 1, unread: true)], at: start.addingTimeInterval(1))
        // The new ID sorts before the retiring ID; allocation must not depend on that order.
        ledger.apply([sample("a-new", .working, 4), sample("z-old", .finished, 1, unread: false)], at: start.addingTimeInterval(4))
        #expect(ledger.visible.map(\.marker) == ["1"])
        #expect(ledger.visible.first?.id.rawValue == "a-new")
    }

    @Test func emptyBatchSurvivesRestartWithoutReimportingOldCompletions() throws {
        var ledger = ActivityLedger()
        ledger.apply([sample("old", .working)], at: start)
        ledger.apply([sample("old", .finished, 1, unread: true)], at: start.addingTimeInterval(1))
        ledger.apply([sample("old", .finished, 1, unread: false)], at: start.addingTimeInterval(4))
        #expect(ledger.visible.isEmpty)
        ledger = try JSONDecoder().decode(ActivityLedger.self, from: JSONEncoder().encode(ledger))
        ledger.apply([sample("old", .finished, 1, unread: true), sample("new", .working, 6)], at: start.addingTimeInterval(6))
        #expect(ledger.visible.map(\.marker) == ["1"])
        #expect(ledger.visible.first?.id.rawValue == "new")
        ledger.apply([sample("old", .working, 7)], at: start.addingTimeInterval(7))
        #expect(ledger.visible.map(\.marker) == ["1", "2"])
    }

    @Test func olderPersistedEmptyLedgerDoesNotReserveHistoricalNumbers() throws {
        var ledger = ActivityLedger()
        ledger.apply([sample("old", .working)], at: start)
        ledger.apply([sample("old", .finished, 1)], at: start.addingTimeInterval(1))
        ledger.apply([sample("old", .finished, 1, unread: false)], at: start.addingTimeInterval(4))
        let encoded = try JSONEncoder().encode(ledger)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var records = try #require(object["records"] as? [[String: Any]])
        records[0]["ordinal"] = 27 // Older versions retained numbers after the list emptied.
        object["records"] = records
        ledger = try JSONDecoder().decode(ActivityLedger.self, from: JSONSerialization.data(withJSONObject: object))
        ledger.apply([sample("old", .working, 6)], at: start.addingTimeInterval(6))
        #expect(ledger.visible.map(\.marker) == ["1"])
    }

    @Test func incompleteOrMissingObservationsDoNotInventCompletion() {
        var ledger = ActivityLedger()
        ledger.apply([sample("a", .working)], at: start)
        ledger.apply([], at: start.addingTimeInterval(10_000))
        ledger.apply([sample("a", nil, 5)], at: start.addingTimeInterval(10_001))
        #expect(ledger.visible.first?.phase == .working)
    }

    @Test func oldReadingsCannotUndoNewerStateAndUnknownReadRetainsDone() {
        var ledger = ActivityLedger()
        ledger.apply([sample("a", .working)], at: start)
        ledger.apply([sample("a", .finished, 2)], at: start.addingTimeInterval(2))
        ledger.apply([sample("a", .working, 1)], at: start.addingTimeInterval(6))
        #expect(ledger.visible.first?.phase == .finished)
        ledger.apply([sample("a", .finished, 2)], at: start.addingTimeInterval(100))
        #expect(ledger.visible.count == 1)
    }

    @Test func archivedTasksDisappearWithoutRenumbering() {
        var ledger = ActivityLedger()
        ledger.apply([sample("a", .working), sample("b", .working)], at: start)
        var reading = sample("a", nil); reading.archived = true
        ledger.apply([reading], at: start.addingTimeInterval(1))
        #expect(ledger.visible.map(\.marker) == ["2"])
    }

    @Test func deeplinksEncodeSessionValues() {
        let url = ChatID(.claude, "local_a&other=x").link
        let parts = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(parts?.queryItems?.count == 1)
        #expect(parts?.queryItems?.first?.value == "local_a&other=x")
        #expect(ChatID(.codex, "example").link?.absoluteString == "codex://threads/example")
    }
}

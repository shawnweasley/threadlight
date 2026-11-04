import Foundation
import Testing
@testable import ThreadlightCore

func event(_ kind: String, at second: Int = 0, ordinal: Bool = true) -> Data {
    Data("{\"timestamp\":\"2026-11-03T08:00:\(String(format: "%02d", second)).000Z\",\(ordinal ? "\"ordinal\":42," : "")\"type\":\"event_msg\",\"payload\":{\"type\":\"\(kind)\"}}\n".utf8)
}

struct Scratch {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("threadlight-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: url) }
    func file(_ name: String) -> URL { url.appendingPathComponent(name) }
}

@Suite struct TailTests {
    @Test func headersSupportOrdinalAndIgnoreEmbeddedOrAncillaryEvents() {
        #expect(HeaderScanner.stamp(event("task_started"))?.phase == .working)
        #expect(HeaderScanner.stamp(event("task_complete", ordinal: false))?.phase == .finished)
        #expect(HeaderScanner.stamp(event("turn_aborted"))?.phase == .finished)
        #expect(HeaderScanner.stamp(event("item_completed")) == nil)
        #expect(HeaderScanner.stamp(Data("{\"type\":\"message\",\"text\":\"task_started\"}".utf8)) == nil)
        let fake = Data("{\"timestamp\":\"2026-11-03T08:00:00Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"text\":\"task_started\"}}".utf8)
        #expect(HeaderScanner.stamp(fake) == nil)
    }

    @Test func multiGigabyteFileHasBoundedReadZeroWarmReadAndRestartCache() throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let path = scratch.file("huge.jsonl"), cache = scratch.file("cache.json")
        FileManager.default.createFile(atPath: path.path, contents: nil)
        let writer = try FileHandle(forWritingTo: path)
        try writer.seek(toOffset: 4 * 1024 * 1024 * 1024)
        try writer.write(contentsOf: Data("\n".utf8) + event("task_started")); try writer.close()
        let reader = TailStore(cache: cache); reader.begin()
        #expect(reader.read(path.path)?.phase == .working)
        #expect(reader.bytesRead <= TailStore.byteLimit)
        reader.flush(); reader.begin()
        #expect(reader.read(path.path)?.phase == .working)
        #expect(reader.bytesRead == 0 && reader.hits == 1)
        let restored = TailStore(cache: cache); restored.begin()
        #expect(restored.read(path.path)?.phase == .working)
        #expect(restored.bytesRead == 0)
        let append = try FileHandle(forWritingTo: path); try append.seekToEnd()
        try append.write(contentsOf: event("task_complete", at: 2)); try append.close()
        restored.begin()
        #expect(restored.read(path.path)?.phase == .finished)
        #expect(restored.bytesRead < 1024)
    }

    @Test func partialLineIsNotInterpretedBeforeNewline() throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let path = scratch.file("partial.jsonl"), reader = TailStore()
        try event("task_started").write(to: path)
        #expect(reader.read(path.path)?.phase == .working)
        let writer = try FileHandle(forWritingTo: path); try writer.seekToEnd()
        try writer.write(contentsOf: event("task_complete", at: 2).dropLast())
        #expect(reader.read(path.path)?.phase == .working)
        try writer.write(contentsOf: Data("\n".utf8)); try writer.close()
        #expect(reader.read(path.path)?.phase == .finished)
    }

    @Test func truncationAndReplacementDoNotKeepStaleWorkingState() throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let path = scratch.file("rotate.jsonl"), reader = TailStore()
        try event("task_started").write(to: path)
        #expect(reader.read(path.path)?.phase == .working)
        try event("task_complete", at: 3).write(to: path, options: .atomic)
        #expect(reader.read(path.path)?.phase == .finished)
        try Data().write(to: path, options: .atomic)
        #expect(reader.read(path.path) == nil)
    }

    @Test func hugeUnterminatedBodyDoesNotGrowMemoryOrHideNextStatus() throws {
        let scratch = try Scratch(); defer { scratch.remove() }
        let path = scratch.file("body.jsonl"), reader = TailStore()
        try event("task_started").write(to: path)
        _ = reader.read(path.path)
        let writer = try FileHandle(forWritingTo: path); try writer.seekToEnd()
        try writer.write(contentsOf: Data(repeating: 120, count: 200_000))
        reader.begin()
        #expect(reader.read(path.path)?.phase == .working)
        #expect(reader.bytesRead <= TailStore.byteLimit)
        try writer.write(contentsOf: Data("\n".utf8) + event("turn_aborted", at: 4)); try writer.close()
        #expect(reader.read(path.path)?.phase == .finished)
    }
}

import Foundation

/// Bounded, incremental reads. A cursor may stop inside a huge record without
/// retaining its body. Resume from the record start only if it fits the budget.
public final class TailStore {
    public static let byteLimit = 65_536
    private struct Cursor: Codable {
        var inode: UInt64
        var size: UInt64
        var modified: Date
        var resume: UInt64
        var skipping: Bool
        var stamp: StatusStamp?
    }
    private var cursors: [String: Cursor] = [:]
    private let location: URL?
    private var dirty = false
    public private(set) var bytesRead = 0
    public private(set) var hits = 0

    public init(cache: URL? = nil) {
        location = cache
        if let cache, let data = try? Data(contentsOf: cache),
           let saved = try? JSONDecoder().decode([String: Cursor].self, from: data) { cursors = saved }
    }

    public func begin() { bytesRead = 0; hits = 0 }
    public func flush() {
        guard dirty, let location, let data = try? JSONEncoder().encode(cursors) else { return }
        do {
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: location, options: .atomic); dirty = false
        } catch { /* Cache failures do not turn into false status changes. */ }
    }

    public func read(_ path: String) -> StatusStamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let length = attrs[.size] as? NSNumber, let modified = attrs[.modificationDate] as? Date else { return cursors[path]?.stamp }
        let size = length.uint64Value
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let previous = cursors[path]
        if let previous, previous.inode == inode, previous.size == size, previous.modified == modified {
            hits += 1; return previous.stamp
        }
        let append = previous.map { $0.inode == inode && size > $0.size } ?? false
        let floor = size > UInt64(Self.byteLimit) ? size - UInt64(Self.byteLimit) : 0
        let start = append ? max(previous!.resume, floor) : floor
        var skip = append && start == previous!.resume ? previous!.skipping : start > 0
        guard let handle = FileHandle(forReadingAtPath: path) else { return previous?.stamp }
        defer { try? handle.close() }
        let bytes: Data
        do { try handle.seek(toOffset: start); bytes = try handle.read(upToCount: Self.byteLimit) ?? Data() }
        catch { return previous?.stamp }
        bytesRead += bytes.count
        var stamp = append ? previous?.stamp : nil
        var lineStart = 0
        bytes.withUnsafeBytes { buffer in
            let raw = buffer.bindMemory(to: UInt8.self)
            for index in raw.indices where raw[index] == 10 {
                if !skip, let found = HeaderScanner.stamp(bytes.subdata(in: lineStart..<min(index, lineStart + 512))) { stamp = found }
                skip = false; lineStart = index + 1
            }
        }
        // Do not parse an unterminated line, even when its prefix looks valid.
        let residual = bytes.count - lineStart
        let resume: UInt64
        let nextSkip: Bool
        if residual > 0 && (skip || residual >= Self.byteLimit) { resume = start + UInt64(bytes.count); nextSkip = true }
        else { resume = start + UInt64(lineStart); nextSkip = false }
        cursors[path] = Cursor(inode: inode, size: size, modified: modified, resume: resume, skipping: nextSkip, stamp: stamp)
        dirty = true
        return stamp
    }
}

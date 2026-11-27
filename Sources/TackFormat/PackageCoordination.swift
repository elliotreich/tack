import Foundation
import TackCore

/// Cross-process advisory lock for one `.tack` package.
///
/// Every Tack writer (the app's autosave, `tackkit mcp`, the CLI) takes this
/// lock around its read-merge-write cycle so two writers never interleave.
/// The lock file lives outside the package (under `/tmp/app.tack.locks`) so it
/// is never synced by iCloud Drive or included in exports.
public enum TackPackageLock {
    public static let lockDirectory = URL(fileURLWithPath: "/tmp/app.tack.locks", isDirectory: true)

    public static func lockURL(for packageURL: URL) -> URL {
        let path = packageURL.standardizedFileURL.resolvingSymlinksInPath().path
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return lockDirectory.appendingPathComponent(String(format: "%016llx.lock", hash))
    }

    public static func withLock<T>(_ packageURL: URL, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let path = lockURL(for: packageURL).path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw TackFormatError.invalidPackage("Could not open lock file \(path): errno \(errno)")
        }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            if errno != EINTR {
                throw TackFormatError.invalidPackage("Could not lock \(path): errno \(errno)")
            }
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

extension TackPackage {
    /// Reads `board.json` from disk, or nil when the package or file does not exist yet.
    public static func readBoardIfPresent(at url: URL) throws -> Board? {
        let boardURL = url.appendingPathComponent(boardFilename)
        guard FileManager.default.fileExists(atPath: boardURL.path) else { return nil }
        return try load(from: url).board
    }

    /// Saves `board`, first merging in anything another writer put on disk since
    /// `base` was read. Returns the board that was written. Holds the package lock.
    @discardableResult
    public static func saveMerging(_ board: Board, base: Board?, to url: URL) throws -> Board {
        try TackPackageLock.withLock(url) {
            var toWrite = board
            if let base, let disk = try? readBoardIfPresent(at: url), disk != base {
                toWrite = TackBoardMerge.merge(base: base, local: board, remote: disk)
            }
            try save(toWrite, to: url)
            // Return what is on disk now: ISO-8601 dates drop sub-second precision,
            // and callers compare this against later reads to spot outside edits.
            return try load(from: url).board
        }
    }

    /// Locked read-modify-write for out-of-app writers (MCP server, CLI).
    /// `body` receives the current on-disk board; the result is validated and saved atomically.
    @discardableResult
    public static func mutate<T>(at url: URL, _ body: (inout Board) throws -> T) throws -> (board: Board, result: T) {
        try TackPackageLock.withLock(url) {
            var board = try load(from: url).board
            let result = try body(&board)
            board.touch()
            try validate(board, in: url)
            try save(board, to: url)
            return (try load(from: url).board, result)
        }
    }
}

/// Watches a `.tack` package for changes made by other processes. Atomic writes
/// replace `board.json`, which shows up as a write to the package directory.
/// Events are coalesced and delivered on the main queue.
public final class TackPackageWatcher: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    private let queue = DispatchQueue(label: "app.tack.package-watcher")
    private var pending: DispatchWorkItem?

    public init?(packageURL: URL, debounce: TimeInterval = 0.2, onChange: @escaping @Sendable () -> Void) {
        let fd = open(packageURL.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let item = DispatchWorkItem { DispatchQueue.main.async(execute: onChange) }
            self.pending = item
            self.queue.asyncAfter(deadline: .now() + debounce, execute: item)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    public func cancel() {
        queue.sync { pending?.cancel() }
        source.cancel()
    }

    deinit { source.cancel() }
}

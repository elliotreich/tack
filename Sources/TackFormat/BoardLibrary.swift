import Foundation
import TackCore

public struct TackBoardLibraryEntry: Identifiable, Sendable {
    public let url: URL
    public let title: String
    public let noteCount: Int
    public let modifiedAt: Date

    public var id: String { url.standardizedFileURL.path }

    public init(url: URL, title: String, noteCount: Int, modifiedAt: Date) {
        self.url = url
        self.title = title
        self.noteCount = noteCount
        self.modifiedAt = modifiedAt
    }
}

public enum TackBoardLibrary {
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tack", isDirectory: true)
    }

    public static func discover(in directory: URL) throws -> [TackBoardLibraryEntry] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let children = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return children.compactMap { url in
            guard url.pathExtension.lowercased() == "tack",
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let loaded = try? TackPackage.load(from: url) else {
                return nil
            }
            let boardURL = url.appendingPathComponent(TackPackage.boardFilename)
            let modifiedAt = (try? boardURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            return TackBoardLibraryEntry(
                url: url,
                title: loaded.board.title,
                noteCount: loaded.board.notes.count,
                modifiedAt: modifiedAt
            )
        }
        .sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    public static func uniqueDestination(for title: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let safeTitle = cleaned.isEmpty ? "Untitled Board" : cleaned
        var candidate = directory.appendingPathComponent("\(safeTitle).tack", isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(safeTitle) \(number).tack", isDirectory: true)
            number += 1
        }
        return candidate
    }
}

public struct TackBoardSessionState: Sendable {
    public var board: Board
    public var packageURL: URL?
    public var hasPendingChanges: Bool
    /// The board as last read from or written to disk. Saves merge in any
    /// changes another writer made since then instead of overwriting them.
    public var diskBoard: Board?

    public init(board: Board = Board(), packageURL: URL? = nil, hasPendingChanges: Bool = false, diskBoard: Board? = nil) {
        self.board = board
        self.packageURL = packageURL
        self.hasPendingChanges = hasPendingChanges
        self.diskBoard = diskBoard
    }
}

public enum TackBoardSessionTransitions {
    public static func flush(_ state: inout TackBoardSessionState, libraryDirectory: URL) throws {
        guard state.hasPendingChanges else { return }

        var savedBoard = state.board
        savedBoard.touch()
        let destination = try state.packageURL ?? TackBoardLibrary.uniqueDestination(for: savedBoard.title, in: libraryDirectory)
        savedBoard = try TackPackage.saveMerging(savedBoard, base: state.packageURL == nil ? nil : state.diskBoard, to: destination)

        state.board = savedBoard
        state.diskBoard = savedBoard
        state.packageURL = destination
        state.hasPendingChanges = false
    }

    public static func open(
        _ url: URL,
        state: inout TackBoardSessionState,
        libraryDirectory: URL
    ) throws {
        guard url.standardizedFileURL != state.packageURL?.standardizedFileURL else { return }
        var next = state
        try flush(&next, libraryDirectory: libraryDirectory)
        let loaded = try TackPackage.load(from: url)
        next.board = loaded.board
        next.packageURL = loaded.rootURL
        next.hasPendingChanges = false
        next.diskBoard = loaded.board
        state = next
    }

    public static func startNew(_ state: inout TackBoardSessionState, libraryDirectory: URL) throws {
        var next = state
        try flush(&next, libraryDirectory: libraryDirectory)
        next.board = Board()
        next.packageURL = nil
        next.hasPendingChanges = false
        next.diskBoard = nil
        state = next
    }
}

import Foundation
import TackCore

public struct TackManifest: Codable, Equatable, Sendable {
    public var format: String
    public var schemaVersion: String
    public var boardID: UUID
    public var boardTitle: String
    public var noteCount: Int
    public var groupCount: Int
    public var captureCount: Int
    public var generatedAt: Date

    public init(board: Board, generatedAt: Date = Date()) {
        self.format = "app.tack.board"
        self.schemaVersion = board.schemaVersion
        self.boardID = board.id
        self.boardTitle = board.title
        self.noteCount = board.notes.count
        self.groupCount = board.groups.count
        self.captureCount = board.captures.count
        self.generatedAt = generatedAt
    }
}

public struct LoadedTackPackage: Sendable {
    public let board: Board
    public let rootURL: URL

    public init(board: Board, rootURL: URL) {
        self.board = board
        self.rootURL = rootURL
    }
}

public enum TackFormatError: LocalizedError {
    case notDirectory(URL)
    case missingBoardJSON(URL)
    case invalidPackage(String)

    public var errorDescription: String? {
        switch self {
        case .notDirectory(let url): return "Tack package is not a directory package: \(url.path)"
        case .missingBoardJSON(let url): return "Tack package is missing board.json: \(url.path)"
        case .invalidPackage(let message): return message
        }
    }
}

public enum TackPackage {
    public static let boardFilename = "board.json"
    public static let manifestFilename = "manifest.json"

    public static func load(from url: URL) throws -> LoadedTackPackage {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TackFormatError.notDirectory(url)
        }

        let boardURL = url.appendingPathComponent(boardFilename)
        guard FileManager.default.fileExists(atPath: boardURL.path) else {
            throw TackFormatError.missingBoardJSON(url)
        }

        do {
            let board = try decode(Board.self, from: Data(contentsOf: boardURL))
            try validate(board, in: url)
            return LoadedTackPackage(board: board, rootURL: url)
        } catch {
            if let formatError = error as? TackFormatError { throw formatError }
            throw TackFormatError.invalidPackage("Could not decode \(boardURL.path): \(error.localizedDescription)")
        }
    }

    public static func save(_ board: Board, to url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw TackFormatError.invalidPackage("Cannot write a Tack package over a regular file: \(url.path)")
        }

        try validate(board, in: url)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: url.appendingPathComponent("media/notes", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: url.appendingPathComponent("media/captures", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: url.appendingPathComponent("ops", isDirectory: true), withIntermediateDirectories: true)

        let boardData = try encode(board)
        let manifestData = try encode(TackManifest(board: board))
        try boardData.write(to: url.appendingPathComponent(boardFilename), options: .atomic)
        try manifestData.write(to: url.appendingPathComponent(manifestFilename), options: .atomic)
    }

    public static func validate(_ board: Board, in rootURL: URL? = nil, requireAssets: Bool = false) throws {
        var errors: [String] = []

        if board.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("schemaVersion is empty")
        }
        if board.canvas.width <= 0 || board.canvas.height <= 0 || !board.canvas.width.isFinite || !board.canvas.height.isFinite {
            errors.append("canvas dimensions must be finite and positive")
        }

        let noteIDs = Set(board.notes.map(\.id))
        if noteIDs.count != board.notes.count { errors.append("notes contain duplicate IDs") }
        let groupIDs = Set(board.groups.map(\.id))
        if groupIDs.count != board.groups.count { errors.append("groups contain duplicate IDs") }
        let captureIDs = Set(board.captures.map(\.id))
        if captureIDs.count != board.captures.count { errors.append("captures contain duplicate IDs") }

        for note in board.notes {
            let values = [note.frame.x, note.frame.y, note.frame.width, note.frame.height, note.rotation]
            if values.contains(where: { !$0.isFinite }) || note.frame.width <= 0 || note.frame.height <= 0 {
                errors.append("note \(note.id.uuidString) has invalid geometry")
            }
            let colorValues = [note.color.red, note.color.green, note.color.blue, note.color.alpha]
            if colorValues.contains(where: { !$0.isFinite || $0 < 0 || $0 > 1 }) {
                errors.append("note \(note.id.uuidString) has invalid color")
            }
            if let fontSize = note.fontSize, !fontSize.isFinite || fontSize <= 0 || fontSize > 512 {
                errors.append("note \(note.id.uuidString) has invalid font size")
            }
            if let confidence = note.ocrConfidence, !confidence.isFinite || confidence < 0 || confidence > 1 {
                errors.append("note \(note.id.uuidString) has invalid OCR confidence")
            }
            if let imagePath = note.imagePath {
                validateRelativeAssetPath(imagePath, owner: "note \(note.id.uuidString)", rootURL: rootURL, requireAssets: requireAssets, errors: &errors)
            }
        }

        for capture in board.captures {
            if let imagePath = capture.imagePath {
                validateRelativeAssetPath(imagePath, owner: "capture \(capture.id.uuidString)", rootURL: rootURL, requireAssets: requireAssets, errors: &errors)
            }
        }

        if let pinnedNoteID = board.pinnedNoteID, !noteIDs.contains(pinnedNoteID) {
            errors.append("pinnedNoteID does not reference a note")
        }

        for group in board.groups {
            let values = [group.frame.x, group.frame.y, group.frame.width, group.frame.height]
            if values.contains(where: { !$0.isFinite }) || group.frame.width < 0 || group.frame.height < 0 {
                errors.append("group \(group.id.uuidString) has invalid geometry")
            }
            if Set(group.noteIDs).count != group.noteIDs.count {
                errors.append("group \(group.id.uuidString) contains duplicate note IDs")
            }
            let missing = group.noteIDs.filter { !noteIDs.contains($0) }
            if !missing.isEmpty {
                errors.append("group \(group.id.uuidString) references missing notes")
            }
        }

        if !errors.isEmpty {
            throw TackFormatError.invalidPackage(errors.joined(separator: "; "))
        }
    }

    private static func validateRelativeAssetPath(
        _ path: String,
        owner: String,
        rootURL: URL?,
        requireAssets: Bool,
        errors: inout [String]
    ) {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let isSafe = !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") &&
            !components.contains("..") && !components.contains(".") && !components.contains("")
        guard isSafe else {
            errors.append("\(owner) has an unsafe image path")
            return
        }

        guard let rootURL else { return }
        let rootPath = rootURL.standardizedFileURL.path
        let assetURL = rootURL.appendingPathComponent(path).standardizedFileURL
        guard assetURL.path.hasPrefix(rootPath + "/") else {
            errors.append("\(owner) image path escapes the package")
            return
        }
        if requireAssets && !FileManager.default.fileExists(atPath: assetURL.path) {
            errors.append("\(owner) image is missing")
        }
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

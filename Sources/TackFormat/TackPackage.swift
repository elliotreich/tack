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
            return LoadedTackPackage(board: board, rootURL: url)
        } catch {
            throw TackFormatError.invalidPackage("Could not decode \(boardURL.path): \(error.localizedDescription)")
        }
    }

    public static func save(_ board: Board, to url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw TackFormatError.invalidPackage("Cannot write a Tack package over a regular file: \(url.path)")
        }

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

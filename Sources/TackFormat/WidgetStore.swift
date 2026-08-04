import Foundation
import TackCore

public struct TackWidgetSnapshot: Codable, Equatable, Sendable {
    public static let widgetKind = "app.tack.pinned-note"

    public let boardID: UUID
    public let boardTitle: String
    public let noteID: UUID
    public let text: String
    public let color: TackColor
    public let imagePath: String?
    public let fontName: String?
    public let fontSize: Double?
    public let isBold: Bool?
    public let isItalic: Bool?
    public let updatedAt: Date

    public init(
        boardID: UUID,
        boardTitle: String,
        noteID: UUID,
        text: String,
        color: TackColor,
        imagePath: String? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil,
        isBold: Bool? = nil,
        isItalic: Bool? = nil,
        updatedAt: Date = Date()
    ) {
        self.boardID = boardID
        self.boardTitle = boardTitle
        self.noteID = noteID
        self.text = text
        self.color = color
        self.imagePath = imagePath
        self.fontName = fontName
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.updatedAt = updatedAt
    }
}

public enum TackWidgetStore {
    public static let appGroupIdentifier = "group.app.tack"

    public static var snapshotURL: URL {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) ??
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root
            .appendingPathComponent("Tack", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }

    public static func imageURL(for noteID: UUID, fileExtension: String = "jpg") -> URL {
        let safeExtension = fileExtension.filter { $0.isLetter || $0.isNumber }.lowercased()
        let suffix = safeExtension.isEmpty ? "img" : safeExtension
        return snapshotURL.deletingLastPathComponent()
            .appendingPathComponent("pinned-note-\(noteID.uuidString).\(suffix)")
    }

    public static func save(_ snapshot: TackWidgetSnapshot) throws {
        try save(snapshot, to: snapshotURL)
    }

    public static func save(_ snapshot: TackWidgetSnapshot, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try TackPackage.encode(snapshot).write(to: url, options: .atomic)
    }

    public static func load() throws -> TackWidgetSnapshot {
        try load(from: snapshotURL)
    }

    public static func load(from url: URL) throws -> TackWidgetSnapshot {
        try TackPackage.decode(TackWidgetSnapshot.self, from: Data(contentsOf: url))
    }

    public static func clear() throws {
        try clear(at: snapshotURL)
        let directory = snapshotURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let imageFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("pinned-note-") }
        for imageFile in imageFiles {
            try FileManager.default.removeItem(at: imageFile)
        }
    }

    public static func clear(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

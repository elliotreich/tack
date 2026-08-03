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
    public static var snapshotURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tack", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }

    public static func save(_ snapshot: TackWidgetSnapshot) throws {
        let directory = snapshotURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try TackPackage.encode(snapshot).write(to: snapshotURL, options: .atomic)
    }

    public static func load() throws -> TackWidgetSnapshot {
        try TackPackage.decode(TackWidgetSnapshot.self, from: Data(contentsOf: snapshotURL))
    }

    public static func clear() throws {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return }
        try FileManager.default.removeItem(at: snapshotURL)
    }
}

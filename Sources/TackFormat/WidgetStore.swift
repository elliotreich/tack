import Foundation
import Darwin
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

/// Stable identity for one note on one board, used by configured widgets.
public struct TackWidgetIdentity: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let boardID: UUID
    public let noteID: UUID

    public var id: String { "\(boardID.uuidString).\(noteID.uuidString)" }

    public init(boardID: UUID, noteID: UUID) {
        self.boardID = boardID
        self.noteID = noteID
    }

    public init?(id: String) {
        let components = id.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2,
              let boardID = UUID(uuidString: String(components[0])),
              let noteID = UUID(uuidString: String(components[1])) else { return nil }
        self.init(boardID: boardID, noteID: noteID)
    }
}

public enum TackWidgetStore {
    public static let appGroupIdentifier = "YAU948K7T5.app.tack"

    private struct Catalog: Codable {
        var snapshots: [TackWidgetSnapshot]
        var defaultIdentity: TackWidgetIdentity? = nil
    }

    public static var snapshotURL: URL {
        widgetDirectory.appendingPathComponent("widget-snapshot.json")
    }

    public static var catalogURL: URL {
        widgetDirectory.appendingPathComponent("widget-catalog.json")
    }

    private static var widgetDirectory: URL {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) ??
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("Tack", isDirectory: true)
    }

    public static func imageURL(for noteID: UUID, fileExtension: String = "jpg") -> URL {
        imageURL(boardID: nil, noteID: noteID, fileExtension: fileExtension)
    }

    public static func imageURL(for snapshot: TackWidgetSnapshot, fileExtension: String = "jpg") -> URL {
        imageURL(boardID: snapshot.boardID, noteID: snapshot.noteID, fileExtension: fileExtension)
    }

    public static func imageURL(boardID: UUID, noteID: UUID, fileExtension: String = "jpg") -> URL {
        imageURL(boardID: Optional(boardID), noteID: noteID, fileExtension: fileExtension)
    }

    private static func imageURL(boardID: UUID?, noteID: UUID, fileExtension: String) -> URL {
        let safeExtension = fileExtension.filter { $0.isLetter || $0.isNumber }.lowercased()
        let suffix = safeExtension.isEmpty ? "img" : safeExtension
        let identity = boardID.map { "\($0.uuidString)-" } ?? ""
        return widgetDirectory.appendingPathComponent("pinned-note-\(identity)\(noteID.uuidString).\(suffix)")
    }

    public static func save(_ snapshot: TackWidgetSnapshot) throws {
        try upsert(snapshot)
    }

    public static func save(_ snapshot: TackWidgetSnapshot, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try TackPackage.encode(snapshot).write(to: url, options: .atomic)
    }

    public static func load() throws -> TackWidgetSnapshot {
        guard let snapshot = try defaultSnapshot() else { throw CocoaError(.fileNoSuchFile) }
        return snapshot
    }

    public static func load(from url: URL) throws -> TackWidgetSnapshot {
        try TackPackage.decode(TackWidgetSnapshot.self, from: Data(contentsOf: url))
    }

    public static func clear() throws {
        try withCatalogLock(at: catalogURL) {
            try saveCatalog(Catalog(snapshots: []), to: catalogURL)
            try clear(at: snapshotURL)
        }
    }

    /// Returns every note pinned to a desktop widget, newest first.
    /// A single snapshot written by earlier Tack builds is read as a one-item catalog.
    public static func allSnapshots() throws -> [TackWidgetSnapshot] {
        try allSnapshots(catalogURL: catalogURL, legacySnapshotURL: snapshotURL)
    }

    public static func allSnapshots(catalogURL: URL, legacySnapshotURL: URL) throws -> [TackWidgetSnapshot] {
        try readCatalogOrLegacy(catalogURL: catalogURL, legacySnapshotURL: legacySnapshotURL).snapshots
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The default target for widgets that do not have an explicit note selection.
    /// Refreshing an existing pinned note never changes this identity.
    public static func defaultSnapshot() throws -> TackWidgetSnapshot? {
        try defaultSnapshot(catalogURL: catalogURL, legacySnapshotURL: snapshotURL)
    }

    public static func defaultSnapshot(catalogURL: URL, legacySnapshotURL: URL) throws -> TackWidgetSnapshot? {
        let catalog = try readCatalogOrLegacy(catalogURL: catalogURL, legacySnapshotURL: legacySnapshotURL)
        if let identity = catalog.defaultIdentity,
           let snapshot = catalog.snapshots.first(where: { $0.boardID == identity.boardID && $0.noteID == identity.noteID }) {
            return snapshot
        }
        return catalog.snapshots.sorted(by: fallbackOrder).first
    }

    public static func snapshot(boardID: UUID, noteID: UUID) throws -> TackWidgetSnapshot? {
        try allSnapshots().first { $0.boardID == boardID && $0.noteID == noteID }
    }

    public static func snapshot(boardID: UUID, noteID: UUID, catalogURL: URL, legacySnapshotURL: URL) throws -> TackWidgetSnapshot? {
        try allSnapshots(catalogURL: catalogURL, legacySnapshotURL: legacySnapshotURL)
            .first { $0.boardID == boardID && $0.noteID == noteID }
    }

    public static func contains(boardID: UUID, noteID: UUID) throws -> Bool {
        try snapshot(boardID: boardID, noteID: noteID) != nil
    }

    /// Adds or refreshes one pinned note, preserving every other widget's note.
    public static func upsert(_ snapshot: TackWidgetSnapshot) throws {
        try upsert(snapshot, catalogURL: catalogURL, legacySnapshotURL: snapshotURL)
    }

    public static func upsert(_ snapshot: TackWidgetSnapshot, catalogURL: URL, legacySnapshotURL: URL) throws {
        try withCatalogLock(at: catalogURL) {
            var catalog = try readCatalogOrLegacy(catalogURL: catalogURL, legacySnapshotURL: legacySnapshotURL)
            let isNewPin = !catalog.snapshots.contains { $0.boardID == snapshot.boardID && $0.noteID == snapshot.noteID }
            catalog.snapshots.removeAll { $0.boardID == snapshot.boardID && $0.noteID == snapshot.noteID }
            catalog.snapshots.append(snapshot)
            let hasCurrentDefault = catalog.defaultIdentity.map { identity in
                catalog.snapshots.contains { $0.boardID == identity.boardID && $0.noteID == identity.noteID }
            } ?? false
            if !hasCurrentDefault || isNewPin {
                catalog.defaultIdentity = TackWidgetIdentity(boardID: snapshot.boardID, noteID: snapshot.noteID)
            }
            try saveCatalog(catalog, to: catalogURL)
            // Keep the pre-catalog file current for widgets already installed
            // with the earlier static configuration.
            let defaultSnapshot = catalog.snapshots.first {
                $0.boardID == catalog.defaultIdentity?.boardID && $0.noteID == catalog.defaultIdentity?.noteID
            } ?? snapshot
            try save(defaultSnapshot, to: legacySnapshotURL)
        }
    }

    /// Removes only the selected board/note pair. Other configured widgets remain available.
    public static func remove(boardID: UUID, noteID: UUID) throws {
        try remove(boardID: boardID, noteID: noteID, catalogURL: catalogURL, legacySnapshotURL: snapshotURL)
    }

    public static func remove(boardID: UUID, noteID: UUID, catalogURL: URL, legacySnapshotURL: URL) throws {
        try withCatalogLock(at: catalogURL) {
            var catalog = try readCatalogOrLegacy(catalogURL: catalogURL, legacySnapshotURL: legacySnapshotURL)
            catalog.snapshots.removeAll { $0.boardID == boardID && $0.noteID == noteID }
            if catalog.defaultIdentity == TackWidgetIdentity(boardID: boardID, noteID: noteID) {
                catalog.defaultIdentity = catalog.snapshots.sorted(by: fallbackOrder).first.map {
                    TackWidgetIdentity(boardID: $0.boardID, noteID: $0.noteID)
                }
            }
            try saveCatalog(catalog, to: catalogURL)
            if let defaultSnapshot = catalog.defaultIdentity.flatMap({ identity in
                catalog.snapshots.first { $0.boardID == identity.boardID && $0.noteID == identity.noteID }
            }) {
                try save(defaultSnapshot, to: legacySnapshotURL)
            } else {
                try clear(at: legacySnapshotURL)
            }
        }
    }

    private static func readCatalogOrLegacy(catalogURL: URL, legacySnapshotURL: URL) throws -> Catalog {
        if FileManager.default.fileExists(atPath: catalogURL.path) {
            return try loadCatalog(from: catalogURL)
        }
        guard FileManager.default.fileExists(atPath: legacySnapshotURL.path) else { return Catalog(snapshots: []) }
        let legacy = try load(from: legacySnapshotURL)
        return Catalog(snapshots: [legacy], defaultIdentity: TackWidgetIdentity(boardID: legacy.boardID, noteID: legacy.noteID))
    }

    private static func loadCatalog(from url: URL) throws -> Catalog {
        let data = try Data(contentsOf: url)
        return try TackPackage.decode(Catalog.self, from: data)
    }

    private static func saveCatalog(_ catalog: Catalog, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TackPackage.encode(catalog).write(to: url, options: .atomic)
    }

    private static func fallbackOrder(_ lhs: TackWidgetSnapshot, _ rhs: TackWidgetSnapshot) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return TackWidgetIdentity(boardID: lhs.boardID, noteID: lhs.noteID).id <
            TackWidgetIdentity(boardID: rhs.boardID, noteID: rhs.noteID).id
    }

    private static func withCatalogLock<T>(at catalogURL: URL, _ body: () throws -> T) throws -> T {
        let directory = catalogURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent("widget-catalog.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    public static func clear(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

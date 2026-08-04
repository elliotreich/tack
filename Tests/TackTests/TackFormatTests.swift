import Foundation
import XCTest
import TackCore
import TackFormat
import TackInterop

final class TackFormatTests: XCTestCase {
    func testDirectoryPackageRoundTripsBoard() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tack-format-\(UUID().uuidString).tack")
        defer { try? FileManager.default.removeItem(at: root) }

        let note = TackNote(
            frame: TackRect(x: 10, y: 20, width: 180, height: 180),
            color: .lavender,
            text: "Hello Tack",
            fontName: "Georgia",
            fontSize: 28,
            isBold: true,
            isItalic: true
        )
        let board = Board(title: "Round trip", notes: [note], pinnedNoteID: note.id)
        try TackPackage.save(board, to: root)

        let loaded = try TackPackage.load(from: root)
        XCTAssertEqual(loaded.board.id, board.id)
        XCTAssertEqual(loaded.board.title, board.title)
        XCTAssertEqual(loaded.board.canvas, board.canvas)
        XCTAssertEqual(loaded.board.notes.map(\.id), board.notes.map(\.id))
        XCTAssertEqual(loaded.board.notes.map(\.text), board.notes.map(\.text))
        XCTAssertEqual(loaded.board.notes.map(\.frame), board.notes.map(\.frame))
        XCTAssertEqual(loaded.board.notes.map(\.color), board.notes.map(\.color))
        XCTAssertEqual(loaded.board.notes.map(\.fontName), board.notes.map(\.fontName))
        XCTAssertEqual(loaded.board.notes.map(\.fontSize), board.notes.map(\.fontSize))
        XCTAssertEqual(loaded.board.notes.map(\.isBold), board.notes.map(\.isBold))
        XCTAssertEqual(loaded.board.notes.map(\.isItalic), board.notes.map(\.isItalic))
        XCTAssertEqual(loaded.board.pinnedNoteID, board.pinnedNoteID)
        XCTAssertEqual(loaded.rootURL, root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
    }

    func testLegacyFixtureImports() throws {
        let archive = try makeLegacyArchive()
        defer { try? FileManager.default.removeItem(at: archive) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tack-import-\(UUID().uuidString).tack")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try LegacyPostitImporter.importArchive(at: archive, to: root)
        XCTAssertEqual(result.sourceNoteCount, 2)
        XCTAssertEqual(result.board.groups.count, 1)
        XCTAssertEqual(result.copiedNoteImageCount, 0)
        XCTAssertEqual(result.board.title, "Fixture Board")
        XCTAssertEqual(result.board.notes.map(\.text), ["Hello fixture", "World fixture"])

        let loaded = try TackPackage.load(from: root)
        XCTAssertEqual(loaded.board.notes.count, 2)
    }

    func testRealLegacyArchiveImportsWhenConfigured() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["TACK_LEGACY_FIXTURE"] else {
            throw XCTSkip("set TACK_LEGACY_FIXTURE to run the full local Post-it regression fixture")
        }
        let archive = URL(fileURLWithPath: fixturePath)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: archive.path), "configured Post-it fixture is not present")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tack-import-\(UUID().uuidString).tack")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try LegacyPostitImporter.importArchive(at: archive, to: root)
        XCTAssertEqual(result.sourceNoteCount, 383)
        XCTAssertEqual(result.board.groups.count, 53)
        XCTAssertGreaterThan(result.copiedNoteImageCount, 350)
        XCTAssertEqual(result.board.title, "2025")
    }

    func testOlderBoardWithoutNewOptionalFieldsStillLoads() throws {
        let note = TackNote(frame: TackRect(x: 10, y: 20, width: 180, height: 180), text: "Older board")
        let board = Board(title: "Older board", notes: [note])
        let encoded = try TackPackage.encode(board)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var notes = try XCTUnwrap(object["notes"] as? [[String: Any]])
        notes[0].removeValue(forKey: "fontName")
        notes[0].removeValue(forKey: "fontSize")
        notes[0].removeValue(forKey: "isBold")
        notes[0].removeValue(forKey: "isItalic")
        object["notes"] = notes
        object.removeValue(forKey: "pinnedNoteID")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let loaded = try TackPackage.decode(Board.self, from: legacyData)
        XCTAssertEqual(loaded.notes.first?.text, "Older board")
        XCTAssertNil(loaded.notes.first?.fontName)
        XCTAssertNil(loaded.notes.first?.fontSize)
        XCTAssertNil(loaded.pinnedNoteID)
    }

    func testUnsafeAssetPathIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tack-invalid-\(UUID().uuidString).tack")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let note = TackNote(
            frame: TackRect(x: 0, y: 0, width: 180, height: 180),
            imagePath: "../../outside.jpg",
            isCaptured: true
        )
        let board = Board(notes: [note])
        try TackPackage.encode(board).write(to: root.appendingPathComponent(TackPackage.boardFilename))

        XCTAssertThrowsError(try TackPackage.load(from: root)) { error in
            XCTAssertTrue(error.localizedDescription.contains("unsafe image path"))
        }
    }

    func testValidationRequiresReferencedAssetsWhenRequested() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tack-assets-\(UUID().uuidString).tack")
        defer { try? FileManager.default.removeItem(at: root) }
        let note = TackNote(
            frame: TackRect(x: 0, y: 0, width: 180, height: 180),
            imagePath: "media/notes/missing.jpg",
            isCaptured: true
        )
        let capture = TackCapture(imagePath: "media/captures/missing.jpg")
        let board = Board(notes: [note], captures: [capture])
        try TackPackage.save(board, to: root)

        XCTAssertThrowsError(try TackPackage.validate(board, in: root, requireAssets: true)) { error in
            XCTAssertTrue(error.localizedDescription.contains("image is missing"))
            XCTAssertTrue(error.localizedDescription.contains(capture.id.uuidString))
        }
    }

    func testExportersEscapeText() {
        let note = TackNote(
            frame: TackRect(x: 0, y: 0, width: 180, height: 180),
            text: "Line, \"quoted\"\nnext",
            groupName: "Ideas"
        )
        let board = Board(title: "Export", notes: [note])
        let csv = TackExporter.csv(for: board)
        XCTAssertTrue(csv.contains("\"Line, \"\"quoted\"\"\nnext\""))
        XCTAssertTrue(csv.contains("font,font_size,bold,italic"))
        XCTAssertTrue(TackExporter.markdown(for: board).contains("Line, \"quoted\" next"))
    }

    func testWidgetStoreRoundTripsAtExplicitURL() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tack-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = TackWidgetSnapshot(
            boardID: UUID(),
            boardTitle: "Widget board",
            noteID: UUID(),
            text: "Widget note",
            color: .orange,
            fontName: "Georgia",
            fontSize: 24,
            isBold: true,
            isItalic: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try TackWidgetStore.save(snapshot, to: url)
        XCTAssertEqual(try TackWidgetStore.load(from: url), snapshot)
        try TackWidgetStore.clear(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func makeLegacyArchive() throws -> URL {
        let fixtureDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/legacy-mini", isDirectory: true)
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-mini-\(UUID().uuidString).postit")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", archive.path, "."]
        process.currentDirectoryURL = fixtureDirectory
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return archive
    }
}

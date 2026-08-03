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

    func testRealLegacyArchiveImportsWhenPresent() throws {
        let archive = URL(fileURLWithPath: "/Users/elliot.reich/Library/Containers/maccatalyst.com.mmm.post-it/Data/tmp/opened_boards/85794D04-A804-4CAF-8503-2FF891239D37.postit")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: archive.path), "local Post-it fixture is not present")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tack-import-\(UUID().uuidString).tack")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try LegacyPostitImporter.importArchive(at: archive, to: root)
        XCTAssertEqual(result.sourceNoteCount, 383)
        XCTAssertEqual(result.board.groups.count, 53)
        XCTAssertGreaterThan(result.copiedNoteImageCount, 350)
        XCTAssertEqual(result.board.title, "2025")

        let loaded = try TackPackage.load(from: root)
        XCTAssertEqual(loaded.board.notes.count, 383)
    }
}

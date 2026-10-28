import Foundation
import XCTest
import TackCore
import TackFormat

final class BoardLibraryTests: XCTestCase {
    func testSwitchFlushesPendingBoardAndNewBoardDoesNotDiscardIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tack-session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var first = TackBoardSessionState(
            board: Board(title: "First", notes: [TackNote(frame: TackRect(x: 0, y: 0, width: 80, height: 80), text: "Initial")]),
            hasPendingChanges: true
        )
        try TackBoardSessionTransitions.flush(&first, libraryDirectory: root)
        let firstURL = try XCTUnwrap(first.packageURL)

        let secondURL = root.appendingPathComponent("Second.tack", isDirectory: true)
        try TackPackage.save(Board(title: "Second", notes: [TackNote(frame: TackRect(x: 0, y: 0, width: 80, height: 80), text: "Second board")]), to: secondURL)

        first.board.notes[0].text = "Saved before switch"
        first.board.notes[0].modifiedAt = Date()
        first.hasPendingChanges = true
        try TackBoardSessionTransitions.open(secondURL, state: &first, libraryDirectory: root)
        XCTAssertEqual(first.board.title, "Second")
        XCTAssertEqual(try TackPackage.load(from: firstURL).board.notes.first?.text, "Saved before switch")

        first.board.notes[0].text = "Saved before new board"
        first.board.notes[0].modifiedAt = Date()
        first.hasPendingChanges = true
        try TackBoardSessionTransitions.startNew(&first, libraryDirectory: root)
        XCTAssertNil(first.packageURL)
        XCTAssertTrue(first.board.notes.isEmpty)
        XCTAssertEqual(try TackPackage.load(from: secondURL).board.notes.first?.text, "Saved before new board")
    }

    func testFailedFlushAbortsBoardSwitch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tack-session-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let validURL = root.appendingPathComponent("Valid.tack", isDirectory: true)
        try TackPackage.save(Board(title: "Valid"), to: validURL)
        let blockerURL = root.appendingPathComponent("Blocker.tack")
        XCTAssertTrue(FileManager.default.createFile(atPath: blockerURL.path, contents: Data("not a board directory".utf8)))
        let target = root.appendingPathComponent("Target.tack", isDirectory: true)
        try TackPackage.save(Board(title: "Target"), to: target)

        var state = TackBoardSessionState(
            board: Board(title: "Still current", notes: [TackNote(frame: TackRect(x: 0, y: 0, width: 80, height: 80), text: "unsaved")]),
            packageURL: blockerURL,
            hasPendingChanges: true
        )
        XCTAssertThrowsError(try TackBoardSessionTransitions.open(target, state: &state, libraryDirectory: root))
        XCTAssertEqual(state.board.title, "Still current")
        XCTAssertEqual(state.packageURL, blockerURL)
        XCTAssertTrue(state.hasPendingChanges)
    }

    func testLibraryDiscoversValidPackagesAndChoosesCollisionSafeNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tack-library-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appendingPathComponent("First.tack", isDirectory: true)
        try TackPackage.save(Board(title: "First", notes: [TackNote(frame: TackRect(x: 0, y: 0, width: 80, height: 80), text: "One")]), to: firstURL)
        let invalidURL = root.appendingPathComponent("Broken.tack", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidURL, withIntermediateDirectories: true)

        let entries = try TackBoardLibrary.discover(in: root)
        XCTAssertEqual(entries.map(\.title), ["First"])
        XCTAssertEqual(entries.first?.noteCount, 1)
        XCTAssertEqual(try TackBoardLibrary.uniqueDestination(for: "First", in: root).lastPathComponent, "First 2.tack")
    }
}

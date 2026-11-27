import Foundation
import Testing
import TackAgent
import TackCore
import TackFormat
import TackInterop

private func tempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tack-agent-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func note(_ text: String, x: Double = 0, y: Double = 0, modified: Date = Date(timeIntervalSince1970: 1_000)) -> TackNote {
    TackNote(frame: TackRect(x: x, y: y, width: 100, height: 100), text: text, createdAt: modified, modifiedAt: modified)
}

@Suite("Three-way board merge")
struct MergeTests {
    @Test func takesRemoteEditWhenLocalUnchanged() {
        let a = note("a")
        let base = Board(notes: [a])
        var remote = base
        remote.notes[0].text = "agent edit"
        #expect(TackBoardMerge.merge(base: base, local: base, remote: remote).notes[0].text == "agent edit")
    }

    @Test func keepsBothSidesNonConflictingChanges() {
        let a = note("a"), b = note("b")
        let base = Board(notes: [a, b])
        var local = base
        local.notes[0].text = "typed in app"
        var remote = base
        remote.notes[1].frame.x = 500
        remote.notes.append(note("added by agent"))
        let merged = TackBoardMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.notes.map(\.text) == ["typed in app", "b", "added by agent"])
        #expect(merged.notes[1].frame.x == 500)
    }

    @Test func newerEditWinsOnTrueConflict() {
        let a = note("a")
        let base = Board(notes: [a])
        var local = base
        local.notes[0].text = "older"
        local.notes[0].modifiedAt = Date(timeIntervalSince1970: 2_000)
        var remote = base
        remote.notes[0].text = "newer"
        remote.notes[0].modifiedAt = Date(timeIntervalSince1970: 3_000)
        #expect(TackBoardMerge.merge(base: base, local: local, remote: remote).notes[0].text == "newer")
    }

    @Test func editBeatsConcurrentDeleteAndRepairsGroups() {
        let a = note("a"), b = note("b")
        let group = TackGroup(name: "G", frame: TackRect(x: 0, y: 0, width: 1, height: 1), noteIDs: [a.id, b.id])
        let base = Board(notes: [a, b], groups: [group], pinnedNoteID: b.id)
        var local = base
        local.notes[0].text = "edited"          // app edits a
        var remote = base
        remote.notes.removeAll()                 // agent deletes both
        remote.groups[0].noteIDs = []
        remote.pinnedNoteID = nil
        let merged = TackBoardMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.notes.map(\.text) == ["edited"])
        #expect(merged.pinnedNoteID == nil)
        #expect(throws: Never.self) { try TackPackage.validate(merged) }
    }

    @Test func saveMergingDoesNotClobberExternalWrite() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("B.tack")
        let base = Board(title: "B", notes: [note("a")])
        try TackPackage.save(base, to: url)

        // An agent adds a note on disk while the app still holds `base`.
        try TackPackage.mutate(at: url) { $0.notes.append(note("from agent")) }

        var appBoard = base
        appBoard.notes[0].text = "from app"
        let written = try TackPackage.saveMerging(appBoard, base: base, to: url)
        let disk = try TackPackage.load(from: url).board
        #expect(written == disk)
        #expect(Set(disk.notes.map(\.text)) == ["from app", "from agent"])
    }

    @Test func sessionFlushMergesExternalChanges() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("S.tack")
        try TackPackage.save(Board(title: "S", notes: [note("a")]), to: url)
        var state = TackBoardSessionState()
        try TackBoardSessionTransitions.open(url, state: &state, libraryDirectory: root)
        try TackPackage.mutate(at: url) { $0.notes.append(note("agent")) }
        state.board.notes[0].text = "app"
        state.hasPendingChanges = true
        try TackBoardSessionTransitions.flush(&state, libraryDirectory: root)
        #expect(Set(try TackPackage.load(from: url).board.notes.map(\.text)) == ["app", "agent"])
        #expect(state.diskBoard == state.board)
    }
}

@Suite("Package watcher")
struct WatcherTests {
    @Test func firesOnAtomicBoardWrite() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("W.tack")
        try TackPackage.save(Board(title: "W"), to: url)
        let fired = Flag()
        let watcher = try #require(TackPackageWatcher(packageURL: url, debounce: 0.05) { fired.set() })
        defer { watcher.cancel() }
        try TackPackage.mutate(at: url) { $0.notes.append(note("x")) }
        for _ in 0..<40 where !fired.value { try await Task.sleep(nanoseconds: 50_000_000) }
        #expect(fired.value)
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

@Suite("Board service")
struct ServiceTests {
    @Test func createSearchMoveGroupUndo() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = TackBoardService(root: root)
        let board = try service.createBoard(title: "Plans")

        let created = try service.createNotes([
            .init(text: "Buy milk", group: "Errands"),
            .init(text: "Call mom", color: .pink, group: "Errands"),
            .init(text: "Ship Tack MCP")
        ], on: "Plans")
        #expect(created.count == 3)
        // Auto-placement never overlaps.
        for (i, a) in created.enumerated() {
            for b in created[(i + 1)...] {
                #expect(!(a.frame.x < b.frame.x + b.frame.width && a.frame.x + a.frame.width > b.frame.x &&
                          a.frame.y < b.frame.y + b.frame.height && a.frame.y + a.frame.height > b.frame.y))
            }
        }

        let hits = try service.search("mom")
        #expect(hits.map(\.1.text) == ["Call mom"])
        #expect(try service.search("", group: "errands").count == 2)

        let ref = try service.resolve(board.board.id.uuidString)
        #expect(ref.board.groups.first?.noteIDs.count == 2)
        try TackPackage.validate(ref.board, in: ref.url)

        _ = try service.moveNotes([.init(id: created[2].id.uuidString, dx: 1000)], on: "plans")
        #expect(try service.note(created[2].id.uuidString, on: service.resolve("Plans")).frame.x == created[2].frame.x + 1000)

        // Undo reverses the move.
        _ = try service.undoLastChange(on: "Plans")
        #expect(try service.note(created[2].id.uuidString, on: service.resolve("Plans")).frame.x == created[2].frame.x)

        // Delete and undo restores the note and its group membership.
        _ = try service.deleteNotes([created[0].id.uuidString], on: "Plans")
        #expect(try service.resolve("Plans").board.notes.count == 2)
        _ = try service.undoLastChange(on: "Plans")
        let restored = try service.resolve("Plans").board
        #expect(restored.notes.count == 3)
        #expect(restored.groups.first { $0.name == "Errands" }?.noteIDs.contains(created[0].id) == true)
        try TackPackage.validate(restored, in: try service.resolve("Plans").url)
    }

    @Test func undoRefusesWhenPersonEditedSince() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = TackBoardService(root: root)
        _ = try service.createBoard(title: "U")
        let created = try service.createNotes([.init(text: "a")], on: "U")
        _ = try service.updateNote(created[0].id.uuidString, patch: { var p = TackBoardService.NotePatch(); p.text = "agent"; return p }(), on: "U")
        // The person edits the same note in the app afterwards.
        let url = try service.resolve("U").url
        try TackPackage.mutate(at: url) { board in
            board.notes[0].text = "person"
            board.notes[0].modifiedAt = Date()
        }
        #expect(throws: TackAgentError.self) { try service.undoLastChange(on: "U") }
        #expect(try service.resolve("U").board.notes[0].text == "person")
    }

    @Test func readOnlyAndSandbox() throws {
        let root = try tempRoot()
        let outside = try tempRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try TackPackage.save(Board(title: "Outside"), to: outside.appendingPathComponent("O.tack"))
        let service = TackBoardService(root: root, readOnly: true)
        #expect(throws: TackAgentError.readOnly) { try service.createBoard(title: "x") }
        #expect(throws: TackAgentError.self) { try service.resolve(outside.appendingPathComponent("O.tack").path) }
        let allowed = TackBoardService(root: root, extraBoards: [outside.appendingPathComponent("O.tack")])
        #expect(try allowed.resolve(outside.appendingPathComponent("O.tack").path).board.title == "Outside")
    }

    @Test func colorsParseAndDescribe() throws {
        #expect(try TackColorName.parse("Pink") == .pink)
        #expect(TackColorName.describe(try TackColorName.parse("#FF0000")) == "#FF0000")
        #expect(TackColorName.describe(.lavender) == "lavender")
        #expect(throws: TackAgentError.self) { try TackColorName.parse("plaid") }
    }
}

@Suite("MCP protocol")
struct MCPTests {
    private func call(_ server: TackMCPServer, _ json: String) throws -> JSONValue {
        let line = try #require(server.handle(line: json))
        return try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    @Test func handshakeListAndCall() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = TackMCPServer(service: TackBoardService(root: root), version: "test")

        let initialize = try call(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#)
        #expect(initialize["result"]?["protocolVersion"] == "2025-06-18")
        #expect(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)

        let tools = try call(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let names = tools["result"]?["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        #expect(names.contains("create_notes") && names.contains("search_notes") && names.contains("undo_agent_change"))

        _ = try call(server, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"create_board","arguments":{"title":"Demo"}}}"#)
        let created = try call(server, #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"create_notes","arguments":{"board":"Demo","notes":[{"text":"hello","color":"blue","group":"G"}]}}}"#)
        #expect(created["result"]?["isError"] == false)

        let outline = try call(server, #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_board","arguments":{"board":"Demo"}}}"#)
        let text = outline["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        #expect(text.contains("## G") && text.contains("hello — blue"))

        let bad = try call(server, #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get_board","arguments":{"board":"nope"}}}"#)
        #expect(bad["result"]?["isError"] == true)

        let resources = try call(server, #"{"jsonrpc":"2.0","id":7,"method":"resources/list"}"#)
        #expect(resources["result"]?["resources"]?.arrayValue?.count == 1)

        let unknown = try call(server, #"{"jsonrpc":"2.0","id":8,"method":"nope"}"#)
        #expect(unknown["error"]?["code"] == -32601)
    }

    @Test func readOnlyHidesWriteTools() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = TackMCPServer(service: TackBoardService(root: root, readOnly: true), version: "test")
        let tools = try call(server, #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        let names = tools["result"]?["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        #expect(!names.contains("create_notes"))
        let denied = try call(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"delete_notes","arguments":{}}}"#)
        #expect(denied["error"] != nil)
    }
}

@Suite("Post-it importer text")
struct ImporterTextTests {
    @Test func typedTextAndUserCorrectionsBeatOCR() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/legacy-mini", isDirectory: true)
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString).postit")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", archive.path, "."]
        zip.currentDirectoryURL = fixture
        try zip.run()
        zip.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: archive) }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString).tack")
        defer { try? FileManager.default.removeItem(at: out) }
        let result = try LegacyPostitImporter.importArchive(at: archive, to: out)
        #expect(result.board.notes.map(\.text) == ["Hello fixture", "World fixture", "Typed over a blank note", "Delete apps on phone"])
    }
}

@Suite("Board library")
struct LibraryTests {
    @Test func listsEveryBoardAndDisambiguatesSharedTitles() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<12 {
            let url = try TackBoardLibrary.uniqueDestination(for: "Untitled Board", in: root)
            try TackPackage.save(Board(title: "Untitled Board", notes: Array(repeating: (), count: index % 3).map { note("n") }), to: url)
        }
        let entries = try TackBoardLibrary.discover(in: root)
        #expect(entries.count == 12)
        #expect(Set(entries.map(\.subtitle)).count == 12)
        #expect(entries.contains { $0.subtitle == "0 notes" })          // "Untitled Board.tack": name matches title
        #expect(entries.contains { $0.subtitle.hasSuffix("· Untitled Board 7") })
    }
}

import Foundation
import TackCapture
import TackCore
import TackFormat

public enum TackAgentError: LocalizedError, Equatable {
    case boardNotFound(String)
    case ambiguousBoard(String, [String])
    case noteNotFound(String)
    case outsideRoot(String)
    case readOnly
    case invalidArgument(String)
    case conflict(String)

    public var errorDescription: String? {
        switch self {
        case .boardNotFound(let ref): return "No board matches '\(ref)'. Call list_boards to see board ids and titles."
        case .ambiguousBoard(let ref, let matches): return "'\(ref)' matches several boards (\(matches.joined(separator: ", "))). Use the board id."
        case .noteNotFound(let ref): return "No note with id '\(ref)' on this board."
        case .outsideRoot(let path): return "\(path) is outside the boards this server may touch. Start it with --root or --board to allow it."
        case .readOnly: return "This server was started with --read-only; writing tools are disabled."
        case .invalidArgument(let message): return message
        case .conflict(let message): return message
        }
    }
}

/// Everything an agent can do to Tack boards, independent of transport.
/// The MCP server and the CLI are thin layers over this type.
///
/// Safety model:
/// - Only packages under `root` (default `~/Documents/Tack`) or explicitly
///   allowed with `extraBoards` are visible; nothing else on disk is touched.
/// - Writes take the package lock and re-read `board.json` first, so they never
///   overwrite edits the running app saved a moment ago; the app in turn merges
///   and reloads (see `TackBoardMerge`).
/// - Every write appends a before/after record to `ops/agent-journal.jsonl`
///   so `undo_agent_change` can reverse it.
public struct TackBoardService: Sendable {
    public let root: URL
    public let extraBoards: [URL]
    public let readOnly: Bool

    public init(root: URL = TackBoardLibrary.defaultDirectory, extraBoards: [URL] = [], readOnly: Bool = false) {
        self.root = root.standardizedFileURL
        self.extraBoards = extraBoards.map(\.standardizedFileURL)
        self.readOnly = readOnly
    }

    // MARK: Boards

    public struct BoardRef: Sendable {
        public let url: URL
        public let board: Board
    }

    public func boards() throws -> [BoardRef] {
        var urls = try TackBoardLibrary.discover(in: root).map(\.url)
        for extra in extraBoards where !urls.contains(where: { $0.standardizedFileURL == extra }) {
            urls.append(extra)
        }
        return urls.compactMap { url in
            (try? TackPackage.load(from: url)).map { BoardRef(url: url, board: $0.board) }
        }
    }

    /// Resolves a board by id, exact title, unique title prefix, or package path.
    public func resolve(_ reference: String) throws -> BoardRef {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TackAgentError.invalidArgument("board is required") }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasSuffix(".tack") && trimmed.contains("/") {
            let url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL
            try ensureAllowed(url)
            return BoardRef(url: url, board: try TackPackage.load(from: url).board)
        }

        let all = try boards()
        if let id = UUID(uuidString: trimmed), let match = all.first(where: { $0.board.id == id }) { return match }
        let exact = all.filter { $0.board.title.caseInsensitiveCompare(trimmed) == .orderedSame }
        if exact.count == 1 { return exact[0] }
        let byFolder = all.filter { $0.url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(trimmed) == .orderedSame }
        if byFolder.count == 1 { return byFolder[0] }
        let candidates = exact.isEmpty ? all.filter { $0.board.title.lowercased().hasPrefix(trimmed.lowercased()) } : exact
        if candidates.count == 1 { return candidates[0] }
        if candidates.count > 1 {
            throw TackAgentError.ambiguousBoard(trimmed, candidates.map { "\($0.board.title) [\($0.board.id.uuidString)]" })
        }
        throw TackAgentError.boardNotFound(trimmed)
    }

    func ensureAllowed(_ url: URL) throws {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.resolvingSymlinksInPath().path
        if path.hasPrefix(rootPath + "/") { return }
        if extraBoards.contains(where: { $0.resolvingSymlinksInPath().path == path }) { return }
        throw TackAgentError.outsideRoot(url.path)
    }

    public func createBoard(title: String) throws -> BoardRef {
        try requireWritable()
        let board = Board(title: title.isEmpty ? "Untitled Board" : title)
        let url = try TackBoardLibrary.uniqueDestination(for: board.title, in: root)
        try TackPackage.save(board, to: url)
        try journal(url, tool: "create_board", summary: "Created board \(board.title)", before: [], after: [])
        return BoardRef(url: url, board: board)
    }

    // MARK: Reading

    public func search(_ query: String, board: String? = nil, group: String? = nil, limit: Int = 50) throws -> [(BoardRef, TackNote)] {
        let refs = try board.map { [try resolve($0)] } ?? boards()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hits: [(BoardRef, TackNote)] = []
        for ref in refs {
            for note in ref.board.notes {
                if let group, note.groupName?.caseInsensitiveCompare(group) != .orderedSame { continue }
                if needle.isEmpty || note.text.lowercased().contains(needle) || (note.groupName?.lowercased().contains(needle) ?? false) {
                    hits.append((ref, note))
                    if hits.count >= limit { return hits }
                }
            }
        }
        return hits
    }

    public func note(_ id: String, on board: BoardRef) throws -> TackNote {
        guard let uuid = UUID(uuidString: id), let note = board.board.notes.first(where: { $0.id == uuid }) else {
            throw TackAgentError.noteNotFound(id)
        }
        return note
    }

    // MARK: Writing

    public struct NoteDraft: Sendable {
        public var text: String
        public var x: Double?
        public var y: Double?
        public var width: Double?
        public var height: Double?
        public var color: TackColor?
        public var group: String?

        public init(text: String, x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil, color: TackColor? = nil, group: String? = nil) {
            self.text = text
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.color = color
            self.group = group
        }
    }

    public func createNotes(_ drafts: [NoteDraft], on reference: String) throws -> [TackNote] {
        try requireWritable()
        guard !drafts.isEmpty else { throw TackAgentError.invalidArgument("Give at least one note.") }
        guard drafts.count <= 200 else { throw TackAgentError.invalidArgument("At most 200 notes per call.") }
        let ref = try resolve(reference)
        return try write(ref.url, tool: "create_notes", summary: "Created \(drafts.count) note(s)") { board in
            let size = typicalNoteSize(board)
            var created: [TackNote] = []
            for draft in drafts {
                let width = draft.width ?? size.width
                let height = draft.height ?? size.height
                let origin: (x: Double, y: Double)
                if let x = draft.x, let y = draft.y {
                    origin = (x, y)
                } else {
                    if let members = draft.group.flatMap({ name in board.notes.filter { $0.groupName == name }.nonEmpty }) {
                        origin = freeSlot(in: board, near: members, width: width, height: height)
                    } else {
                        origin = clearSpace(in: board, width: width, height: height)
                    }
                }
                let note = TackNote(
                    frame: TackRect(x: origin.x, y: origin.y, width: width, height: height),
                    color: draft.color ?? .yellow,
                    text: draft.text
                )
                board.notes.append(note)
                if let group = draft.group { assign([note.id], toGroup: group, in: &board) }
                created.append(board.notes.first { $0.id == note.id } ?? note)
            }
            return created
        }
    }

    public struct NotePatch: Sendable {
        public var text: String?
        public var color: TackColor?
        public var group: String??
        public var fontName: String?
        public var fontSize: Double?
        public var isBold: Bool?
        public var isItalic: Bool?
        public var x: Double?
        public var y: Double?
        public var width: Double?
        public var height: Double?
        public var rotation: Double?

        public init() {}
    }

    public func updateNote(_ id: String, patch: NotePatch, on reference: String) throws -> TackNote {
        try requireWritable()
        let ref = try resolve(reference)
        return try write(ref.url, tool: "update_note", summary: "Updated note \(id)") { board in
            guard let uuid = UUID(uuidString: id), let index = board.notes.firstIndex(where: { $0.id == uuid }) else {
                throw TackAgentError.noteNotFound(id)
            }
            var note = board.notes[index]
            if let text = patch.text { note.text = text }
            if let color = patch.color { note.color = color }
            if let fontName = patch.fontName { note.fontName = fontName.isEmpty ? nil : fontName }
            if let fontSize = patch.fontSize { note.fontSize = fontSize }
            if let isBold = patch.isBold { note.isBold = isBold }
            if let isItalic = patch.isItalic { note.isItalic = isItalic }
            if let x = patch.x { note.frame.x = x }
            if let y = patch.y { note.frame.y = y }
            if let width = patch.width { note.frame.width = width }
            if let height = patch.height { note.frame.height = height }
            if let rotation = patch.rotation { note.rotation = rotation }
            note.modifiedAt = Date()
            board.notes[index] = note
            if let group = patch.group {
                if let group { assign([uuid], toGroup: group, in: &board) }
                else { ungroup([uuid], in: &board) }
            }
            refreshGroupFrames(&board)
            return board.notes.first { $0.id == uuid }!
        }
    }

    public struct Move: Sendable {
        public var id: String
        public var x: Double?
        public var y: Double?
        public var dx: Double?
        public var dy: Double?

        public init(id: String, x: Double? = nil, y: Double? = nil, dx: Double? = nil, dy: Double? = nil) {
            self.id = id
            self.x = x
            self.y = y
            self.dx = dx
            self.dy = dy
        }
    }

    public func moveNotes(_ moves: [Move], on reference: String) throws -> [TackNote] {
        try requireWritable()
        guard !moves.isEmpty, moves.count <= 500 else { throw TackAgentError.invalidArgument("Give 1–500 moves.") }
        let ref = try resolve(reference)
        return try write(ref.url, tool: "move_notes", summary: "Moved \(moves.count) note(s)") { board in
            var moved: [UUID] = []
            for move in moves {
                guard let uuid = UUID(uuidString: move.id), let index = board.notes.firstIndex(where: { $0.id == uuid }) else {
                    throw TackAgentError.noteNotFound(move.id)
                }
                if let x = move.x { board.notes[index].frame.x = x }
                if let y = move.y { board.notes[index].frame.y = y }
                if let dx = move.dx { board.notes[index].frame.x += dx }
                if let dy = move.dy { board.notes[index].frame.y += dy }
                board.notes[index].modifiedAt = Date()
                moved.append(uuid)
            }
            refreshGroupFrames(&board)
            return board.notes.filter { moved.contains($0.id) }
        }
    }

    public func deleteNotes(_ ids: [String], on reference: String) throws -> Int {
        try requireWritable()
        let ref = try resolve(reference)
        let uuids = try ids.map { id -> UUID in
            guard let uuid = UUID(uuidString: id), ref.board.notes.contains(where: { $0.id == uuid }) else { throw TackAgentError.noteNotFound(id) }
            return uuid
        }
        return try write(ref.url, tool: "delete_notes", summary: "Deleted \(uuids.count) note(s)") { board in
            let before = board.notes.count
            board.notes.removeAll { uuids.contains($0.id) }
            for index in board.groups.indices { board.groups[index].noteIDs.removeAll { uuids.contains($0) } }
            if let pinned = board.pinnedNoteID, uuids.contains(pinned) { board.pinnedNoteID = nil }
            refreshGroupFrames(&board)
            return before - board.notes.count
        }
    }

    public func group(_ ids: [String], as name: String, on reference: String) throws -> TackGroup {
        try requireWritable()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TackAgentError.invalidArgument("Group name is empty.") }
        let ref = try resolve(reference)
        return try write(ref.url, tool: "group_notes", summary: "Grouped \(ids.count) note(s) as \(trimmed)") { board in
            let uuids = try ids.map { id -> UUID in
                guard let uuid = UUID(uuidString: id), board.notes.contains(where: { $0.id == uuid }) else { throw TackAgentError.noteNotFound(id) }
                return uuid
            }
            assign(uuids, toGroup: trimmed, in: &board)
            refreshGroupFrames(&board)
            return board.groups.first { $0.name == trimmed }!
        }
    }

    public func renameBoard(_ reference: String, to title: String) throws -> Board {
        try requireWritable()
        let ref = try resolve(reference)
        return try write(ref.url, tool: "rename_board", summary: "Renamed board to \(title)") { board in
            board.title = title
            return board
        }
    }

    public func capture(imageAt imageURL: URL, on reference: String, groupName: String?) throws -> CaptureResult {
        try requireWritable()
        let ref = try resolve(reference)
        let originX = ref.board.notes.map { $0.frame.x + $0.frame.width }.max().map { $0 + 120 } ?? 80
        let name = groupName ?? imageURL.deletingPathExtension().lastPathComponent
        let result = try TackImageCapture.capture(imageAt: imageURL, to: ref.url, originX: originX, originY: 80, groupName: name)
        _ = try write(ref.url, tool: "capture_image", summary: "Captured \(result.notes.count) note(s) from \(imageURL.lastPathComponent)") { board in
            board.notes.append(contentsOf: result.notes)
            board.groups.append(result.group)
            board.captures.append(result.capture)
            board.canvas.width = max(board.canvas.width, result.canvasWidth)
            board.canvas.height = max(board.canvas.height, result.canvasHeight)
            return true
        }
        return result
    }

    // MARK: Journal and undo

    public struct JournalEntry: Codable, Sendable {
        public var id: UUID
        public var at: Date
        public var tool: String
        public var summary: String
        public var before: [TackNote]
        public var after: [TackNote]
        public var beforeGroups: [TackGroup]?
        public var afterGroups: [TackGroup]?
        public var undone: Bool?
    }

    public static let journalPath = "ops/agent-journal.jsonl"

    public func journalEntries(_ reference: String) throws -> [JournalEntry] {
        let ref = try resolve(reference)
        return readJournal(ref.url)
    }

    /// Reverts the most recent agent change that has not been undone yet, as long as
    /// the notes it touched have not been edited since.
    public func undoLastChange(on reference: String) throws -> JournalEntry {
        try requireWritable()
        let ref = try resolve(reference)
        guard let entry = readJournal(ref.url).last(where: { $0.undone != true && ($0.before != $0.after || $0.beforeGroups != $0.afterGroups) }) else {
            throw TackAgentError.conflict("There is no agent change to undo on this board.")
        }
        try write(ref.url, tool: "undo_agent_change", summary: "Undid: \(entry.summary)", undoing: entry.id) { board in
            for after in entry.after {
                guard let current = board.notes.first(where: { $0.id == after.id }) else { continue }
                if current != after {
                    throw TackAgentError.conflict("Note \(after.id.uuidString) changed after '\(entry.summary)', so it was not undone.")
                }
            }
            let beforeByID = Dictionary(entry.before.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let afterIDs = Set(entry.after.map(\.id))
            board.notes.removeAll { afterIDs.contains($0.id) && beforeByID[$0.id] == nil }
            for (id, note) in beforeByID {
                if let index = board.notes.firstIndex(where: { $0.id == id }) { board.notes[index] = note }
                else { board.notes.append(note) }
            }
            if let beforeGroups = entry.beforeGroups {
                let afterGroupIDs = Set((entry.afterGroups ?? []).map(\.id))
                let beforeGroupIDs = Set(beforeGroups.map(\.id))
                board.groups.removeAll { afterGroupIDs.contains($0.id) && !beforeGroupIDs.contains($0.id) }
                for group in beforeGroups {
                    if let index = board.groups.firstIndex(where: { $0.id == group.id }) { board.groups[index] = group }
                    else { board.groups.append(group) }
                }
            }
            let noteIDs = Set(board.notes.map(\.id))
            for index in board.groups.indices { board.groups[index].noteIDs.removeAll { !noteIDs.contains($0) } }
            return true
        }
        return entry
    }

    // MARK: Internals

    private func requireWritable() throws {
        if readOnly { throw TackAgentError.readOnly }
    }

    @discardableResult
    private func write<T>(_ url: URL, tool: String, summary: String, undoing: UUID? = nil, _ body: (inout Board) throws -> T) throws -> T {
        try ensureAllowed(url)
        var beforeBoard: Board?
        let outcome = try TackPackage.mutate(at: url) { board -> T in
            beforeBoard = board
            return try body(&board)
        }
        guard let beforeBoard else { return outcome.result }
        let afterBoard = outcome.board
        let beforeByID = Dictionary(beforeBoard.notes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let afterByID = Dictionary(afterBoard.notes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let changed = Set(beforeByID.keys).union(afterByID.keys).filter { beforeByID[$0] != afterByID[$0] }
        let groupsChanged = beforeBoard.groups != afterBoard.groups
        try journal(
            url,
            tool: tool,
            summary: summary,
            before: changed.compactMap { beforeByID[$0] },
            after: changed.compactMap { afterByID[$0] },
            beforeGroups: groupsChanged ? beforeBoard.groups : nil,
            afterGroups: groupsChanged ? afterBoard.groups : nil,
            undoing: undoing
        )
        return outcome.result
    }

    private func journal(_ url: URL, tool: String, summary: String, before: [TackNote], after: [TackNote],
                         beforeGroups: [TackGroup]? = nil, afterGroups: [TackGroup]? = nil, undoing: UUID? = nil) throws {
        let journalURL = url.appendingPathComponent(Self.journalPath)
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var entries = readJournal(url)
        if let undoing, let index = entries.firstIndex(where: { $0.id == undoing }) {
            entries[index].undone = true
        }
        entries.append(JournalEntry(id: UUID(), at: Date(), tool: tool, summary: summary, before: before, after: after,
                                    beforeGroups: beforeGroups, afterGroups: afterGroups, undone: nil))
        // Keep the journal bounded; it is an undo log, not an archive.
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data()
        for entry in entries {
            data.append(try encoder.encode(entry))
            data.append(0x0A)
        }
        try data.write(to: journalURL, options: .atomic)
    }

    private func readJournal(_ url: URL) -> [JournalEntry] {
        guard let data = try? Data(contentsOf: url.appendingPathComponent(Self.journalPath)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(JournalEntry.self, from: Data($0)) }
    }

    private func typicalNoteSize(_ board: Board) -> (width: Double, height: Double) {
        guard !board.notes.isEmpty else { return (180, 180) }
        let widths = board.notes.map(\.frame.width).sorted()
        let heights = board.notes.map(\.frame.height).sorted()
        return (widths[widths.count / 2], heights[heights.count / 2])
    }

    /// First spot, scanning rows left to right below the top of `anchor`'s bounds,
    /// where a note of this size does not overlap anything.
    private func freeSlot(in board: Board, near anchor: [TackNote], width: Double, height: Double) -> (x: Double, y: Double) {
        guard let first = anchor.first else { return (80, 80) }
        var minX = first.frame.x, minY = first.frame.y, maxX = first.frame.x + first.frame.width
        for note in anchor {
            minX = min(minX, note.frame.x)
            minY = min(minY, note.frame.y)
            maxX = max(maxX, note.frame.x + note.frame.width)
        }
        let gap = max(12, width * 0.15)
        let rowWidth = max(maxX - minX, width * 4)
        var y = minY
        for _ in 0..<400 {
            var x = minX
            while x + width <= minX + rowWidth + 0.5 {
                let candidate = TackRect(x: x, y: y, width: width, height: height).insetBy(dx: -gap / 2, dy: -gap / 2)
                if !board.notes.contains(where: { overlaps($0.frame, candidate) }) { return (x, y) }
                x += width + gap
            }
            y += height + gap
        }
        return (minX, y)
    }

    /// Somewhere that is not inside the existing layout: a fresh column to the
    /// right of everything, so new topics do not get scattered into old ones.
    private func clearSpace(in board: Board, width: Double, height: Double) -> (x: Double, y: Double) {
        guard let first = board.notes.first else { return (80, 80) }
        var maxX = first.frame.x + first.frame.width, minY = first.frame.y
        for note in board.notes {
            maxX = max(maxX, note.frame.x + note.frame.width)
            minY = min(minY, note.frame.y)
        }
        return (maxX + max(80, width * 0.5), minY)
    }

    private func overlaps(_ a: TackRect, _ b: TackRect) -> Bool {
        a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y
    }

    private func assign(_ ids: [UUID], toGroup name: String, in board: inout Board) {
        ungroup(ids, in: &board)
        if let index = board.groups.firstIndex(where: { $0.name == name }) {
            board.groups[index].noteIDs.append(contentsOf: ids)
        } else {
            board.groups.append(TackGroup(name: name, frame: TackRect(x: 0, y: 0, width: 0, height: 0), noteIDs: ids))
        }
        for index in board.notes.indices where ids.contains(board.notes[index].id) {
            board.notes[index].groupName = name
        }
        refreshGroupFrames(&board)
    }

    private func ungroup(_ ids: [UUID], in board: inout Board) {
        for index in board.groups.indices { board.groups[index].noteIDs.removeAll { ids.contains($0) } }
        for index in board.notes.indices where ids.contains(board.notes[index].id) {
            board.notes[index].groupName = nil
        }
    }

    private func refreshGroupFrames(_ board: inout Board) {
        for index in board.groups.indices {
            let members = board.notes.filter { board.groups[index].noteIDs.contains($0.id) }
            guard let first = members.first else { continue }
            var minX = first.frame.x, minY = first.frame.y
            var maxX = first.frame.x + first.frame.width, maxY = first.frame.y + first.frame.height
            for note in members {
                minX = min(minX, note.frame.x)
                minY = min(minY, note.frame.y)
                maxX = max(maxX, note.frame.x + note.frame.width)
                maxY = max(maxY, note.frame.y + note.frame.height)
            }
            board.groups[index].frame = TackRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }
}

extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}

// MARK: Colors

public enum TackColorName {
    public static let named: [(String, TackColor)] = [
        ("yellow", .yellow), ("blue", .blue), ("green", .green), ("pink", .pink),
        ("white", .white), ("lavender", .lavender), ("orange", .orange)
    ]

    public static func parse(_ value: String) throws -> TackColor {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let match = named.first(where: { $0.0 == lowered }) { return match.1 }
        var hex = lowered.hasPrefix("#") ? String(lowered.dropFirst()) : lowered
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let raw = UInt32(hex, radix: 16) else {
            throw TackAgentError.invalidArgument("Unknown color '\(value)'. Use \(named.map(\.0).joined(separator: ", ")) or #RRGGBB.")
        }
        return TackColor(red: Double((raw >> 16) & 0xFF) / 255, green: Double((raw >> 8) & 0xFF) / 255, blue: Double(raw & 0xFF) / 255)
    }

    /// Nearest named color, or a hex string when nothing is close.
    public static func describe(_ color: TackColor) -> String {
        let best = named.min { distance($0.1, color) < distance($1.1, color) }
        if let best, distance(best.1, color) < 0.06 { return best.0 }
        let hex = [color.red, color.green, color.blue].map { String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded())) }.joined()
        return "#\(hex)"
    }

    private static func distance(_ a: TackColor, _ b: TackColor) -> Double {
        let dr = a.red - b.red, dg = a.green - b.green, db = a.blue - b.blue
        return dr * dr + dg * dg + db * db
    }
}

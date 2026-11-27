import Foundation
import TackCore
import TackFormat

/// Tool catalog and dispatch for `TackMCPServer`. Read tools are always listed;
/// write tools are hidden when the server runs with `--read-only`.
public enum TackMCPTools {
    public struct Output {
        public var text: String
        public var structured: JSONValue
    }

    static let boardParam: JSONValue = ["type": "string", "description": "Board id, title, or package path (see list_boards)."]
    static let colorParam: JSONValue = ["type": "string", "description": "yellow, blue, green, pink, white, lavender, orange, or #RRGGBB."]

    static func schema(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        ["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) }), "additionalProperties": false]
    }

    static func tool(_ name: String, _ title: String, _ description: String, _ input: JSONValue,
                     readOnly: Bool, destructive: Bool = false, idempotent: Bool = false) -> JSONValue {
        [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": input,
            "annotations": [
                "title": .string(title),
                "readOnlyHint": .bool(readOnly),
                "destructiveHint": .bool(destructive),
                "idempotentHint": .bool(idempotent || readOnly),
                "openWorldHint": false
            ]
        ]
    }

    public static func definitions(readOnly: Bool) -> [JSONValue] {
        let reads: [JSONValue] = [
            tool("list_boards", "List boards", "List every Tack board with its id, title, note count, groups and package path.",
                 schema([:]), readOnly: true),
            tool("get_board", "Read a board",
                 "Read one board. format=outline (default) gives notes grouped and in reading order with ids; format=json gives the full board.json.",
                 schema(["board": boardParam, "format": ["type": "string", "enum": ["outline", "json"]]], required: ["board"]), readOnly: true),
            tool("search_notes", "Search notes",
                 "Find notes whose text or group contains the query (case-insensitive) across all boards, or one board. Empty query lists notes.",
                 schema([
                    "query": ["type": "string"], "board": boardParam,
                    "group": ["type": "string", "description": "Only notes in this group."],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 500]
                 ], required: ["query"]), readOnly: true),
            tool("get_note", "Read a note",
                 "Full detail for one note, including the absolute path of its image crop if it was photographed (read that file to see the handwriting).",
                 schema(["board": boardParam, "note_id": ["type": "string"]], required: ["board", "note_id"]), readOnly: true),
            tool("export_board", "Export a board", "Export a board as markdown (grouped bullet list) or csv.",
                 schema(["board": boardParam, "format": ["type": "string", "enum": ["markdown", "csv"]]], required: ["board", "format"]), readOnly: true),
            tool("list_agent_changes", "List agent changes", "Recent changes made through this server on a board (newest last).",
                 schema(["board": boardParam, "limit": ["type": "integer", "minimum": 1, "maximum": 100]], required: ["board"]), readOnly: true)
        ]
        guard !readOnly else { return reads }

        let noteDraft: JSONValue = schema([
            "text": ["type": "string"],
            "group": ["type": "string", "description": "Put the note in this group (created if missing); it is placed next to the group."],
            "color": colorParam,
            "x": ["type": "number"], "y": ["type": "number"],
            "width": ["type": "number", "exclusiveMinimum": 0], "height": ["type": "number", "exclusiveMinimum": 0]
        ], required: ["text"])

        let writes: [JSONValue] = [
            tool("create_board", "Create a board", "Create a new empty board in the Tack folder.",
                 schema(["title": ["type": "string"]], required: ["title"]), readOnly: false),
            tool("rename_board", "Rename a board", "Change a board's title.",
                 schema(["board": boardParam, "title": ["type": "string"]], required: ["board", "title"]), readOnly: false, idempotent: true),
            tool("create_notes", "Create notes",
                 "Add one or more notes. Omit x/y to let Tack find free space (next to the group, if given).",
                 schema(["board": boardParam, "notes": ["type": "array", "items": noteDraft, "minItems": 1, "maxItems": 200]], required: ["board", "notes"]),
                 readOnly: false),
            tool("update_note", "Edit a note",
                 "Change a note's text, color, group (null removes it from its group), typography, position, size or rotation. Only given fields change.",
                 schema([
                    "board": boardParam, "note_id": ["type": "string"],
                    "text": ["type": "string"], "color": colorParam,
                    "group": ["type": ["string", "null"]],
                    "font_name": ["type": "string"], "font_size": ["type": "number"],
                    "bold": ["type": "boolean"], "italic": ["type": "boolean"],
                    "x": ["type": "number"], "y": ["type": "number"],
                    "width": ["type": "number"], "height": ["type": "number"], "rotation": ["type": "number"]
                 ], required: ["board", "note_id"]), readOnly: false, idempotent: true),
            tool("move_notes", "Move notes", "Move notes to absolute x/y, or by dx/dy. Use this to lay out or cluster notes.",
                 schema(["board": boardParam, "moves": ["type": "array", "minItems": 1, "maxItems": 500, "items": schema([
                    "note_id": ["type": "string"], "x": ["type": "number"], "y": ["type": "number"],
                    "dx": ["type": "number"], "dy": ["type": "number"]
                 ], required: ["note_id"])]], required: ["board", "moves"]), readOnly: false),
            tool("group_notes", "Group notes", "Put notes into a named group (created if missing), removing them from any other group.",
                 schema(["board": boardParam, "name": ["type": "string"], "note_ids": ["type": "array", "items": ["type": "string"], "minItems": 1]],
                        required: ["board", "name", "note_ids"]), readOnly: false, idempotent: true),
            tool("delete_notes", "Delete notes", "Delete notes. Reversible with undo_agent_change.",
                 schema(["board": boardParam, "note_ids": ["type": "array", "items": ["type": "string"], "minItems": 1]], required: ["board", "note_ids"]),
                 readOnly: false, destructive: true),
            tool("capture_image", "Capture paper notes",
                 "Detect sticky notes in a photo or scan with on-device Vision, OCR each one, and add them to the board as a new group.",
                 schema(["board": boardParam, "image_path": ["type": "string", "description": "Absolute path to a JPEG/PNG/HEIC image."],
                         "group": ["type": "string"]], required: ["board", "image_path"]), readOnly: false),
            tool("undo_agent_change", "Undo last agent change",
                 "Reverse the most recent change made through this server on a board, unless the person has since edited the same notes.",
                 schema(["board": boardParam], required: ["board"]), readOnly: false, destructive: true)
        ]
        return reads + writes
    }

    public static func call(_ name: String, arguments args: JSONValue, service: TackBoardService) throws -> Output {
        switch name {
        case "list_boards":
            let boards = try service.boards()
            let items: [JSONValue] = boards.map { ref in
                [
                    "id": .string(ref.board.id.uuidString), "title": .string(ref.board.title),
                    "notes": .number(Double(ref.board.notes.count)),
                    "groups": .array(ref.board.groups.map { .string($0.name) }),
                    "modified_at": .string(iso(ref.board.modifiedAt)), "path": .string(ref.url.path)
                ]
            }
            let text = boards.isEmpty ? "No boards in \(service.root.path)." : boards.map {
                "- \($0.board.title) — \($0.board.notes.count) notes, \($0.board.groups.count) groups [\($0.board.id.uuidString)]"
            }.joined(separator: "\n")
            return Output(text: text, structured: ["boards": .array(items)])

        case "get_board":
            let ref = try service.resolve(try string(args, "board"))
            if args["format"]?.stringValue == "json" {
                let value = try JSONValue.from(ref.board)
                return Output(text: value.compactString(pretty: true), structured: ["board": value, "path": .string(ref.url.path)])
            }
            return Output(text: outline(ref), structured: try boardSummary(ref))

        case "search_notes":
            let limit = Int(args["limit"]?.doubleValue ?? 50)
            let hits = try service.search(try string(args, "query", allowEmpty: true), board: args["board"]?.stringValue,
                                          group: args["group"]?.stringValue, limit: max(1, min(500, limit)))
            let items = hits.map { ref, note -> JSONValue in
                var value = noteSummary(note, board: ref)
                if case .object(var object) = value {
                    object["board"] = .string(ref.board.title)
                    object["board_id"] = .string(ref.board.id.uuidString)
                    value = .object(object)
                }
                return value
            }
            let text = hits.isEmpty ? "No matching notes." : hits.map { ref, note in
                "- [\(ref.board.title)\(note.groupName.map { " / \($0)" } ?? "")] \(oneLine(note.text)) (\(note.id.uuidString))"
            }.joined(separator: "\n")
            return Output(text: text, structured: ["notes": .array(items), "count": .number(Double(hits.count))])

        case "get_note":
            let ref = try service.resolve(try string(args, "board"))
            let note = try service.note(try string(args, "note_id"), on: ref)
            var detail = try JSONValue.from(note)
            if case .object(var object) = detail {
                object["color_name"] = .string(TackColorName.describe(note.color))
                if let imagePath = note.imagePath { object["image_file"] = .string(ref.url.appendingPathComponent(imagePath).path) }
                detail = .object(object)
            }
            return Output(text: detail.compactString(pretty: true), structured: ["note": detail])

        case "export_board":
            let ref = try service.resolve(try string(args, "board"))
            let format = try string(args, "format")
            let text: String
            switch format {
            case "markdown": text = TackExporter.markdown(for: ref.board)
            case "csv": text = TackExporter.csv(for: ref.board)
            default: throw TackAgentError.invalidArgument("format must be markdown or csv")
            }
            return Output(text: text, structured: ["format": .string(format), "content": .string(text)])

        case "list_agent_changes":
            let limit = Int(args["limit"]?.doubleValue ?? 20)
            let entries = try service.journalEntries(try string(args, "board")).suffix(max(1, min(100, limit)))
            let items: [JSONValue] = entries.map {
                ["id": .string($0.id.uuidString), "at": .string(iso($0.at)), "tool": .string($0.tool),
                 "summary": .string($0.summary), "undone": .bool($0.undone ?? false)]
            }
            let text = entries.isEmpty ? "No agent changes recorded." : entries.map {
                "- \(iso($0.at)) \($0.tool): \($0.summary)\($0.undone == true ? " (undone)" : "")"
            }.joined(separator: "\n")
            return Output(text: text, structured: ["changes": .array(items)])

        case "create_board":
            let ref = try service.createBoard(title: try string(args, "title"))
            return Output(text: "Created \(ref.board.title) [\(ref.board.id.uuidString)] at \(ref.url.path)",
                          structured: ["id": .string(ref.board.id.uuidString), "title": .string(ref.board.title), "path": .string(ref.url.path)])

        case "rename_board":
            let board = try service.renameBoard(try string(args, "board"), to: try string(args, "title"))
            return Output(text: "Renamed to \(board.title).", structured: ["id": .string(board.id.uuidString), "title": .string(board.title)])

        case "create_notes":
            let reference = try string(args, "board")
            guard let items = args["notes"]?.arrayValue else { throw TackAgentError.invalidArgument("notes must be an array") }
            let drafts = try items.map { item in
                TackBoardService.NoteDraft(
                    text: try string(item, "text", allowEmpty: true),
                    x: item["x"]?.doubleValue, y: item["y"]?.doubleValue,
                    width: try positive(item["width"]), height: try positive(item["height"]),
                    color: try item["color"]?.stringValue.map(TackColorName.parse),
                    group: item["group"]?.stringValue
                )
            }
            let created = try service.createNotes(drafts, on: reference)
            let ref = try service.resolve(reference)
            return Output(
                text: "Created \(created.count) note(s):\n" + created.map { "- \(oneLine($0.text)) (\($0.id.uuidString)) at \(Int($0.frame.x)),\(Int($0.frame.y))" }.joined(separator: "\n"),
                structured: ["notes": .array(created.map { noteSummary($0, board: ref) })]
            )

        case "update_note":
            var patch = TackBoardService.NotePatch()
            patch.text = args["text"]?.stringValue
            patch.color = try args["color"]?.stringValue.map(TackColorName.parse)
            if let group = args["group"] { patch.group = .some(group.isNull ? nil : group.stringValue) }
            patch.fontName = args["font_name"]?.stringValue
            patch.fontSize = args["font_size"]?.doubleValue
            patch.isBold = args["bold"]?.boolValue
            patch.isItalic = args["italic"]?.boolValue
            patch.x = args["x"]?.doubleValue
            patch.y = args["y"]?.doubleValue
            patch.width = try positive(args["width"])
            patch.height = try positive(args["height"])
            patch.rotation = args["rotation"]?.doubleValue
            let reference = try string(args, "board")
            let note = try service.updateNote(try string(args, "note_id"), patch: patch, on: reference)
            return Output(text: "Updated \(note.id.uuidString): \(oneLine(note.text))",
                          structured: ["note": noteSummary(note, board: try service.resolve(reference))])

        case "move_notes":
            guard let items = args["moves"]?.arrayValue else { throw TackAgentError.invalidArgument("moves must be an array") }
            let moves = try items.map {
                TackBoardService.Move(id: try string($0, "note_id"), x: $0["x"]?.doubleValue, y: $0["y"]?.doubleValue,
                                      dx: $0["dx"]?.doubleValue, dy: $0["dy"]?.doubleValue)
            }
            let reference = try string(args, "board")
            let moved = try service.moveNotes(moves, on: reference)
            let ref = try service.resolve(reference)
            return Output(text: "Moved \(moved.count) note(s).", structured: ["notes": .array(moved.map { noteSummary($0, board: ref) })])

        case "group_notes":
            let ids = try stringArray(args, "note_ids")
            let group = try service.group(ids, as: try string(args, "name"), on: try string(args, "board"))
            return Output(text: "Group \(group.name) now has \(group.noteIDs.count) note(s).",
                          structured: ["group": .string(group.name), "note_ids": .array(group.noteIDs.map { .string($0.uuidString) })])

        case "delete_notes":
            let count = try service.deleteNotes(try stringArray(args, "note_ids"), on: try string(args, "board"))
            return Output(text: "Deleted \(count) note(s). undo_agent_change restores them.", structured: ["deleted": .number(Double(count))])

        case "capture_image":
            let path = (try string(args, "image_path") as NSString).expandingTildeInPath
            let result = try service.capture(imageAt: URL(fileURLWithPath: path), on: try string(args, "board"), groupName: args["group"]?.stringValue)
            let text = "Captured \(result.notes.count) note(s) into group \(result.group.name)\(result.usedFallback ? " (no note shapes found; kept the whole image as one note)" : "")."
            return Output(text: text, structured: [
                "group": .string(result.group.name),
                "notes": .array(result.notes.map { ["id": .string($0.id.uuidString), "text": .string($0.text)] })
            ])

        case "undo_agent_change":
            let entry = try service.undoLastChange(on: try string(args, "board"))
            return Output(text: "Undid: \(entry.summary)", structured: ["undone": .string(entry.summary), "id": .string(entry.id.uuidString)])

        default:
            throw TackAgentError.invalidArgument("Unknown tool: \(name)")
        }
    }

    // MARK: Rendering

    /// Notes grouped, each group in reading order (top-to-bottom, then left-to-right).
    public static func outline(_ ref: TackBoardService.BoardRef) -> String {
        let board = ref.board
        var lines = ["# \(board.title)", "", "id: \(board.id.uuidString) · \(board.notes.count) notes · \(ref.url.path)", ""]
        let grouped = Dictionary(grouping: board.notes) { $0.groupName ?? "" }
        let order = board.groups.map(\.name).filter { grouped[$0] != nil } + (grouped[""] != nil ? [""] : [])
        var seen = Set<String>()
        for name in order + grouped.keys.sorted() where seen.insert(name).inserted {
            lines.append(name.isEmpty ? "## Ungrouped" : "## \(name)")
            let notes = grouped[name, default: []].sorted {
                abs($0.frame.y - $1.frame.y) > min($0.frame.height, $1.frame.height) / 2 ? $0.frame.y < $1.frame.y : $0.frame.x < $1.frame.x
            }
            for note in notes {
                var tags = [TackColorName.describe(note.color)]
                if note.imagePath != nil { tags.append("image") }
                if board.pinnedNoteID == note.id { tags.append("pinned") }
                let text = oneLine(note.text)
                lines.append("- \(text.isEmpty ? "(no text)" : text) — \(tags.joined(separator: ", ")) @\(Int(note.frame.x)),\(Int(note.frame.y)) `\(note.id.uuidString)`")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func boardSummary(_ ref: TackBoardService.BoardRef) throws -> JSONValue {
        [
            "id": .string(ref.board.id.uuidString), "title": .string(ref.board.title), "path": .string(ref.url.path),
            "groups": .array(ref.board.groups.map { ["name": .string($0.name), "note_ids": .array($0.noteIDs.map { .string($0.uuidString) })] }),
            "notes": .array(ref.board.notes.map { noteSummary($0, board: ref) })
        ]
    }

    static func noteSummary(_ note: TackNote, board: TackBoardService.BoardRef) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(note.id.uuidString), "text": .string(note.text),
            "color": .string(TackColorName.describe(note.color)),
            "x": .number(note.frame.x), "y": .number(note.frame.y),
            "width": .number(note.frame.width), "height": .number(note.frame.height),
            "captured": .bool(note.isCaptured)
        ]
        if let group = note.groupName { object["group"] = .string(group) }
        if let imagePath = note.imagePath { object["image_file"] = .string(board.url.appendingPathComponent(imagePath).path) }
        if note.rotation != 0 { object["rotation"] = .number(note.rotation) }
        return .object(object)
    }

    // MARK: Argument helpers

    static func string(_ args: JSONValue, _ key: String, allowEmpty: Bool = false) throws -> String {
        guard let value = args[key]?.stringValue else { throw TackAgentError.invalidArgument("\(key) is required and must be a string") }
        if !allowEmpty && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TackAgentError.invalidArgument("\(key) must not be empty")
        }
        return value
    }

    static func stringArray(_ args: JSONValue, _ key: String) throws -> [String] {
        guard let values = args[key]?.arrayValue?.compactMap(\.stringValue), !values.isEmpty else {
            throw TackAgentError.invalidArgument("\(key) must be a non-empty array of strings")
        }
        return values
    }

    static func positive(_ value: JSONValue?) throws -> Double? {
        guard let number = value?.doubleValue else { return nil }
        guard number > 0, number.isFinite else { throw TackAgentError.invalidArgument("width and height must be positive") }
        return number
    }

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " / ").trimmingCharacters(in: .whitespaces)
    }

    static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

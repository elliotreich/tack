import Foundation
import TackCore
import TackFormat

/// A Model Context Protocol server over stdio (newline-delimited JSON-RPC 2.0).
///
/// Run it with `tackkit mcp`. It works on the `.tack` packages directly, so the
/// Tack app does not need to be running; when it is, the app notices the change
/// on disk and merges it into the open board.
public final class TackMCPServer {
    public static let protocolVersion = "2025-06-18"
    public static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    let service: TackBoardService
    let version: String

    public init(service: TackBoardService, version: String) {
        self.service = service
        self.version = version
    }

    /// Reads requests from stdin until EOF and writes responses to stdout.
    public func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let response = handle(line: line) {
                FileHandle.standardOutput.write(Data((response + "\n").utf8))
            }
        }
    }

    /// Handles one JSON-RPC message; returns the serialized response, or nil for notifications.
    public func handle(line: String) -> String? {
        guard let request = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            return respond(id: .null, error: (-32700, "Parse error"))
        }
        let id = request["id"]
        guard let method = request["method"]?.stringValue else {
            return id == nil ? nil : respond(id: id!, error: (-32600, "Invalid request"))
        }
        guard let id else { return nil } // notification (e.g. notifications/initialized)
        let params = request["params"] ?? .object([:])

        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.stringValue ?? Self.protocolVersion
            let agreed = Self.supportedProtocolVersions.contains(requested) ? requested : Self.protocolVersion
            return respond(id: id, result: [
                "protocolVersion": .string(agreed),
                "capabilities": ["tools": ["listChanged": false], "resources": ["listChanged": false]],
                "serverInfo": ["name": "tack", "title": "Tack boards", "version": .string(version)],
                "instructions": .string(Self.instructions(service: service))
            ])
        case "ping":
            return respond(id: id, result: [:])
        case "tools/list":
            return respond(id: id, result: ["tools": .array(TackMCPTools.definitions(readOnly: service.readOnly))])
        case "tools/call":
            guard let name = params["name"]?.stringValue else {
                return respond(id: id, error: (-32602, "tools/call needs a tool name"))
            }
            let arguments = params["arguments"] ?? .object([:])
            guard TackMCPTools.definitions(readOnly: service.readOnly).contains(where: { $0["name"]?.stringValue == name }) else {
                return respond(id: id, error: (-32602, "Unknown tool: \(name)"))
            }
            do {
                let output = try TackMCPTools.call(name, arguments: arguments, service: service)
                return respond(id: id, result: [
                    "content": [["type": "text", "text": .string(output.text)]],
                    "structuredContent": output.structured,
                    "isError": false
                ])
            } catch {
                // Tool failures are results the model can read and react to, not protocol errors.
                return respond(id: id, result: [
                    "content": [["type": "text", "text": .string(error.localizedDescription)]],
                    "isError": true
                ])
            }
        case "resources/list":
            let boards = (try? service.boards()) ?? []
            return respond(id: id, result: ["resources": .array(boards.map { ref in
                [
                    "uri": .string("tack://board/\(ref.board.id.uuidString)"),
                    "name": .string(ref.board.title),
                    "description": .string("\(ref.board.notes.count) notes · \(ref.url.path)"),
                    "mimeType": "text/markdown"
                ]
            })])
        case "resources/read":
            guard let uri = params["uri"]?.stringValue, uri.hasPrefix("tack://board/") else {
                return respond(id: id, error: (-32602, "Expected a tack://board/<id> uri"))
            }
            do {
                let ref = try service.resolve(String(uri.dropFirst("tack://board/".count)))
                return respond(id: id, result: ["contents": [[
                    "uri": .string(uri), "mimeType": "text/markdown",
                    "text": .string(TackMCPTools.outline(ref))
                ]]])
            } catch {
                return respond(id: id, error: (-32002, error.localizedDescription))
            }
        default:
            return respond(id: id, error: (-32601, "Method not found: \(method)"))
        }
    }

    static func instructions(service: TackBoardService) -> String {
        """
        Tack is a local-first Mac whiteboard of sticky notes. Each board is a `.tack` package under \(service.root.path).
        Notes have an id, text, color, a frame (x, y, width, height in unbounded canvas points; y grows downward), an optional group, and may carry an image crop from a photographed paper note.
        Start with list_boards, then get_board (outline) or search_notes. Boards can be named by id or title.
        Writes are saved straight to disk and the Tack app merges them live; every write is journaled and undo_agent_change reverses the latest one.
        Prefer create_notes with a group and no coordinates: Tack places new notes next to that group without overlapping anything.\(service.readOnly ? "\nThis server is read-only." : "")
        """
    }

    private func respond(id: JSONValue, result: JSONValue) -> String {
        JSONValue.object(["jsonrpc": "2.0", "id": id, "result": result]).compactString()
    }

    private func respond(id: JSONValue, error: (Int, String)) -> String {
        JSONValue.object(["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(error.0)), "message": .string(error.1)]]).compactString()
    }
}

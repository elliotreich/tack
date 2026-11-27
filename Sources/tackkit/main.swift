import Foundation
import TackAgent
import TackCapture
import TackCore
import TackFormat
import TackInterop

@main
struct TackKit {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("tackkit: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }

        switch command {
        case "validate":
            guard arguments.count >= 2 else { throw CLIError.usage("validate requires a .tack package path") }
            let loaded = try TackPackage.load(from: URL(fileURLWithPath: arguments[1]))
            try TackPackage.validate(loaded.board, in: loaded.rootURL, requireAssets: true)
            print("title=\(loaded.board.title)")
            print("notes=\(loaded.board.notes.count)")
            print("groups=\(loaded.board.groups.count)")
            print("captures=\(loaded.board.captures.count)")
            print("missing_images=0")
        case "convert":
            guard arguments.count >= 3 else { throw CLIError.usage("convert requires an input .postit and output .tack path") }
            let options = LegacyImportOptions(retainOriginalCaptures: !arguments.contains("--omit-captures"))
            let result = try LegacyPostitImporter.importArchive(
                at: URL(fileURLWithPath: arguments[1]),
                to: URL(fileURLWithPath: arguments[2]),
                options: options
            )
            print("title=\(result.board.title)")
            print("notes=\(result.sourceNoteCount)")
            print("images=\(result.copiedNoteImageCount)")
            print("groups=\(result.board.groups.count)")
            print("output=\(result.destinationURL.path)")
            for warning in result.warnings { fputs("warning: \(warning)\n", stderr) }
        case "capture":
            guard arguments.count >= 3 else { throw CLIError.usage("capture requires an image and output .tack path") }
            let output = URL(fileURLWithPath: arguments[2])
            try TackPackage.save(Board(title: URL(fileURLWithPath: arguments[1]).deletingPathExtension().lastPathComponent), to: output)
            let result = try TackImageCapture.capture(imageAt: URL(fileURLWithPath: arguments[1]), to: output, groupName: URL(fileURLWithPath: arguments[1]).deletingPathExtension().lastPathComponent)
            var board = try TackPackage.load(from: output).board
            board.notes = result.notes
            board.groups = [result.group]
            board.captures = [result.capture]
            board.canvas.width = result.canvasWidth
            board.canvas.height = result.canvasHeight
            board.touch()
            try TackPackage.save(board, to: output)
            print("notes=\(result.notes.count)")
            print("output=\(output.path)")
        case "mcp":
            let service = try agentService(arguments)
            let version = (try? String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("VERSION"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0.1.0"
            TackMCPServer(service: service, version: version).run()
        case "list":
            let service = try agentService(arguments)
            print(try TackMCPTools.call("list_boards", arguments: [:], service: service).text)
        case "show":
            guard arguments.count >= 2, !arguments[1].hasPrefix("--") else { throw CLIError.usage("show requires a board id, title or path") }
            let service = try agentService(arguments)
            let format: JSONValue = arguments.contains("--json") ? "json" : "outline"
            print(try TackMCPTools.call("get_board", arguments: ["board": .string(arguments[1]), "format": format], service: service).text)
        case "search":
            guard arguments.count >= 2 else { throw CLIError.usage("search requires a query") }
            let service = try agentService(arguments)
            var args: [String: JSONValue] = ["query": .string(arguments[1])]
            if let board = option("--in", arguments) { args["board"] = .string(board) }
            print(try TackMCPTools.call("search_notes", arguments: .object(args), service: service).text)
        case "help", "--help", "-h":
            printUsage()
        default:
            throw CLIError.usage("unknown command '\(command)'")
        }
    }

    private static func printUsage() {
        print("""
        tackkit — inspect and migrate Tack boards

        Usage:
          tackkit validate board.tack
          tackkit convert legacy.postit board.tack [--omit-captures]
          tackkit capture wall.jpg board.tack
          tackkit list [--root DIR]
          tackkit show <board id|title|path> [--json] [--root DIR]
          tackkit search <query> [--in <board>] [--root DIR]
          tackkit mcp [--root DIR] [--board PATH ...] [--read-only]

        mcp runs a Model Context Protocol server on stdin/stdout so agents
        (Claude Code, Codex, ...) can read and edit boards. --root defaults to
        ~/Documents/Tack (or $TACK_ROOT); --board allows one extra package.
        """)
    }

    private static func option(_ name: String, _ arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func agentService(_ arguments: [String]) throws -> TackBoardService {
        let rootPath = option("--root", arguments) ?? ProcessInfo.processInfo.environment["TACK_ROOT"]
        let root = rootPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ?? TackBoardLibrary.defaultDirectory
        var extras: [URL] = []
        for (index, argument) in arguments.enumerated() where argument == "--board" && index + 1 < arguments.count {
            extras.append(URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath, isDirectory: true))
        }
        return TackBoardService(root: root, extraBoards: extras, readOnly: arguments.contains("--read-only"))
    }
}

private enum CLIError: LocalizedError {
    case usage(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): return "\(message)\nRun 'tackkit help' for usage."
        case .invalid(let message): return message
        }
    }
}

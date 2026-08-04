import Foundation
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
            let options = LegacyImportOptions(retainOriginalCaptures: arguments.contains("--retain-captures"))
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
          tackkit convert legacy.postit board.tack [--retain-captures]
          tackkit capture wall.jpg board.tack
        """)
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

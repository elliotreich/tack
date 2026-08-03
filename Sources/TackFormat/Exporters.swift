import Foundation
import TackCore

public enum TackExporter {
    public static func markdown(for board: Board) -> String {
        var lines = ["# \(board.title)", "", "<!-- Exported by Tack -->", ""]
        let groups = Dictionary(grouping: board.notes) { $0.groupName ?? "Ungrouped" }
        for group in groups.keys.sorted() {
            lines.append("## \(group)")
            lines.append("")
            for note in groups[group, default: []].sorted(by: { $0.frame.y < $1.frame.y }) {
                let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append("- \(text.isEmpty ? "[Untitled note]" : text.replacingOccurrences(of: "\n", with: " "))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func csv(for board: Board) -> String {
        var lines = ["text,group,color,rotation,x,y,width,height,captured,ocr_confidence,image"]
        for note in board.notes {
            let values: [String] = [
                note.text,
                note.groupName ?? "",
                "#\(hex(note.color.red))\(hex(note.color.green))\(hex(note.color.blue))",
                String(note.rotation),
                String(note.frame.x),
                String(note.frame.y),
                String(note.frame.width),
                String(note.frame.height),
                note.isCaptured ? "true" : "false",
                note.ocrConfidence.map { String($0) } ?? "",
                note.imagePath ?? ""
            ]
            lines.append(values.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func writeMarkdown(_ board: Board, to url: URL) throws {
        try markdown(for: board).data(using: .utf8)?.write(to: url, options: .atomic)
    }

    public static func writeCSV(_ board: Board, to url: URL) throws {
        try csv(for: board).data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func hex(_ value: Double) -> String {
        String(format: "%02X", Int(min(1, max(0, value)) * 255))
    }
}

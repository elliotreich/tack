import Foundation
import TackCore
import TackFormat

public struct LegacyImportOptions: Sendable {
    public var retainOriginalCaptures: Bool

    public init(retainOriginalCaptures: Bool = false) {
        self.retainOriginalCaptures = retainOriginalCaptures
    }
}

public struct LegacyImportResult: Sendable {
    public let board: Board
    public let destinationURL: URL
    public let sourceNoteCount: Int
    public let copiedNoteImageCount: Int
    public let warnings: [String]

    public init(board: Board, destinationURL: URL, sourceNoteCount: Int, copiedNoteImageCount: Int, warnings: [String]) {
        self.board = board
        self.destinationURL = destinationURL
        self.sourceNoteCount = sourceNoteCount
        self.copiedNoteImageCount = copiedNoteImageCount
        self.warnings = warnings
    }
}

public enum LegacyPostitError: LocalizedError {
    case archiveMissing(URL)
    case extractionFailed(String)
    case missingIndex(URL)
    case missingSheet(URL)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .archiveMissing(let url): return "Legacy Post-it archive not found: \(url.path)"
        case .extractionFailed(let message): return "Could not extract legacy Post-it archive: \(message)"
        case .missingIndex(let url): return "Legacy archive is missing index.json: \(url.path)"
        case .missingSheet(let url): return "Legacy archive contains no sheet JSON: \(url.path)"
        case .invalidJSON(let message): return "Could not parse legacy Post-it JSON: \(message)"
        }
    }
}

public enum LegacyPostitImporter {
    public static func importArchive(at archiveURL: URL, to destinationURL: URL, options: LegacyImportOptions = LegacyImportOptions()) throws -> LegacyImportResult {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw LegacyPostitError.archiveMissing(archiveURL)
        }

        let fileManager = FileManager.default
        let extractionURL = fileManager.temporaryDirectory.appendingPathComponent("tack-import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractionURL) }

        try extract(archiveURL, to: extractionURL)

        let indexURL = extractionURL.appendingPathComponent("index.json")
        guard fileManager.fileExists(atPath: indexURL.path) else {
            throw LegacyPostitError.missingIndex(archiveURL)
        }

        let index = try decode(LegacyIndex.self, from: Data(contentsOf: indexURL))
        let sheetURLs = try fileManager.contentsOfDirectory(at: extractionURL, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("sheet-") && $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let sheetURL = sheetURLs.first else {
            throw LegacyPostitError.missingSheet(archiveURL)
        }
        let sheet = try decode(LegacySheet.self, from: Data(contentsOf: sheetURL))
        let title = nonEmpty(index.boardName) ?? nonEmpty(sheet.name) ?? archiveURL.deletingPathExtension().lastPathComponent

        var rawNotes: [TackNote] = []
        var rawGroups: [TackGroup] = []
        var warnings: [String] = []
        var usedIDs = Set<UUID>()
        var captures = Set<String>()
        var contentUUIDByNoteID: [UUID: String] = [:]

        for (clusterIndex, cluster) in sheet.clusters.enumerated() {
            let clusterName = nonEmpty(cluster.name) ?? "Group \(clusterIndex + 1)"
            let groupID = UUID()
            let groupOriginX = cluster.positionX ?? 0
            let groupOriginY = cluster.positionY ?? 0
            var groupNoteIDs: [UUID] = []
            var groupRect = TackRect(x: groupOriginX, y: groupOriginY, width: cluster.width ?? 0, height: cluster.height ?? 0)

            for legacyNote in cluster.notes {
                let noteID = uniqueUUID(preferred: legacyNote.noteUUID ?? legacyNote.contentUUID, used: &usedIDs)
                let width = max(48, legacyNote.width ?? 76.2)
                let height = max(48, legacyNote.height ?? 76.2)
                let centerX = legacyNote.centerX ?? 0
                let centerY = legacyNote.centerY ?? 0
                let noteFrame = TackRect(x: groupOriginX + centerX - width / 2, y: groupOriginY + centerY - height / 2, width: width, height: height)
                let color = legacyNote.backgroundColor.map { TackColor(red: clamp($0.red ?? 1), green: clamp($0.green ?? 0.93), blue: clamp($0.blue ?? 0.32), alpha: clamp($0.alpha ?? 1)) } ?? .yellow
                let text = legacyNote.ocr?.text ?? legacyNote.text ?? legacyNote.userText ?? ""
                let sourceCaptureID = nonEmpty(legacyNote.board)
                if let sourceCaptureID { captures.insert(sourceCaptureID) }
                if let contentUUID = nonEmpty(legacyNote.contentUUID) { contentUUIDByNoteID[noteID] = contentUUID }

                let note = TackNote(
                    id: noteID,
                    frame: noteFrame,
                    rotation: legacyNote.layoutRotation ?? 0,
                    color: color,
                    text: text,
                    groupName: clusterName,
                    imagePath: legacyNote.contentUUID == nil ? nil : "media/notes/\(noteID.uuidString).jpg",
                    sourceCaptureID: sourceCaptureID,
                    ocrConfidence: legacyNote.ocr?.confidence,
                    isCaptured: !(legacyNote.isDigitalNote ?? false)
                )
                rawNotes.append(note)
                groupNoteIDs.append(noteID)
                groupRect = union(groupRect, noteFrame)
            }

            rawGroups.append(TackGroup(id: groupID, name: clusterName, frame: groupRect, noteIDs: groupNoteIDs))
        }

        let minX = rawNotes.map(\.frame.x).min() ?? 0
        let minY = rawNotes.map(\.frame.y).min() ?? 0
        let maxX = rawNotes.map { $0.frame.x + $0.frame.width }.max() ?? 1200
        let maxY = rawNotes.map { $0.frame.y + $0.frame.height }.max() ?? 800
        let shiftX = 80 - minX
        let shiftY = 80 - minY

        var notes = rawNotes
        for index in notes.indices {
            notes[index].frame.x += shiftX
            notes[index].frame.y += shiftY
        }
        var groups = rawGroups
        for index in groups.indices {
            groups[index].frame.x += shiftX
            groups[index].frame.y += shiftY
        }

        var board = Board(
            title: title,
            canvas: CanvasSettings(width: max(1200, maxX - minX + 160), height: max(800, maxY - minY + 160)),
            notes: notes,
            groups: groups,
            captures: captures.sorted().compactMap { UUID(uuidString: $0) }.map { TackCapture(id: $0) }
        )

        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destinationURL.appendingPathComponent("media/notes", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destinationURL.appendingPathComponent("media/captures", isDirectory: true), withIntermediateDirectories: true)

        var copiedImages = 0
        for note in notes {
            guard let contentUUID = contentUUIDByNoteID[note.id], !contentUUID.isEmpty else { continue }
            let source = extractionURL.appendingPathComponent("note-\(contentUUID)-enhanced.jpg")
            let destination = destinationURL.appendingPathComponent(note.imagePath ?? "")
            guard fileManager.fileExists(atPath: source.path) else {
                warnings.append("Missing legacy image for note \(note.id.uuidString) (content \(contentUUID)).")
                continue
            }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
            copiedImages += 1
        }

        if options.retainOriginalCaptures {
            let captureFiles = try fileManager.contentsOfDirectory(at: extractionURL, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("capture-") && ["jpg", "jpeg", "json"].contains($0.pathExtension.lowercased()) }
            for source in captureFiles {
                let destination = destinationURL.appendingPathComponent("media/captures").appendingPathComponent(source.lastPathComponent)
                if !fileManager.fileExists(atPath: destination.path) {
                    try fileManager.copyItem(at: source, to: destination)
                }
            }
        }

        let thumbnailSource = extractionURL.appendingPathComponent("sheet-thumbnail.png")
        if fileManager.fileExists(atPath: thumbnailSource.path) {
            do {
                try fileManager.copyItem(at: thumbnailSource, to: destinationURL.appendingPathComponent("thumbnail.png"))
            } catch {
                warnings.append("Could not copy the legacy sheet thumbnail: \(error.localizedDescription)")
            }
        }

        board.touch()
        try TackPackage.save(board, to: destinationURL)
        return LegacyImportResult(board: board, destinationURL: destinationURL, sourceNoteCount: notes.count, copiedNoteImageCount: copiedImages, warnings: warnings)
    }

    private static func extract(_ archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archiveURL.path, "-d", destinationURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            throw LegacyPostitError.extractionFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unzip exited with status \(process.terminationStatus)"
            throw LegacyPostitError.extractionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LegacyPostitError.invalidJSON(error.localizedDescription)
        }
    }

    private static func uniqueUUID(preferred: String?, used: inout Set<UUID>) -> UUID {
        if let preferred, let candidate = UUID(uuidString: preferred), !used.contains(candidate) {
            used.insert(candidate)
            return candidate
        }
        var candidate = UUID()
        while used.contains(candidate) { candidate = UUID() }
        used.insert(candidate)
        return candidate
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    private static func union(_ lhs: TackRect, _ rhs: TackRect) -> TackRect {
        let minX = min(lhs.x, rhs.x)
        let minY = min(lhs.y, rhs.y)
        let maxX = max(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = max(lhs.y + lhs.height, rhs.y + rhs.height)
        return TackRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private struct LegacyIndex: Decodable {
    let boardName: String?

    enum CodingKeys: String, CodingKey {
        case boardName
    }
}

private struct LegacySheet: Decodable {
    let uuid: String?
    let name: String?
    let clusters: [LegacyCluster]

    enum CodingKeys: String, CodingKey {
        case uuid = "UUID"
        case name
        case clusters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        clusters = try container.decodeIfPresent([LegacyCluster].self, forKey: .clusters) ?? []
    }
}

private struct LegacyCluster: Decodable {
    let name: String?
    let positionX: Double?
    let positionY: Double?
    let width: Double?
    let height: Double?
    let notes: [LegacyNote]

    enum CodingKeys: String, CodingKey {
        case name
        case positionX
        case positionY
        case width
        case height
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        positionX = try container.decodeIfPresent(Double.self, forKey: .positionX)
        positionY = try container.decodeIfPresent(Double.self, forKey: .positionY)
        width = try container.decodeIfPresent(Double.self, forKey: .width)
        height = try container.decodeIfPresent(Double.self, forKey: .height)
        notes = try container.decodeIfPresent([LegacyNote].self, forKey: .notes) ?? []
    }
}

private struct LegacyNote: Decodable {
    let isDigitalNote: Bool?
    let noteUUID: String?
    let contentUUID: String?
    let board: String?
    let backgroundColor: LegacyColor?
    let centerX: Double?
    let centerY: Double?
    let width: Double?
    let height: Double?
    let layoutRotation: Double?
    let ocr: LegacyOCR?
    let text: String?
    let userText: String?

    enum CodingKeys: String, CodingKey {
        case isDigitalNote
        case noteUUID
        case contentUUID
        case board
        case backgroundColor
        case centerX
        case centerY
        case width
        case height
        case layoutRotation
        case ocr
        case text
        case userText
    }
}

private struct LegacyColor: Decodable {
    let red: Double?
    let green: Double?
    let blue: Double?
    let alpha: Double?
}

private struct LegacyOCR: Decodable {
    let text: String?
    let confidence: Double?
}

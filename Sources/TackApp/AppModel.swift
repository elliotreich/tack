import AppKit
import SwiftUI
import TackCore
import TackCapture
import TackFormat
import TackInterop
import UniformTypeIdentifiers
import WidgetKit

enum NoteFilter: Equatable {
    case all
    case captured
    case textOnly
    case group(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var board: Board
    @Published var packageURL: URL?
    @Published var selectedNoteID: UUID?
    @Published var searchText = ""
    @Published var zoom: CGFloat = 1
    @Published var pan = CGSize.zero
    @Published var statusMessage = "Ready"
    @Published var isCapturing = false
    @Published var noteFilter: NoteFilter = .all
    @Published var viewportSize = CGSize(width: 900, height: 650)
    @Published var editingNoteID: UUID?
    private var autosaveTask: Task<Void, Never>?

    init() {
        board = Board()
    }

    var selectedNote: TackNote? {
        guard let selectedNoteID else { return nil }
        return board.notes.first { $0.id == selectedNoteID }
    }

    var filteredNotes: [TackNote] {
        let notes: [TackNote]
        switch noteFilter {
        case .all:
            notes = board.notes
        case .captured:
            notes = board.notes.filter(\.isCaptured)
        case .textOnly:
            notes = board.notes.filter { !$0.isCaptured }
        case .group(let name):
            notes = board.notes.filter { $0.groupName == name }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return notes }
        return notes.filter {
            $0.text.lowercased().contains(query) || ($0.groupName?.lowercased().contains(query) ?? false)
        }
    }

    var capturedNoteCount: Int { board.notes.filter(\.isCaptured).count }
    var textOnlyNoteCount: Int { board.notes.count - capturedNoteCount }

    func noteCount(for filter: NoteFilter) -> Int {
        switch filter {
        case .all: return board.notes.count
        case .captured: return capturedNoteCount
        case .textOnly: return textOnlyNoteCount
        case .group(let name): return board.notes.filter { $0.groupName == name }.count
        }
    }

    var groupNames: [String] {
        Array(Set(board.groups.map(\.name))).sorted()
    }

    func newBoard() {
        autosaveTask?.cancel()
        autosaveTask = nil
        board = Board()
        packageURL = nil
        selectedNoteID = nil
        editingNoteID = nil
        try? TackWidgetStore.clear()
        WidgetCenter.shared.reloadTimelines(ofKind: TackWidgetSnapshot.widgetKind)
        zoom = 1
        pan = .zero
        noteFilter = .all
        statusMessage = "New board"
    }

    func importLegacy() {
        let panel = NSOpenPanel()
        panel.title = "Import a Post-it Board"
        panel.message = "Choose a .postit board exported from the Post-it app."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.zip, UTType.data]
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            autosaveTask?.cancel()
            autosaveTask = nil
            let destination = try uniqueDestination(for: sourceURL.deletingPathExtension().lastPathComponent)
            let result = try LegacyPostitImporter.importArchive(at: sourceURL, to: destination)
            board = result.board
            packageURL = result.destinationURL
            selectedNoteID = board.notes.first?.id
            editingNoteID = nil
            try? publishWidgetSnapshot()
            zoom = 1
            pan = .zero
            noteFilter = .all
            statusMessage = "Imported \(result.sourceNoteCount) notes · \(result.copiedNoteImageCount) images"
            if !result.warnings.isEmpty {
                statusMessage += " · \(result.warnings.count) warning(s)"
            }
        } catch {
            presentError(error)
        }
    }

    func openTack() {
        let panel = NSOpenPanel()
        panel.title = "Open a Tack Board"
        panel.message = "Choose a .tack directory package."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.allowedContentTypes = [UTType.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            autosaveTask?.cancel()
            autosaveTask = nil
            let loaded = try TackPackage.load(from: url)
            board = loaded.board
            packageURL = loaded.rootURL
            selectedNoteID = board.notes.first?.id
            editingNoteID = nil
            try? publishWidgetSnapshot()
            zoom = 1
            pan = .zero
            noteFilter = .all
            statusMessage = "Opened \(board.notes.count) notes"
        } catch {
            presentError(error)
        }
    }

    func save() {
        autosaveTask?.cancel()
        autosaveTask = nil
        writeBoard(status: "Saved · \(board.notes.count) notes")
    }

    private func writeBoard(status: String? = nil) {
        do {
            let destination = try packageURL ?? uniqueDestination(for: board.title)
            board.touch()
            try TackPackage.save(board, to: destination)
            packageURL = destination
            try publishWidgetSnapshot()
            if let status { statusMessage = status }
        } catch {
            presentError(error)
        }
    }

    func addNote() {
        let noteWidth = 180.0
        let noteHeight = 180.0
        let worldCenterX = (viewportSize.width * 0.5 - pan.width) / max(zoom, 0.01)
        let worldCenterY = (viewportSize.height * 0.5 - pan.height) / max(zoom, 0.01)
        let baseX = worldCenterX - noteWidth / 2
        let baseY = worldCenterY - noteHeight / 2
        let offset = 28.0
        var noteX = baseX
        var noteY = baseY
        var attempt = 0
        while board.notes.contains(where: { overlaps($0.frame, TackRect(x: noteX, y: noteY, width: noteWidth, height: noteHeight)) }) && attempt < 100 {
            noteX = baseX + offset * Double(attempt % 8)
            noteY = baseY + offset * Double(attempt / 8)
            attempt += 1
        }
        let note = TackNote(
            frame: TackRect(
                x: noteX,
                y: noteY,
                width: noteWidth,
                height: noteHeight
            ),
            color: .yellow
        )
        board.notes.append(note)
        board.touch()
        selectedNoteID = note.id
        statusMessage = "Added note"
        scheduleAutosave()
    }

    func captureImage() {
        guard !isCapturing else { return }
        let panel = NSOpenPanel()
        panel.title = "Capture Notes from an Image"
        panel.message = "Choose a photo, scan, screenshot, or exported wall image. Tack will detect note-shaped regions and OCR each one on-device."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            autosaveTask?.cancel()
            autosaveTask = nil
            let destination = try packageURL ?? uniqueDestination(for: board.title == "Untitled Board" ? sourceURL.deletingPathExtension().lastPathComponent : board.title)
            if packageURL == nil {
                packageURL = destination
                try TackPackage.save(board, to: destination)
            }
            let originX = board.notes.map { $0.frame.x + $0.frame.width }.max().map { $0 + 120 } ?? 80
            isCapturing = true
            statusMessage = "Capturing and transcribing…"
            let groupName = sourceURL.deletingPathExtension().lastPathComponent
            Task {
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try TackImageCapture.capture(
                            imageAt: sourceURL,
                            to: destination,
                            originX: originX,
                            originY: 80,
                            groupName: groupName
                        )
                    }.value
                    board.notes.append(contentsOf: result.notes)
                    board.groups.append(result.group)
                    board.captures.append(result.capture)
                    board.canvas.width = max(board.canvas.width, result.canvasWidth)
                    board.canvas.height = max(board.canvas.height, result.canvasHeight)
                    if board.title == "Untitled Board" { board.title = groupName }
                    board.touch()
                    try TackPackage.save(board, to: destination)
                    selectedNoteID = result.notes.first?.id
                    statusMessage = "Captured \(result.notes.count) note(s)\(result.usedFallback ? " · whole image kept as one note" : "")"
                } catch {
                    presentError(error)
                }
                isCapturing = false
            }
        } catch {
            presentError(error)
        }
    }

    func exportMarkdown() {
        let panel = NSSavePanel()
        panel.title = "Export Markdown"
        panel.nameFieldStringValue = "\(board.title).md"
        panel.allowedContentTypes = [.text]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try TackExporter.writeMarkdown(board, to: url)
            statusMessage = "Exported Markdown"
        } catch { presentError(error) }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "Export CSV"
        panel.nameFieldStringValue = "\(board.title).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try TackExporter.writeCSV(board, to: url)
            statusMessage = "Exported CSV"
        } catch { presentError(error) }
    }

    func deleteSelected() {
        guard let selectedNoteID else { return }
        board.notes.removeAll { $0.id == selectedNoteID }
        for index in board.groups.indices {
            board.groups[index].noteIDs.removeAll { $0 == selectedNoteID }
        }
        if board.pinnedNoteID == selectedNoteID {
            board.pinnedNoteID = nil
            try? TackWidgetStore.clear()
            WidgetCenter.shared.reloadTimelines(ofKind: TackWidgetSnapshot.widgetKind)
        }
        board.touch()
        self.selectedNoteID = nil
        editingNoteID = nil
        statusMessage = "Deleted note"
        scheduleAutosave()
    }

    func beginEditing(_ id: UUID) {
        selectedNoteID = id
        editingNoteID = id
    }

    func endEditing() {
        editingNoteID = nil
    }

    func togglePinnedNote() {
        guard let selectedNoteID, board.notes.contains(where: { $0.id == selectedNoteID }) else { return }
        if board.pinnedNoteID == selectedNoteID {
            board.pinnedNoteID = nil
            do {
                try TackWidgetStore.clear()
                WidgetCenter.shared.reloadTimelines(ofKind: TackWidgetSnapshot.widgetKind)
                board.touch()
                writeBoard(status: "Unpinned note")
            } catch {
                presentError(error)
            }
        } else {
            board.pinnedNoteID = selectedNoteID
            writeBoard(status: "Pinned note to desktop widget")
        }
    }

    func isPinned(_ id: UUID) -> Bool {
        board.pinnedNoteID == id
    }

    func updateNote(_ id: UUID, _ update: (inout TackNote) -> Void) {
        guard let index = board.notes.firstIndex(where: { $0.id == id }) else { return }
        update(&board.notes[index])
        board.notes[index].modifiedAt = Date()
        board.touch()
        scheduleAutosave()
    }

    func setFrame(_ id: UUID, _ frame: TackRect) {
        updateNote(id) { $0.frame = frame }
    }

    func updateViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewportSize = size
    }

    func fitCanvas(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewportSize = size
        let usable = CGSize(width: max(100, size.width - 48), height: max(100, size.height - 48))
        guard let bounds = noteBounds else {
            zoom = 1
            pan = CGSize(width: size.width / 2, height: size.height / 2)
            return
        }

        let padding = 120.0
        let worldWidth = max(320, bounds.width + padding * 2)
        let worldHeight = max(240, bounds.height + padding * 2)
        zoom = min(1.25, max(0.08, min(usable.width / worldWidth, usable.height / worldHeight)))
        let leftWorld = bounds.x - padding
        let topWorld = bounds.y - padding
        pan = CGSize(
            width: (size.width - worldWidth * zoom) / 2 - leftWorld * zoom,
            height: (size.height - worldHeight * zoom) / 2 - topWorld * zoom
        )
    }

    func visibleNotes(in size: CGSize) -> [TackNote] {
        guard zoom > 0 else { return filteredNotes }
        let margin = 240 / zoom
        let minX = -pan.width / zoom - margin
        let minY = -pan.height / zoom - margin
        let maxX = (size.width - pan.width) / zoom + margin
        let maxY = (size.height - pan.height) / zoom + margin
        return filteredNotes.filter {
            $0.frame.x < maxX &&
                $0.frame.x + $0.frame.width > minX &&
                $0.frame.y < maxY &&
                $0.frame.y + $0.frame.height > minY
        }
    }

    func imageURL(for note: TackNote) -> URL? {
        guard let imagePath = note.imagePath, let packageURL else { return nil }
        return packageURL.appendingPathComponent(imagePath)
    }

    private func uniqueDestination(for title: String) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let tackFolder = documents.appendingPathComponent("Tack", isDirectory: true)
        try FileManager.default.createDirectory(at: tackFolder, withIntermediateDirectories: true)

        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Board" : title
        var candidate = tackFolder.appendingPathComponent("\(safeTitle).tack", isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = tackFolder.appendingPathComponent("\(safeTitle) \(number).tack", isDirectory: true)
            number += 1
        }
        return candidate
    }

    private func presentError(_ error: Error) {
        statusMessage = "Error: \(error.localizedDescription)"
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private var noteBounds: TackRect? {
        guard let first = board.notes.first else { return nil }
        return board.notes.dropFirst().reduce(first.frame) { result, note in
            let minX = min(result.x, note.frame.x)
            let minY = min(result.y, note.frame.y)
            let maxX = max(result.x + result.width, note.frame.x + note.frame.width)
            let maxY = max(result.y + result.height, note.frame.y + note.frame.height)
            return TackRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    private func overlaps(_ lhs: TackRect, _ rhs: TackRect) -> Bool {
        lhs.x < rhs.x + rhs.width &&
            lhs.x + lhs.width > rhs.x &&
            lhs.y < rhs.y + rhs.height &&
            lhs.y + lhs.height > rhs.y
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.writeBoard(status: "Autosaved · \(self?.board.notes.count ?? 0) notes")
        }
    }

    private func publishWidgetSnapshot() throws {
        guard let pinnedNoteID = board.pinnedNoteID,
              let note = board.notes.first(where: { $0.id == pinnedNoteID }) else {
            try TackWidgetStore.clear()
            WidgetCenter.shared.reloadTimelines(ofKind: TackWidgetSnapshot.widgetKind)
            return
        }

        let snapshot = TackWidgetSnapshot(
            boardID: board.id,
            boardTitle: board.title,
            noteID: note.id,
            text: note.text,
            color: note.color,
            imagePath: imageURL(for: note)?.path,
            fontName: note.fontName,
            fontSize: note.fontSize,
            isBold: note.isBold,
            isItalic: note.isItalic,
            updatedAt: Date()
        )
        try TackWidgetStore.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: TackWidgetSnapshot.widgetKind)
    }
}

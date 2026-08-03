import AppKit
import SwiftUI
import TackCore
import TackCapture
import TackFormat
import TackInterop
import UniformTypeIdentifiers

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
            if let status { statusMessage = status }
        } catch {
            presentError(error)
        }
    }

    func addNote() {
        let note = TackNote(frame: TackRect(x: 120, y: 120, width: 180, height: 180), color: .yellow)
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
        board.touch()
        self.selectedNoteID = nil
        statusMessage = "Deleted note"
        scheduleAutosave()
    }

    func updateNote(_ id: UUID, _ update: (inout TackNote) -> Void) {
        guard let index = board.notes.firstIndex(where: { $0.id == id }) else { return }
        update(&board.notes[index])
        board.notes[index].modifiedAt = Date()
        board.touch()
    }

    func setFrame(_ id: UUID, _ frame: TackRect) {
        updateNote(id) { $0.frame = frame }
    }

    func fitCanvas(in size: CGSize) {
        guard board.canvas.width > 0, board.canvas.height > 0, size.width > 0, size.height > 0 else { return }
        let usable = CGSize(width: max(100, size.width - 48), height: max(100, size.height - 48))
        zoom = min(usable.width / board.canvas.width, usable.height / board.canvas.height)
        pan = CGSize(width: (size.width - board.canvas.width * zoom) / 2, height: (size.height - board.canvas.height * zoom) / 2)
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
}

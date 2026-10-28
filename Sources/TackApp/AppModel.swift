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
    @Published private(set) var libraryEntries: [TackBoardLibraryEntry] = []
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
    private let libraryDirectory: URL
    private var hasPendingChanges = false
    weak var activeWindow: NSWindow?

    init(initialBoardURL: URL? = nil) {
        board = Board()
        libraryDirectory = TackBoardLibrary.defaultDirectory
        try? FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        BoardWindowRegistry.shared.register(self)
        refreshLibrary()

        if let initialBoardURL {
            do {
                let loaded = try TackPackage.load(from: initialBoardURL)
                board = loaded.board
                packageURL = loaded.rootURL
                rememberLastBoard(loaded.rootURL)
                try? publishWidgetSnapshots()
                statusMessage = "Reopened \(board.notes.count) notes"
            } catch {
                statusMessage = "Couldn't reopen the last board: \(error.localizedDescription)"
            }
        }
    }

    static func lastOpenedBoardURL() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: "app.tack.lastBoardPath"),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func refreshLibrary() {
        do {
            libraryEntries = try TackBoardLibrary.discover(in: libraryDirectory)
        } catch {
            statusMessage = "Couldn't read Tack boards: \(error.localizedDescription)"
        }
    }

    func activateWindow() {
        guard let activeWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        activeWindow.makeKeyAndOrderFront(nil)
    }

    func displayError(_ error: Error) {
        presentError(error)
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
        do {
            try flushPendingChanges()
            var state = currentSessionState
            try TackBoardSessionTransitions.startNew(&state, libraryDirectory: libraryDirectory)
            apply(state)
        } catch {
            presentError(error)
            return
        }
        selectedNoteID = nil
        editingNoteID = nil
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
            try flushPendingChanges()
            let destination = try TackBoardLibrary.uniqueDestination(
                for: sourceURL.deletingPathExtension().lastPathComponent,
                in: libraryDirectory
            )
            let result = try LegacyPostitImporter.importArchive(at: sourceURL, to: destination)
            board = result.board
            packageURL = result.destinationURL
            hasPendingChanges = false
            selectedNoteID = board.notes.first?.id
            editingNoteID = nil
            rememberLastBoard(result.destinationURL)
            try? publishWidgetSnapshots()
            zoom = 1
            pan = .zero
            noteFilter = .all
            statusMessage = "Imported \(result.sourceNoteCount) notes · \(result.copiedNoteImageCount) images"
            refreshLibrary()
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

        openBoard(at: url)
    }

    func openBoard(at url: URL) {
        if packageURL?.standardizedFileURL == url.standardizedFileURL { return }
        if let otherWindow = BoardWindowRegistry.shared.openModel(for: url, excluding: self) {
            otherWindow.activateWindow()
            statusMessage = "Focused the window already showing \(otherWindow.board.title)"
            return
        }

        do {
            try flushPendingChanges()
            var state = currentSessionState
            try TackBoardSessionTransitions.open(url, state: &state, libraryDirectory: libraryDirectory)
            apply(state)
            autosaveTask?.cancel()
            autosaveTask = nil
            selectedNoteID = board.notes.first?.id
            editingNoteID = nil
            rememberLastBoard(url)
            try? publishWidgetSnapshots()
            zoom = 1
            pan = .zero
            noteFilter = .all
            statusMessage = "Opened \(board.notes.count) notes"
            refreshLibrary()
        } catch {
            presentError(error)
        }
    }

    func save() {
        autosaveTask?.cancel()
        autosaveTask = nil
        hasPendingChanges = true
        writeBoard(status: "Saved · \(board.notes.count) notes")
    }

    private func writeBoard(status: String? = nil) {
        do {
            try flushPendingChanges()
            if let status { statusMessage = status }
        } catch {
            presentError(error)
        }
    }

    func flushPendingChanges() throws {
        autosaveTask?.cancel()
        autosaveTask = nil
        let savedChanges = hasPendingChanges
        var state = currentSessionState
        try TackBoardSessionTransitions.flush(&state, libraryDirectory: libraryDirectory)
        apply(state)
        if savedChanges, let packageURL {
            rememberLastBoard(packageURL)
            refreshLibrary()
        }
        try publishWidgetSnapshots()
    }

    private var currentSessionState: TackBoardSessionState {
        TackBoardSessionState(board: board, packageURL: packageURL, hasPendingChanges: hasPendingChanges)
    }

    private func apply(_ state: TackBoardSessionState) {
        board = state.board
        packageURL = state.packageURL
        hasPendingChanges = state.hasPendingChanges
    }

    private func rememberLastBoard(_ url: URL) {
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: "app.tack.lastBoardPath")
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
            try flushPendingChanges()
            let destination = try packageURL ?? TackBoardLibrary.uniqueDestination(
                for: board.title == "Untitled Board" ? sourceURL.deletingPathExtension().lastPathComponent : board.title,
                in: libraryDirectory
            )
            if packageURL == nil {
                packageURL = destination
                hasPendingChanges = true
                try flushPendingChanges()
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
                    hasPendingChanges = true
                    try flushPendingChanges()
                    try publishWidgetSnapshots()
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
        do {
            let wasPinned = try TackWidgetStore.contains(boardID: board.id, noteID: selectedNoteID)
            board.notes.removeAll { $0.id == selectedNoteID }
            for index in board.groups.indices {
                board.groups[index].noteIDs.removeAll { $0 == selectedNoteID }
            }
            if board.pinnedNoteID == selectedNoteID { board.pinnedNoteID = nil }
            self.selectedNoteID = nil
            editingNoteID = nil
            hasPendingChanges = true
            try flushPendingChanges()
            if wasPinned {
                try TackWidgetStore.remove(boardID: board.id, noteID: selectedNoteID)
                WidgetCenter.shared.reloadTimelines(ofKind: TackWidgetSnapshot.widgetKind)
            }
            try publishWidgetSnapshots()
            statusMessage = "Deleted note"
        } catch {
            presentError(error)
        }
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
        do {
            let isCatalogued = try TackWidgetStore.contains(boardID: board.id, noteID: selectedNoteID)
            let wasPinned = isCatalogued || board.pinnedNoteID == selectedNoteID
            let previousMarker = board.pinnedNoteID
            if wasPinned {
                if board.pinnedNoteID == selectedNoteID { board.pinnedNoteID = nil }
                hasPendingChanges = true
                try flushPendingChanges()
                do {
                    try TackWidgetStore.remove(boardID: board.id, noteID: selectedNoteID)
                    WidgetCenter.shared.reloadTimelines(ofKind: TackWidgetSnapshot.widgetKind)
                    statusMessage = "Unpinned note"
                } catch {
                    board.pinnedNoteID = previousMarker
                    hasPendingChanges = true
                    try? flushPendingChanges()
                    throw error
                }
            } else {
                board.pinnedNoteID = selectedNoteID
                hasPendingChanges = true
                try flushPendingChanges()
                do {
                    try publishWidgetSnapshots()
                    statusMessage = "Pinned note to desktop widget"
                } catch {
                    board.pinnedNoteID = previousMarker
                    hasPendingChanges = true
                    try? flushPendingChanges()
                    throw error
                }
            }
        } catch {
            presentError(error)
        }
    }

    func isPinned(_ id: UUID) -> Bool {
        (try? TackWidgetStore.contains(boardID: board.id, noteID: id)) ?? (board.pinnedNoteID == id)
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
        // Keep these as simple CGFloat expressions for older Swift compilers in CI.
        let scaledWidth = CGFloat(worldWidth) * zoom
        let scaledHeight = CGFloat(worldHeight) * zoom
        let originX = CGFloat(leftWorld) * zoom
        let originY = CGFloat(topWorld) * zoom
        let offsetX = (size.width - scaledWidth) / 2 - originX
        let offsetY = (size.height - scaledHeight) / 2 - originY
        pan = CGSize(width: offsetX, height: offsetY)
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
        hasPendingChanges = true
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

    private func publishWidgetSnapshots() throws {
        var pinnedIDs = Set(try TackWidgetStore.allSnapshots()
            .filter { $0.boardID == board.id }
            .map(\.noteID))
        if let legacyPinnedID = board.pinnedNoteID { pinnedIDs.insert(legacyPinnedID) }

        for noteID in pinnedIDs {
            guard let note = board.notes.first(where: { $0.id == noteID }) else {
                try TackWidgetStore.remove(boardID: board.id, noteID: noteID)
                continue
            }

            let widgetImagePath: String?
            if let sourceURL = imageURL(for: note), FileManager.default.fileExists(atPath: sourceURL.path) {
                let destinationURL = TackWidgetStore.imageURL(boardID: board.id, noteID: note.id, fileExtension: sourceURL.pathExtension)
                try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contentsOf: sourceURL).write(to: destinationURL, options: .atomic)
                widgetImagePath = destinationURL.path
            } else {
                widgetImagePath = nil
            }

            try TackWidgetStore.upsert(TackWidgetSnapshot(
                boardID: board.id,
                boardTitle: board.title,
                noteID: note.id,
                text: note.text,
                color: note.color,
                imagePath: widgetImagePath,
                fontName: note.fontName,
                fontSize: note.fontSize,
                isBold: note.isBold,
                isItalic: note.isItalic,
                updatedAt: Date()
            ))
        }

        if !pinnedIDs.isEmpty {
            WidgetCenter.shared.reloadTimelines(ofKind: TackWidgetSnapshot.widgetKind)
        }
    }
}

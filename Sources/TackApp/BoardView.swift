import AppKit
import SwiftUI
import TackCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showInspector = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
                Text(model.board.title)
                    .font(.headline)
                Text("\(model.board.notes.count) notes")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                Button {
                    model.captureImage()
                } label: {
                    Label(model.isCapturing ? "Capturing…" : "Capture", systemImage: model.isCapturing ? "hourglass" : "camera.viewfinder")
                }
                .buttonStyle(.borderless)
                .disabled(model.isCapturing)
                Menu {
                    Button("Export Markdown…") { model.exportMarkdown() }
                    Button("Export CSV…") { model.exportCSV() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                TextField("Search notes and groups", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            HStack(spacing: 0) {
                BoardSidebar(model: model)
                    .frame(width: 180)
                Divider()
                BoardCanvas(model: model)
                if showInspector {
                    Divider()
                    NoteInspector(model: model)
                        .frame(width: 270)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct BoardSidebar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BOARD")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                filterButton("All notes", systemImage: "square.grid.2x2", filter: .all)
                filterButton("Captured", systemImage: "photo.on.rectangle", filter: .captured)
                filterButton("Text-only", systemImage: "character.textbox", filter: .textOnly)
            }
            .font(.callout)

            if !model.groupNames.isEmpty {
                Text("GROUPS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                ForEach(model.groupNames, id: \.self) { group in
                    filterButton(group, systemImage: "folder", filter: .group(group))
                }
            }
            Spacer()
            Text(model.statusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func filterButton(_ title: String, systemImage: String, filter: NoteFilter) -> some View {
        Button {
            model.noteFilter = filter
        } label: {
            Label {
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(model.noteCount(for: filter))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: systemImage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.noteFilter == filter ? Color.accentColor : .primary)
    }
}

struct BoardCanvas: View {
    @ObservedObject var model: AppModel
    @State private var panOrigin: CGSize?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let canvasRect = CGRect(
                        x: model.pan.width,
                        y: model.pan.height,
                        width: model.board.canvas.width * model.zoom,
                        height: model.board.canvas.height * model.zoom
                    )
                    context.fill(Path(canvasRect), with: .color(model.board.canvas.background.swiftUIColor))
                    guard model.board.canvas.showsGrid else { return }
                    var grid = Path()
                    let spacing = max(12, 40 * model.zoom)
                    var x = canvasRect.minX
                    while x <= canvasRect.maxX {
                        grid.move(to: CGPoint(x: x, y: canvasRect.minY))
                        grid.addLine(to: CGPoint(x: x, y: canvasRect.maxY))
                        x += spacing
                    }
                    var y = canvasRect.minY
                    while y <= canvasRect.maxY {
                        grid.move(to: CGPoint(x: canvasRect.minX, y: y))
                        grid.addLine(to: CGPoint(x: canvasRect.maxX, y: y))
                        y += spacing
                    }
                    context.stroke(grid, with: .color(.black.opacity(0.07)), lineWidth: 0.6)
                }

                ForEach(model.filteredNotes) { note in
                    PositionedNote(model: model, note: note)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if panOrigin == nil { panOrigin = model.pan }
                        guard let panOrigin else { return }
                        model.pan = CGSize(width: panOrigin.width + value.translation.width, height: panOrigin.height + value.translation.height)
                    }
                    .onEnded { _ in panOrigin = nil }
            )
            .onAppear { model.fitCanvas(in: proxy.size) }
            .onChange(of: model.board.id) { _, _ in model.fitCanvas(in: proxy.size) }
            .onChange(of: model.board.canvas.width) { _, _ in model.fitCanvas(in: proxy.size) }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                Button("Fit") { model.fitCanvas(in: CGSize(width: 900, height: 650)) }
                Slider(value: $model.zoom, in: 0.05...2)
                    .frame(width: 120)
                Text("\(Int(model.zoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 42, alignment: .trailing)
            }
            .padding(8)
            .background(.regularMaterial, in: Capsule())
            .padding(12)
        }
    }
}

private struct PositionedNote: View {
    @ObservedObject var model: AppModel
    let note: TackNote
    @State private var dragOrigin: TackRect?

    var body: some View {
        NoteCard(note: note, imageURL: model.imageURL(for: note), isSelected: model.selectedNoteID == note.id)
            .frame(width: note.frame.width * model.zoom, height: note.frame.height * model.zoom)
            .position(
                x: model.pan.width + note.frame.midX * model.zoom,
                y: model.pan.height + note.frame.midY * model.zoom
            )
            .rotationEffect(.radians(note.rotation))
            .onTapGesture { model.selectedNoteID = note.id }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragOrigin == nil { dragOrigin = note.frame }
                        guard let dragOrigin else { return }
                        let dx = value.translation.width / max(model.zoom, 0.01)
                        let dy = value.translation.height / max(model.zoom, 0.01)
                        model.setFrame(note.id, TackRect(x: dragOrigin.x + dx, y: dragOrigin.y + dy, width: dragOrigin.width, height: dragOrigin.height))
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
    }
}

private struct NoteInspector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("INSPECTOR")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if let note = model.selectedNote {
                Text(note.groupName ?? (note.isCaptured ? "Captured note" : "Digital note"))
                    .font(.headline)
                TextEditor(text: Binding(
                    get: { model.selectedNote?.text ?? "" },
                    set: { value in
                        guard let id = model.selectedNoteID else { return }
                        model.updateNote(id) { $0.text = value }
                    }
                ))
                .font(.body)
                .frame(minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

                HStack {
                    Text("Position")
                    Spacer()
                    Text("\(Int(note.frame.x)), \(Int(note.frame.y))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("OCR")
                    Spacer()
                    Text(note.ocrConfidence.map { "\(Int($0 * 100))%" } ?? "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    model.deleteSelected()
                } label: {
                    Label("Delete note", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            } else {
                ContentUnavailableView("No note selected", systemImage: "pin", description: Text("Select a note on the canvas to edit its text or move it."))
            }
            Spacer()
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct NoteCard: View {
    let note: TackNote
    let imageURL: URL?
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(note.color.swiftUIColor)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)

            if let imageURL, let nsImage = NSImage(contentsOf: imageURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else if !note.text.isEmpty {
                Text(note.text)
                    .font(.system(size: max(9, min(22, note.frame.width * 0.14)), weight: .medium, design: .rounded))
                    .foregroundStyle(.black.opacity(0.82))
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(.black.opacity(0.22))
            }

            RoundedRectangle(cornerRadius: 5)
                .stroke(isSelected ? Color.accentColor : .black.opacity(0.12), lineWidth: isSelected ? 3 : 1)
        }
    }
}

private extension TackColor {
    var swiftUIColor: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
}

import AppKit
import SwiftUI
import TackCore

private struct NoteColorChoice: Identifiable {
    let name: String
    let color: TackColor

    var id: String { name }
}

private let noteColorChoices = [
    NoteColorChoice(name: "Yellow", color: .yellow),
    NoteColorChoice(name: "Blue", color: .blue),
    NoteColorChoice(name: "Green", color: .green),
    NoteColorChoice(name: "Pink", color: .pink),
    NoteColorChoice(name: "Lavender", color: .lavender),
    NoteColorChoice(name: "Orange", color: .orange),
    NoteColorChoice(name: "White", color: .white)
]

private let noteFontChoices = ["System", "Helvetica Neue", "Avenir Next", "Georgia", "Menlo"]
private let noteSizeChoices: [Double] = [12, 14, 16, 18, 22, 28, 36]

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
                    model.addNote()
                } label: {
                    Label("New note", systemImage: "plus.square")
                }
                .buttonStyle(.borderless)
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
                    let viewportRect = CGRect(origin: .zero, size: size)
                    context.fill(Path(viewportRect), with: .color(model.board.canvas.background.swiftUIColor))
                    guard model.board.canvas.showsGrid else { return }
                    var grid = Path()
                    let spacing = max(12, 40 * model.zoom)
                    let startX = model.pan.width.truncatingRemainder(dividingBy: spacing)
                    let startY = model.pan.height.truncatingRemainder(dividingBy: spacing)
                    var x = startX >= 0 ? startX : startX + spacing
                    while x <= size.width {
                        grid.move(to: CGPoint(x: x, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: size.height))
                        x += spacing
                    }
                    var y = startY >= 0 ? startY : startY + spacing
                    while y <= size.height {
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                        y += spacing
                    }
                    context.stroke(grid, with: .color(.black.opacity(0.07)), lineWidth: 0.6)
                }

                ForEach(model.visibleNotes(in: proxy.size)) { note in
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
            .onAppear {
                model.updateViewport(proxy.size)
                model.fitCanvas(in: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                model.updateViewport(newSize)
            }
            .onChange(of: model.board.id) { _, _ in model.fitCanvas(in: proxy.size) }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                Button("Fit") { model.fitCanvas(in: model.viewportSize) }
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
        NoteCard(
            note: note,
            imageURL: model.imageURL(for: note),
            isSelected: model.selectedNoteID == note.id,
            isEditing: model.editingNoteID == note.id,
            text: Binding(
                get: { model.board.notes.first(where: { $0.id == note.id })?.text ?? note.text },
                set: { value in model.updateNote(note.id) { $0.text = value } }
            )
        )
            .frame(width: note.frame.width * model.zoom, height: note.frame.height * model.zoom)
            .position(
                x: model.pan.width + note.frame.midX * model.zoom,
                y: model.pan.height + note.frame.midY * model.zoom
            )
            .rotationEffect(.radians(note.rotation))
            .onTapGesture(count: 2) { model.beginEditing(note.id) }
            .onTapGesture { model.selectedNoteID = note.id }
            .contextMenu {
                Button(model.isPinned(note.id) ? "Unpin from desktop" : "Pin to desktop widget") {
                    model.selectedNoteID = note.id
                    model.togglePinnedNote()
                }
                Button("Edit note") { model.beginEditing(note.id) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(note.text.isEmpty ? "Empty note" : "Note: \(note.text)")
            .accessibilityHint("Click to select. Double-click to edit.")
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

                Text("STYLE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                NoteStyleControls(model: model, note: note)

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
                Button {
                    model.togglePinnedNote()
                } label: {
                    Label(
                        model.isPinned(note.id) ? "Unpin from desktop" : "Pin to desktop widget",
                        systemImage: model.isPinned(note.id) ? "pin.slash" : "pin"
                    )
                }
                .buttonStyle(.borderless)
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

private struct NoteStyleControls: View {
    @ObservedObject var model: AppModel
    let note: TackNote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(noteFontChoices, id: \.self) { fontName in
                        Button(fontName) {
                            model.updateNote(note.id) { $0.fontName = fontName == "System" ? nil : fontName }
                        }
                    }
                } label: {
                    Label(note.fontName ?? "System", systemImage: "textformat")
                }
                .menuStyle(.borderlessButton)

                Menu {
                    Button("Auto") {
                        model.updateNote(note.id) { $0.fontSize = nil }
                    }
                    ForEach(noteSizeChoices, id: \.self) { size in
                        Button("\(Int(size)) pt") {
                            model.updateNote(note.id) { $0.fontSize = size }
                        }
                    }
                } label: {
                    Label(note.fontSize.map { "\(Int($0)) pt" } ?? "Auto", systemImage: "textformat.size")
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 8) {
                Toggle("Bold", isOn: Binding(
                    get: { model.selectedNote?.isBold == true },
                    set: { value in model.updateNote(note.id) { $0.isBold = value } }
                ))
                .toggleStyle(.button)
                Toggle("Italic", isOn: Binding(
                    get: { model.selectedNote?.isItalic == true },
                    set: { value in model.updateNote(note.id) { $0.isItalic = value } }
                ))
                .toggleStyle(.button)
            }

            HStack(spacing: 7) {
                Text("Color")
                    .foregroundStyle(.secondary)
                ForEach(noteColorChoices) { choice in
                    Button {
                        model.updateNote(note.id) { $0.color = choice.color }
                    } label: {
                        Circle()
                            .fill(choice.color.swiftUIColor)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.9), lineWidth: note.color == choice.color ? 2 : 0)
                            }
                            .overlay {
                                Circle()
                                    .stroke(.black.opacity(note.color == choice.color ? 0.65 : 0.16), lineWidth: note.color == choice.color ? 2 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(choice.name)
                    .accessibilityLabel("\(choice.name) note color")
                    .accessibilityAddTraits(note.color == choice.color ? .isSelected : [])
                }
            }
        }
    }
}

private struct NoteCard: View {
    let note: TackNote
    let imageURL: URL?
    let isSelected: Bool
    let isEditing: Bool
    @Binding var text: String
    @FocusState private var isFocused: Bool

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
            }

            if isEditing {
                NoteEditor(note: note, text: $text, isFocused: $isFocused)
                    .padding(5)
            } else if imageURL == nil && !note.text.isEmpty {
                NoteText(note: note)
                    .foregroundStyle(.black.opacity(0.82))
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if imageURL == nil {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(.black.opacity(0.22))
            }

            RoundedRectangle(cornerRadius: 5)
                .stroke(isSelected ? Color.accentColor : .black.opacity(0.12), lineWidth: isSelected ? 3 : 1)
        }
        .onChange(of: isEditing) { _, value in
            if value {
                DispatchQueue.main.async { isFocused = true }
            } else {
                isFocused = false
            }
        }
        .onAppear {
            if isEditing {
                DispatchQueue.main.async { isFocused = true }
            }
        }
    }
}

private struct NoteEditor: View {
    let note: TackNote
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        Group {
            if note.isItalic == true {
                TextEditor(text: $text)
                    .italic()
                    .focused($isFocused)
            } else {
                TextEditor(text: $text)
                    .focused($isFocused)
            }
        }
        .font(note.displayFont)
        .fontWeight(note.isBold == true ? .bold : .medium)
        .foregroundStyle(.black.opacity(0.86))
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}

private struct NoteText: View {
    let note: TackNote

    var body: some View {
        Group {
            if note.isItalic == true {
                Text(note.text).italic()
            } else {
                Text(note.text)
            }
        }
        .font(note.displayFont)
        .fontWeight(note.isBold == true ? .bold : .medium)
    }
}

private extension TackNote {
    var displayFont: Font {
        let size = CGFloat(fontSize ?? max(9, min(22, frame.width * 0.14)))
        let weight: Font.Weight = isBold == true ? .bold : .medium
        if let fontName, !fontName.isEmpty {
            return .custom(fontName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }
}

private extension TackColor {
    var swiftUIColor: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
}

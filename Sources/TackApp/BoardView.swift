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

private enum TackUI {
    static let accent = Color.orange
    static let panelRadius: CGFloat = 10
    static let sidebarWidth: CGFloat = 196
    static let inspectorWidth: CGFloat = 292
    static let sectionLabel = Font.caption2.weight(.semibold)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showInspector = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(TackUI.accent.opacity(0.18))
                        Image(systemName: "pin.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(TackUI.accent)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.board.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(model.board.notes.count) \(model.board.notes.count == 1 ? "note" : "notes")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        model.addNote()
                    } label: {
                        Label("New note", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TackUI.accent)
                    .controlSize(.small)

                    Button {
                        model.captureImage()
                    } label: {
                        Label(model.isCapturing ? "Capturing…" : "Capture", systemImage: model.isCapturing ? "hourglass" : "camera.viewfinder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isCapturing)

                    Menu {
                        Button("Export Markdown…") { model.exportMarkdown() }
                        Button("Export CSV…") { model.exportCSV() }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Search notes and groups", text: $model.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                }
                .frame(width: 220)

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.bar)

            Divider()

            HStack(spacing: 0) {
                BoardSidebar(model: model)
                    .frame(width: TackUI.sidebarWidth)
                Divider()
                BoardCanvas(model: model)
                if showInspector {
                    Divider()
                    NoteInspector(model: model)
                        .frame(width: TackUI.inspectorWidth)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct BoardSidebar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BOARD")
                .font(TackUI.sectionLabel)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 3) {
                filterButton("All notes", systemImage: "square.grid.2x2", filter: .all)
                filterButton("Captured", systemImage: "photo.on.rectangle", filter: .captured)
                filterButton("Text-only", systemImage: "character.textbox", filter: .textOnly)
            }
            .font(.callout)

            if !model.groupNames.isEmpty {
                Text("GROUPS")
                    .font(TackUI.sectionLabel)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                ForEach(model.groupNames, id: \.self) { group in
                    filterButton(group, systemImage: "folder.fill", filter: .group(group))
                }
            }
            Spacer()
            Divider()
                .padding(.vertical, 10)
            HStack(alignment: .top, spacing: 7) {
                Circle()
                    .fill(TackUI.accent)
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
                Text(model.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(.horizontal, 8)
        }
        .padding(12)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(model.noteFilter == filter ? TackUI.accent.opacity(0.16) : .clear)
            }
            .overlay {
                if model.noteFilter == filter {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(TackUI.accent.opacity(0.28), lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.noteFilter == filter ? TackUI.accent : .primary)
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
                    context.stroke(grid, with: .color(.black.opacity(0.055)), lineWidth: 0.6)
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
        .overlay(alignment: .center) {
            if model.board.notes.isEmpty {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(TackUI.accent.opacity(0.14))
                        Image(systemName: "square.and.pencil")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(TackUI.accent)
                    }
                    .frame(width: 52, height: 52)

                    VStack(spacing: 5) {
                        Text("Your board is ready")
                            .font(.title3.weight(.semibold))
                        Text("Start with a thought, or capture a wall of notes.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        model.addNote()
                    } label: {
                        Label("Add your first note", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TackUI.accent)
                    .controlSize(.small)
                }
                .frame(maxWidth: 300)
                .padding(28)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.quaternary, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                Button {
                    model.fitCanvas(in: model.viewportSize)
                } label: {
                    Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderless)
                Slider(value: $model.zoom, in: 0.05...2)
                    .frame(width: 120)
                Text("\(Int(model.zoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 42, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
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
            isPinned: model.isPinned(note.id),
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("INSPECTOR")
                    .font(TackUI.sectionLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.selectedNote != nil {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)

            Divider()

            if let note = model.selectedNote {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.groupName ?? (note.isCaptured ? "Captured note" : "Digital note"))
                                .font(.title3.weight(.semibold))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(note.color.swiftUIColor)
                                    .frame(width: 8, height: 8)
                                Text(note.isCaptured ? "Captured from image" : "Created in Tack")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("CONTENT")
                                .font(TackUI.sectionLabel)
                                .foregroundStyle(.secondary)
                            TextEditor(text: Binding(
                                get: { model.selectedNote?.text ?? "" },
                                set: { value in
                                    guard let id = model.selectedNoteID else { return }
                                    model.updateNote(id) { $0.text = value }
                                }
                            ))
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .frame(height: 166)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.42), in: RoundedRectangle(cornerRadius: TackUI.panelRadius))
                            .overlay {
                                RoundedRectangle(cornerRadius: TackUI.panelRadius)
                                    .stroke(.quaternary, lineWidth: 1)
                            }
                            .overlay(alignment: .topLeading) {
                                if note.text.isEmpty {
                                    Text("Write something…")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 12)
                                        .allowsHitTesting(false)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("STYLE")
                                .font(TackUI.sectionLabel)
                                .foregroundStyle(.secondary)
                            NoteStyleControls(model: model, note: note)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text("DETAILS")
                                .font(TackUI.sectionLabel)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 7)
                            VStack(spacing: 0) {
                                detailRow("Position", value: "\(Int(note.frame.x)), \(Int(note.frame.y))")
                                Divider()
                                detailRow("OCR", value: note.ocrConfidence.map { "\(Int($0 * 100))%" } ?? "—")
                            }
                            .padding(.horizontal, 10)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.28), in: RoundedRectangle(cornerRadius: TackUI.panelRadius))
                        }

                        VStack(spacing: 8) {
                            Button {
                                model.togglePinnedNote()
                            } label: {
                                Label(
                                    model.isPinned(note.id) ? "Unpin from desktop" : "Pin to desktop widget",
                                    systemImage: model.isPinned(note.id) ? "pin.slash" : "pin"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(TackUI.accent)

                            Button(role: .destructive) {
                                model.deleteSelected()
                            } label: {
                                Label("Delete note", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                }
            } else {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(TackUI.accent.opacity(0.14))
                        Image(systemName: "cursorarrow.click.2")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(TackUI.accent)
                    }
                    .frame(width: 52, height: 52)
                    Text("Choose a note")
                        .font(.title3.weight(.semibold))
                    Text("Select a note on the canvas to edit its text, style, or position.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 230)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
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
                    styleMenuLabel(note.fontName ?? "System", systemImage: "textformat")
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
                    styleMenuLabel(note.fontSize.map { "\(Int($0)) pt" } ?? "Auto", systemImage: "textformat.size")
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
                .tint(TackUI.accent)
            }
            .tint(TackUI.accent)

            HStack(spacing: 8) {
                Text("Color")
                    .foregroundStyle(.secondary)
                ForEach(noteColorChoices) { choice in
                    Button {
                        model.updateNote(note.id) { $0.color = choice.color }
                    } label: {
                        Circle()
                            .fill(choice.color.swiftUIColor)
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle()
                                    .stroke(note.color == choice.color ? TackUI.accent : .black.opacity(0.16), lineWidth: note.color == choice.color ? 2.5 : 1)
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

    private func styleMenuLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct NoteCard: View {
    let note: TackNote
    let imageURL: URL?
    let isSelected: Bool
    let isPinned: Bool
    let isEditing: Bool
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(note.color.swiftUIColor)
                .shadow(color: .black.opacity(isSelected ? 0.24 : 0.16), radius: isSelected ? 8 : 4, y: isSelected ? 4 : 2)

            if let imageURL, let nsImage = NSImage(contentsOf: imageURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.68))
                    .padding(6)
                    .background(.white.opacity(0.42), in: Circle())
                    .padding(7)
            }

            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? TackUI.accent : .black.opacity(0.14), lineWidth: isSelected ? 2.5 : 1)
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

import AppKit
import AppIntents
import SwiftUI
import TackCore
import TackFormat
import WidgetKit

struct TackPinnedNoteEntry: TimelineEntry {
    let date: Date
    let snapshot: TackWidgetSnapshot?
    let unavailable: Bool

    init(date: Date, snapshot: TackWidgetSnapshot?, unavailable: Bool = false) {
        self.date = date
        self.snapshot = snapshot
        self.unavailable = unavailable
    }
}

struct TackPinnedNoteProvider: AppIntentTimelineProvider {
    typealias Intent = SelectTackNoteIntent

    func placeholder(in context: Context) -> TackPinnedNoteEntry {
        TackPinnedNoteEntry(date: Date(), snapshot: TackWidgetSnapshot(
            boardID: UUID(),
            boardTitle: "Tack",
            noteID: UUID(),
            text: "Pin a note from Tack",
            color: .yellow
        ))
    }

    func snapshot(for configuration: SelectTackNoteIntent, in context: Context) async -> TackPinnedNoteEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectTackNoteIntent, in context: Context) async -> Timeline<TackPinnedNoteEntry> {
        let entry = entry(for: configuration)
        let refresh = Date().addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func snapshot(for configuration: SelectTackNoteIntent) -> TackWidgetSnapshot? {
        do {
            guard let note = configuration.note else {
                return try TackWidgetStore.defaultSnapshot()
            }
            return try TackWidgetStore.snapshot(boardID: note.boardID, noteID: note.noteID)
        } catch {
            return nil
        }
    }

    private func entry(for configuration: SelectTackNoteIntent) -> TackPinnedNoteEntry {
        let snapshot = snapshot(for: configuration)
        return TackPinnedNoteEntry(date: Date(), snapshot: snapshot, unavailable: configuration.note != nil && snapshot == nil)
    }
}

struct TackPinnedNoteEntity: AppEntity, Identifiable {
    typealias ID = String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tack note")
    static let defaultQuery = TackPinnedNoteEntityQuery()

    let boardID: UUID
    let noteID: UUID
    let boardTitle: String
    let preview: String

    var id: String { "\(boardID.uuidString).\(noteID.uuidString)" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(boardTitle)", subtitle: "\(preview)")
    }

    var identity: TackWidgetIdentity { TackWidgetIdentity(boardID: boardID, noteID: noteID) }

    init(snapshot: TackWidgetSnapshot) {
        boardID = snapshot.boardID
        noteID = snapshot.noteID
        boardTitle = String(snapshot.boardTitle.prefix(60))
        let oneLine = snapshot.text.split(whereSeparator: \.isNewline).joined(separator: " ")
        preview = String((oneLine.isEmpty ? "Image note" : oneLine).prefix(72))
    }

    init(identity: TackWidgetIdentity) {
        boardID = identity.boardID
        noteID = identity.noteID
        boardTitle = "Unavailable Tack note"
        preview = "This note is no longer pinned"
    }
}

struct TackPinnedNoteEntityQuery: EntityQuery {
    func entities(for identifiers: [TackPinnedNoteEntity.ID]) async throws -> [TackPinnedNoteEntity] {
        let requestedIDs = Set(identifiers)
        let available = try TackWidgetStore.allSnapshots()
            .map { TackPinnedNoteEntity(snapshot: $0) }
            .filter { requestedIDs.contains($0.id) }
        let availableByID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        return identifiers.compactMap { identifier in
            if let entity = availableByID[identifier] { return entity }
            guard let identity = TackWidgetIdentity(id: identifier) else { return nil }
            return TackPinnedNoteEntity(identity: identity)
        }
    }

    func suggestedEntities() async throws -> [TackPinnedNoteEntity] {
        try TackWidgetStore.allSnapshots().map(TackPinnedNoteEntity.init(snapshot:))
    }
}

struct SelectTackNoteIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a Tack note"
    static let description = IntentDescription("Choose which pinned Tack note this widget displays.")

    @Parameter(title: "Note") var note: TackPinnedNoteEntity?

    init() {
        note = nil
    }
}

struct TackPinnedNoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TackPinnedNoteEntry

    var body: some View {
        ZStack {
            if let imagePath = entry.snapshot?.imagePath,
               let image = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay {
                        (entry.snapshot?.color.swiftUIColor ?? TackColor.yellow.swiftUIColor)
                            .opacity(0.12)
                    }
            }

            if let snapshot = entry.snapshot {
                fittedNoteText(snapshot)
                    .padding(14)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "pin.slash")
                        .font(.title2)
                    Text(entry.unavailable ? "This note is no longer pinned" : "Pin a note from Tack")
                        .font(.headline)
                }
                .foregroundStyle(.black)
            }
        }
        .containerBackground(for: .widget) {
            (entry.snapshot?.color.swiftUIColor ?? TackColor.yellow.swiftUIColor)
        }
    }

    @ViewBuilder
    private func fittedNoteText(_ snapshot: TackWidgetSnapshot) -> some View {
        let baseSize = snapshot.baseFontSize(for: family)
        if snapshot.fontSize != nil {
            noteText(snapshot, size: baseSize)
        } else {
            ViewThatFits(in: .vertical) {
                noteText(snapshot, size: baseSize)
                noteText(snapshot, size: baseSize - 2)
                noteText(snapshot, size: baseSize - 4)
                noteText(snapshot, size: baseSize - 6)
                noteText(snapshot, size: baseSize - 8)
                noteText(snapshot, size: baseSize * 0.58)
            }
        }
    }

    @ViewBuilder
    private func noteText(_ snapshot: TackWidgetSnapshot, size: CGFloat) -> some View {
        Text(snapshot.text.isEmpty ? "New note" : snapshot.text)
            .font(snapshot.font(size: size))
            .fontWeight(snapshot.isBold == true ? .bold : .regular)
            .italic(snapshot.isItalic == true)
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

struct TackPinnedNoteWidget: Widget {
    static let kind = TackWidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SelectTackNoteIntent.self, provider: TackPinnedNoteProvider()) { entry in
            TackPinnedNoteWidgetView(entry: entry)
        }
        .configurationDisplayName("Pinned Note")
        .description("Keep one Tack note visible on your Mac desktop.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct TackWidgets: WidgetBundle {
    var body: some Widget {
        TackPinnedNoteWidget()
    }
}

private extension TackWidgetSnapshot {
    func font(size: CGFloat) -> Font {
        guard let fontName, !fontName.isEmpty, fontName != "System" else {
            return .system(size: size)
        }
        return .custom(fontName, size: size)
    }

    func baseFontSize(for family: WidgetFamily) -> CGFloat {
        if let fontSize, fontSize.isFinite, fontSize > 0 {
            return CGFloat(fontSize)
        }
        let preferredSize: CGFloat = text.count <= 48 ? 24 : 18
        return family == .systemMedium ? preferredSize + 2 : preferredSize
    }

}

private extension TackColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

import AppKit
import SwiftUI
import TackCore
import TackFormat
import WidgetKit

struct TackPinnedNoteEntry: TimelineEntry {
    let date: Date
    let snapshot: TackWidgetSnapshot?
}

struct TackPinnedNoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> TackPinnedNoteEntry {
        TackPinnedNoteEntry(date: Date(), snapshot: TackWidgetSnapshot(
            boardID: UUID(),
            boardTitle: "Tack",
            noteID: UUID(),
            text: "Pin a note from Tack",
            color: .yellow
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (TackPinnedNoteEntry) -> Void) {
        completion(TackPinnedNoteEntry(date: Date(), snapshot: try? TackWidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TackPinnedNoteEntry>) -> Void) {
        let entry = TackPinnedNoteEntry(date: Date(), snapshot: try? TackWidgetStore.load())
        let refresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
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
                    Text("Pin a note from Tack")
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
        StaticConfiguration(kind: Self.kind, provider: TackPinnedNoteProvider()) { entry in
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

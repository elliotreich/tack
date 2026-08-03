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
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(entry.snapshot?.color.swiftUIColor ?? TackColor.yellow.swiftUIColor)
                .shadow(color: .black.opacity(0.16), radius: 5, y: 3)

            if let imagePath = entry.snapshot?.imagePath,
               let image = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if let snapshot = entry.snapshot {
                Text(snapshot.text.isEmpty ? "New note" : snapshot.text)
                    .font(snapshot.font)
                    .fontWeight(snapshot.isBold == true ? .bold : .medium)
                    .italic(snapshot.isItalic == true)
                    .foregroundStyle(.black.opacity(0.84))
                    .multilineTextAlignment(.leading)
                    .lineLimit(family == .systemSmall ? 9 : 14)
                    .padding(family == .systemSmall ? 14 : 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "pin.slash")
                        .font(.title2)
                    Text("Pin a note from Tack")
                        .font(.headline)
                }
                .foregroundStyle(.black.opacity(0.62))
                .padding()
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
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
    }
}

@main
struct TackWidgets: WidgetBundle {
    var body: some Widget {
        TackPinnedNoteWidget()
    }
}

private extension TackWidgetSnapshot {
    var font: Font {
        let size = CGFloat(fontSize ?? 18)
        guard let fontName, !fontName.isEmpty, fontName != "System" else {
            return .system(size: size, design: .rounded)
        }
        return .custom(fontName, size: size)
    }
}

private extension TackColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

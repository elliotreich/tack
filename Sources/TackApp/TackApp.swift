import SwiftUI

@main
struct TackApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Tack") {
            ContentView(model: model)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Board") { model.newBoard() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("Board") {
                Button("Import Post-it Board…") { model.importLegacy() }
                Button("Capture Notes from Image…") { model.captureImage() }
                Button("Open Tack Board…") { model.openTack() }
                Button("Save") { model.save() }
                    .keyboardShortcut("s", modifiers: [.command])
                Divider()
                Button("New Note") { model.addNote() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("Delete Selected Note") { model.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: [.command])
                Divider()
                Button("Export Markdown…") { model.exportMarkdown() }
                Button("Export CSV…") { model.exportCSV() }
            }
        }
    }
}

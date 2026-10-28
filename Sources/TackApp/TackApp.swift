import SwiftUI

@main
struct TackApp: App {
    @NSApplicationDelegateAdaptor(TackAppDelegate.self) private var appDelegate
    @StateObject private var launchSequence = BoardLaunchSequence()

    var body: some Scene {
        WindowGroup("Tack", id: BoardWindow.sceneID) {
            BoardWindow(initialBoardURL: launchSequence.takeInitialBoardURL())
        }
        .defaultSize(width: 1320, height: 860)
        .commands { TackCommands() }
    }
}

private struct TackCommands: Commands {
    @FocusedValue(\.tackAppModel) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Board") { model?.newBoard() }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(model == nil)
            Button("New Window") { openWindow(id: BoardWindow.sceneID) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("Board") {
            Button("Open Board…") { model?.openTack() }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(model == nil)
            Button("Import Post-it Board…") { model?.importLegacy() }
                .disabled(model == nil)
            Button("Capture Notes from Image…") { model?.captureImage() }
                .disabled(model == nil)
            Button("Save") { model?.save() }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(model == nil)
            Divider()
            Button("New Note") { model?.addNote() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(model == nil)
            Button("Delete Selected Note") { model?.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(model == nil)
            Divider()
            Button("Export Markdown…") { model?.exportMarkdown() }
                .disabled(model == nil)
            Button("Export CSV…") { model?.exportCSV() }
                .disabled(model == nil)
        }
    }
}

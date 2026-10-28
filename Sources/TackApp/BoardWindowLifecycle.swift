import AppKit
import SwiftUI

@MainActor
final class BoardWindowRegistry {
    static let shared = BoardWindowRegistry()

    private final class WeakModel {
        weak var value: AppModel?
        init(_ value: AppModel) { self.value = value }
    }

    private var weakModels: [WeakModel] = []

    private var models: [AppModel] {
        weakModels.removeAll { $0.value == nil }
        return weakModels.compactMap(\.value)
    }

    func register(_ model: AppModel) {
        guard !models.contains(where: { $0 === model }) else { return }
        weakModels.append(WeakModel(model))
    }

    func openModel(for url: URL, excluding model: AppModel) -> AppModel? {
        models.first {
            $0 !== model && $0.packageURL?.standardizedFileURL == url.standardizedFileURL
        }
    }

    func flushAll() throws {
        for model in models { try model.flushPendingChanges() }
    }
}

@MainActor
struct BoardWindow: View {
    static let sceneID = "board-window"

    @StateObject private var model: AppModel

    init(initialBoardURL: URL?) {
        _model = StateObject(wrappedValue: AppModel(initialBoardURL: initialBoardURL))
    }

    var body: some View {
        ContentView(model: model)
            .focusedSceneValue(\.tackAppModel, model)
            .overlay(alignment: .topLeading) {
                WindowCloseGuard(model: model)
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
            .frame(minWidth: 1040, minHeight: 680)
    }
}

@MainActor
struct WindowCloseGuard: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(to: view)
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        weak var model: AppModel?
        weak var window: NSWindow?
        nonisolated(unsafe) weak var previousDelegate: (any NSWindowDelegate)?

        init(model: AppModel) { self.model = model }

        func attach(to view: NSView) {
            guard let window = view.window else {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let view else { return }
                    self?.attach(to: view)
                }
                return
            }
            if self.window === window, window.delegate === self { return }
            self.window = window
            if window.delegate !== self { previousDelegate = window.delegate }
            window.delegate = self
            model?.activeWindow = window
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            do {
                try model?.flushPendingChanges()
                return previousDelegate?.windowShouldClose?(sender) ?? true
            } catch {
                model?.displayError(error)
                return false
            }
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if previousDelegate?.responds(to: selector) == true { return previousDelegate }
            return super.forwardingTarget(for: selector)
        }
    }
}

@MainActor
final class BoardLaunchSequence: ObservableObject {
    private var consumed = false
    private let initialURL = AppModel.lastOpenedBoardURL()

    func takeInitialBoardURL() -> URL? {
        guard !consumed else { return nil }
        consumed = true
        return initialURL
    }
}

@MainActor
final class TackAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do {
            try BoardWindowRegistry.shared.flushAll()
            return .terminateNow
        } catch {
            NSAlert(error: error).runModal()
            return .terminateCancel
        }
    }
}

private struct TackAppModelFocusKey: FocusedValueKey {
    typealias Value = AppModel
}

extension FocusedValues {
    var tackAppModel: AppModel? {
        get { self[TackAppModelFocusKey.self] }
        set { self[TackAppModelFocusKey.self] = newValue }
    }
}

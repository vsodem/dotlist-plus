import SwiftUI

@main
@MainActor
struct DotListApp: App {
    @StateObject private var store = DotListStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Color.accentColor)
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 560)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 740)
        .commands {
            CommandMenu("Dot List") {
                Button("Next review") { store.apply(.beginReview) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!store.ready || store.state.selection.phase != .idle || store.availableCount == 0)
                Button("Yes, dot it") { store.apply(.answer(true)) }
                    .keyboardShortcut("y", modifiers: [.command, .shift])
                    .disabled(!store.ready || store.state.selection.phase != .reviewing)
                Button("No, skip") { store.apply(.answer(false)) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!store.ready || store.state.selection.phase != .reviewing)
                Divider()
                Button("Done") { store.apply(.complete) }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!store.ready || store.state.selection.phase != .executing)
                Button("Worked on it, not finished") { store.apply(.partial) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(!store.ready || store.state.selection.phase != .executing)
            }
        }
        #endif
    }
}

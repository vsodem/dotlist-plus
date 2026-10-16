import SwiftUI

@main
@MainActor
struct DotListApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PushNotifications.self) private var pushNotifications
    #else
    @NSApplicationDelegateAdaptor(PushNotifications.self) private var pushNotifications
    #endif
    @StateObject private var store: DotListStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = DotListStore(storage: JSONLocalStorage(),
                                 remote: CloudKitSync(), syncServiceName: "iCloud")
        _store = StateObject(wrappedValue: store)
        PushNotifications.synchronize = { [weak store] in
            guard let store else { return false }
            let before = store.state
            await store.syncNow()
            return before != store.state
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(store.scope)
                .environmentObject(store)
                .tint(Color.accentColor)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.syncNow() } }
                }
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 560)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 740)
        .commands {
            CommandMenu("Dot List") {
                Button("Next review") { Task { await store.apply(.beginReview) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!store.ready || store.state.selection.phase != .idle || store.availableCount == 0)
                Button("Yes, dot it") { Task { await store.apply(.answer(true)) } }
                    .keyboardShortcut("y", modifiers: [.command, .shift])
                    .disabled(!store.ready || store.state.selection.phase != .reviewing)
                Button("No, skip") { Task { await store.apply(.answer(false)) } }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!store.ready || store.state.selection.phase != .reviewing)
                Divider()
                Button("Done") { Task { await store.apply(.complete) } }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!store.ready || store.state.selection.phase != .executing)
                Button("Worked on it, not finished") { Task { await store.apply(.partial) } }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(!store.ready || store.state.selection.phase != .executing)
            }
        }
        #endif
    }
}

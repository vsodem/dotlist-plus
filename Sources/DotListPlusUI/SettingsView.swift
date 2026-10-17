import DotListPlusCore
import DotListPlusApplication
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var store: DotListPlusStore
    @State private var importing = false
    @State private var exporting = false
    @State private var document = BackupDocument(data: Data())
    @State private var pendingImport: LoadedList?
    @State private var confirmingImport = false
    @State private var confirmingErase = false
    @State private var confirmationState: ListState?
    @State private var confirmationScope: String?
    @State private var choices: [String: MergeChoice] = [:]
    @State private var wholeListChoice: MergeChoice?
    @State private var confirmingWholeList = false

    var body: some View {
        Form {
            Section {
                NavigationLink { RulesView() } label: { Label("How Dot List Plus works", systemImage: theme.icons.help) }
                Text("Projects, outcomes, and prerequisites extend the Final Version method. Your dots always belong to available actions.")
                    .font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
            } header: { Text("Your method") }
            Section("\(store.syncServiceName) sync") {
                Text(store.syncStatus)
                if store.syncing { ProgressView("Syncing…") }
                Button("Sync now") { Task { await store.syncNow() } }
                    .disabled(!store.ready || store.syncing)
                Text("One personal list per \(store.syncServiceName) account. Changes save on this device first. Each account keeps a separate list.")
                    .font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
            }
            if !store.conflicts.isEmpty {
                Section("Resolve sync conflicts") {
                    Text("Both versions are saved until you choose. Choosing a complete list removes changes found only in the other version. A recovery copy stays on this device.")
                    ForEach(store.conflicts) { conflict in
                        VStack(alignment: .leading, spacing: theme.layout.compactGap) {
                            Text(conflict.title).font(theme.typography.headline)
                            Text("This device: " + conflict.localDescription)
                            Text("\(store.syncServiceName): " + conflict.remoteDescription)
                            Picker("Keep", selection: Binding<MergeChoice?>(
                                get: { choices[conflict.id] }, set: { choices[conflict.id] = $0 })) {
                                Text("Choose a version").tag(nil as MergeChoice?)
                                Text("This device").tag(Optional(MergeChoice.local))
                                Text("\(store.syncServiceName)").tag(Optional(MergeChoice.remote))
                            }
                        }
                    }
                    Button("Save conflict choices") { Task { await store.resolve(choices) } }
                        .disabled(store.conflicts.contains { choices[$0.id] == nil } || store.syncing)
                    Button("Use this device's complete list…") {
                        wholeListChoice = .local; confirmingWholeList = true
                    }
                    Button("Use \(store.syncServiceName)'s complete list…") {
                        wholeListChoice = .remote; confirmingWholeList = true
                    }
                }
            }
            Section {
                Button("Export backup", systemImage: theme.icons.export) {
                    do {
                        document = BackupDocument(data: try BackupCodec.encode(store.state))
                        exporting = true
                    } catch { store.error = error.localizedDescription }
                }.disabled(!store.ready)
                Button("Import backup", systemImage: theme.icons.importBackup) { confirmationState = store.state; confirmationScope = store.scope; importing = true }.disabled(!store.ready)
                Text("Lists save on this device before syncing with \(store.syncServiceName). JSON backups remain portable and include work items, projects, order, and review progress. Recovery copies stay on this device.")
                    .font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
                if !store.ready {
                    Button("Retry opening saved list") { Task { await store.reload() } }
                    Text("The saved file is incompatible or unreadable. Keep it intact and restore a valid local-store recovery copy separately.")
                        .font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
                }
            } header: { Text("Data & backups") }
            Section {
                Button("Erase current list", role: .destructive) { confirmationState = store.state; confirmationScope = store.scope; confirmingErase = true }.disabled(!store.ready)
                Text("This clears the active projects, work items, and selections. Local recovery backups are kept. To clear only the dots, use Choose again in Focus.")
                    .font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
            } header: { Text("Start over") }
        }
        .confirmationDialog("Replace the merged list with one complete version?", isPresented: $confirmingWholeList, titleVisibility: .visible) {
            Button("Use complete list", role: .destructive) {
                if let wholeListChoice { Task { await store.resolve(["list.structure": wholeListChoice]) } }
            }
        } message: {
            Text("Changes found only in the other version will be removed from the synced list. A recovery copy stays on this device.")
        }
        .onChange(of: store.conflicts) { _, _ in choices = [:] }
        .formStyle(.grouped)
        .themeScreen()
        .navigationTitle("Settings")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: ProductIdentity.backupFile) { result in
            if case .failure(let error) = result { store.error = "Export failed. \(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                pendingImport = try BackupCodec.decode(Data(contentsOf: url))
                confirmingImport = true
            } catch { store.error = "Import failed. Your current list is unchanged. \(error.localizedDescription)" }
        }
        .confirmationDialog("Replace the synced list?", isPresented: $confirmingImport, titleVisibility: .visible) {
            Button("Replace with imported list", role: .destructive) {
                if let pendingImport, let confirmationState, let confirmationScope { Task { await store.replace(with: pendingImport, expectedState: confirmationState, expectedScope: confirmationScope) } }
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("The import contains \(pendingImport?.state.workItems.count ?? 0) work items and \(pendingImport?.state.projects.count ?? 0) projects. This replaces the list and syncs the change to your other devices using this \(store.syncServiceName) account. Concurrent edits may need conflict choices. A recovery copy stays on this device.")
        }
        .confirmationDialog("Erase the synced Dot List Plus?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase current list", role: .destructive) { Task { if let confirmationState, let confirmationScope { await store.apply(.eraseCurrentList, expectedState: confirmationState, expectedScope: confirmationScope) } } }
        } message: { Text("Export a backup first if you want an easily accessible copy. This clears your active work items, projects, and dots. This erasure syncs to other devices using this \(store.syncServiceName) account. Concurrent edits may need conflict choices. Local recovery backups are kept.") }
    }
}

@MainActor
struct RulesView: View {
    var body: some View {
        List {
            Section("Choose") {
                Text("Start a review to capture the actions available right now. The first action gets a dot.")
                Text("For each later action, ask: Do I want to do this before the last dotted action? Yes adds a dot; No moves on.")
                Text("Projects and outcomes provide context. They never receive dots.")
            }
            Section("Work") {
                Text("Work backward through your dots. Done means finished. Worked on it, not finished keeps the same action and moves it to the bottom.")
                Text("Finishing a prerequisite unlocks dependent actions for the next review. It never adds them to the existing dotted chain.")
            }
            Section("Change course") {
                Text("Make urgent puts an available action next. During review, this ends the review and keeps the dots already chosen.")
                Text("A blocked action cannot be urgent. Choose an available prerequisite yourself.")
                Text("Choose again clears only the selection. Resuming the app restores the selection exactly.")
            }
            Section("Relationships") {
                Text("Every child of an outcome is required. An empty outcome needs breakdown; it is not complete.")
                Text("All prerequisites must be finished. Prerequisites stay in one project and cannot form a circle.")
                Text("Change relationships, delete work, or reopen actions only while idle. Titles and ordinary new actions can change during a cycle.")
            }
            Section("Changing the method") {
                Text("The editable specification is docs/APP_RULES.md in the project. Change the rule and its example there, then ask Codex to update the app and its tests. Editing that document alone does not change the running app.")
                NavigationLink("Read the full specification") { SpecificationView() }
            }
        }
        .themeScreen()
        .navigationTitle("How it works")
    }
}

@MainActor
struct SpecificationView: View {
    @Environment(\.appTheme) private var theme
    private var specification: String {
        guard let url = Bundle.main.url(forResource: "APP_RULES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The full specification is in docs/APP_RULES.md in the project."
        }
        return text
    }
    var body: some View {
        ScrollView {
            Text(specification).textSelection(.enabled)
                .frame(maxWidth: theme.layout.readingWidth, alignment: .leading).padding(theme.layout.pageInset).frame(maxWidth: .infinity)
        }
        .themeScreen()
        .navigationTitle("App specification")
    }
}

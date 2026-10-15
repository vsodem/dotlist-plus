import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var store: DotListStore
    @State private var importing = false
    @State private var exporting = false
    @State private var document = BackupDocument(data: Data())
    @State private var pendingImport: LoadedList?
    @State private var confirmingImport = false
    @State private var confirmingErase = false

    var body: some View {
        Form {
            Section {
                NavigationLink { RulesView() } label: { Label("How Dot List works", systemImage: "book") }
                Text("Projects, broad tasks, and prerequisites extend the Final Version method. Your dots always belong to available actions.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Your method") }
            Section {
                Button("Export backup", systemImage: "square.and.arrow.up") {
                    do {
                        document = BackupDocument(data: try DotListFile.encode(store.state))
                        exporting = true
                    } catch { store.error = error.localizedDescription }
                }.disabled(!store.ready)
                Button("Import backup or browser list", systemImage: "square.and.arrow.down") { importing = true }
                Text("Lists are saved on this device after every successful change. There are no accounts or automatic sync between iPhone and Mac. Export and import a backup to transfer your list.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("For the browser demo, use Export for native app in its footer. Import that JSON file here. The browser's original data is left untouched.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !store.ready {
                    Button("Retry opening saved list") { store.reload() }
                    Text("You can recover by importing a valid backup. The unreadable saved file will be copied before replacement.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Data & backups") }
            Section {
                Button("Erase all data", role: .destructive) { confirmingErase = true }.disabled(!store.ready)
                Text("This clears the active projects, tasks, and selections. Local recovery backups are kept. To clear only the dots, use Choose again in Focus.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Start over") }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "DotList-backup") { result in
            if case .failure(let error) = result { store.error = "Export failed. \(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                pendingImport = try DotListFile.decode(Data(contentsOf: url))
                confirmingImport = true
            } catch { store.error = "Import failed. Your current list is unchanged. \(error.localizedDescription)" }
        }
        .confirmationDialog("Replace this device's list?", isPresented: $confirmingImport, titleVisibility: .visible) {
            Button("Replace with imported list", role: .destructive) {
                if let pendingImport { store.replace(with: pendingImport) }
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("The import contains \(pendingImport?.state.tasks.count ?? 0) tasks and \(pendingImport?.state.projects.count ?? 0) projects. A copy of the current saved file will be kept on this device.")
        }
        .confirmationDialog("Erase all Dot List data on this device?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase all data", role: .destructive) { store.apply(.eraseAll) }
        } message: { Text("Export a backup first if you want an easily accessible copy. This clears your active tasks, projects, and dots. Local recovery backups are kept; other devices are not affected.") }
    }
}

@MainActor
struct RulesView: View {
    var body: some View {
        List {
            Section("Choose") {
                Text("Start a review to capture the actions available right now. The first action gets a dot.")
                Text("For each later action, ask: Do I want to do this before the last dotted action? Yes adds a dot; No moves on.")
                Text("Projects and broad tasks provide context. They never receive dots.")
            }
            Section("Work") {
                Text("Work backward through your dots. Done means finished. Worked on it, not finished keeps the same action and moves it to the bottom.")
                Text("Finishing a prerequisite unlocks dependent actions for the next review. It never adds them to the existing chain.")
            }
            Section("Change course") {
                Text("Make urgent puts an available action next. During review, this ends the review and keeps the dots already chosen.")
                Text("A blocked action cannot be urgent. Choose an available prerequisite yourself.")
                Text("Choose again clears only the selection. Resuming the app restores the selection exactly.")
            }
            Section("Relationships") {
                Text("Every child of a broad task is required. An empty broad task needs breakdown; it is not complete.")
                Text("All prerequisites must be finished. Prerequisites stay in one project and cannot form a circle.")
                Text("Change relationships, delete work, or reopen actions only while idle. Titles and ordinary new actions can change during a cycle.")
            }
            Section("Changing the method") {
                Text("The editable specification is docs/APP_RULES.md in the project. Change the rule and its example there, then ask Codex to update the app and its tests. Editing that document alone does not change the running app.")
                NavigationLink("Read the full specification") { SpecificationView() }
            }
        }
        .navigationTitle("How it works")
    }
}

@MainActor
struct SpecificationView: View {
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
                .frame(maxWidth: 760, alignment: .leading).padding().frame(maxWidth: .infinity)
        }
        .navigationTitle("App specification")
    }
}

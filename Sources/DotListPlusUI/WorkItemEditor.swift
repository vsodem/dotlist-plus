import DotListPlusCore
import DotListPlusApplication
import SwiftUI

@MainActor
struct WorkItemEditor: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var store: DotListPlusStore
    @Environment(\.dismiss) private var dismiss
    let original: WorkItem?
    @State private var title: String
    @State private var kind: WorkItem.Kind
    @State private var projectID: ID?
    @State private var outcomeID: ID?
    @State private var prerequisites: Set<ID>
    @State private var editingState: ListState?
    @State private var deleting = false
    @State private var breakingDown = false
    @State private var addingChild = false
    private var idle: Bool { store.state.selection.phase == .idle }

    init(workItem: WorkItem? = nil, projectID: ID? = nil, outcomeID: ID? = nil) {
        original = workItem
        _title = State(initialValue: workItem?.title ?? "")
        _kind = State(initialValue: workItem?.kind ?? .action)
        _projectID = State(initialValue: workItem?.projectID ?? projectID)
        _outcomeID = State(initialValue: workItem?.outcomeID ?? outcomeID)
        _prerequisites = State(initialValue: Set(workItem?.prerequisiteIDs ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What needs doing?") {
                    TextField("Title", text: $title, axis: .vertical).lineLimit(1...5)
                    if original == nil {
                        Picker("Type", selection: $kind) {
                            Text("Action").tag(WorkItem.Kind.action)
                            Text("Outcome").tag(WorkItem.Kind.outcome)
                        }.disabled(!idle)
                    }
                }
                Section {
                    Picker("Project", selection: $projectID) {
                        Text("No project").tag(nil as ID?)
                        ForEach(store.state.projects) { Text($0.title).tag(Optional($0.id)) }
                    }
                    if kind == .action {
                        Picker("Outcome", selection: $outcomeID) {
                            Text("None").tag(nil as ID?)
                            ForEach(store.state.workItems.filter { $0.kind == .outcome && $0.projectID == projectID }) {
                                Text($0.title).tag(Optional($0.id))
                            }
                        }
                    }
                } header: { Text("Belongs to") }
                footer: { Text("An outcome groups required actions. Their order does not create prerequisites.") }
                .disabled(!idle && original != nil)

                if kind == .action {
                    Section {
                        let choices = store.state.workItems.filter { $0.kind == .action && $0.id != original?.id && $0.projectID == projectID }
                        if choices.isEmpty { Text("No other actions in this project yet.").foregroundStyle(theme.colors.secondaryText) }
                        ForEach(choices) { workItem in
                            Toggle(isOn: Binding(get: { prerequisites.contains(workItem.id) }, set: { selected in
                                if selected { prerequisites.insert(workItem.id) } else { prerequisites.remove(workItem.id) }
                            })) {
                                VStack(alignment: .leading) {
                                    Text(WorkItemRules.label(workItem, in: store.state))
                                    if workItem.completedAt != nil { Text("Complete").font(theme.typography.caption).foregroundStyle(theme.colors.secondaryText) }
                                }
                            }
                        }
                    } header: { Text("Must finish first") }
                    footer: { Text("All selected prerequisites must be finished. Partial work does not unlock this action.") }
                    .disabled(!idle)
                }

                if let original, original.kind == .outcome {
                    Section("Required actions") {
                        ForEach(store.state.workItems.filter { $0.outcomeID == original.id }) { workItem in
                            Label(workItem.title, systemImage: workItem.completedAt == nil ? theme.icons.action : theme.icons.complete)
                        }
                        Button("Add required action", systemImage: theme.icons.add) { addingChild = true }
                        Text("Adding a required action changes outcome progress. It does not add prerequisite links to other actions.")
                            .font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
                    }
                }
                if !idle {
                    Text("Titles and new ordinary actions can be saved during a cycle. Use Choose again in Focus to edit existing relationships.")
                        .font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
                }
                if let error = store.error { Text(error).foregroundStyle(theme.colors.danger) }
                if let original {
                    Section {
                        if original.kind == .action && original.completedAt == nil && original.outcomeID == nil {
                            Button("Convert to outcome", systemImage: theme.icons.convert) { breakingDown = true }.disabled(!idle)
                        }
                        if original.completedAt != nil {
                            Button("Reopen action") { Task { if await store.apply(.reopenAction(original.id), expectedState: editingState) { dismiss() } } }.disabled(!idle)
                        }
                        Button("Delete \(original.kind == .outcome ? "outcome" : "action")", role: .destructive) { deleting = true }.disabled(!idle)
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { if editingState == nil { editingState = store.state } }
            .themeScreen()
            .navigationTitle(original == nil ? "Add work" : "Edit work")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: projectID) { _, newValue in
                if let outcomeID, store.state.workItem(outcomeID)?.projectID != newValue { self.outcomeID = nil }
                prerequisites = Set(prerequisites.filter { store.state.workItem($0)?.projectID == newValue })
            }
            .onChange(of: kind) { _, newValue in
                if newValue == .outcome { outcomeID = nil; prerequisites = [] }
            }
            .confirmationDialog("Delete this work?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { if let original, await store.apply(.deleteWorkItem(original.id), expectedState: editingState) { dismiss() } } }
            } message: { Text("Referenced prerequisites and outcomes with required actions cannot be deleted.") }
            .sheet(isPresented: $breakingDown) {
                if let original { OutcomeConversionView(workItemID: original.id, onComplete: { dismiss() }) }
            }
            .sheet(isPresented: $addingChild) {
                if let original { WorkItemEditor(projectID: original.projectID, outcomeID: original.id) }
            }
        }
        #if os(macOS)
        .frame(minWidth: theme.layout.workEditor.width, minHeight: theme.layout.workEditor.height)
        #endif
    }

    private func save() {
        let orderedPrerequisites = store.state.workItems.map(\.id).filter { prerequisites.contains($0) }
        var changes: [ListChange] = []
        if let original {
            changes.append(.renameWorkItem(original.id, title))
            if original.projectID != projectID || original.outcomeID != outcomeID || Set(original.prerequisiteIDs) != prerequisites {
                changes.append(.updateRelationships(original.id, project: projectID, parent: outcomeID, prerequisites: orderedPrerequisites))
            }
        } else {
            changes.append(.addWorkItem(WorkItem(title: title, kind: kind, projectID: projectID, outcomeID: outcomeID, prerequisiteIDs: orderedPrerequisites)))
        }
        Task { if await store.apply(changes, expectedState: editingState) { dismiss() } }
    }
}

@MainActor
struct OutcomeConversionView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var store: DotListPlusStore
    @Environment(\.dismiss) private var dismiss
    let workItemID: ID
    let onComplete: () -> Void
    @State private var text = ""
    @State private var editingState: ListState?
    @State private var confirming = false
    private var titles: [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("One required action per line, in list order") {
                    TextEditor(text: $text).frame(minHeight: theme.layout.editorTextHeight).accessibilityLabel("Required actions, one per line")
                }
                Section("Review the relationship changes") {
                    if let workItem = store.state.workItem(workItemID) {
                        Text("‘\(workItem.title)’ becomes an outcome. Its ID stays the same. Each required action gets a new ID.")
                        let required = workItem.prerequisiteIDs.compactMap(store.state.workItem)
                        Text(required.isEmpty ? "The required actions will have no prerequisites." : "Every required action will require: " + required.map(\.title).joined(separator: ", "))
                        let dependents = store.state.workItems.filter { $0.prerequisiteIDs.contains(workItemID) }
                        Text(dependents.isEmpty ? "No other actions currently depend on this action." : "These actions will require every new required action: " + dependents.map(\.title).joined(separator: ", "))
                        Text("The required actions replace the action in list order. They will not require one another unless you add those links separately.")
                    }
                }
                if let error = store.error { Text(error).foregroundStyle(theme.colors.danger) }
            }
            .onAppear { if editingState == nil { editingState = store.state } }
            .themeScreen()
            .navigationTitle("Convert to outcome")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Convert to outcome") { confirming = true }.disabled(titles.isEmpty) }
            }
            .confirmationDialog("Create \(titles.count) required \(titles.count == 1 ? "action" : "actions") and transfer these relationships?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Convert to outcome") {
                    Task { if await store.apply(.convertActionToOutcome(workItemID, titles: titles), expectedState: editingState) { dismiss(); onComplete() } }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: theme.layout.conversionEditor.width, minHeight: theme.layout.conversionEditor.height)
        #endif
    }
}

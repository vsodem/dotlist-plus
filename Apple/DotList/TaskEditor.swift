import SwiftUI

@MainActor
struct TaskEditor: View {
    @EnvironmentObject private var store: DotListStore
    @Environment(\.dismiss) private var dismiss
    let original: WorkTask?
    @State private var title: String
    @State private var kind: WorkTask.Kind
    @State private var projectId: ID?
    @State private var parentId: ID?
    @State private var prerequisites: Set<ID>
    @State private var editingState: AppState?
    @State private var deleting = false
    @State private var breakingDown = false
    @State private var addingChild = false
    private var idle: Bool { store.state.selection.phase == .idle }

    init(task: WorkTask? = nil, projectID: ID? = nil, parentID: ID? = nil) {
        original = task
        _title = State(initialValue: task?.title ?? "")
        _kind = State(initialValue: task?.kind ?? .action)
        _projectId = State(initialValue: task?.projectId ?? projectID)
        _parentId = State(initialValue: task?.parentId ?? parentID)
        _prerequisites = State(initialValue: Set(task?.prerequisiteIds ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What needs doing?") {
                    TextField("Title", text: $title, axis: .vertical).lineLimit(1...5)
                    if original == nil {
                        Picker("Type", selection: $kind) {
                            Text("Action").tag(WorkTask.Kind.action)
                            Text("Broad task").tag(WorkTask.Kind.group)
                        }.disabled(!idle)
                    }
                }
                Section {
                    Picker("Project", selection: $projectId) {
                        Text("No project").tag(nil as ID?)
                        ForEach(store.state.projects) { Text($0.title).tag(Optional($0.id)) }
                    }
                    if kind == .action {
                        Picker("Broad task", selection: $parentId) {
                            Text("None").tag(nil as ID?)
                            ForEach(store.state.tasks.filter { $0.kind == .group && $0.projectId == projectId }) {
                                Text($0.title).tag(Optional($0.id))
                            }
                        }
                    }
                } header: { Text("Belongs to") }
                footer: { Text("A broad task groups required actions. Their order does not create prerequisites.") }
                .disabled(!idle && original != nil)

                if kind == .action {
                    Section {
                        let choices = store.state.tasks.filter { $0.kind == .action && $0.id != original?.id && $0.projectId == projectId }
                        if choices.isEmpty { Text("No other actions in this project yet.").foregroundStyle(.secondary) }
                        ForEach(choices) { task in
                            Toggle(isOn: Binding(get: { prerequisites.contains(task.id) }, set: { selected in
                                if selected { prerequisites.insert(task.id) } else { prerequisites.remove(task.id) }
                            })) {
                                VStack(alignment: .leading) {
                                    Text(TaskRules.label(task, in: store.state))
                                    if task.completedAt != nil { Text("Complete").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    } header: { Text("Must finish first") }
                    footer: { Text("All selected prerequisites must be finished. Partial work does not unlock this action.") }
                    .disabled(!idle)
                }

                if let original, original.kind == .group {
                    Section("Required child actions") {
                        ForEach(store.state.tasks.filter { $0.parentId == original.id }) { task in
                            Label(task.title, systemImage: task.completedAt == nil ? "circle" : "checkmark.circle")
                        }
                        Button("Add child action", systemImage: "plus") { addingChild = true }
                        Text("Adding a child changes group progress. It does not add prerequisite links to other actions.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !idle {
                    Text("Titles and new ordinary actions can be saved during a cycle. Use Choose again in Focus to edit existing relationships.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
                if let original {
                    Section {
                        if original.kind == .action && original.completedAt == nil && original.parentId == nil {
                            Button("Break into substeps", systemImage: "list.bullet.indent") { breakingDown = true }.disabled(!idle)
                        }
                        if original.completedAt != nil {
                            Button("Reopen action") { Task { if await store.apply(.reopen(original.id), expectedState: editingState) { dismiss() } } }.disabled(!idle)
                        }
                        Button("Delete \(original.kind == .group ? "broad task" : "action")", role: .destructive) { deleting = true }.disabled(!idle)
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { if editingState == nil { editingState = store.state } }
            .navigationTitle(original == nil ? "Add work" : "Edit work")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: projectId) { _, newValue in
                if let parentId, store.state.task(parentId)?.projectId != newValue { self.parentId = nil }
                prerequisites = Set(prerequisites.filter { store.state.task($0)?.projectId == newValue })
            }
            .onChange(of: kind) { _, newValue in
                if newValue == .group { parentId = nil; prerequisites = [] }
            }
            .confirmationDialog("Delete this work?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { if let original, await store.apply(.deleteTask(original.id), expectedState: editingState) { dismiss() } } }
            } message: { Text("Referenced prerequisites and broad tasks with children cannot be deleted.") }
            .sheet(isPresented: $breakingDown) {
                if let original { BreakdownView(taskID: original.id, onComplete: { dismiss() }) }
            }
            .sheet(isPresented: $addingChild) {
                if let original { TaskEditor(projectID: original.projectId, parentID: original.id) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 580)
        #endif
    }

    private func save() {
        let orderedPrerequisites = store.state.tasks.map(\.id).filter { prerequisites.contains($0) }
        var changes: [Change] = []
        if let original {
            changes.append(.renameTask(original.id, title))
            if original.projectId != projectId || original.parentId != parentId || Set(original.prerequisiteIds) != prerequisites {
                changes.append(.relationships(original.id, project: projectId, parent: parentId, prerequisites: orderedPrerequisites))
            }
        } else {
            changes.append(.addTask(WorkTask(title: title, kind: kind, projectId: projectId, parentId: parentId, prerequisiteIds: orderedPrerequisites)))
        }
        Task { if await store.apply(changes, expectedState: editingState) { dismiss() } }
    }
}

@MainActor
struct BreakdownView: View {
    @EnvironmentObject private var store: DotListStore
    @Environment(\.dismiss) private var dismiss
    let taskID: ID
    let onComplete: () -> Void
    @State private var text = ""
    @State private var editingState: AppState?
    @State private var confirming = false
    private var titles: [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("One required substep per line, in list order") {
                    TextEditor(text: $text).frame(minHeight: 140).accessibilityLabel("Substeps, one per line")
                }
                Section("Review the relationship changes") {
                    if let task = store.state.task(taskID) {
                        Text("‘\(task.title)’ becomes a broad task. Its ID stays the same. Each substep gets a new ID.")
                        let required = task.prerequisiteIds.compactMap(store.state.task)
                        Text(required.isEmpty ? "The substeps will have no prerequisites." : "Every substep will require: " + required.map(\.title).joined(separator: ", "))
                        let dependents = store.state.tasks.filter { $0.prerequisiteIds.contains(taskID) }
                        Text(dependents.isEmpty ? "No other actions currently depend on this action." : "These actions will require every new substep: " + dependents.map(\.title).joined(separator: ", "))
                        Text("The substeps replace the action in list order. They will not require one another unless you add those links separately.")
                    }
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }
            .onAppear { if editingState == nil { editingState = store.state } }
            .navigationTitle("Break into substeps")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply breakdown") { confirming = true }.disabled(titles.isEmpty) }
            }
            .confirmationDialog("Create \(titles.count) required substeps and transfer these relationships?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Apply breakdown") {
                    Task { if await store.apply(.breakDown(taskID, titles: titles), expectedState: editingState) { dismiss(); onComplete() } }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 520)
        #endif
    }
}

import SwiftUI

@MainActor
struct WorkView: View {
    @EnvironmentObject private var store: DotListStore
    @State private var projectId: ID?
    @State private var showCompleted = false
    @State private var adding = false
    @State private var editing: WorkTask?
    @State private var blockedUrgent: WorkTask?
    @State private var managingProjects = false
    private var state: AppState { store.state }
    private var actions: [WorkTask] {
        let ordered = state.actionOrder.compactMap(state.task)
        let completed = showCompleted ? state.tasks.filter { $0.kind == .action && $0.completedAt != nil } : []
        return (ordered + completed).filter { projectId == nil || $0.projectId == projectId }
    }
    private var groups: [WorkTask] {
        state.tasks.filter { $0.kind == .group && (projectId == nil || $0.projectId == projectId) }
    }

    var body: some View {
        List {
            Section {
                Picker("Project", selection: $projectId) {
                    Text("All projects & ungrouped").tag(nil as ID?)
                    ForEach(state.projects) { Text($0.title).tag(Optional($0.id)) }
                }
                if let id = projectId {
                    Text(progressText(TaskRules.projectProgress(id, in: state))).foregroundStyle(.secondary)
                }
                Toggle("Show completed actions", isOn: $showCompleted)
            }
            if state.selection.phase != .idle {
                Section {
                    Text("Titles and new actions can be edited now. Use Choose again in Focus before changing relationships or deleting work.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !groups.isEmpty {
                Section("Broad tasks") {
                    ForEach(groups) { group in
                        Button { editing = group } label: {
                            HStack(alignment: .top) {
                                Image(systemName: "square.stack").foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(TaskRules.label(group, in: state)).foregroundStyle(.primary)
                                    Text(progressText(TaskRules.groupProgress(group.id, in: state))).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Section("Actions · list order") {
                if actions.isEmpty {
                    ContentUnavailableView("No actions here", systemImage: "list.bullet", description: Text("Add an action, or show completed work."))
                }
                ForEach(actions) { task in
                    HStack(alignment: .top, spacing: 12) {
                        Button { editing = task } label: { taskLabel(task) }
                            .buttonStyle(.plain)
                        if task.completedAt == nil {
                            Menu {
                                Button("Edit action", systemImage: "pencil") { editing = task }
                                if TaskRules.available(task, in: state) {
                                    Button("Make urgent", systemImage: "bolt") { Task { await store.apply(.urgent(task.id)) } }
                                } else {
                                    Button("Find prerequisite to make urgent", systemImage: "bolt") { blockedUrgent = task }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Options for \(task.title)")
                        }
                    }.padding(.vertical, 3)
                }
            }
        }
        .navigationTitle("All work")
        .toolbar {
            ToolbarItemGroup {
                Button { managingProjects = true } label: { Label("Projects", systemImage: "folder") }
                Button { adding = true } label: { Label("Add action", systemImage: "plus") }
            }
        }
        .disabled(!store.ready || store.saving || !store.conflicts.isEmpty)
        .sheet(isPresented: $adding) { TaskEditor(projectID: projectId) }
        .sheet(item: $editing) { TaskEditor(task: $0) }
        .sheet(item: $blockedUrgent) { UrgentPrerequisiteView(taskID: $0.id) }
        .sheet(isPresented: $managingProjects) { ProjectsView() }
        .onChange(of: state.projects) { _, projects in
            if let projectId, !projects.contains(where: { $0.id == projectId }) { self.projectId = nil }
        }
    }

    private func taskLabel(_ task: WorkTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.completedAt != nil ? "checkmark.circle" : state.selection.chain.contains(task.id) ? "circle.fill" : "circle")
                .foregroundStyle(state.selection.chain.contains(task.id) ? Color.accentColor : Color.secondary)
                .frame(width: 20).padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(TaskRules.label(task, in: state))
                    .strikethrough(task.completedAt != nil)
                    .foregroundStyle(task.completedAt == nil ? .primary : .secondary)
                if task.completedAt != nil {
                    Text("Complete").font(.caption).foregroundStyle(.secondary)
                } else if !TaskRules.available(task, in: state) {
                    Label("Requires: " + TaskRules.blockers(task, in: state).map(\.title).joined(separator: ", "), systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(state.selection.chain.contains(task.id) ? "Dotted" : "Available for review")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct UrgentPrerequisiteView: View {
    @EnvironmentObject private var store: DotListStore
    @Environment(\.dismiss) private var dismiss
    let taskID: ID
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("‘\(store.state.task(taskID)?.title ?? "This action")’ is blocked. Choose an available prerequisite to make urgent. Nothing is selected automatically.")
                }
                Section("Available prerequisites") {
                    ForEach(TaskRules.availablePrerequisites(of: taskID, in: store.state)) { task in
                        Button {
                            Task { if await store.apply(.urgent(task.id)) { dismiss() } }
                        } label: { Label(TaskRules.label(task, in: store.state), systemImage: "bolt") }
                    }
                }
                Text("Completing a prerequisite unlocks dependent work for a later review. It does not make that work urgent.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Unblock urgent work")
            .toolbar { Button("Close") { dismiss() } }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
        #endif
    }
}

@MainActor
struct ProjectsView: View {
    @EnvironmentObject private var store: DotListStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Project?
    @State private var adding = false
    var body: some View {
        NavigationStack {
            List {
                if store.state.projects.isEmpty { Text("Projects group related work. Add one to get started.").foregroundStyle(.secondary) }
                ForEach(store.state.projects) { project in
                    Button { editing = project } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.title).foregroundStyle(.primary)
                            Text(progressText(TaskRules.projectProgress(project.id, in: store.state))).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if store.state.selection.phase != .idle {
                    Text("Use Choose again before creating or deleting projects.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Label("Add project", systemImage: "plus") }
                        .disabled(store.state.selection.phase != .idle)
                }
            }
            .sheet(isPresented: $adding) { ProjectEditor() }
            .sheet(item: $editing) { ProjectEditor(project: $0) }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }
}

@MainActor
struct ProjectEditor: View {
    @EnvironmentObject private var store: DotListStore
    @Environment(\.dismiss) private var dismiss
    let project: Project?
    @State private var editingState: AppState?
    @State private var title: String
    @State private var deleting = false
    init(project: Project? = nil) {
        self.project = project
        _title = State(initialValue: project?.title ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $title)
                if let error = store.error { Text(error).foregroundStyle(.red) }
                if let project {
                    Button("Delete project", role: .destructive) { deleting = true }
                        .disabled(store.state.selection.phase != .idle || store.state.tasks.contains { $0.projectId == project.id })
                    Text("A project can be deleted once all its work has been moved or removed.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .onAppear { if editingState == nil { editingState = store.state } }
            .navigationTitle(project == nil ? "New project" : "Edit project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let change: Change = project.map { .renameProject($0.id, title) } ?? .addProject(Project(title: title))
                        Task { if await store.apply(change, expectedState: editingState) { dismiss() } }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this project?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete project", role: .destructive) { Task { if let project, await store.apply(.deleteProject(project.id), expectedState: editingState) { dismiss() } } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #endif
    }
}

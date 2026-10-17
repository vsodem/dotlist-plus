import DotListPlusCore
import DotListPlusApplication
import SwiftUI

@MainActor
struct AllWorkView: View {
    @EnvironmentObject private var store: DotListPlusStore
    @State private var projectID: ID?
    @State private var showCompleted = false
    @State private var adding = false
    @State private var editing: WorkItem?
    @State private var blockedUrgent: WorkItem?
    @State private var managingProjects = false
    private var state: ListState { store.state }
    private var actions: [WorkItem] {
        let ordered = state.actionOrder.compactMap(state.workItem)
        let completed = showCompleted ? state.workItems.filter { $0.kind == .action && $0.completedAt != nil } : []
        return (ordered + completed).filter { projectID == nil || $0.projectID == projectID }
    }
    private var outcomes: [WorkItem] {
        state.workItems.filter { $0.kind == .outcome && (projectID == nil || $0.projectID == projectID) }
    }

    var body: some View {
        List {
            Section {
                Picker("Project", selection: $projectID) {
                    Text("All projects & ungrouped").tag(nil as ID?)
                    ForEach(state.projects) { Text($0.title).tag(Optional($0.id)) }
                }
                if let id = projectID {
                    Text(progressText(WorkItemRules.projectProgress(id, in: state))).foregroundStyle(.secondary)
                }
                Toggle("Show completed actions", isOn: $showCompleted)
            }
            if state.selection.phase != .idle {
                Section {
                    Text("Titles and new actions can be edited now. Use Choose again in Focus before changing relationships or deleting work.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !outcomes.isEmpty {
                Section("Outcomes") {
                    ForEach(outcomes) { outcome in
                        Button { editing = outcome } label: {
                            HStack(alignment: .top) {
                                Image(systemName: "square.stack").foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(WorkItemRules.label(outcome, in: state)).foregroundStyle(.primary)
                                    Text(progressText(WorkItemRules.outcomeProgress(outcome.id, in: state))).font(.caption).foregroundStyle(.secondary)
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
                ForEach(actions) { workItem in
                    HStack(alignment: .top, spacing: 12) {
                        Button { editing = workItem } label: { workItemLabel(workItem) }
                            .buttonStyle(.plain)
                        if workItem.completedAt == nil {
                            Menu {
                                Button("Edit action", systemImage: "pencil") { editing = workItem }
                                if WorkItemRules.available(workItem, in: state) {
                                    Button("Make urgent", systemImage: "bolt") { Task { await store.apply(.makeUrgent(workItem.id)) } }
                                } else {
                                    Button("Find prerequisite to make urgent", systemImage: "bolt") { blockedUrgent = workItem }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Options for \(workItem.title)")
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
        .sheet(isPresented: $adding) { WorkItemEditor(projectID: projectID) }
        .sheet(item: $editing) { WorkItemEditor(workItem: $0) }
        .sheet(item: $blockedUrgent) { UrgentPrerequisiteView(workItemID: $0.id) }
        .sheet(isPresented: $managingProjects) { ProjectsView() }
        .onChange(of: state.projects) { _, projects in
            if let projectID, !projects.contains(where: { $0.id == projectID }) { self.projectID = nil }
        }
    }

    private func workItemLabel(_ workItem: WorkItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: workItem.completedAt != nil ? "checkmark.circle" : state.selection.dottedActionIDs.contains(workItem.id) ? "circle.fill" : "circle")
                .foregroundStyle(state.selection.dottedActionIDs.contains(workItem.id) ? Color.accentColor : Color.secondary)
                .frame(width: 20).padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(WorkItemRules.label(workItem, in: state))
                    .strikethrough(workItem.completedAt != nil)
                    .foregroundStyle(workItem.completedAt == nil ? .primary : .secondary)
                if workItem.completedAt != nil {
                    Text("Complete").font(.caption).foregroundStyle(.secondary)
                } else if !WorkItemRules.available(workItem, in: state) {
                    Label("Requires: " + WorkItemRules.blockers(workItem, in: state).map(\.title).joined(separator: ", "), systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(state.selection.dottedActionIDs.contains(workItem.id) ? "Dotted" : "Available for review")
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
    @EnvironmentObject private var store: DotListPlusStore
    @Environment(\.dismiss) private var dismiss
    let workItemID: ID
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("‘\(store.state.workItem(workItemID)?.title ?? "This action")’ is blocked. Choose an available prerequisite to make urgent. Nothing is selected automatically.")
                }
                Section("Available prerequisites") {
                    ForEach(WorkItemRules.availablePrerequisites(of: workItemID, in: store.state)) { workItem in
                        Button {
                            Task { if await store.apply(.makeUrgent(workItem.id)) { dismiss() } }
                        } label: { Label(WorkItemRules.label(workItem, in: store.state), systemImage: "bolt") }
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
    @EnvironmentObject private var store: DotListPlusStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Project?
    @State private var adding = false
    var body: some View {
        NavigationStack {
            List {
                if store.state.projects.isEmpty { Text("Projects collect related work. Add one to get started.").foregroundStyle(.secondary) }
                ForEach(store.state.projects) { project in
                    Button { editing = project } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.title).foregroundStyle(.primary)
                            Text(progressText(WorkItemRules.projectProgress(project.id, in: store.state))).font(.caption).foregroundStyle(.secondary)
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
    @EnvironmentObject private var store: DotListPlusStore
    @Environment(\.dismiss) private var dismiss
    let project: Project?
    @State private var editingState: ListState?
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
                        .disabled(store.state.selection.phase != .idle || store.state.workItems.contains { $0.projectID == project.id })
                    Text("A project can be deleted once all its work has been moved or removed.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .onAppear { if editingState == nil { editingState = store.state } }
            .navigationTitle(project == nil ? "New project" : "Edit project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let change: ListChange = project.map { .renameProject($0.id, title) } ?? .addProject(Project(title: title))
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

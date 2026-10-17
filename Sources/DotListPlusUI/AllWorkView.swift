import DotListPlusCore
import DotListPlusApplication
import SwiftUI

@MainActor
struct AllWorkView: View {
    @Environment(\.appTheme) private var theme
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
                    Text(progressText(WorkItemRules.projectProgress(id, in: state))).foregroundStyle(theme.colors.secondaryText)
                }
                Toggle("Show completed actions", isOn: $showCompleted)
            }
            if state.selection.phase != .idle {
                Section {
                    Text("Titles and new actions can be edited now. Use Choose again in Focus before changing relationships or deleting work.")
                        .font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
                }
            }
            if !outcomes.isEmpty {
                Section("Outcomes") {
                    ForEach(outcomes) { outcome in
                        Button { editing = outcome } label: {
                            HStack(alignment: .top) {
                                Image(systemName: theme.icons.outcome).foregroundStyle(theme.colors.accent)
                                VStack(alignment: .leading, spacing: theme.layout.labelGap) {
                                    Text(WorkItemRules.label(outcome, in: state)).foregroundStyle(theme.colors.text)
                                    Text(progressText(WorkItemRules.outcomeProgress(outcome.id, in: state))).font(theme.typography.caption).foregroundStyle(theme.colors.secondaryText)
                                }
                                Spacer()
                                Image(systemName: theme.icons.disclosure).font(theme.typography.caption).foregroundStyle(theme.colors.secondaryText)
                            }.padding(.vertical, theme.layout.detailGap)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Section("Actions · list order") {
                if actions.isEmpty {
                    ContentUnavailableView("No actions here", systemImage: theme.icons.work, description: Text("Add an action, or show completed work."))
                }
                ForEach(actions) { workItem in
                    HStack(alignment: .top, spacing: theme.layout.rowGap) {
                        Button { editing = workItem } label: { workItemLabel(workItem) }
                            .buttonStyle(.plain)
                        if workItem.completedAt == nil {
                            Menu {
                                Button("Edit action", systemImage: theme.icons.edit) { editing = workItem }
                                if WorkItemRules.available(workItem, in: state) {
                                    Button("Make urgent", systemImage: theme.icons.urgent) { Task { await store.apply(.makeUrgent(workItem.id)) } }
                                } else {
                                    Button("Find prerequisite to make urgent", systemImage: theme.icons.urgent) { blockedUrgent = workItem }
                                }
                            } label: {
                                Image(systemName: theme.icons.more).frame(width: theme.layout.hitTarget, height: theme.layout.hitTarget)
                            }
                            .accessibilityLabel("Options for \(workItem.title)")
                        }
                    }.padding(.vertical, theme.layout.rowInset)
                }
            }
        }
        .themeScreen()
        .navigationTitle("All work")
        .toolbar {
            ToolbarItemGroup {
                Button { managingProjects = true } label: { Label("Projects", systemImage: theme.icons.project) }
                Button { adding = true } label: { Label("Add action", systemImage: theme.icons.add) }
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
        HStack(alignment: .top, spacing: theme.layout.rowGap) {
            Image(systemName: workItem.completedAt != nil ? theme.icons.complete : state.selection.dottedActionIDs.contains(workItem.id) ? theme.icons.dot : theme.icons.action)
                .foregroundStyle(state.selection.dottedActionIDs.contains(workItem.id) ? theme.colors.accent : theme.colors.secondaryText)
                .themeGlow(active: state.selection.dottedActionIDs.contains(workItem.id))
                .frame(width: theme.layout.iconWidth).padding(.top, theme.layout.labelGap)
            VStack(alignment: .leading, spacing: theme.layout.detailGap) {
                Text(WorkItemRules.label(workItem, in: state))
                    .strikethrough(workItem.completedAt != nil)
                    .foregroundStyle(workItem.completedAt == nil ? theme.colors.text : theme.colors.secondaryText)
                if workItem.completedAt != nil {
                    Text("Complete").font(theme.typography.caption).foregroundStyle(theme.colors.secondaryText)
                } else if !WorkItemRules.available(workItem, in: state) {
                    Label("Requires: " + WorkItemRules.blockers(workItem, in: state).map(\.title).joined(separator: ", "), systemImage: theme.icons.blocked)
                        .font(theme.typography.caption).foregroundStyle(theme.colors.secondaryText)
                } else {
                    Text(state.selection.dottedActionIDs.contains(workItem.id) ? "Dotted" : "Available for review")
                        .font(theme.typography.caption).foregroundStyle(theme.colors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: theme.layout.hitTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct UrgentPrerequisiteView: View {
    @Environment(\.appTheme) private var theme
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
                        } label: { Label(WorkItemRules.label(workItem, in: store.state), systemImage: theme.icons.urgent) }
                    }
                }
                Text("Completing a prerequisite unlocks dependent work for a later review. It does not make that work urgent.")
                    .font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
                if let error = store.error { Text(error).foregroundStyle(theme.colors.danger) }
            }
            .themeScreen()
            .navigationTitle("Unblock urgent work")
            .toolbar { Button("Close") { dismiss() } }
        }
        #if os(macOS)
        .frame(minWidth: theme.layout.urgentEditor.width, minHeight: theme.layout.urgentEditor.height)
        #endif
    }
}

@MainActor
struct ProjectsView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var store: DotListPlusStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Project?
    @State private var adding = false
    var body: some View {
        NavigationStack {
            List {
                if store.state.projects.isEmpty { Text("Projects collect related work. Add one to get started.").foregroundStyle(theme.colors.secondaryText) }
                ForEach(store.state.projects) { project in
                    Button { editing = project } label: {
                        VStack(alignment: .leading, spacing: theme.layout.labelGap) {
                            Text(project.title).foregroundStyle(theme.colors.text)
                            Text(progressText(WorkItemRules.projectProgress(project.id, in: store.state))).font(theme.typography.caption).foregroundStyle(theme.colors.secondaryText)
                        }
                    }
                }
                if store.state.selection.phase != .idle {
                    Text("Use Choose again before creating or deleting projects.").font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
                }
            }
            .themeScreen()
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Label("Add project", systemImage: theme.icons.add) }
                        .disabled(store.state.selection.phase != .idle)
                }
            }
            .sheet(isPresented: $adding) { ProjectEditor() }
            .sheet(item: $editing) { ProjectEditor(project: $0) }
        }
        #if os(macOS)
        .frame(minWidth: theme.layout.projects.width, minHeight: theme.layout.projects.height)
        #endif
    }
}

@MainActor
struct ProjectEditor: View {
    @Environment(\.appTheme) private var theme
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
                if let error = store.error { Text(error).foregroundStyle(theme.colors.danger) }
                if let project {
                    Button("Delete project", role: .destructive) { deleting = true }
                        .disabled(store.state.selection.phase != .idle || store.state.workItems.contains { $0.projectID == project.id })
                    Text("A project can be deleted once all its work has been moved or removed.").font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
                }
            }
            .onAppear { if editingState == nil { editingState = store.state } }
            .themeScreen()
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
        .frame(minWidth: theme.layout.projectEditor.width, minHeight: theme.layout.projectEditor.height)
        #endif
    }
}

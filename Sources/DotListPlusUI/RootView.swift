import DotListPlusCore
import DotListPlusApplication
import SwiftUI

@MainActor
public struct RootView: View {
    public init() {}
    @EnvironmentObject private var store: DotListPlusStore
    @State private var destination: Destination? = .focus
    enum Destination: String, CaseIterable, Identifiable {
        case focus = "Focus", work = "All work", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self { case .focus: return "circle.inset.filled"; case .work: return "list.bullet"; case .settings: return "gearshape" }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let error = store.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error).font(.callout).textSelection(.enabled)
                    Spacer(minLength: 0)
                    if store.ready {
                        Button("Dismiss") { store.error = nil }
                    } else {
                        Button("Retry") { Task { await store.reload() } }
                    }
                }
                .padding().background(.red.opacity(0.12))
                .accessibilityElement(children: .contain)
            }
            if let notice = store.notice {
                HStack(alignment: .top) {
                    Text(notice).font(.callout)
                    Spacer(minLength: 0)
                    Button("Dismiss") { store.notice = nil }
                }.padding().background(.orange.opacity(0.12))
            }
            #if os(macOS)
            NavigationSplitView {
                List(Destination.allCases, selection: $destination) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                }
                .navigationTitle("Dot List Plus")
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            } detail: {
                NavigationStack { screen(destination ?? .focus) }
            }
            #else
            TabView {
                ForEach(Destination.allCases) { item in
                    NavigationStack { screen(item) }
                        .tabItem { Label(item.rawValue, systemImage: item.icon) }
                }
            }
            #endif
        }
    }

    @ViewBuilder private func screen(_ destination: Destination) -> some View {
        switch destination {
        case .focus: FocusView()
        case .work: AllWorkView()
        case .settings: SettingsView()
        }
    }
}

@MainActor
struct FocusView: View {
    @EnvironmentObject private var store: DotListPlusStore
    @State private var adding = false
    @State private var choosingAgain = false
    private var state: ListState { store.state }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("ONE THING AT A TIME", systemImage: "circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(store.unfinishedCount) remaining").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 20) {
                    switch state.selection.phase {
                    case .idle: idlePrompt
                    case .reviewing: reviewPrompt
                    case .executing: executionPrompt
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.quaternary))

                if !state.selection.dottedActionIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(state.selection.phase == .reviewing ? "Selected so far" : "Your dotted chain")
                            .font(.headline)
                        Text("Work from the last dot back to the first.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(Array(state.selection.dottedActionIDs.reversed()), id: \.self) { id in
                            if let workItem = state.workItem(id) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "circle.fill").font(.caption).foregroundStyle(Color.accentColor).padding(.top, 5)
                                    Text(WorkItemRules.label(workItem, in: state)).frame(maxWidth: .infinity, alignment: .leading)
                                    if id == state.selection.dottedActionIDs.last { Text("Next").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }.padding(.horizontal, 8)
                    Button("Choose again", role: .destructive) { choosingAgain = true }
                        .buttonStyle(.bordered).controlSize(.large)
                }
            }
            .frame(maxWidth: 640)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color.accentColor.opacity(0.035))
        .navigationTitle("Focus")
        .toolbar { Button { adding = true } label: { Label("Add action", systemImage: "plus") }.disabled(!store.ready || store.saving || !store.conflicts.isEmpty) }
        .disabled(!store.ready || store.saving || !store.conflicts.isEmpty)
        .sheet(isPresented: $adding) { WorkItemEditor() }
        .confirmationDialog("Choose again?", isPresented: $choosingAgain, titleVisibility: .visible) {
            Button("Clear dots and return to idle", role: .destructive) { Task { await store.apply(.clearSelection) } }
        } message: { Text("Your work items, relationships, completed work, and list order will stay as they are.") }
    }

    @ViewBuilder private var idlePrompt: some View {
        if store.availableCount > 0 {
            Text("Find your next action.").font(.largeTitle.bold())
            Text("\(store.availableCount) available \(store.availableCount == 1 ? "action" : "actions"). Compare them one at a time, then follow your dots.")
                .foregroundStyle(.secondary)
            Button("Start review", systemImage: "arrow.right") { Task { await store.apply(.beginReview) } }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else if store.unfinishedCount > 0 || store.needsBreakdown {
            Text("Make the next step clear.").font(.title.bold())
            Text("Check blocked actions and outcomes in All work. An outcome needs at least one action before it can be worked.")
                .foregroundStyle(.secondary)
        } else if state.workItems.isEmpty {
            Text("A little less deciding.").font(.largeTitle.bold())
            Text("Add what’s on your mind. Dot List Plus helps you choose what to do next, one comparison at a time.")
                .foregroundStyle(.secondary)
            Button("Add your first action", systemImage: "plus") { adding = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            Label("No remaining work", systemImage: "checkmark.circle").font(.title.bold())
            Text("Your completed work is kept in All work. Add an action whenever you’re ready.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var reviewPrompt: some View {
        if let candidate = state.candidate, let benchmark = state.reviewBenchmark {
            Text("Comparison \(state.selection.candidateIndex) of \(state.selection.candidateActionIDs.count - 1)")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Text("Do I want to do").font(.title3)
                Text(WorkItemRules.label(candidate, in: state)).font(.title2.bold()).foregroundStyle(Color.accentColor)
                Text("before").font(.title3)
                Text(WorkItemRules.label(benchmark, in: state) + "?").font(.title2.bold())
            }.accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                HStack { yesButton; noButton }
                VStack(alignment: .leading) { yesButton; noButton }
            }
            Text("New actions will wait for the next review.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var yesButton: some View {
        Button("Yes, dot it") { Task { await store.apply(.answerReview(true)) } }.buttonStyle(.borderedProminent).controlSize(.large)
    }
    private var noButton: some View {
        Button("No, skip") { Task { await store.apply(.answerReview(false)) } }.buttonStyle(.bordered).controlSize(.large)
    }

    @ViewBuilder private var executionPrompt: some View {
        if let workItem = state.nextAction {
            Text("NEXT UP").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(WorkItemRules.label(workItem, in: state)).font(.largeTitle.bold())
            Text("Make a start. You don’t have to finish it in one sitting.").foregroundStyle(.secondary)
            Button("Done", systemImage: "checkmark") { Task { await store.apply(.completeNextAction) } }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Worked on it, not finished", systemImage: "arrow.down.to.line") { Task { await store.apply(.recordPartialWork) } }
                .buttonStyle(.bordered).controlSize(.large)
            Text("Unfinished work moves to the bottom. Anything it blocks stays blocked.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

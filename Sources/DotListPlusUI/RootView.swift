import DotListPlusCore
import DotListPlusApplication
import SwiftUI

@MainActor
public struct RootView: View {
    private let theme: AppTheme
    public init(theme: AppTheme = ThemeConfiguration.active) { self.theme = theme }
    @EnvironmentObject private var store: DotListPlusStore
    @State private var destination: Destination? = .focus
    enum Destination: String, CaseIterable, Identifiable {
        case focus = "Focus", work = "All work", settings = "Settings"
        var id: String { rawValue }
        func icon(in theme: AppTheme) -> String {
            switch self { case .focus: return theme.icons.focus; case .work: return theme.icons.work; case .settings: return theme.icons.settings }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let error = store.error {
                HStack(alignment: .top) {
                    Image(systemName: theme.icons.warning)
                    Text(error).font(theme.typography.callout).textSelection(.enabled)
                    Spacer(minLength: 0)
                    if store.ready {
                        Button("Dismiss") { store.error = nil }
                    } else {
                        Button("Retry") { Task { await store.reload() } }
                    }
                }
                .padding(theme.layout.pageInset).background(theme.colors.danger.opacity(theme.colors.bannerOpacity))
                .accessibilityElement(children: .contain)
            }
            if let notice = store.notice {
                HStack(alignment: .top) {
                    Text(notice).font(theme.typography.callout)
                    Spacer(minLength: 0)
                    Button("Dismiss") { store.dismissNotice() }
                        .disabled(store.saving)
                }.padding(theme.layout.pageInset).background(theme.colors.notice.opacity(theme.colors.bannerOpacity))
            }
            #if os(macOS)
            NavigationSplitView {
                List(Destination.allCases, selection: $destination) { item in
                    Label(item.rawValue, systemImage: item.icon(in: theme)).tag(item)
                }
                .themeScreen()
                .navigationTitle("Dot List Plus")
                .navigationSplitViewColumnWidth(min: theme.layout.sidebarMinimum, ideal: theme.layout.sidebarIdeal)
            } detail: {
                NavigationStack { screen(destination ?? .focus) }
            }
            #else
            TabView {
                ForEach(Destination.allCases) { item in
                    NavigationStack { screen(item) }
                        .tabItem { Label(item.rawValue, systemImage: item.icon(in: theme)) }
                }
            }
            #endif
        }
        .appTheme(theme)
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
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var store: DotListPlusStore
    @State private var adding = false
    @State private var choosingAgain = false
    private var state: ListState { store.state }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.layout.sectionGap) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        focusLabel.fixedSize()
                        Spacer()
                        remainingLabel.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: theme.layout.compactGap) {
                        focusLabel
                        remainingLabel
                    }
                }
                VStack(alignment: .leading, spacing: theme.layout.cardGap) {
                    switch state.selection.phase {
                    case .idle: idlePrompt
                    case .reviewing: reviewPrompt
                    case .executing: executionPrompt
                    }
                }
                .themeCard()
                .themeChange(state.selection)

                if !state.selection.dottedActionIDs.isEmpty {
                    VStack(alignment: .leading, spacing: theme.layout.groupGap) {
                        Text(state.selection.phase == .reviewing ? "Selected so far" : "Your dotted chain")
                            .font(theme.typography.headline).foregroundStyle(theme.colors.text)
                        Text("Work from the last dot back to the first.")
                            .font(theme.typography.subheadline).foregroundStyle(theme.colors.secondaryText)
                        ForEach(Array(state.selection.dottedActionIDs.reversed()), id: \.self) { id in
                            if let workItem = state.workItem(id) {
                                HStack(alignment: .top, spacing: theme.layout.rowGap) {
                                    Image(systemName: theme.icons.dot).font(theme.typography.caption).foregroundStyle(theme.colors.accent).themeGlow().padding(.top, theme.layout.iconOffset)
                                    Text(WorkItemRules.label(workItem, in: state)).foregroundStyle(theme.colors.text).frame(maxWidth: .infinity, alignment: .leading)
                                    if id == state.selection.dottedActionIDs.last { Text("Next").font(theme.typography.eyebrow).foregroundStyle(theme.colors.highlight) }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }.padding(.horizontal, theme.layout.compactGap)
                        .themeChange(state.selection.dottedActionIDs)
                    Button("Choose again", role: .destructive) { choosingAgain = true }
                        .themeButton()
                }
            }
            .frame(maxWidth: theme.layout.focusWidth)
            .padding(theme.layout.pageInset)
            .frame(maxWidth: .infinity)
        }
        .themeScreen()
        .navigationTitle("Focus")
        .toolbar { Button { adding = true } label: { Label("Add action", systemImage: theme.icons.add) }.disabled(!store.ready || store.saving || !store.conflicts.isEmpty) }
        .disabled(!store.ready || store.saving || !store.conflicts.isEmpty)
        .sheet(isPresented: $adding) { WorkItemEditor() }
        .confirmationDialog("Choose again?", isPresented: $choosingAgain, titleVisibility: .visible) {
            Button("Clear dots and return to idle", role: .destructive) { Task { await store.apply(.clearSelection) } }
        } message: { Text("Your work items, relationships, completed work, and list order will stay as they are.") }
    }

    private var focusLabel: some View {
        Label("ONE THING AT A TIME", systemImage: theme.icons.dot)
            .font(theme.typography.eyebrow).foregroundStyle(theme.colors.secondaryText)
    }

    private var remainingLabel: some View {
        Text("\(store.unfinishedCount) remaining")
            .font(theme.typography.caption).foregroundStyle(theme.colors.secondaryText)
    }

    @ViewBuilder private var idlePrompt: some View {
        if store.availableCount > 0 {
            Text("Find your next action.").font(theme.typography.hero).foregroundStyle(theme.colors.text)
            Text("\(store.availableCount) available \(store.availableCount == 1 ? "action" : "actions"). Compare them one at a time, then follow your dots.")
                .foregroundStyle(theme.colors.secondaryText)
            Button("Start review", systemImage: theme.icons.forward) { Task { await store.apply(.beginReview) } }
                .themeButton(prominent: true)
        } else if store.unfinishedCount > 0 || store.needsBreakdown {
            Text("Make the next step clear.").font(theme.typography.title).foregroundStyle(theme.colors.text)
            Text("Check blocked actions and outcomes in All work. An outcome needs at least one action before it can be worked.")
                .foregroundStyle(theme.colors.secondaryText)
        } else if state.workItems.isEmpty {
            Text("A little less deciding.").font(theme.typography.hero).foregroundStyle(theme.colors.text)
            Text("Add what’s on your mind. Dot List Plus helps you choose what to do next, one comparison at a time.")
                .foregroundStyle(theme.colors.secondaryText)
            Button("Add your first action", systemImage: theme.icons.add) { adding = true }
                .themeButton(prominent: true)
        } else {
            Label("No remaining work", systemImage: theme.icons.complete).font(theme.typography.title).foregroundStyle(theme.colors.text)
            Text("Your completed work is kept in All work. Add an action whenever you’re ready.").foregroundStyle(theme.colors.secondaryText)
        }
    }

    @ViewBuilder private var reviewPrompt: some View {
        if let candidate = state.candidate, let benchmark = state.reviewBenchmark {
            Text("Comparison \(state.selection.candidateIndex) of \(state.selection.candidateActionIDs.count - 1)")
                .font(theme.typography.subheadline).foregroundStyle(theme.colors.secondaryText)
            VStack(alignment: .leading, spacing: theme.layout.rowGap) {
                Text("Do I want to do").font(theme.typography.title3).foregroundStyle(theme.colors.text)
                Text(WorkItemRules.label(candidate, in: state)).font(theme.typography.title2).foregroundStyle(theme.colors.accent)
                Text("before").font(theme.typography.title3).foregroundStyle(theme.colors.text)
                Text(WorkItemRules.label(benchmark, in: state) + "?").font(theme.typography.title2).foregroundStyle(theme.colors.text)
            }.accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                HStack { yesButton; noButton }
                VStack(alignment: .leading) { yesButton; noButton }
            }
            Text("New actions will wait for the next review.").font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
        }
    }

    private var yesButton: some View {
        Button("Yes, dot it") { Task { await store.apply(.answerReview(true)) } }.themeButton(prominent: true)
    }
    private var noButton: some View {
        Button("No, skip") { Task { await store.apply(.answerReview(false)) } }.themeButton()
    }

    @ViewBuilder private var executionPrompt: some View {
        if let workItem = state.nextAction {
            Text("NEXT UP").font(theme.typography.eyebrow).foregroundStyle(theme.colors.secondaryText)
            Text(WorkItemRules.label(workItem, in: state)).font(theme.typography.hero).foregroundStyle(theme.colors.text)
            Text("Make a start. You don’t have to finish it in one sitting.").foregroundStyle(theme.colors.secondaryText)
            Button("Done", systemImage: theme.icons.done) { Task { await store.apply(.completeNextAction) } }
                .themeButton(prominent: true)
            Button("Worked on it, not finished", systemImage: theme.icons.partial) { Task { await store.apply(.recordPartialWork) } }
                .themeButton()
            Text("Unfinished work moves to the bottom. Anything it blocks stays blocked.")
                .font(theme.typography.footnote).foregroundStyle(theme.colors.secondaryText)
        }
    }
}

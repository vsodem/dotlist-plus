import DotListPlusCore
import DotListPlusApplication
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class DotListPlusStore: ObservableObject {
    @Published public private(set) var state = ListState()
    @Published public private(set) var scope = "local"
    @Published public private(set) var ready = false
    @Published private(set) var saving = false
    @Published private(set) var syncing = false
    @Published private(set) var syncStatus = "Opening saved list…"
    @Published private(set) var conflicts: [MergeConflict] = []
    @Published var error: String?
    @Published var notice: String?
    let syncServiceName: String
    private let coordinator: SyncCoordinator
    private var generation = -1
    private var syncRequested = false
    private var syncWaiters: [CheckedContinuation<Void, Never>] = []
    private var observation: Task<Void, Never>?

    public init(coordinator: SyncCoordinator, syncServiceName: String) {
        self.syncServiceName = syncServiceName
        self.coordinator = coordinator
        observation = Task { [weak self] in
            await self?.reload()
            let requests = await coordinator.requests()
            for await _ in requests {
                guard !Task.isCancelled else { break }
                await self?.syncNow()
            }
        }
    }

    deinit { observation?.cancel() }

    private func receive(_ view: CoordinatorSnapshot) {
        guard view.generation >= generation else { return }
        generation = view.generation
        scope = view.scope
        state = view.state
        syncStatus = view.status
        conflicts = view.conflicts
        notice = view.notice
        ready = true
    }

    func reload() async {
        do {
            receive(try await coordinator.load())
            error = nil
            await syncNow()
        } catch {
            ready = false
            self.error = "Could not open your saved list. The original file has been kept. \(error.localizedDescription)"
        }
    }

    @discardableResult
    public func apply(_ change: ListChange, expectedState: ListState? = nil, expectedScope: String? = nil) async -> Bool { await apply([change], expectedState: expectedState, expectedScope: expectedScope) }

    @discardableResult
    func apply(_ changes: [ListChange], expectedState: ListState? = nil, expectedScope: String? = nil) async -> Bool {
        guard ready, !saving else { return false }
        saving = true
        defer { saving = false }
        do {
            receive(try await coordinator.apply(changes, expectedScope: expectedScope ?? scope, expectedState: expectedState ?? state))
            error = nil
            Task { await syncNow() }
            return true
        } catch {
            self.error = "Change not saved. \(error.localizedDescription)"
            return false
        }
    }

    func replace(with loaded: LoadedList, expectedState: ListState, expectedScope: String) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            receive(try await coordinator.replace(with: loaded.state, notice: loaded.notice, expectedScope: expectedScope, expectedState: expectedState))
            error = nil
            Task { await syncNow() }
        } catch { self.error = "Import not saved. \(error.localizedDescription)" }
    }

    public func syncNow() async {
        guard ready else { return }
        if syncing {
            syncRequested = true
            await withCheckedContinuation { syncWaiters.append($0) }
            return
        }
        syncing = true
        defer {
            syncing = false
            let waiting = syncWaiters
            syncWaiters.removeAll()
            for waiter in waiting { waiter.resume() }
        }
        repeat {
            syncRequested = false
            do { receive(try await coordinator.sync()) }
            catch { self.error = error.localizedDescription }
        } while syncRequested
    }

    func resolve(_ choices: [String: MergeChoice]) async {
        do {
            receive(try await coordinator.resolve(choices, expectedScope: scope))
            error = nil
            await syncNow()
        } catch { self.error = error.localizedDescription }
    }

    public var availableCount: Int { state.workItems.filter { WorkItemRules.available($0, in: state) }.count }
    var unfinishedCount: Int { state.actionOrder.count }
    var needsBreakdown: Bool {
        state.workItems.contains { $0.kind == .outcome && WorkItemRules.outcomeProgress($0.id, in: state) == .needsBreakdown }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw RuleError("The backup could not be read.") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

func progressText(_ progress: WorkProgress) -> String {
    switch progress {
    case .empty: return "No work yet"
    case .needsBreakdown: return "Needs required actions"
    case .complete: return "Complete"
    case .inProgress(let completed, let total): return "\(completed) of \(total) complete"
    }
}

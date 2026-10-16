import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DotListStore: ObservableObject {
    @Published private(set) var state = AppState()
    @Published private(set) var scope = "local"
    @Published private(set) var ready = false
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

    init(storage: any LocalStorage, remote: any RemoteSync, syncServiceName: String) {
        self.syncServiceName = syncServiceName
        coordinator = SyncCoordinator(storage: storage, remote: remote)
        observation = Task { [weak self] in
            await self?.reload()
            let requests = await remote.requests()
            for await _ in requests {
                guard !Task.isCancelled else { break }
                await self?.syncNow()
            }
        }
    }

    deinit { observation?.cancel() }

    private func receive(_ view: SyncView) {
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
    func apply(_ change: Change, expectedState: AppState? = nil) async -> Bool { await apply([change], expectedState: expectedState) }

    @discardableResult
    func apply(_ changes: [Change], expectedState: AppState? = nil) async -> Bool {
        guard ready, !saving else { return false }
        saving = true
        defer { saving = false }
        do {
            receive(try await coordinator.apply(changes, expectedScope: scope, expectedState: expectedState ?? state))
            error = nil
            Task { await syncNow() }
            return true
        } catch {
            self.error = "Change not saved. \(error.localizedDescription)"
            return false
        }
    }

    func replace(with loaded: LoadedList) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            receive(try await coordinator.replace(with: loaded.state, notice: loaded.notice, expectedScope: scope))
            error = nil
            Task { await syncNow() }
        } catch { self.error = "Import not saved. \(error.localizedDescription)" }
    }

    func syncNow() async {
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

    var availableCount: Int { state.tasks.filter { TaskRules.available($0, in: state) }.count }
    var unfinishedCount: Int { state.actionOrder.count }
    var needsBreakdown: Bool {
        state.tasks.contains { $0.kind == .group && TaskRules.groupProgress($0.id, in: state) == .needsBreakdown }
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

func progressText(_ progress: Progress) -> String {
    switch progress {
    case .empty: return "No work yet"
    case .needsBreakdown: return "Needs breakdown"
    case .complete: return "Complete"
    case .inProgress(let completed, let total): return "\(completed) of \(total) complete"
    }
}

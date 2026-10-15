import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DotListStore: ObservableObject {
    @Published private(set) var state = AppState()
    @Published private(set) var ready = false
    @Published var error: String?
    @Published var notice: String?
    private let file: DotListFile

    init(file: DotListFile? = nil) {
        self.file = file ?? DotListFile(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DotList", isDirectory: true).appendingPathComponent("state-v2.json"))
        reload()
    }

    func reload() {
        do {
            let loaded = try file.load()
            state = loaded.state
            notice = loaded.notice
            ready = true
            error = nil
        } catch {
            ready = false
            self.error = "Could not open your saved list. The original file has been kept. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func apply(_ change: Change) -> Bool { apply([change]) }

    /// Save before publishing: a failed write never looks like a successful action.
    @discardableResult
    func apply(_ changes: [Change]) -> Bool {
        guard ready else { return false }
        do {
            var next = state
            for change in changes { next = try SelectionRules.transition(next, change) }
            if changes.contains(where: { if case .eraseAll = $0 { return true }; return false }) {
                try file.backUpExisting()
            }
            try file.save(next)
            state = next
            error = nil
            return true
        } catch {
            self.error = "Change not saved. \(error.localizedDescription)"
            return false
        }
    }

    func replace(with loaded: LoadedList) {
        do {
            try file.backUpExisting()
            try file.save(loaded.state)
            state = loaded.state
            notice = loaded.notice ?? "Imported your list. A copy of the previous saved file was kept on this device."
            ready = true
            error = nil
        } catch {
            self.error = "Import not saved. Your existing data is unchanged. \(error.localizedDescription)"
        }
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

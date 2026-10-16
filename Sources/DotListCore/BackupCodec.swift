import Foundation

public struct LoadedList: Sendable {
    public let state: AppState
    public let notice: String?
}

public enum BackupCodec {
    public static func decode(_ data: Data) throws -> LoadedList {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RuleError("This is not a Dot List file. Your existing data has not been changed.")
        }
        if object["schemaVersion"] == nil { return try migrateLegacy(data) }
        guard (object["schemaVersion"] as? Int) == 2 else { throw RuleError("This file uses an unsupported version of Dot List.") }
        let savedSelection = object["selection"]
        object["selection"] = ["phase": "idle", "chain": [], "candidates": [], "cursor": 0] as [String: Any]
        var state = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: object))
        try TaskRules.validate(state)
        do {
            guard let savedSelection else { throw RuleError("Missing selection.") }
            state.selection = try JSONDecoder().decode(Selection.self, from: JSONSerialization.data(withJSONObject: savedSelection, options: .fragmentsAllowed))
            try SelectionRules.validate(state)
            return LoadedList(state: state, notice: nil)
        } catch {
            state.selection = Selection()
            return LoadedList(state: state, notice: "Your tasks were recovered, but the saved selection was invalid. Please start a new review.")
        }
    }

    private static func migrateLegacy(_ data: Data) throws -> LoadedList {
        struct Legacy: Decodable {
            struct Task: Decodable { let id: String; let text: String; let doneAt: Double? }
            let tasks: [Task]
        }
        let legacy = try JSONDecoder().decode(Legacy.self, from: data)
        var state = AppState()
        state.tasks = legacy.tasks.map { WorkTask(id: $0.id, title: $0.text, completedAt: $0.doneAt) }
        state.actionOrder = state.tasks.filter { $0.completedAt == nil }.map(\.id)
        try TaskRules.validate(state)
        return LoadedList(state: state, notice: "Imported your browser tasks. Start a new review: the old dots were reset once. Your browser data is unchanged.")
    }

    public static func encode(_ state: AppState) throws -> Data {
        try TaskRules.validate(state)
        try SelectionRules.validate(state)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }
}

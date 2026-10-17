import Foundation

/// Compile together with the core sources; no benchmark-only package target is needed.
@main
struct RoutineMerge {
    static func main() throws {
        print("actions,scenario,run1_ms,run2_ms,run3_ms,run4_ms,run5_ms,median_ms")
        for count in [100, 500, 1_000, 2_000] {
            var base = ListState()
            base.workItems = (0..<count).map { WorkItem(id: "action-\($0)", title: "Action \($0)") }
            base.actionOrder = base.workItems.map(\.id)
            for scenario in ["identical", "title-only"] {
                var local = base
                if scenario == "title-only" { local.workItems[count / 2].title = "Edited title" }
                // Warm up outside the timed samples. Consume and check each result.
                let warmed = try merge(base, local)
                precondition(warmed == local)
                var milliseconds: [Double] = []
                for _ in 0..<5 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let result = try merge(base, local)
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start
                    precondition(result == local)
                    milliseconds.append(Double(elapsed) / 1_000_000)
                }
                let values = milliseconds + [milliseconds.sorted()[2]]
                print("\(count),\(scenario)," + values.map { String(format: "%.3f", $0) }.joined(separator: ","))
            }
        }
    }

    private static func merge(_ base: ListState, _ local: ListState) throws -> ListState {
        let result = try ListMerge.merge(base: base, local: local, remote: base)
        precondition(result.conflicts.isEmpty && result.notice == nil)
        return result.state!
    }
}

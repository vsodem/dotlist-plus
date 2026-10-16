import XCTest
@testable import DotListCore

final class MergeTests: XCTestCase {
    private func list(_ ids: [String]) -> AppState {
        var state = AppState()
        state.tasks = ids.map { WorkTask(id: $0, title: $0) }
        state.actionOrder = ids
        return state
    }

    func testIndependentAdditionsAndCompatibleEditsSurvive() throws {
        let base = list(["a"])
        var local = list(["a", "b"])
        local.tasks[0].title = "Renamed"
        var remote = list(["a", "c"])
        remote.tasks[0].completedAt = 100
        remote.actionOrder = ["c"]
        let result = try ListMerge.merge(base: base, local: local, remote: remote)
        let merged = try XCTUnwrap(result.state)
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(merged.task("a")?.title, "Renamed")
        XCTAssertEqual(merged.task("a")?.completedAt, 100)
        XCTAssertEqual(Set(merged.tasks.map(\.id)), ["a", "b", "c"])
        XCTAssertEqual(Set(merged.actionOrder), ["b", "c"])
    }

    func testConflictingTitleRequiresExplicitChoice() throws {
        let base = list(["a"])
        var local = base
        var remote = base
        local.tasks[0].title = "Local title"
        remote.tasks[0].title = "Remote title"
        let pending = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertNil(pending.state)
        let conflict = try XCTUnwrap(pending.conflicts.first)
        let resolved = try ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .remote])
        XCTAssertEqual(resolved.state?.task("a")?.title, "Remote title")
        XCTAssertTrue(resolved.conflicts.isEmpty)
    }

    func testDeletionOfUnchangedTaskAndDeletionAgainstEdit() throws {
        let base = list(["a", "b"])
        let local = list(["b"])
        XCTAssertEqual(try ListMerge.merge(base: base, local: local, remote: base).state?.tasks.map(\.id), ["b"])
        var remote = base
        remote.tasks[0].title = "Edited"
        let pending = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertNil(pending.state)
        let conflict = try XCTUnwrap(pending.conflicts.first)
        XCTAssertEqual(try ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .local]).state?.tasks.map(\.id), ["b"])
        XCTAssertEqual(try ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .remote]).state?.task("a")?.title, "Edited")
    }

    func testFirstSyncUsesIDsAndDoesNotTreatAbsenceAsDeletion() throws {
        let merged = try XCTUnwrap(ListMerge.merge(base: nil, local: list(["a"]), remote: list(["a", "b"])).state)
        XCTAssertEqual(merged.tasks.map(\.id), ["a", "b"])
        var remote = list(["a"])
        remote.tasks[0].title = "Different"
        XCTAssertNil(try ListMerge.merge(base: nil, local: list(["a"]), remote: remote).state)
    }

    func testIndependentAdditionsConvergeWithoutRepeatedUploads() throws {
        var a = list(["a"])
        a.projects = [Project(id: "pa", title: "A")]
        var b = list(["b"])
        b.projects = [Project(id: "pb", title: "B")]
        let shared = try XCTUnwrap(ListMerge.merge(base: AppState(), local: b, remote: a).state)
        let aSynced = try XCTUnwrap(ListMerge.merge(base: a, local: a, remote: shared).state)
        XCTAssertEqual(aSynced, shared, "An unchanged device must adopt the shared snapshot without another upload.")
        let bSynced = try XCTUnwrap(ListMerge.merge(base: shared, local: shared, remote: aSynced).state)
        XCTAssertEqual(bSynced, aSynced)
    }

    func testRelationshipsConflictAsOneUnit() throws {
        var base = list(["a", "b"])
        base.projects = [Project(id: "p", title: "Project")]
        var local = base
        var remote = base
        local.tasks[0].projectId = "p"
        remote.tasks[0].prerequisiteIds = ["b"]
        let pending = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(pending.conflicts.count, 1)
        let conflict = try XCTUnwrap(pending.conflicts.first)
        let merged = try XCTUnwrap(ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .remote]).state)
        XCTAssertNil(merged.task("a")?.projectId)
        XCTAssertEqual(merged.task("a")?.prerequisiteIds, ["b"])
    }

    func testOneSidedReorderPreservesIndependentAddition() throws {
        let base = list(["a", "b", "c"])
        var local = base
        local.actionOrder = ["c", "a", "b"]
        let remote = list(["a", "b", "c", "d"])
        let merged = try XCTUnwrap(ListMerge.merge(base: base, local: local, remote: remote).state)
        XCTAssertEqual(merged.actionOrder, ["c", "a", "b", "d"])
    }

    func testOneSidedReorderWithAdditionInsideOldOrder() throws {
        let base = list(["a", "b", "c"])
        let local = list(["c", "a", "b"])
        let remote = list(["a", "b", "d", "c"])
        let merged = try XCTUnwrap(ListMerge.merge(base: base, local: local, remote: remote).state)
        XCTAssertEqual(merged.actionOrder, ["c", "a", "b", "d"])
    }

    func testIncompatibleOrdersRequireChoiceWithoutDroppingAdditions() throws {
        let base = list(["a", "b", "c"])
        let local = list(["b", "a", "c", "l"])
        let remote = list(["a", "c", "b", "r"])
        let pending = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertNil(pending.state)
        let conflict = try XCTUnwrap(pending.conflicts.first)
        for choice in [MergeChoice.local, .remote] {
            let merged = try XCTUnwrap(ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: choice]).state)
            XCTAssertEqual(Set(merged.actionOrder), ["a", "b", "c", "l", "r"])
            XCTAssertEqual(merged.actionOrder.filter { ["a", "b", "c"].contains($0) }, choice == .local ? ["b", "a", "c"] : ["a", "c", "b"])
        }
    }

    func testInvalidCombinedGraphOffersWholeListChoice() throws {
        let base = list(["a", "b"])
        var local = base
        var remote = base
        local.tasks[0].prerequisiteIds = ["b"]
        remote.tasks[1].prerequisiteIds = ["a"]
        let pending = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertNil(pending.state)
        let conflict = try XCTUnwrap(pending.conflicts.first)
        XCTAssertEqual(try ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .local]).state, local)
        XCTAssertEqual(try ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .remote]).state, remote)
    }

    func testOneSidedSelectionSurvivesAndDivergentSelectionResets() throws {
        let base = list(["a", "b", "c"])
        let local = try SelectionRules.transition(base, .urgent("a"))
        var remote = base
        remote.tasks[1].title = "Renamed"
        let merged = try XCTUnwrap(ListMerge.merge(base: base, local: local, remote: remote).state)
        XCTAssertEqual(merged.selection, local.selection)
        remote = try SelectionRules.transition(base, .urgent("c"))
        let divergent = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(divergent.state?.selection, Selection())
        XCTAssertNotNil(divergent.notice)
    }

    func testSelectionInvalidatedByMergeResetsWithNotice() throws {
        let base = list(["a", "b"])
        let local = try SelectionRules.transition(base, .beginReview)
        let remote = list(["b"])
        let result = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(result.state?.selection, Selection())
        XCTAssertNotNil(result.notice)
    }

    func testInvalidInputsAreRejected() throws {
        var invalid = list(["a"])
        invalid.tasks.append(invalid.tasks[0])
        XCTAssertThrowsError(try ListMerge.merge(base: nil, local: invalid, remote: list([])))
        XCTAssertThrowsError(try ListMerge.merge(base: invalid, local: list([]), remote: list([])))
    }
}

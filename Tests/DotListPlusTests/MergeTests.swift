import XCTest
import DotListPlusCore
import DotListPlusApplication

final class MergeTests: XCTestCase {
    private func list(_ ids: [String]) -> ListState {
        var state = ListState()
        state.workItems = ids.map { WorkItem(id: $0, title: $0) }
        state.actionOrder = ids
        return state
    }

    func testIndependentAdditionsAndCompatibleEditsSurvive() throws {
        let base = list(["a"])
        var local = list(["a", "b"])
        local.workItems[0].title = "Renamed"
        var remote = list(["a", "c"])
        remote.workItems[0].completedAt = 100
        remote.actionOrder = ["c"]
        let result = try ListMerge.merge(base: base, local: local, remote: remote)
        let merged = try XCTUnwrap(result.state)
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(merged.workItem("a")?.title, "Renamed")
        XCTAssertEqual(merged.workItem("a")?.completedAt, 100)
        XCTAssertEqual(Set(merged.workItems.map(\.id)), ["a", "b", "c"])
        XCTAssertEqual(Set(merged.actionOrder), ["b", "c"])
    }

    func testConflictingTitleRequiresExplicitChoice() throws {
        let base = list(["a"])
        var local = base
        var remote = base
        local.workItems[0].title = "Local title"
        remote.workItems[0].title = "Remote title"
        let pending = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertNil(pending.state)
        let conflict = try XCTUnwrap(pending.conflicts.first)
        let resolved = try ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .remote])
        XCTAssertEqual(resolved.state?.workItem("a")?.title, "Remote title")
        XCTAssertTrue(resolved.conflicts.isEmpty)
    }

    func testDeletionOfUnchangedTaskAndDeletionAgainstEdit() throws {
        let base = list(["a", "b"])
        let local = list(["b"])
        XCTAssertEqual(try ListMerge.merge(base: base, local: local, remote: base).state?.workItems.map(\.id), ["b"])
        var remote = base
        remote.workItems[0].title = "Edited"
        let pending = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertNil(pending.state)
        let conflict = try XCTUnwrap(pending.conflicts.first)
        XCTAssertEqual(try ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .local]).state?.workItems.map(\.id), ["b"])
        XCTAssertEqual(try ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .remote]).state?.workItem("a")?.title, "Edited")
    }

    func testFirstSyncUsesIDsAndDoesNotTreatAbsenceAsDeletion() throws {
        let merged = try XCTUnwrap(ListMerge.merge(base: nil, local: list(["a"]), remote: list(["a", "b"])).state)
        XCTAssertEqual(merged.workItems.map(\.id), ["a", "b"])
        var remote = list(["a"])
        remote.workItems[0].title = "Different"
        XCTAssertNil(try ListMerge.merge(base: nil, local: list(["a"]), remote: remote).state)
    }

    func testIndependentAdditionsConvergeWithoutRepeatedUploads() throws {
        var a = list(["a"])
        a.projects = [Project(id: "pa", title: "A")]
        var b = list(["b"])
        b.projects = [Project(id: "pb", title: "B")]
        let shared = try XCTUnwrap(ListMerge.merge(base: ListState(), local: b, remote: a).state)
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
        local.workItems[0].projectID = "p"
        remote.workItems[0].prerequisiteIDs = ["b"]
        let pending = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(pending.conflicts.count, 1)
        let conflict = try XCTUnwrap(pending.conflicts.first)
        let merged = try XCTUnwrap(ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .remote]).state)
        XCTAssertNil(merged.workItem("a")?.projectID)
        XCTAssertEqual(merged.workItem("a")?.prerequisiteIDs, ["b"])
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
        local.workItems[0].prerequisiteIDs = ["b"]
        remote.workItems[1].prerequisiteIDs = ["a"]
        let pending = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertNil(pending.state)
        let conflict = try XCTUnwrap(pending.conflicts.first)
        XCTAssertEqual(try ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .local]).state, local)
        XCTAssertEqual(try ListMerge.merge(base: base, local: local, remote: remote, choices: [conflict.id: .remote]).state, remote)
    }

    func testOneSidedSelectionSurvivesAndDivergentSelectionResets() throws {
        let base = list(["a", "b", "c"])
        let local = try ListRules.transition(base, .makeUrgent("a"))
        var remote = base
        remote.workItems[1].title = "Renamed"
        let merged = try XCTUnwrap(ListMerge.merge(base: base, local: local, remote: remote).state)
        XCTAssertEqual(merged.selection, local.selection)
        remote = try ListRules.transition(base, .makeUrgent("c"))
        let divergent = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(divergent.state?.selection, SelectionState())
        XCTAssertNotNil(divergent.notice)
    }

    func testSelectionInvalidatedByMergeResetsWithNotice() throws {
        let base = list(["a", "b"])
        let local = try ListRules.transition(base, .beginReview)
        let remote = list(["b"])
        let result = try ListMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(result.state?.selection, SelectionState())
        XCTAssertNotNil(result.notice)
    }

    func testInvalidInputsAreRejected() throws {
        var invalid = list(["a"])
        invalid.workItems.append(invalid.workItems[0])
        XCTAssertThrowsError(try ListMerge.merge(base: nil, local: invalid, remote: list([]))) {
            XCTAssertEqual($0 as? RuleError, RuleError("Work item IDs must be unique."))
        }
        XCTAssertThrowsError(try ListMerge.merge(base: invalid, local: list([]), remote: list([]))) {
            XCTAssertEqual($0 as? RuleError, RuleError("Work item IDs must be unique."))
        }
    }
}

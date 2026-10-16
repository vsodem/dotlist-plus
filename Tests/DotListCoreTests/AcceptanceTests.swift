import XCTest
@testable import DotListCore

final class AcceptanceTests: XCTestCase {
    func list(_ tasks: [WorkTask]) -> AppState {
        var state = AppState()
        state.tasks = tasks
        state.actionOrder = tasks.filter { $0.kind == .action && $0.completedAt == nil }.map(\.id)
        return state
    }

    func action(_ id: String, requires: [String] = [], parent: String? = nil) -> WorkTask {
        WorkTask(id: id, title: id, parentId: parent, prerequisiteIds: requires)
    }

    func step(_ state: inout AppState, _ change: Change) throws {
        state = try SelectionRules.transition(state, change, now: 1000)
    }

    func testLunchUnlocksWithoutChangingRemainingChain() throws {
        var state = list([action("Reply"), action("Groceries"), action("Cook", requires: ["Groceries"])])
        XCTAssertFalse(TaskRules.available(state.task("Cook")!, in: state))
        XCTAssertEqual(TaskRules.blockers(state.task("Cook")!, in: state).map(\.id), ["Groceries"])
        try step(&state, .beginReview)
        XCTAssertEqual(state.selection.candidates, ["Reply", "Groceries"])
        try step(&state, .answer(true))
        XCTAssertEqual(state.nextAction?.id, "Groceries")
        try step(&state, .complete)
        XCTAssertTrue(TaskRules.available(state.task("Cook")!, in: state))
        XCTAssertEqual(state.selection.chain, ["Reply"])
        try step(&state, .complete)
        XCTAssertEqual(state.selection.phase, .idle)
        XCTAssertTrue(state.selection.chain.isEmpty)
        try step(&state, .beginReview)
        XCTAssertEqual(state.nextAction?.id, "Cook")
    }

    func testLastPrerequisiteDotReturnsToIdle() throws {
        var state = list([action("Groceries"), action("Cook", requires: ["Groceries"])])
        try step(&state, .beginReview)
        XCTAssertEqual(state.selection.phase, .executing)
        try step(&state, .complete)
        XCTAssertEqual(state.selection, Selection())
        XCTAssertTrue(TaskRules.available(state.task("Cook")!, in: state))
    }

    func testPartialPreservesIdentityAndEveryRelationship() throws {
        var state = list([WorkTask(id: "group", title: "Lunch", kind: .group), action("Buy", parent: "group"), action("Cook", requires: ["Buy"], parent: "group")])
        let original = state.task("Buy")!
        try step(&state, .beginReview)
        try step(&state, .partial)
        XCTAssertEqual(state.task("Buy"), original)
        XCTAssertEqual(state.tasks.count, 3)
        XCTAssertEqual(state.actionOrder, ["Cook", "Buy"])
        XCTAssertFalse(TaskRules.available(state.task("Cook")!, in: state))
        XCTAssertEqual(state.selection, Selection())
    }

    func testYesNoAndReverseExecution() throws {
        var state = list([action("A"), action("B"), action("C"), action("D")])
        try step(&state, .beginReview)
        try step(&state, .answer(false))
        try step(&state, .answer(true))
        try step(&state, .answer(true))
        XCTAssertEqual(state.selection.chain, ["A", "C", "D"])
        for expected in ["D", "C", "A"] {
            XCTAssertEqual(state.nextAction?.id, expected)
            try step(&state, .complete)
        }
        XCTAssertEqual(state.actionOrder, ["B"])
        XCTAssertEqual(state.selection.phase, .idle)
    }

    func testNoAfterYesAdvancesPastCandidate() throws {
        var state = list([action("A"), action("B"), action("C"), action("D")])
        try step(&state, .beginReview)
        try step(&state, .answer(true))
        try step(&state, .answer(false))
        XCTAssertEqual(state.candidate?.id, "D")
        XCTAssertEqual(state.selection.chain, ["A", "B"])
    }

    func testIndependentChildrenAndDerivedProgress() throws {
        var state = list([WorkTask(id: "room", title: "Clean room", kind: .group), action("Organize", parent: "room"), action("Sweep", parent: "room"), action("Mop", requires: ["Sweep"], parent: "room")])
        try step(&state, .beginReview)
        XCTAssertEqual(state.selection.candidates, ["Organize", "Sweep"])
        try step(&state, .answer(true))
        try step(&state, .complete)
        XCTAssertEqual(TaskRules.groupProgress("room", in: state), .inProgress(completed: 1, total: 3))
        XCTAssertEqual(state.nextAction?.id, "Organize")
        XCTAssertEqual(TaskRules.label(state.task("Mop")!, in: state), "Clean room › Mop")
        XCTAssertFalse(state.selection.chain.contains("room"))
        try step(&state, .complete)
        try step(&state, .beginReview)
        try step(&state, .complete)
        XCTAssertEqual(TaskRules.groupProgress("room", in: state), .complete)
    }

    func testEmptyGroupAndEmptyProjectAreNotComplete() throws {
        var state = AppState()
        try step(&state, .addProject(Project(id: "p", title: "Home")))
        XCTAssertEqual(TaskRules.projectProgress("p", in: state), .empty)
        try step(&state, .addTask(WorkTask(id: "g", title: "Room", kind: .group, projectId: "p")))
        XCTAssertEqual(TaskRules.groupProgress("g", in: state), .needsBreakdown)
        XCTAssertEqual(TaskRules.projectProgress("p", in: state), .needsBreakdown)
        try step(&state, .beginReview)
        XCTAssertEqual(state.selection, Selection())
    }

    func testBreakdownTransfersLinksAtomicallyAndPreservesPosition() throws {
        var state = list([action("Before"), action("Broad", requires: ["Before"]), action("After", requires: ["Broad"])])
        try step(&state, .breakDown("Broad", titles: ["First", "Second"]))
        let children = state.tasks.filter { $0.parentId == "Broad" }
        XCTAssertEqual(children.map(\.title), ["First", "Second"])
        XCTAssertTrue(children.allSatisfy { $0.prerequisiteIds == ["Before"] })
        XCTAssertEqual(state.task("After")?.prerequisiteIds, children.map(\.id))
        XCTAssertEqual(state.task("Broad")?.kind, .group)
        XCTAssertEqual(state.task("Broad")?.prerequisiteIds, [])
        XCTAssertEqual(state.actionOrder, ["Before"] + children.map(\.id) + ["After"])
        try step(&state, .addTask(action("Later", parent: "Broad")))
        XCTAssertEqual(state.task("After")?.prerequisiteIds, children.map(\.id))
        XCTAssertThrowsError(try SelectionRules.transition(state, .breakDown(children[0].id, titles: ["Nested"])))
    }

    func testOrdinaryAdditionAndTitleEditPreserveReviewSnapshot() throws {
        var state = list([action("A"), action("B"), action("C")])
        try step(&state, .beginReview)
        let selection = state.selection
        try step(&state, .addTask(action("New")))
        try step(&state, .renameTask("B", "Renamed"))
        XCTAssertEqual(state.selection, selection)
        XCTAssertEqual(state.candidate?.title, "Renamed")
        try step(&state, .answer(true))
        try step(&state, .answer(false))
        XCTAssertFalse(state.selection.chain.contains("New"))
    }

    func testUrgentDuringReviewRetainsDotsAndEndsReview() throws {
        var state = list([action("A"), action("B"), action("C"), action("D")])
        try step(&state, .beginReview)
        try step(&state, .answer(true))
        try step(&state, .urgent("D"))
        XCTAssertEqual(state.selection.phase, .executing)
        XCTAssertEqual(state.selection.chain, ["A", "B", "D"])
        XCTAssertEqual(state.selection.candidates, [])
        XCTAssertEqual(state.selection.cursor, 0)
        try step(&state, .urgent("A"))
        XCTAssertEqual(state.selection.chain, ["B", "D", "A"])
        XCTAssertEqual(state.actionOrder, ["B", "C", "D", "A"])
    }

    func testBlockedUrgencyShowsAvailableAncestorsWithoutChangingState() throws {
        let state = list([action("A"), action("B", requires: ["A"]), action("C"), action("D", requires: ["B", "C"])])
        XCTAssertEqual(TaskRules.availablePrerequisites(of: "D", in: state).map(\.id), ["A", "C"])
        XCTAssertThrowsError(try SelectionRules.transition(state, .urgent("D")))
        XCTAssertTrue(state.selection.chain.isEmpty)
    }

    func testChooseAgainOnlyClearsSelection() throws {
        var state = list([action("A"), action("B")])
        let original = state
        try step(&state, .beginReview)
        try step(&state, .chooseAgain)
        XCTAssertEqual(state, original)
    }

    func testStructuralChangesRequireIdle() throws {
        var state = list([action("A"), action("B"), action("C")])
        try step(&state, .beginReview)
        for change: Change in [.deleteTask("C"), .relationships("C", project: nil, parent: nil, prerequisites: ["A"]), .breakDown("A", titles: ["Child"]), .reopen("A")] {
            XCTAssertThrowsError(try SelectionRules.transition(state, change))
        }
        XCTAssertThrowsError(try SelectionRules.transition(state, .complete))
    }

    func testRejectsCircularMissingDuplicateSelfAndGroupPrerequisites() throws {
        let state = list([action("A"), action("B", requires: ["A"]), WorkTask(id: "G", title: "Group", kind: .group)])
        for prerequisites in [["B"], ["Missing"], ["A"], ["G"], ["B", "B"]] {
            XCTAssertThrowsError(try SelectionRules.transition(state, .relationships("A", project: nil, parent: nil, prerequisites: prerequisites)))
        }
        XCTAssertEqual(state.task("A")?.prerequisiteIds, [])
    }

    func testRejectsCrossProjectLinksAndInvalidParents() throws {
        var state = AppState()
        try step(&state, .addProject(Project(id: "P", title: "P")))
        try step(&state, .addTask(WorkTask(id: "A", title: "A", projectId: "P")))
        try step(&state, .addTask(action("B")))
        XCTAssertThrowsError(try SelectionRules.transition(state, .relationships("B", project: nil, parent: nil, prerequisites: ["A"])))
        XCTAssertThrowsError(try SelectionRules.transition(state, .relationships("B", project: nil, parent: "A", prerequisites: [])))
    }

    func testDeletionAndReopeningProtectReferences() throws {
        var state = list([action("A"), action("B", requires: ["A"])])
        try step(&state, .beginReview)
        try step(&state, .complete)
        XCTAssertNotNil(state.task("A")?.completedAt)
        XCTAssertTrue(TaskRules.available(state.task("B")!, in: state))
        XCTAssertThrowsError(try SelectionRules.transition(state, .deleteTask("A")))
        try step(&state, .beginReview)
        try step(&state, .complete)
        XCTAssertThrowsError(try SelectionRules.transition(state, .reopen("A")))
        try step(&state, .reopen("B"))
        try step(&state, .reopen("A"))
        XCTAssertEqual(state.actionOrder, ["B", "A"])
        XCTAssertFalse(TaskRules.available(state.task("B")!, in: state))
    }

    func testNonemptyGroupCannotBeDeleted() throws {
        let state = list([WorkTask(id: "G", title: "Group", kind: .group), action("A", parent: "G")])
        XCTAssertThrowsError(try SelectionRules.transition(state, .deleteTask("G")))
    }

    func testResumeReviewAndExecutionExactly() throws {
        var state = list([action("A"), action("B"), action("C")])
        try step(&state, .beginReview)
        try step(&state, .answer(true))
        var restored = try BackupCodec.decode(BackupCodec.encode(state))
        XCTAssertEqual(restored.state, state)
        XCTAssertNil(restored.notice)
        try step(&state, .answer(false))
        restored = try BackupCodec.decode(BackupCodec.encode(state))
        XCTAssertEqual(restored.state, state)
        XCTAssertNil(restored.notice)
    }

    func testInvalidSelectionRecoversTasksButInvalidTasksFail() throws {
        let original = list([action("A"), action("B")])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupCodec.encode(original)) as? [String: Any])
        object["selection"] = ["phase": "reviewing", "chain": ["Missing"], "candidates": ["A"], "cursor": 99]
        let recovered = try BackupCodec.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(recovered.state, original)
        XCTAssertNotNil(recovered.notice)
        object["actionOrder"] = ["Missing"]
        XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testMalformedSelectionCanRecover() throws {
        let original = list([action("A")])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupCodec.encode(original)) as? [String: Any])
        object["selection"] = "not a selection"
        let restored = try BackupCodec.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.state, original)
        XCTAssertNotNil(restored.notice)
    }

    func testLegacyImportPreservesIDsDatesAndDoesNotGuessRelationships() throws {
        let data = Data(#"{"tasks":[{"id":"old","text":"Groceries","doneAt":1234},{"id":"new","text":"Groceries","doneAt":null}],"mode":"executing","reviewCursor":null}"#.utf8)
        let imported = try BackupCodec.decode(data)
        XCTAssertEqual(imported.state.tasks.map(\.id), ["old", "new"])
        XCTAssertEqual(imported.state.task("old")?.completedAt, 1234)
        XCTAssertEqual(imported.state.actionOrder, ["new"])
        XCTAssertTrue(imported.state.tasks.allSatisfy { $0.prerequisiteIds.isEmpty })
        XCTAssertEqual(imported.state.selection, Selection())
        XCTAssertNotNil(imported.notice)
    }

}

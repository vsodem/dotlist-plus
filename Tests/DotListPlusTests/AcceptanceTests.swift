import XCTest
import DotListPlusCore
import DotListPlusApplication

final class AcceptanceTests: XCTestCase {
    func list(_ workItems: [WorkItem]) -> ListState {
        var state = ListState()
        state.workItems = workItems
        state.actionOrder = workItems.filter { $0.kind == .action && $0.completedAt == nil }.map(\.id)
        return state
    }

    func action(_ id: String, requires: [String] = [], parent: String? = nil) -> WorkItem {
        WorkItem(id: id, title: id, outcomeID: parent, prerequisiteIDs: requires)
    }

    func step(_ state: inout ListState, _ change: ListChange) throws {
        state = try ListRules.transition(state, change, now: 1000)
    }

    func assertRejected(_ original: ListState, _ change: ListChange, _ message: String,
                        file: StaticString = #filePath, line: UInt = #line) {
        var state = original
        XCTAssertThrowsError(try step(&state, change), file: file, line: line) {
            XCTAssertEqual($0 as? RuleError, RuleError(message), file: file, line: line)
        }
        XCTAssertEqual(state, original, file: file, line: line)
    }

    func testLunchUnlocksWithoutChangingRemainingChain() throws {
        var state = list([action("Reply"), action("Groceries"), action("Cook", requires: ["Groceries"])])
        XCTAssertFalse(WorkItemRules.available(state.workItem("Cook")!, in: state))
        XCTAssertEqual(WorkItemRules.blockers(state.workItem("Cook")!, in: state).map(\.id), ["Groceries"])
        try step(&state, .beginReview)
        XCTAssertEqual(state.selection.candidateActionIDs, ["Reply", "Groceries"])
        try step(&state, .answerReview(true))
        XCTAssertEqual(state.nextAction?.id, "Groceries")
        try step(&state, .completeNextAction)
        XCTAssertTrue(WorkItemRules.available(state.workItem("Cook")!, in: state))
        XCTAssertEqual(state.selection.dottedActionIDs, ["Reply"])
        try step(&state, .completeNextAction)
        XCTAssertEqual(state.selection.phase, .idle)
        XCTAssertTrue(state.selection.dottedActionIDs.isEmpty)
        try step(&state, .beginReview)
        XCTAssertEqual(state.nextAction?.id, "Cook")
    }

    func testLastPrerequisiteDotReturnsToIdle() throws {
        var state = list([action("Groceries"), action("Cook", requires: ["Groceries"])])
        try step(&state, .beginReview)
        XCTAssertEqual(state.selection.phase, .executing)
        try step(&state, .completeNextAction)
        XCTAssertEqual(state.selection, SelectionState())
        XCTAssertTrue(WorkItemRules.available(state.workItem("Cook")!, in: state))
    }

    func testPartialPreservesIdentityAndEveryRelationship() throws {
        var state = list([WorkItem(id: "outcome", title: "Lunch", kind: .outcome), action("Buy", parent: "outcome"), action("Cook", requires: ["Buy"], parent: "outcome")])
        let original = state.workItem("Buy")!
        try step(&state, .beginReview)
        try step(&state, .recordPartialWork)
        XCTAssertEqual(state.workItem("Buy"), original)
        XCTAssertEqual(state.workItems.count, 3)
        XCTAssertEqual(state.actionOrder, ["Cook", "Buy"])
        XCTAssertFalse(WorkItemRules.available(state.workItem("Cook")!, in: state))
        XCTAssertEqual(state.selection, SelectionState())
    }

    func testYesNoAndReverseExecution() throws {
        var state = list([action("A"), action("B"), action("C"), action("D")])
        try step(&state, .beginReview)
        try step(&state, .answerReview(false))
        try step(&state, .answerReview(true))
        try step(&state, .answerReview(true))
        XCTAssertEqual(state.selection.dottedActionIDs, ["A", "C", "D"])
        for expected in ["D", "C", "A"] {
            XCTAssertEqual(state.nextAction?.id, expected)
            try step(&state, .completeNextAction)
        }
        XCTAssertEqual(state.actionOrder, ["B"])
        XCTAssertEqual(state.selection.phase, .idle)
    }

    func testNoAfterYesAdvancesPastCandidate() throws {
        var state = list([action("A"), action("B"), action("C"), action("D")])
        try step(&state, .beginReview)
        try step(&state, .answerReview(true))
        try step(&state, .answerReview(false))
        XCTAssertEqual(state.candidate?.id, "D")
        XCTAssertEqual(state.selection.dottedActionIDs, ["A", "B"])
    }

    func testIndependentChildrenAndDerivedProgress() throws {
        var state = list([WorkItem(id: "room", title: "Clean room", kind: .outcome), action("Organize", parent: "room"), action("Sweep", parent: "room"), action("Mop", requires: ["Sweep"], parent: "room")])
        try step(&state, .beginReview)
        XCTAssertEqual(state.selection.candidateActionIDs, ["Organize", "Sweep"])
        try step(&state, .answerReview(true))
        try step(&state, .completeNextAction)
        XCTAssertEqual(WorkItemRules.outcomeProgress("room", in: state), .inProgress(completed: 1, total: 3))
        XCTAssertEqual(state.nextAction?.id, "Organize")
        XCTAssertEqual(WorkItemRules.label(state.workItem("Mop")!, in: state), "Clean room › Mop")
        XCTAssertFalse(state.selection.dottedActionIDs.contains("room"))
        try step(&state, .completeNextAction)
        try step(&state, .beginReview)
        try step(&state, .completeNextAction)
        XCTAssertEqual(WorkItemRules.outcomeProgress("room", in: state), .complete)
    }

    func testEmptyOutcomeAndEmptyProjectAreNotComplete() throws {
        var state = ListState()
        try step(&state, .addProject(Project(id: "p", title: "Home")))
        XCTAssertEqual(WorkItemRules.projectProgress("p", in: state), .empty)
        try step(&state, .addWorkItem(WorkItem(id: "g", title: "Room", kind: .outcome, projectID: "p")))
        XCTAssertEqual(WorkItemRules.outcomeProgress("g", in: state), .needsBreakdown)
        XCTAssertEqual(WorkItemRules.projectProgress("p", in: state), .needsBreakdown)
        try step(&state, .beginReview)
        XCTAssertEqual(state.selection, SelectionState())
    }

    func testBreakdownTransfersLinksAtomicallyAndPreservesPosition() throws {
        var state = list([action("Before"), action("Broad", requires: ["Before"]), action("After", requires: ["Broad"])])
        try step(&state, .convertActionToOutcome("Broad", titles: ["First", "Second"]))
        let children = state.workItems.filter { $0.outcomeID == "Broad" }
        XCTAssertEqual(children.map(\.title), ["First", "Second"])
        XCTAssertTrue(children.allSatisfy { $0.prerequisiteIDs == ["Before"] })
        XCTAssertEqual(state.workItem("After")?.prerequisiteIDs, children.map(\.id))
        XCTAssertEqual(state.workItem("Broad")?.kind, .outcome)
        XCTAssertEqual(state.workItem("Broad")?.prerequisiteIDs, [])
        XCTAssertEqual(state.actionOrder, ["Before"] + children.map(\.id) + ["After"])
        try step(&state, .addWorkItem(action("Later", parent: "Broad")))
        XCTAssertEqual(state.workItem("After")?.prerequisiteIDs, children.map(\.id))
        assertRejected(state, .convertActionToOutcome(children[0].id, titles: ["Nested"]),
                       "Only an unfinished action without a parent can be broken into required actions.")
    }

    func testOrdinaryAdditionAndTitleEditPreserveReviewSnapshot() throws {
        var state = list([action("A"), action("B"), action("C")])
        try step(&state, .beginReview)
        let selection = state.selection
        try step(&state, .addWorkItem(action("New")))
        try step(&state, .renameWorkItem("B", "Renamed"))
        XCTAssertEqual(state.selection, selection)
        XCTAssertEqual(state.candidate?.title, "Renamed")
        try step(&state, .answerReview(true))
        try step(&state, .answerReview(false))
        XCTAssertFalse(state.selection.dottedActionIDs.contains("New"))
    }

    func testUrgentDuringReviewRetainsDotsAndEndsReview() throws {
        var state = list([action("A"), action("B"), action("C"), action("D")])
        try step(&state, .beginReview)
        try step(&state, .answerReview(true))
        try step(&state, .makeUrgent("D"))
        XCTAssertEqual(state.selection.phase, .executing)
        XCTAssertEqual(state.selection.dottedActionIDs, ["A", "B", "D"])
        XCTAssertEqual(state.selection.candidateActionIDs, [])
        XCTAssertEqual(state.selection.candidateIndex, 0)
        try step(&state, .makeUrgent("A"))
        XCTAssertEqual(state.selection.dottedActionIDs, ["B", "D", "A"])
        XCTAssertEqual(state.actionOrder, ["B", "C", "D", "A"])
    }

    func testBlockedUrgencyShowsAvailableAncestorsWithoutChangingState() throws {
        let state = list([action("A"), action("B", requires: ["A"]), action("C"), action("D", requires: ["B", "C"])])
        XCTAssertEqual(WorkItemRules.availablePrerequisites(of: "D", in: state).map(\.id), ["A", "C"])
        assertRejected(state, .makeUrgent("D"), "This action is blocked. Choose an available prerequisite to make urgent instead.")
        XCTAssertTrue(state.selection.dottedActionIDs.isEmpty)
    }

    func testChooseAgainOnlyClearsSelection() throws {
        var state = list([action("A"), action("B")])
        let original = state
        try step(&state, .beginReview)
        try step(&state, .clearSelection)
        XCTAssertEqual(state, original)
    }

    func testStructuralChangesRequireIdle() throws {
        var state = list([action("A"), action("B"), action("C"),
                          WorkItem(id: "Done", title: "Done", completedAt: 1000)])
        state.projects = [Project(id: "P", title: "P")]
        try step(&state, .beginReview)
        try step(&state, .addWorkItem(action("New")))
        // Every command succeeds after Choose again. None invalidates the fixed candidates.
        let changes: [ListChange] = [
            .deleteWorkItem("New"),
            .updateRelationships("New", project: nil, parent: nil, prerequisites: ["A"]),
            .convertActionToOutcome("New", titles: ["Child"]), .reopenAction("Done"),
            .addProject(Project(id: "Q", title: "Q")), .deleteProject("P"),
            .addWorkItem(WorkItem(id: "G", title: "G", kind: .outcome)),
            .addWorkItem(action("Dependent", requires: ["A"]))
        ]
        let idle = try ListRules.transition(state, .clearSelection)
        for change in changes {
            _ = try ListRules.transition(idle, change)
            assertRejected(state, change, "Use Choose again before changing relationships, deleting work, or reopening an action.")
        }
        assertRejected(state, .completeNextAction, "Only the next dotted action can be worked or completed.")
    }

    func testRejectsCircularMissingDuplicateSelfAndGroupPrerequisites() throws {
        let state = list([action("A"), action("B", requires: ["A"]), action("C"),
                          WorkItem(id: "G", title: "Group", kind: .outcome)])
        let cases: [([String], String)] = [
            (["B"], "These prerequisites would form a circle. No changes were saved."),
            (["Missing"], "‘A’ has a missing prerequisite or a prerequisite that is not an action."),
            (["A"], "An action cannot require itself."),
            (["G"], "‘A’ has a missing prerequisite or a prerequisite that is not an action."),
            (["C", "C"], "A prerequisite cannot be listed twice.")
        ]
        for (prerequisites, message) in cases {
            assertRejected(state, .updateRelationships("A", project: nil, parent: nil, prerequisites: prerequisites), message)
        }
    }

    func testRejectsCrossProjectLinksAndInvalidParents() throws {
        var state = ListState()
        try step(&state, .addProject(Project(id: "P", title: "P")))
        try step(&state, .addWorkItem(WorkItem(id: "A", title: "A", projectID: "P")))
        try step(&state, .addWorkItem(action("B")))
        assertRejected(state, .updateRelationships("B", project: nil, parent: nil, prerequisites: ["A"]), "Prerequisites must belong to the same project.")
        assertRejected(state, .updateRelationships("B", project: nil, parent: "A", prerequisites: []), "‘B’ needs a valid outcome as its parent.")
    }

    func testDeletionAndReopeningProtectReferences() throws {
        var state = list([action("A"), action("B", requires: ["A"])])
        try step(&state, .beginReview)
        try step(&state, .completeNextAction)
        XCTAssertNotNil(state.workItem("A")?.completedAt)
        XCTAssertTrue(WorkItemRules.available(state.workItem("B")!, in: state))
        assertRejected(state, .deleteWorkItem("A"), "Another action requires this one. Remove that prerequisite link before deleting it.")
        try step(&state, .beginReview)
        try step(&state, .completeNextAction)
        assertRejected(state, .reopenAction("A"), "Reopen ‘B’ before reopening its prerequisite ‘A’.")
        try step(&state, .reopenAction("B"))
        try step(&state, .reopenAction("A"))
        XCTAssertEqual(state.actionOrder, ["B", "A"])
        XCTAssertFalse(WorkItemRules.available(state.workItem("B")!, in: state))
    }

    func testNonemptyOutcomeCannotBeDeleted() throws {
        let state = list([WorkItem(id: "G", title: "Group", kind: .outcome), action("A", parent: "G")])
        assertRejected(state, .deleteWorkItem("G"), "Move or remove this outcome's required actions before deleting it.")
    }

    func testResumeReviewAndExecutionExactly() throws {
        var state = list([action("A"), action("B"), action("C")])
        try step(&state, .beginReview)
        try step(&state, .answerReview(true))
        var restored = try BackupCodec.decode(BackupCodec.encode(state))
        XCTAssertEqual(restored.state, state)
        XCTAssertNil(restored.notice)
        try step(&state, .answerReview(false))
        restored = try BackupCodec.decode(BackupCodec.encode(state))
        XCTAssertEqual(restored.state, state)
        XCTAssertNil(restored.notice)
    }

    func testInvalidImportedSelectionAndWorkAreRejected() throws {
        let original = list([action("A"), action("B")])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupCodec.encode(original)) as? [String: Any])
        var payload = try XCTUnwrap(object["payload"] as? [String: Any])
        payload["selection"] = "not a selection"
        object["payload"] = payload
        XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: object))) {
            guard case DecodingError.typeMismatch = $0 else { return XCTFail("Wrong error: \($0)") }
        }
        var invalidSelection = SelectionState()
        invalidSelection.dottedActionIDs = ["A"] // Only idle's empty-chain rule is violated.
        payload["selection"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(invalidSelection))
        object["payload"] = payload
        XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? RuleError, RuleError("The saved selection is invalid. Start a new review; your work items are preserved."))
        }
        payload["selection"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original.selection))
        payload["actionOrder"] = ["Missing"]
        object["payload"] = payload
        XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? RuleError, RuleError("The action order must contain every unfinished action exactly once."))
        }
    }

    func testReviewBenchmarkIsDistinctFromNextAction() throws {
        var state = list([action("A"), action("B")])
        XCTAssertNil(state.reviewBenchmark)
        XCTAssertNil(state.nextAction)
        try step(&state, .beginReview)
        XCTAssertEqual(state.reviewBenchmark?.id, "A")
        XCTAssertNil(state.nextAction)
        try step(&state, .answerReview(true))
        XCTAssertNil(state.reviewBenchmark)
        XCTAssertEqual(state.nextAction?.id, "B")
    }
}

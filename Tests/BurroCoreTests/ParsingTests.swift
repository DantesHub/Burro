// Provider and Git parsing fixtures cover stale events, NUL paths, renames, and nesting.
import XCTest
@testable import BurroCore

final class ParsingTests: XCTestCase {
    func testClaudeUTCStartMatchesRegardlessOfLocalTimeZone() {
        let started = ISO8601DateFormatter().date(from: "2026-09-26T13:25:22Z")!
        XCTAssertTrue(AgentParsing.matchesClaudeStart("Sat Sep 26 13:25:22 2026", started: started))
        XCTAssertFalse(AgentParsing.matchesClaudeStart("Sat Sep 26 13:25:22 2026", started: started.addingTimeInterval(60)))
        XCTAssertFalse(AgentParsing.matchesClaudeStart("invalid", started: started))
    }
    func testNULWorktreePathsLocksAndDetachedHeads() {
        let raw = "worktree /tmp/repo with space\0HEAD abc\0branch refs/heads/main\0\0worktree /tmp/tree\nwith newline\0HEAD def\0detached\0locked maintenance\0prunable missing\0\0"
        let trees = GitParser.worktrees(raw)
        XCTAssertEqual(trees.count, 2)
        XCTAssertTrue(trees[0].path.hasSuffix("repo with space"))
        XCTAssertEqual(trees[0].branch, "main")
        XCTAssertTrue(trees[1].path.contains("\n"))
        XCTAssertEqual(trees[1].branch, "Detached HEAD")
        XCTAssertTrue(trees[1].locked); XCTAssertTrue(trees[1].prunable)
    }
    func testRenameDoesNotCountOriginalNameAsAChange() {
        let changes = GitParser.changes("R  new.txt\0old.txt\0 M changed.txt\0?? folder/\0")
        XCTAssertEqual(changes.tracked, 2); XCTAssertEqual(changes.untracked, 1)
    }
    func testLongestWorktreeRootOwnsNestedAgentAndProcess() {
        let roots = ["/repo", "/repo/.claude/worktrees/feature"]
        XCTAssertEqual(Paths.owner(of: "/repo/.claude/worktrees/feature/src", in: roots), roots[1])
        XCTAssertNil(Paths.owner(of: "/repo-other", in: roots))
        XCTAssertEqual(Paths.owner(of: "/repo", in: roots), roots[0])
    }
    func testDeadClaudePIDIsInactiveEvenIfRecordSaysWorking() {
        XCTAssertEqual(AgentParsing.claudeState("working", live: false), .inactive)
        XCTAssertEqual(AgentParsing.claudeState("idle", live: true), .idle)
        XCTAssertEqual(AgentParsing.claudeState("future-state", live: true), .unknown)
    }
    func testCodexCompletionOverridesStart() {
        let now = Date()
        let tail = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}\n"
        XCTAssertEqual(AgentParsing.codexState(tail: tail, held: 1, modified: now, now: now), .idle)
        XCTAssertEqual(AgentParsing.codexState(tail: tail, held: 0, modified: now, now: now), .inactive)
    }
    func testCodexRecentEventsWithoutLiveLockAreNotProvenWorking() {
        let now = Date(), tail = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n"
        XCTAssertEqual(AgentParsing.codexState(tail: tail, held: 0, modified: now, now: now), .recent)
        XCTAssertEqual(AgentParsing.codexState(tail: tail, held: 0, modified: now.addingTimeInterval(-900), now: now), .inactive)
        XCTAssertEqual(AgentParsing.codexState(tail: "", held: -1, modified: now, now: now), .unknown)
        XCTAssertEqual(AgentParsing.codexState(tail: "", held: 1, modified: now.addingTimeInterval(-900), now: now), .unknown)
    }
}

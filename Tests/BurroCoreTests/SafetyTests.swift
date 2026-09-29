// Regression coverage ensures incomplete or risky evidence never becomes a safe candidate.
import XCTest
@testable import BurroCore

final class SafetyTests: XCTestCase {
    func cleanFacts() -> GitFacts {
        var facts = GitFacts(); facts.merged = true; facts.unpushed = 0; facts.base = "origin/main"; return facts
    }
    func assess(facts: GitFacts? = nil, primary: Bool = false, locked: Bool = false,
                missing: Bool = false, prunable: Bool = false, protected: Bool = false,
                agents: [AgentSession] = [], processes: [LocalProcess] = [], warnings: [String] = []) -> Assessment {
        SafetyPolicy.assess(primary: primary, locked: locked, missing: missing, prunable: prunable, branch: "feature",
            facts: facts ?? cleanFacts(), agents: agents, processes: processes, protected: protected, coverageWarnings: warnings)
    }
    func session(_ state: AgentState, pinned: Bool = false) -> AgentSession {
        AgentSession(id: "test", provider: .codex, title: "Test", cwd: "/tmp/repo", state: state, updatedAt: Date(), pinned: pinned, evidence: "Fixture")
    }
    func testCleanInactiveMergedWorktreeIsOnlyACandidate() {
        XCTAssertEqual(assess().level, .candidate)
        XCTAssertTrue(assess().reasons.contains { $0.contains("local snapshot") })
    }
    func testDirtyAndUntrackedFilesBlockCleanup() {
        var facts = cleanFacts(); facts.changed = 1
        XCTAssertEqual(assess(facts: facts).level, .keep)
        facts.changed = 0; facts.untracked = 1
        XCTAssertEqual(assess(facts: facts).level, .keep)
    }
    func testUnknownAndFailedChecksCannotBeSafe() {
        XCTAssertEqual(assess(facts: GitFacts()).level, .review)
        var facts = cleanFacts(); facts.errors = ["status failed"]
        XCTAssertEqual(assess(facts: facts).level, .review)
        XCTAssertEqual(assess(warnings: ["agent database unreadable"]).level, .review)
        XCTAssertEqual(assess(missing: true).level, .review)
        XCTAssertEqual(assess(prunable: true).level, .review)
    }
    func testIgnoredDataRequiresReview() {
        var facts = cleanFacts(); facts.ignoredCount = 1; facts.ignored = [".env.local"]
        XCTAssertEqual(assess(facts: facts).level, .review)
    }
    func testIdleAndUncertainAgentsProtectWorktree() {
        for state in [AgentState.working, .waiting, .scheduled, .idle, .recent, .unknown] {
            XCTAssertEqual(assess(agents: [session(state)]).level, .keep, state.rawValue)
        }
        XCTAssertEqual(assess(agents: [session(.inactive)]).level, .candidate)
        XCTAssertEqual(assess(agents: [session(.inactive, pinned: true)]).level, .keep)
    }
    func testPrimaryLocksProcessesAndManualProtectionBlockCleanup() {
        XCTAssertEqual(assess(primary: true).level, .keep)
        XCTAssertEqual(assess(locked: true).level, .keep)
        XCTAssertEqual(assess(protected: true).level, .keep)
        XCTAssertEqual(assess(processes: [LocalProcess(pid: 123, name: "node", cwd: "/tmp/repo", started: Date())]).level, .keep)
        var facts = cleanFacts(); facts.operationInProgress = true
        XCTAssertEqual(assess(facts: facts).level, .keep)
    }
    func testUnmergedAndUnpushedCommitsBlockCleanup() {
        var facts = cleanFacts(); facts.merged = false
        XCTAssertEqual(assess(facts: facts).level, .keep)
        facts.merged = true; facts.unpushed = 1
        XCTAssertEqual(assess(facts: facts).level, .keep)
    }
}

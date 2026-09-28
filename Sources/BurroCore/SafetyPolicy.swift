// Cleanup advice is conservative: unknown evidence can never produce a safe candidate.
import Foundation

public enum SafetyPolicy {
    public static func assess(primary: Bool, locked: Bool, missing: Bool, prunable: Bool,
                              branch: String, facts: GitFacts, agents: [AgentSession],
                              processes: [LocalProcess], protected: Bool,
                              coverageWarnings: [String]) -> Assessment {
        var blockers: [String] = []
        if primary { blockers.append("Main checkout of this repository") }
        if protected { blockers.append("Protected by you") }
        if locked { blockers.append("Git has locked this worktree") }
        if ["main", "master", "staging", "develop"].contains(branch) { blockers.append("Protected branch: \(branch)") }
        if agents.contains(where: { $0.pinned }) { blockers.append("A pinned Codex chat is attached") }
        let open = agents.filter { $0.state.keepsWorktree }.count
        if open > 0 { blockers.append("\(open) agent session(s) still open, active, or uncertain") }
        if !processes.isEmpty { blockers.append("\(processes.count) local process(es) using this folder") }
        if facts.changed > 0 { blockers.append("\(facts.changed) tracked file(s) changed") }
        if facts.untracked > 0 { blockers.append("\(facts.untracked) untracked file(s) or folder(s)") }
        if facts.operationInProgress { blockers.append("A Git operation or index lock is present") }
        if facts.merged == false { blockers.append("HEAD is not merged into \(facts.base ?? "the comparison branch")") }
        if let count = facts.unpushed, count > 0 { blockers.append("\(count) commit(s) absent from local remote-tracking refs") }
        var review = facts.errors + coverageWarnings
        if missing { review.append("Worktree folder is missing; inspect its Git registration") }
        if prunable { review.append("Git marks this registration as prunable") }
        if facts.ignoredCount > 0 { review.append("\(facts.ignoredCount) ignored file(s) or folder(s) may contain local data") }
        if facts.merged == nil { review.append("Merge status could not be verified") }
        if facts.unpushed == nil { review.append("Remote commit coverage could not be verified") }
        if !blockers.isEmpty { return Assessment(level: .keep, reasons: blockers + review) }
        if !review.isEmpty { return Assessment(level: .review, reasons: review) }
        return Assessment(level: .candidate, reasons: [
            "No detected agent or process using this worktree",
            "Clean, including untracked and ignored files",
            "HEAD is contained in \(facts.base ?? "the comparison branch")",
            "All commits are covered by local remote-tracking refs",
            "Candidate based on a local snapshot. Recheck before removal; remote refs are not refreshed automatically."
        ])
    }
}

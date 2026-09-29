import Foundation

public enum WorktreeRemoval {
    /// Never force removal or delete the branch. Git performs the final dirty/locked check.
    public static func remove(_ tree: Worktree) -> String? {
        guard !tree.isPrimary, !tree.protectedByUser, tree.assessment.level == .candidate else {
            return "This worktree cannot be removed: " + tree.assessment.reasons.joined(separator: "; ")
        }
        let runner = CommandRunner()
        let listed = runner.git(tree.repositoryPath, ["worktree", "list", "--porcelain", "-z"])
        let records = GitParser.worktrees(listed.output)
        guard listed.succeeded, let record = records.first(where: { $0.path == tree.path }),
              records.first?.path != tree.path, !record.locked, !record.prunable, record.head == tree.head else {
            return "Worktree registration changed. Refresh and review it again."
        }
        let facts = GitReader().facts(record, base: tree.facts.base)
        guard facts.errors.isEmpty, facts.merged == true, facts.unpushed == 0,
              facts.changed == 0, facts.untracked == 0, facts.ignoredCount == 0, !facts.operationInProgress else {
            return "Worktree changed or contains local data. Nothing was deleted; inspect it in Burro."
        }
        let result = runner.git(tree.repositoryPath, ["worktree", "remove", "--", tree.path])
        guard result.succeeded else { return "Git refused removal: " + (result.error.isEmpty ? "Refresh and check the worktree." : result.error) }
        return nil
    }
}

// Discover registered worktrees and collect read-only evidence for cleanup decisions.
import Foundation

public struct WorktreeRecord: Sendable {
    public var path: String
    public var head: String = ""
    public var branch: String = "Detached HEAD"
    public var locked = false
    public var prunable = false
    public var bare = false
}
public enum GitParser {
    public static func worktrees(_ output: String) -> [WorktreeRecord] {
        var records: [WorktreeRecord] = []; var current: WorktreeRecord?
        for field in output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init) {
            if field.hasPrefix("worktree ") {
                if let current { records.append(current) }
                current = WorktreeRecord(path: Paths.canonical(String(field.dropFirst(9))))
            } else if field.hasPrefix("HEAD ") { current?.head = String(field.dropFirst(5)) }
            else if field.hasPrefix("branch ") { current?.branch = String(field.dropFirst(7)).replacingOccurrences(of: "refs/heads/", with: "") }
            else if field == "locked" || field.hasPrefix("locked ") { current?.locked = true }
            else if field == "prunable" || field.hasPrefix("prunable ") { current?.prunable = true }
            else if field == "bare" { current?.bare = true }
        }
        if let current { records.append(current) }
        return records
    }
    public static func changes(_ output: String) -> (tracked: Int, untracked: Int) {
        let entries = output.split(separator: "\0", omittingEmptySubsequences: true)
        var tracked = 0, untracked = 0, index = 0
        while index < entries.count {
            let code = String(entries[index].prefix(2))
            if code == "??" { untracked += 1 } else { tracked += 1 }
            index += code.contains("R") || code.contains("C") ? 2 : 1
        }
        return (tracked, untracked)
    }
}
public struct GitReader: Sendable {
    let runner = CommandRunner()
    public init() {}
    public func comparisonBase(_ path: String, override: String?) -> String? {
        if let override, !override.isEmpty {
            return runner.git(path, ["rev-parse", "--verify", "--end-of-options", override + "^{commit}"]).succeeded ? override : nil
        }
        let symbolic = runner.git(path, ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"])
        let choices = (symbolic.succeeded ? [symbolic.output.trimmingCharacters(in: .whitespacesAndNewlines)] : []) + ["origin/main", "origin/master", "origin/staging"]
        return choices.first { runner.git(path, ["rev-parse", "--verify", "--end-of-options", $0 + "^{commit}"]).succeeded }
    }
    public func facts(_ record: WorktreeRecord, base: String?) -> GitFacts {
        var facts = GitFacts(); facts.base = base
        guard FileManager.default.fileExists(atPath: record.path) else { facts.errors.append("Folder cannot be inspected"); return facts }
        if FileManager.default.fileExists(atPath: record.path + "/.gitmodules") {
            facts.errors.append("Repository declares submodules; inspect their local data separately")
        }
        let status = runner.git(record.path, ["status", "--porcelain=v1", "-z", "--untracked-files=normal", "--ignore-submodules=none"])
        if status.succeeded {
            let changes = GitParser.changes(status.output); facts.changed = changes.tracked; facts.untracked = changes.untracked
        } else { facts.errors.append(status.timedOut ? "Git status timed out" : "Git status failed") }
        let ignored = runner.git(record.path, ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"])
        if ignored.succeeded {
            let entries = ignored.output.split(separator: "\0").map(String.init)
            facts.ignored = Array(entries.prefix(12)); facts.ignoredCount = entries.count
        } else { facts.errors.append("Ignored files could not be checked") }
        if let base {
            let merged = runner.git(record.path, ["merge-base", "--is-ancestor", "HEAD", base])
            if !merged.timedOut && [0, 1].contains(merged.code) { facts.merged = merged.code == 0 }
        }
        let unpushed = runner.git(record.path, ["rev-list", "--count", "HEAD", "--not", "--remotes"])
        if unpushed.succeeded { facts.unpushed = Int(unpushed.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let timestamp = runner.git(record.path, ["log", "-1", "--format=%ct"])
        if let seconds = Double(timestamp.output.trimmingCharacters(in: .whitespacesAndNewlines)) { facts.lastCommit = Date(timeIntervalSince1970: seconds) }
        let gitDir = runner.git(record.path, ["rev-parse", "--absolute-git-dir"])
        if gitDir.succeeded {
            let path = gitDir.output.trimmingCharacters(in: .whitespacesAndNewlines)
            facts.operationInProgress = ["index.lock", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "BISECT_LOG"].contains {
                FileManager.default.fileExists(atPath: path + "/" + $0)
            }
        } else { facts.errors.append("Git operation state could not be checked") }
        return facts
    }
}

// Group display rows by host and checkout, without changing session ownership or status.
import Foundation

public struct NotchWorkspace: Identifiable, Sendable {
    public var id: String
    public var groups: [NotchGroup]
    public var sessions: [AgentSession] { groups.flatMap(\.members) }
    public var status: WorkspaceStatus {
        let live = groups.flatMap { group in group.members.filter { !group.unavailableIDs.contains($0.id) && $0.remote?.stale != true } }
        guard !live.isEmpty else { return .unavailable }
        if live.contains(where: { $0.state == .waiting }) { return .waiting }
        if live.contains(where: { $0.state == .working }) { return .running }
        if live.contains(where: { $0.state == .scheduled }) { return .scheduled }
        if live.contains(where: { $0.state == .unknown || $0.state == .recent }) { return .unknown }
        let completions = live.filter(\.showsCompletion)
        for delivery in [DeliveryStatus.inProgress, .uncommitted, .needsPush, .behind, .needsMerge, .merged, .synced] {
            if completions.contains(where: { $0.deliveryStatus == delivery }) { return WorkspaceStatus(delivery) }
        }
        return completions.isEmpty ? .idle : .done
    }
    public static func grouped(_ groups: [NotchGroup], path: (AgentSession) -> String) -> [Self] {
        var result: [Self] = []
        var indices: [String: Int] = [:]
        for group in groups {
            guard let session = group.root ?? group.workers.first else { continue }
            let location = path(session)
            let host = session.remote?.hostID.uuidString ?? "local"
            let key = host + ":" + (location.isEmpty ? "session:" + group.id : location)
            if let index = indices[key] { result[index].groups.append(group) }
            else { indices[key] = result.count; result.append(Self(id: key, groups: [group])) }
        }
        return result
    }
}

public enum WorkspaceStatus: String, Sendable, CaseIterable {
    case waiting = "Needs you", running = "Running", scheduled = "Scheduled", unknown = "Unknown"
    case uncommitted = "Uncommitted changes", needsPush = "Needs push", needsMerge = "Needs to merge"
    case behind = "Needs pull", inProgress = "Git operation", merged = "Merged", done = "Done"
    case idle = "Idle", unavailable = "Last seen"
    public init(_ delivery: DeliveryStatus) {
        switch delivery {
        case .uncommitted: self = .uncommitted
        case .needsPush: self = .needsPush
        case .needsMerge: self = .needsMerge
        case .behind: self = .behind
        case .inProgress: self = .inProgress
        case .merged: self = .merged
        case .synced: self = .done
        }
    }
}
public struct WorkspaceSummary: Sendable {
    public let workspaces: [NotchWorkspace]
    public init(_ workspaces: [NotchWorkspace]) { self.workspaces = workspaces }
    public func count(_ status: WorkspaceStatus) -> Int { workspaces.filter { $0.status == status }.count }
    public var workingCount: Int { count(.running) }
    public var waitingCount: Int { count(.waiting) }
    public var scheduledCount: Int { count(.scheduled) }
    public var needsMergeCount: Int { count(.needsMerge) }
    public var mergedCount: Int { count(.merged) }
    public var unknownDeliveryCount: Int { count(.done) }
    public var doneCount: Int { count(.done) + count(.merged) }
    public var pendingCount: Int { count(.uncommitted) + count(.needsPush) + count(.needsMerge) + count(.behind) + count(.inProgress) }
    public var attentionCount: Int { waitingCount + pendingCount + doneCount }
}

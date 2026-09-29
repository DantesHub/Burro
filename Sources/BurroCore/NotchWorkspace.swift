// Group display rows by host and checkout, without changing session ownership or status.
import Foundation

public struct NotchWorkspace: Identifiable, Sendable {
    public var id: String
    public var groups: [NotchGroup]
    public var sessions: [AgentSession] { groups.flatMap(\.members) }
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

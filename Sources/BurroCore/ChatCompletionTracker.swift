import Foundation

/// Only observed activity followed by explicit completion generates an alert.
/// Missing/stale samples are not evidence of completion.
public struct ChatCompletionTracker: Sendable {
    private var active: Set<String> = []
    public init() {}
    public mutating func completions(in sessions: [AgentSession]) -> [AgentSession] {
        var result: [AgentSession] = []
        for session in sessions where session.isSubagent != true && session.remote?.stale != true {
            switch session.state {
            case .working, .waiting, .scheduled:
                active.insert(session.id)
            case .idle, .inactive:
                if session.turnCompleted == true && active.remove(session.id) != nil {
                    result.append(session)
                }
            default: break
            }
        }
        return result
    }
}

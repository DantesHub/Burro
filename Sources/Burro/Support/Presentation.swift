// Shared desktop presentation for consistent filters and semantic statuses.
import SwiftUI
import BurroCore

enum WorktreeFilter: Hashable {
    case all, working, inUse, inactive, candidates, protected, remote, repository(String)
    var title: String {
        switch self {
        case .all: "All worktrees"
        case .working: "Working now"
        case .inUse: "In use"
        case .inactive: "Inactive"
        case .candidates: "Safe candidates"
        case .protected: "Protected"
        case .remote: "Remote sessions"
        case .repository: "Repository"
        }
    }
    var icon: String {
        switch self {
        case .all, .repository: "square.stack.3d.up"
        case .working: "waveform.path"
        case .inUse: "person.2"
        case .inactive: "moon"
        case .candidates: "checkmark.circle"
        case .protected: "lock"
        case .remote: "network"
        }
    }
    func matches(_ tree: Worktree) -> Bool {
        switch self {
        case .all: true
        case .working: tree.isWorking
        case .inUse: tree.isInUse
        case .inactive: !tree.isInUse
        case .candidates: tree.assessment.level == .candidate
        case .protected: tree.protectedByUser || tree.isPrimary || tree.isLocked || tree.agents.contains { $0.pinned }
        case .remote: false
        case .repository(let path): tree.repositoryPath == path
        }
    }
}
extension SafetyLevel {
    var color: Color {
        switch self { case .keep: .secondary; case .review: .orange; case .candidate: .green }
    }
    var icon: String {
        switch self { case .keep: "shield.lefthalf.filled"; case .review: "exclamationmark.circle"; case .candidate: "checkmark.circle" }
    }
}
extension AgentState {
    var color: Color {
        switch self { case .working: .green; case .waiting: .orange; case .recent: .blue; case .unknown: .orange; default: .secondary }
    }
}
enum Layout {
    static let small: CGFloat = 6
    static let gap: CGFloat = 12
    static let inset: CGFloat = 20
    static let sidebar: CGFloat = 210
    static let inspector: CGFloat = 320
}
struct SafetyBadge: View {
    var level: SafetyLevel
    var body: some View {
        Label(level.rawValue, systemImage: level.icon)
            .font(.caption.weight(.medium)).foregroundStyle(level.color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(level.color.opacity(0.08), in: Capsule())
            .accessibilityLabel("Cleanup: \(level.rawValue)")
    }
}

// Stable, fixed-height chat targets retain direct navigation and disclose lost session evidence.
import SwiftUI
import BurroCore

struct NotchAgentRow: View {
    let session: AgentSession
    let workspace: String
    var available: Bool
    var workerState: AgentState? = nil
    var select: () -> Void
    var inspect: () -> Void
    @State private var hovering = false
    private var workerLabel: String? {
        guard available else { return nil }
        if workerState == .waiting { return "Worker needs you" }
        if workerState == .working && !session.isDone && ![AgentState.working, .waiting].contains(session.state) { return "Worker running" }
        return nil
    }
    private var color: Color {
        if workerLabel != nil { return workerState == .waiting ? NotchStyle.attention : AgentState.working.color }
        return !available || session.remote?.stale == true ? .secondary : (session.isDone ? .blue : session.state.color)
    }
    private var label: String {
        if !available { return "Unavailable" }
        if let workerLabel { return workerLabel }
        if session.remote?.stale == true { return "Last seen" }
        if session.isDone { return "Done" }
        switch session.state {
        case .working: return "Running"
        case .waiting: return "Needs you"
        case .idle, .inactive: return "Idle"
        default: return session.state.rawValue
        }
    }
    var body: some View {
        Button(action: select) {
            HStack(spacing: 11) {
                Image(systemName: session.provider == .codex ? "terminal" : "sparkle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(session.provider == .codex ? NotchStyle.accent : NotchStyle.claude)
                    .frame(width: 30, height: 30).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.system(size: 12, weight: .medium)).lineLimit(1).foregroundStyle(.white.opacity(0.92))
                    Text("\(session.provider == .codex ? "Codex" : "Claude") · \(workspace)")
                        .font(.system(size: 10)).lineLimit(1).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    if session.isDone && available && workerLabel == nil { Image(systemName: "checkmark.circle.fill").font(.system(size: 9)) }
                    else if session.state == .scheduled && available && session.remote?.stale != true && workerLabel == nil { Image(systemName: "clock").font(.system(size: 10)) }
                    else { Circle().fill(color).frame(width: 4, height: 4) }
                    Text(label)
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            }.padding(.horizontal, 10).frame(height: 56)
                .background(hovering ? .white.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }.disabled(!available)
            .help(available ? (session.chatURL == nil ? "Show details in Burro" : "Open chat in \(session.provider == .codex ? "Codex" : "Claude")") + "\n" + session.title : "No longer present in the latest scan. Update the list to remove this row.")
            .accessibilityHint(session.chatURL == nil ? "Shows session details in Burro" : "Opens this chat in \(session.provider == .codex ? "Codex" : "Claude")")
            .contextMenu { Button("Show in Burro", action: inspect).disabled(!available) }
    }
}

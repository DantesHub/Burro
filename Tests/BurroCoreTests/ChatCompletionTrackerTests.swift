import XCTest
@testable import BurroCore

final class ChatCompletionTrackerTests: XCTestCase {
    func testCompletionTransitionsAndNoStartupBacklog() {
        var tracker = ChatCompletionTracker()
        var chat = AgentSession(id: "chat", provider: .codex, title: "Example", cwd: "/repo", state: .idle,
                                updatedAt: Date(), evidence: "test")
        chat.turnCompleted = true
        XCTAssertTrue(tracker.completions(in: [chat]).isEmpty)
        chat.state = .working; chat.turnCompleted = false
        XCTAssertTrue(tracker.completions(in: [chat]).isEmpty)
        XCTAssertTrue(tracker.completions(in: []).isEmpty)
        chat.state = .unknown
        XCTAssertTrue(tracker.completions(in: [chat]).isEmpty)
        chat.state = .idle; chat.turnCompleted = true
        XCTAssertEqual(tracker.completions(in: [chat]).map(\.id), ["chat"])
        XCTAssertTrue(tracker.completions(in: [chat]).isEmpty)
        chat.state = .working; chat.turnCompleted = false
        _ = tracker.completions(in: [chat])
        chat.state = .inactive; chat.turnCompleted = true
        XCTAssertEqual(tracker.completions(in: [chat]).count, 1)
    }
    func testRemoteReconnectAndWorkers() {
        var tracker = ChatCompletionTracker()
        var chat = AgentSession(id: "remote:chat", provider: .claude, title: "Example", cwd: "/repo", state: .working,
                                updatedAt: Date(), evidence: "test")
        chat.remote = RemoteOrigin(hostID: UUID(), hostName: "Mac16", sampledAt: Date(), stale: false)
        _ = tracker.completions(in: [chat])
        chat.state = .idle; chat.turnCompleted = true; chat.remote?.stale = true
        XCTAssertTrue(tracker.completions(in: [chat]).isEmpty)
        chat.remote?.stale = false
        XCTAssertEqual(tracker.completions(in: [chat]).count, 1)
        chat.isSubagent = true; chat.state = .working
        _ = tracker.completions(in: [chat])
        chat.state = .idle
        XCTAssertTrue(tracker.completions(in: [chat]).isEmpty)
    }
}

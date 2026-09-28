// Check provider identity routing, remote provenance, backwards compatibility, and URL injection boundaries.
import XCTest
@testable import BurroCore

final class AgentChatLinkTests: XCTestCase {
    private let threadID = "11111111-2222-4333-8444-555555555555"
    private func session(_ provider: AgentProvider) -> AgentSession {
        AgentSession(id: "\(provider == .codex ? "codex" : "claude"):\(threadID)", provider: provider,
                     title: "Fixture", cwd: "/workspace", state: .working, updatedAt: Date(), evidence: "fixture")
    }
    func testCodexLinksKeepOnlyTheProviderThreadIDAcrossHosts() {
        var value = session(.codex)
        let expected = "codex://threads/\(threadID)"
        XCTAssertEqual(value.chatURL?.absoluteString, expected)
        let host = UUID()
        value.remote = RemoteOrigin(hostID: host, hostName: "Other Mac", sampledAt: Date(), stale: false)
        value.id = "remote:\(host.uuidString):\(value.id)"
        XCTAssertEqual(value.chatURL?.absoluteString, expected)
        value.id = "remote:\(UUID().uuidString):codex:\(threadID)"
        XCTAssertNil(value.chatURL, "A remote namespace must match its host")
    }
    func testLocalClaudePrefersItsDesktopSessionWithoutImporting() {
        var value = session(.claude)
        value.claudeDesktopSessionID = "local_\(threadID)"
        value.claudeBridgeSessionID = "session_existingRemote"
        XCTAssertEqual(value.chatURL?.absoluteString, "claude://code/continue?session=local_\(threadID)")
    }
    func testRemoteClaudeUsesBridgeAndNeverAnotherMachinesDesktopID() {
        var value = session(.claude)
        value.remote = RemoteOrigin(hostID: UUID(), hostName: "Other Mac", sampledAt: Date(), stale: false)
        value.claudeDesktopSessionID = "local_\(threadID)"
        XCTAssertNil(value.chatURL)
        value.claudeBridgeSessionID = "session_existingRemote"
        XCTAssertEqual(value.chatURL?.absoluteString, "claude://code/session_existingRemote")
    }
    func testLocalBridgeOnlySessionCanOpenButBareCLIUUIDDoesNotImport() {
        var value = session(.claude)
        XCTAssertNil(value.chatURL)
        value.claudeBridgeSessionID = "cse_existing"
        XCTAssertEqual(value.chatURL?.absoluteString, "claude://code/cse_existing")
    }
    func testMetadataCannotInjectURLActionsOrOtherSchemes() {
        for suffix in ["?prompt=send", "#fragment", "/new", "\n", "%2Fnew", "&folder=/tmp"] {
            var codex = session(.codex); codex.id += suffix
            XCTAssertNil(codex.chatURL)
            var claude = session(.claude)
            claude.claudeDesktopSessionID = "local_\(threadID)" + suffix
            claude.claudeBridgeSessionID = "session_existing" + suffix
            XCTAssertNil(claude.chatURL)
        }
    }
    func testOldRemotePayloadRemainsCompatibleAndNewIDsSurviveDecode() throws {
        var value = session(.claude)
        let oldData = try JSONEncoder().encode(value)
        XCTAssertNil(try JSONDecoder().decode(AgentSession.self, from: oldData).chatURL)
        value.claudeDesktopSessionID = "local_\(threadID)"
        value.claudeBridgeSessionID = "session_existing"
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AgentSession.self, from: data)
        XCTAssertEqual(decoded.claudeDesktopSessionID, value.claudeDesktopSessionID)
        XCTAssertEqual(decoded.claudeBridgeSessionID, value.claudeBridgeSessionID)
        XCTAssertEqual(decoded.chatURL, value.chatURL)
    }
}

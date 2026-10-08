import XCTest
@testable import BurroCore

final class FileReadCacheTests: XCTestCase {
    func fixture() throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("first".utf8).write(to: file)
        return file
    }

    func testUnchangedEvidenceIsDecodedOnceAndReplacementInvalidatesIt() throws {
        let file = try fixture(); defer { try? FileManager.default.removeItem(at: file) }
        let cache = FileReadCache<String>()
        var reads = 0
        func load(_ url: URL) throws -> String { reads += 1; return try String(contentsOf: url, encoding: .utf8) }
        XCTAssertEqual(try cache.read(file, load: load), "first")
        XCTAssertEqual(try cache.read(file, load: load), "first")
        XCTAssertEqual(reads, 1)

        // Same byte count AND restored mtime; inode/ctime still expose atomic replacement.
        let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]!
        try Data("other".utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        XCTAssertEqual(try cache.read(file, load: load), "other")
        XCTAssertEqual(reads, 2)
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try cache.read(file, load: load), "Missing files must not return cached evidence")
    }

    func testChangesDuringReadAndFailuresNeverCacheStaleEvidence() throws {
        let file = try fixture(); defer { try? FileManager.default.removeItem(at: file) }
        let cache = FileReadCache<String>()
        XCTAssertThrowsError(try cache.read(file) { url in
            let value = try String(contentsOf: url, encoding: .utf8)
            try Data("second".utf8).write(to: url)
            return value
        })
        XCTAssertEqual(try cache.read(file) { try String(contentsOf: $0, encoding: .utf8) }, "second")
        try Data("third".utf8).write(to: file)
        XCTAssertThrowsError(try cache.read(file) { _ in throw CocoaError(.fileReadUnknown) })
        XCTAssertEqual(try cache.read(file) { try String(contentsOf: $0, encoding: .utf8) }, "third")
    }

    func testNilAndDifferentPreferenceKeysAreCachedIndependently() throws {
        let file = try fixture(); defer { try? FileManager.default.removeItem(at: file) }
        let cache = FileReadCache<String?>()
        XCTAssertNil(try cache.read(file, variant: "absent") { _ in nil })
        XCTAssertEqual(try cache.read(file, variant: "present") { _ in "value" }, "value")
        XCTAssertNil(try cache.read(file, variant: "absent") { _ in XCTFail("Nil is a valid cached result"); return "wrong" })
    }

    func testCachedTurnStillUsesLiveWriterLockAndAge() throws {
        let file = try fixture(); defer { try? FileManager.default.removeItem(at: file) }
        let cache = FileReadCache<AgentParsing.CodexTurn>()
        try Data(#"{"type":"event_msg","payload":{"type":"task_started"}}"#.utf8).write(to: file)
        func read() throws -> AgentParsing.CodexTurn {
            try cache.read(file) { AgentParsing.codexTurn(tail: try String(contentsOf: $0, encoding: .utf8)) }
        }
        let now = Date(), old = now.addingTimeInterval(-900)
        XCTAssertEqual(AgentParsing.codexState(turn: try read(), held: 1, modified: old, now: now), .working)
        XCTAssertEqual(AgentParsing.codexState(turn: try read(), held: 0, modified: old, now: now), .inactive)
        XCTAssertEqual(AgentParsing.codexState(turn: try read(), held: 0, modified: now, now: now), .recent)
        XCTAssertEqual(AgentParsing.codexState(turn: try read(), held: -1, modified: now, now: now), .unknown)
        try Data(#"{"type":"event_msg","payload":{"type":"task_complete"}}"#.utf8).write(to: file)
        XCTAssertTrue(try read().completed)
        XCTAssertEqual(AgentParsing.codexState(turn: try read(), held: 1, modified: now, now: now), .idle)
    }
}

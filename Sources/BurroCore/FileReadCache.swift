// Cache derived metadata, never open provider files for writing or retain their full contents.
import Foundation
import Darwin

struct FileStamp: Equatable {
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let modifiedSeconds: Int
    let modifiedNanos: Int
    let changedSeconds: Int
    let changedNanos: Int

    init(_ url: URL) throws {
        var info = stat()
        guard stat(url.path, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        device = info.st_dev; inode = info.st_ino; size = info.st_size
        modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanos = info.st_mtimespec.tv_nsec
        changedSeconds = info.st_ctimespec.tv_sec; changedNanos = info.st_ctimespec.tv_nsec
    }
}

/// A changed/replaced/missing file must invalidate old evidence immediately. Successful
/// reads alone are cached, and a file changing during a read is retried on the next poll.
final class FileReadCache<Value: Sendable>: @unchecked Sendable {
    enum Failure: Error { case changed }
    private struct Key: Hashable { let path: String; let variant: String }
    private let lock = NSLock()
    private var entries: [Key: (FileStamp, Value)] = [:]

    func read(_ url: URL, variant: String = "", load: (URL) throws -> Value) throws -> Value {
        lock.lock(); defer { lock.unlock() }
        let key = Key(path: url.path, variant: variant)
        do {
            let before = try FileStamp(url)
            if let entry = entries[key], entry.0 == before { return entry.1 }
            entries.removeValue(forKey: key)
            let value = try load(url)
            guard before == (try FileStamp(url)) else { throw Failure.changed }
            if entries.count >= 128 { entries.removeAll(keepingCapacity: true) }
            entries[key] = (before, value)
            return value
        } catch {
            entries.removeValue(forKey: key)
            throw error
        }
    }
}

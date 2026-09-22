import Foundation

/// The save on the device (spec §15): one file, `save.json`, in a directory the app owns (iOS:
/// Application Support). Written whole and atomically — the canonical JSON goes to a temporary file
/// beside it, which is then renamed over the old one, so a crash mid-write leaves the last good
/// record, never half a new one. A record that cannot be read is never replaced silently: `load`
/// says so, and only `replaceRefused` moves it aside — untouched, under a name of its own — and writes a
/// new one. The Android twin is `core/season/SaveStore.kt`.
public struct SaveStore: Sendable {
    /// What was on the device.
    public enum Loaded: Sendable, Equatable {
        /// No save yet: a new player.
        case new(SaveRecord)
        case loaded(SaveRecord)
        /// A save exists and was refused (§15) — why, as a line for the log and the refusal screen.
        case refused(String)
    }

    public static let fileName = "save.json"
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public var file: URL { directory.appendingPathComponent(Self.fileName) }
    private var temporary: URL { directory.appendingPathComponent(Self.fileName + ".tmp") }

    /// Reads the save. A missing file is a new player; anything else that is not a well-formed
    /// record of this version — unreadable bytes included — is refused.
    public func load() -> Loaded {
        let bytes: Data
        do {
            bytes = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return .new(.fresh)
        } catch {
            return .refused("unreadable \(error.localizedDescription)")
        }
        do {
            return .loaded(try SaveRecord.decode(Array(bytes)))
        } catch {
            return .refused(error.description)
        }
    }

    /// Writes `record` atomically: the whole file to `save.json.tmp`, then renamed over `save.json`.
    public func write(_ record: SaveRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = Data(record.encoded().utf8)
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        guard rename(temporary.path, file.path) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path,
                                                          NSLocalizedDescriptionKey: String(cString: strerror(errno))])
        }
    }

    /// After a refusal (§15): the refused file is moved aside, untouched, as `save.refused-N.json`
    /// (the first N free), and a fresh record is written in its place. Returns the fresh record and
    /// where the refused one now lives.
    @discardableResult
    public func replaceRefused() throws -> (record: SaveRecord, keptAt: URL?) {
        var kept: URL?
        if FileManager.default.fileExists(atPath: file.path) {
            var n = 1
            var aside = directory.appendingPathComponent("save.refused-\(n).json")
            while FileManager.default.fileExists(atPath: aside.path) {
                n += 1
                aside = directory.appendingPathComponent("save.refused-\(n).json")
            }
            try FileManager.default.moveItem(at: file, to: aside)
            kept = aside
        }
        let fresh = SaveRecord.fresh
        try write(fresh)
        return (fresh, kept)
    }
}

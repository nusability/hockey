import Foundation

/// The device record on the device (spec §17.1): one file, `device.json`, in the same directory as
/// the save (iOS: Application Support). Written whole and atomically, exactly as `SaveStore` writes
/// `save.json` — the canonical JSON goes to a temporary file beside it, which is then renamed over
/// the old one. The Android twin is `core/telemetry/DeviceStore.kt`.
///
/// It is a **second file and not a branch of the save**, and the three reasons are the whole design
/// (ADR 0009):
///
/// 1. **A refused save cannot reach it.** `SaveStore.replaceRefused()` and starting over name
///    `save.json` and nothing else, so a player who has said yes is never asked again whatever
///    becomes of their career.
/// 2. **A refused device record is never a screen.** Telemetry may not stand between the player and
///    the game, so `replaceRefused(at:installId:)` moves the unreadable file aside and writes a
///    **`replacement`** — stamped as if the question had just been put. Never a `fresh`: a record we
///    lost must serve a full cooldown, never read as long-ago-and-eligible.
/// 3. **It is excluded from device backup.** `isExcludedFromBackup` is set on the file after every
///    write, so an install id can never be restored onto a second phone and counted twice.
///    `save.json` stays backed up — player data is sacred.
public struct DeviceStore: Sendable {
    /// What was on the device — the same three answers `SaveStore.Loaded` gives, and the same
    /// meanings; only what the app does with the third one differs.
    public enum Loaded: Sendable, Equatable {
        /// No record yet: this install has just been seen for the first time.
        case new(DeviceRecord)
        case loaded(DeviceRecord)
        /// A record exists and was refused (§17.1) — why, as a line for the log. Never a screen.
        case refused(String)
    }

    public static let fileName = "device.json"
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public var file: URL { directory.appendingPathComponent(Self.fileName) }
    private var temporary: URL { directory.appendingPathComponent(Self.fileName + ".tmp") }

    /// Reads the record. A missing file is a new install; anything else that is not a well-formed
    /// record of this version — unreadable bytes included — is refused.
    ///
    /// `now` and `installId` are only what a *new* install would be stamped with: the platform mints
    /// the id and reads the clock, the core does neither.
    public func load(at now: Int64, installId: String) -> Loaded {
        let bytes: Data
        do {
            bytes = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return .new(.fresh(at: now, installId: installId))
        } catch {
            return .refused("unreadable \(error.localizedDescription)")
        }
        do {
            return .loaded(try DeviceRecord.decode(Array(bytes)))
        } catch {
            return .refused(error.description)
        }
    }

    /// Writes `record` atomically: the whole file to `device.json.tmp`, then renamed over
    /// `device.json`, and the result kept out of device backup.
    public func write(_ record: DeviceRecord) throws {
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
        try excludeFromBackup()
    }

    /// Keeps the file out of iCloud and iTunes/Finder backups (§17.1). Set after the rename, because
    /// the rename replaces the file the flag was on.
    private func excludeFromBackup() throws {
        var url = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// After a refusal (§17.1): the refused file is moved aside, untouched, as
    /// `device.refused-N.json` (the first N free), and a **replacement** is written in its place.
    ///
    /// The replacement — never a `fresh` — is stamped as if the question had just been put, so the
    /// record we lost reads as brand new and serving a full cooldown. One corrupt byte must not
    /// re-ask a player who has already answered.
    @discardableResult
    public func replaceRefused(at now: Int64, installId: String) throws -> (record: DeviceRecord, keptAt: URL?) {
        var kept: URL?
        if FileManager.default.fileExists(atPath: file.path) {
            var n = 1
            var aside = directory.appendingPathComponent("device.refused-\(n).json")
            while FileManager.default.fileExists(atPath: aside.path) {
                n += 1
                aside = directory.appendingPathComponent("device.refused-\(n).json")
            }
            try FileManager.default.moveItem(at: file, to: aside)
            kept = aside
        }
        let replacement = DeviceRecord.replacement(at: now, installId: installId)
        try write(replacement)
        return (replacement, kept)
    }

    /// The whole of launch, in one call: the record that is on the device, written if it was not
    /// there or could not be read. `refused` is the line to log when it could not — and nothing
    /// more, because a refused device record is never a screen.
    public func loadOrCreate(at now: Int64, installId: String) throws -> (record: DeviceRecord, refused: String?) {
        switch load(at: now, installId: installId) {
        case .loaded(let record):
            return (record, nil)
        case .new(let record):
            try write(record)
            return (record, nil)
        case .refused(let why):
            return (try replaceRefused(at: now, installId: installId).record, why)
        }
    }
}

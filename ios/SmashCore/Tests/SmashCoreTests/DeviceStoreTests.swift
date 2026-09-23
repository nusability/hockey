import Foundation
import Testing
@testable import SmashCore

/// The device record's file (spec §17.1): `device.json`, beside the save and under its own rules.
/// What is worth testing here is not the round trip — `SaveStore` already proves the atomic write —
/// but the three rules that are the whole reason the record is not in the save.
@Suite struct DeviceStoreTests {
    static let id = "7c9e6f81-3b4a-4d2e-8a15-0f6b5c2d9e13"
    static let otherId = "b41d8a27-5e6c-4f19-9d03-2a7b6c4e8f50"
    static let now: Int64 = 1_772_366_400_000

    static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("smash-device-\(UUID().uuidString)")
    }

    @Test func aMissingRecordIsANewInstallAndAWrittenOneReadsBack() throws {
        let store = DeviceStore(directory: Self.directory())
        let fresh = DeviceRecord.fresh(at: Self.now, installId: Self.id)
        #expect(store.load(at: Self.now, installId: Self.id) == .new(fresh))
        #expect(!FileManager.default.fileExists(atPath: store.file.path), "loading writes nothing")

        let (record, refused) = try store.loadOrCreate(at: Self.now, installId: Self.id)
        #expect(record == fresh && refused == nil)
        #expect(try String(contentsOf: store.file, encoding: .utf8) == fresh.encoded())
        let names = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(names == [DeviceStore.fileName], "nothing but the record is left behind")

        // A launch that finds it reads it back and mints nothing: the id on the device wins over the
        // one the platform brought, which is what makes an install id stable for the install's life.
        let played = record.recordingPlayedMatch().recordingPresentation(at: Self.now + 1)
        try store.write(played)
        #expect(store.load(at: Self.now, installId: Self.otherId) == .loaded(played))
        #expect(played.installId == Self.id)
    }

    /// Rule 2 of §17.1, and the one that must never be "simplified": a record we could not read is
    /// replaced by a **`replacement`** — stamped as if the question had just been put — and never by a
    /// `fresh`. Swap the one for the other and this test fails on `lastAskedAt`.
    @Test func aRefusedRecordIsReplacedAsIfTheQuestionHadJustBeenPut() throws {
        let store = DeviceStore(directory: Self.directory())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let bad = Data("{\"version\": 99}".utf8)
        try bad.write(to: store.file)
        guard case .refused(let why) = store.load(at: Self.now, installId: Self.id) else {
            Issue.record("a bad device record must be refused")
            return
        }
        #expect(why == "unknownVersion 99")
        #expect(try Data(contentsOf: store.file) == bad, "loading never touches the file")

        let (record, refused) = try store.loadOrCreate(at: Self.now, installId: Self.id)
        #expect(refused == why, "the refusal is a line for the log, and only that")
        #expect(record == .replacement(at: Self.now, installId: Self.id))
        // The whole point: a full cooldown from now, not a record that reads as never-asked.
        #expect(record.lastAskedAt == Self.now)
        #expect(record.installedAt == Self.now)
        #expect(record != .fresh(at: Self.now, installId: Self.id))
        #expect(try String(contentsOf: store.file, encoding: .utf8) == record.encoded())

        // The refused bytes are kept, untouched, and a second refusal does not overwrite the first.
        let kept = store.refusedDirectory.appendingPathComponent("device-1.json")
        #expect(try Data(contentsOf: kept) == bad)
        try bad.write(to: store.file)
        #expect(try store.replaceRefused(at: Self.now, installId: Self.otherId).keptAt?.lastPathComponent
                == "device-2.json")
    }

    /// Rule 1 of §17.1: the save's refusal path and starting over move `save.json` and write
    /// `save.json`, and name no other file. A player who has said yes is never asked again, whatever
    /// becomes of their career.
    @Test func theSavesRefusalCannotReachTheDeviceRecord() throws {
        let directory = Self.directory()
        let devices = DeviceStore(directory: directory)
        let saves = SaveStore(directory: directory)
        let record = DeviceRecord.fresh(at: Self.now, installId: Self.id).recording(.positive)
        try devices.write(record.recordingPresentation(at: Self.now))
        let before = try Data(contentsOf: devices.file)

        try Data("{\"version\": 99}".utf8).write(to: saves.file)
        _ = try saves.replaceRefused()

        #expect(try Data(contentsOf: devices.file) == before, "starting over left the device record alone")
        #expect(devices.load(at: Self.now + 1, installId: Self.otherId)
                == .loaded(record.recordingPresentation(at: Self.now)))
    }

    /// Rule 3 of §17.1: an install id restored onto a new phone is one install counted as two,
    /// forever — so the file is out of iCloud and iTunes/Finder backups. The save is not: player data
    /// is sacred (principle 13).
    @Test func theRecordIsKeptOutOfBackupAndTheSaveIsNot() throws {
        let directory = Self.directory()
        let devices = DeviceStore(directory: directory)
        try devices.write(.fresh(at: Self.now, installId: Self.id))
        try SaveStore(directory: directory).write(.fresh)

        #expect(try devices.file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let save = try SaveStore(directory: directory).file.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(save.isExcludedFromBackup != true, "the save is backed up")

        // And it survives the rename, which replaces the file the flag was set on.
        try devices.write(.fresh(at: Self.now + 1, installId: Self.id))
        #expect(try devices.file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    /// The all-zero UUID is what a mint that failed looks like. Stored, it would make every phone one
    /// install; so it is refused on decode and the record replaced like any other refusal.
    @Test func theAllZeroInstallIdIsRefused() throws {
        let store = DeviceStore(directory: Self.directory())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let zeroed = DeviceRecord.fresh(at: Self.now, installId: DeviceRecord.noInstallId)
        try Data(zeroed.encoded().utf8).write(to: store.file)
        guard case .refused(let why) = store.load(at: Self.now, installId: Self.id) else {
            Issue.record("the all-zero install id must be refused")
            return
        }
        #expect(why == "brokenRule $.install_id zeroInstallId")
    }

    /// The refused copy lands inside the excluded directory and never beside the record. A backup
    /// rule names exact paths, so a copy written beside `device.json` would be carried off the phone
    /// with the install id still in it (§17.1, §18.1) — which is the one thing this file exists to
    /// prevent.
    @Test func aRefusedCopyIsKeptInsideTheExcludedDirectory() throws {
        let store = DeviceStore(directory: Self.directory())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.file)
        let kept = try store.replaceRefused(at: Self.now, installId: Self.id).keptAt
        #expect(kept?.deletingLastPathComponent().lastPathComponent == DeviceStore.refusedDirectoryName)
        #expect(kept?.lastPathComponent == "device-1.json")
        // Beside the record there is now only the record itself — no copy an exclusion would miss.
        let beside = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(beside.filter { $0.hasPrefix("device.") } == [DeviceStore.fileName])
    }
}

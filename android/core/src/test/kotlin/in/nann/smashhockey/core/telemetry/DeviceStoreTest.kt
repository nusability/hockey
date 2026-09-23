package `in`.nann.smashhockey.core.telemetry

import `in`.nann.smashhockey.core.generated.DeviceRecord
import `in`.nann.smashhockey.core.generated.SaveRecord
import `in`.nann.smashhockey.core.season.SaveStore
import `in`.nann.smashhockey.core.season.fresh
import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The device record's file (spec §17.1): `device.json`, beside the save and under its own rules. What
 * is worth testing here is not the round trip — `SaveStore` already proves the atomic write — but the
 * three rules that are the whole reason the record is not in the save. The iOS twin is
 * `SmashCoreTests/DeviceStoreTests.swift`.
 */
class DeviceStoreTest {
    private val id = "7c9e6f81-3b4a-4d2e-8a15-0f6b5c2d9e13"
    private val otherId = "b41d8a27-5e6c-4f19-9d03-2a7b6c4e8f50"
    private val now = 1_772_366_400_000L

    private fun directory(): File = Files.createTempDirectory("smash-device").toFile()

    @Test fun aMissingRecordIsANewInstallAndAWrittenOneReadsBack() {
        val store = DeviceStore(directory())
        val fresh = DeviceRecord.fresh(now, id)
        assertEquals(DeviceStore.Loaded.New(fresh), store.load(now, id))
        assertTrue("loading writes nothing", !store.file.exists())

        val (record, refused) = store.loadOrCreate(now, id)
        assertEquals(fresh, record)
        assertEquals(null, refused)
        assertEquals(fresh.encoded(), store.file.readText())
        assertEquals(
            "nothing but the record is left behind",
            listOf(DeviceStore.FILE_NAME),
            store.directory.list()!!.toList(),
        )

        // A launch that finds it reads it back and mints nothing: the id on the device wins over the one
        // the platform brought, which is what makes an install id stable for the install's life.
        val played = record.recordingPlayedMatch().recordingPresentation(now + 1)
        store.write(played)
        assertEquals(DeviceStore.Loaded.Found(played), store.load(now, otherId))
        assertEquals(id, played.installId)
    }

    /**
     * Rule 2 of §17.1, and the one that must never be "simplified": a record we could not read is
     * replaced by a **replacement** — stamped as if the question had just been put — and never by a
     * fresh. Swap the one for the other and this test fails on `lastAskedAt`.
     */
    @Test fun aRefusedRecordIsReplacedAsIfTheQuestionHadJustBeenPut() {
        val store = DeviceStore(directory())
        val bad = "{\"version\": 99}".toByteArray()
        store.file.writeBytes(bad)
        assertEquals(DeviceStore.Loaded.Refused("unknownVersion 99"), store.load(now, id))
        assertTrue("loading never touches the file", store.file.readBytes().contentEquals(bad))

        val (record, refused) = store.loadOrCreate(now, id)
        assertEquals("the refusal is a line for the log, and only that", "unknownVersion 99", refused)
        assertEquals(DeviceRecord.replacement(now, id), record)
        // The whole point: a full cooldown from now, not a record that reads as never-asked.
        assertEquals(now, record.lastAskedAt)
        assertEquals(now, record.installedAt)
        assertNotEquals(DeviceRecord.fresh(now, id), record)
        assertEquals(record.encoded(), store.file.readText())

        // The refused bytes are kept, untouched, and a second refusal does not overwrite the first.
        assertTrue(File(store.directory, "device.refused-1.json").readBytes().contentEquals(bad))
        store.file.writeBytes(bad)
        assertEquals("device.refused-2.json", store.replaceRefused(now, otherId).second!!.name)
    }

    /**
     * Rule 1 of §17.1: the save's refusal path and starting over move `save.json` and write
     * `save.json`, and name no other file. A player who has said yes is never asked again, whatever
     * becomes of their career.
     */
    @Test fun theSavesRefusalCannotReachTheDeviceRecord() {
        val directory = directory()
        val devices = DeviceStore(directory)
        val saves = SaveStore(directory)
        val record = DeviceRecord.fresh(now, id).recording(LoveAnswer.POSITIVE).recordingPresentation(now)
        devices.write(record)
        val before = devices.file.readBytes()

        saves.file.writeBytes("{\"version\": 99}".toByteArray())
        saves.replaceRefused()

        assertTrue("starting over left the device record alone", devices.file.readBytes().contentEquals(before))
        assertEquals(DeviceStore.Loaded.Found(record), devices.load(now + 1, otherId))
        assertEquals(SaveStore.Loaded.Found(SaveRecord.fresh()), saves.load())
    }

    /**
     * The all-zero UUID is what a mint that failed looks like. Stored, it would make every phone one
     * install; so it is refused on decode and the record replaced like any other refusal.
     */
    @Test fun theAllZeroInstallIdIsRefused() {
        val store = DeviceStore(directory())
        store.file.writeBytes(DeviceRecord.fresh(now, NO_INSTALL_ID).encoded().toByteArray())
        assertEquals(
            DeviceStore.Loaded.Refused("brokenRule \$.install_id zeroInstallId"),
            store.load(now, id),
        )
    }
}

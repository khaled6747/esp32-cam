package room.test

import android.app.Activity
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.ParcelUuid
import com.example.smart_room.RoomBle
import io.flutter.plugin.common.*
import java.util.UUID

private class Reply : MethodChannel.Result {
    var count = 0
    var code: String? = null
    var succeeded = false
    private fun finish() { check(++count == 1) { "Reply already submitted" } }
    override fun success(value: Any?) { finish(); succeeded = true }
    override fun error(code: String, message: String?, details: Any?) { finish(); this.code = code }
    override fun notImplemented() { finish(); code = "not_implemented" }
}
private class Events : EventChannel.EventSink {
    val values = mutableListOf<Map<String, Any?>>()
    @Suppress("UNCHECKED_CAST")
    override fun success(value: Any?) { values.add(value as Map<String, Any?>) }
}
private class Fixture {
    val activity = Activity()
    val adapter = BluetoothAdapter()
    val events = Events()
    val device = BluetoothDevice("F0:24:F9:10:80:A6")
    val ble: RoomBle
    init {
        Handler.reset(); Build.VERSION.SDK_INT = 36
        activity.services[Context.BLUETOOTH_SERVICE] = BluetoothManager(adapter)
        activity.services[Context.LOCATION_SERVICE] = LocationManager()
        ble = RoomBle(activity, object : BinaryMessenger {})
        ble.onListen(null, events)
    }
    fun call(method: String, arguments: Map<String, Any?>? = null): Reply = Reply().also {
        ble.onMethodCall(MethodCall(method, arguments), it)
    }
    fun scan(): ScanCallback {
        check(call("scan").succeeded)
        return adapter.bluetoothLeScanner!!.callback!!
    }
    fun discover(callback: ScanCallback = scan(), target: BluetoothDevice = device, service: String = RoomBle.SERVICE) {
        callback.onScanResult(1, ScanResult(target, ScanRecord(listOf(ParcelUuid(UUID.fromString(service))))))
        Handler.drain()
    }
    fun connect(epoch: Int = 1): Pair<Reply, BluetoothGatt> {
        val reply = call("connect", mapOf("id" to device.address, "epoch" to epoch))
        return reply to device.lastGatt!!
    }
    fun ready(epoch: Int = 1, mtu: Int = 247): Triple<Reply, BluetoothGatt, BluetoothGattCharacteristic> {
        discover()
        val (reply, gatt) = connect(epoch)
        val service = BluetoothGattService(UUID.fromString(RoomBle.SERVICE))
        val command = BluetoothGattCharacteristic(UUID.fromString(RoomBle.COMMAND))
        val event = BluetoothGattCharacteristic(UUID.fromString(RoomBle.EVENT))
        event.descriptors[UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")] =
            BluetoothGattDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"))
        service.characteristics[command.uuid] = command; service.characteristics[event.uuid] = event
        gatt.services[service.uuid] = service
        gatt.callback.onConnectionStateChange(gatt, 0, BluetoothProfile.STATE_CONNECTED); Handler.drain()
        gatt.callback.onServicesDiscovered(gatt, 0); Handler.drain()
        gatt.callback.onMtuChanged(gatt, mtu, 0); Handler.drain()
        check(reply.count == 0) { "Transport ready before descriptor acknowledgment" }
        gatt.callback.onDescriptorWrite(gatt, gatt.descriptor!!, 0); Handler.drain()
        check(reply.succeeded)
        return Triple(reply, gatt, command)
    }
    fun done() { ble.dispose(); Handler.drain(); Handler.reset() }
}

fun main() {
    var passed = 0; var failed = 0
    fun test(name: String, body: (Fixture) -> Unit) {
        val fixture = Fixture()
        try { body(fixture); ++passed; println("PASS $name") }
        catch (error: Throwable) { ++failed; println("FAIL $name: ${error.message}") }
        finally { try { fixture.done() } catch (error: Throwable) { ++failed; println("FAIL owned cleanup: ${error.message}") } }
    }
    test("service scan filter and current discovery are required") { f ->
        check(f.call("connect", mapOf("id" to f.device.address, "epoch" to 1)).code == "device_not_scanned")
        val scan = f.scan(); check(f.adapter.bluetoothLeScanner!!.filters.single().service!!.uuid.toString() == RoomBle.SERVICE)
        f.discover(scan, service = "0000180f-0000-1000-8000-00805f9b34fb")
        check(f.events.values.none { it["kind"] == "scan_result" }); check(f.device.connects == 0)
    }
    test("old scan callbacks are ignored and discovery is bounded") { f ->
        val old = f.scan(); val current = f.scan()
        f.discover(old); check(f.events.values.none { it["kind"] == "scan_result" })
        for (i in 0..39) f.discover(current, BluetoothDevice("F0:24:F9:10:80:${i.toString(16).padStart(2, '0')}"))
        check(f.events.values.count { it["kind"] == "scan_result" } == 32)
    }
    test("scan callback permission revocation stops and reports rather than crashing the main queue") { f ->
        val scan = f.scan(); f.device.addressFailure = SecurityException("inert permission revocation")
        f.discover(scan)
        check(f.events.values.any { it["kind"] == "error" && it["code"] == "permissions_revoked" })
        check(f.adapter.bluetoothLeScanner!!.callback == null && f.device.connects == 0)
    }
    test("notification bytes are detached before crossing the main queue") { f ->
        val (_, gatt, _) = f.ready()
        val original = byteArrayOf(65, 10)
        gatt.callback.onCharacteristicChanged(gatt, BluetoothGattCharacteristic(UUID.fromString(RoomBle.EVENT)), original)
        original[0] = 66; Handler.drain()
        check((f.events.values.last { it["kind"] == "bytes" }["bytes"] as ByteArray).contentEquals(byteArrayOf(65, 10)))
    }
    test("connect exception completes the pending platform reply exactly once") { f ->
        f.discover(); f.device.failure = SecurityException("inert permission revocation")
        val reply = f.call("connect", mapOf("id" to f.device.address, "epoch" to 1))
        check(reply.count == 1 && reply.code == "permissions_denied")
        check(f.call("disconnect").succeeded)
    }
    test("write exception completes the pending platform reply exactly once") { f ->
        val (_, gatt, _) = f.ready(); gatt.writeFailure = SecurityException("inert permission revocation")
        val reply = f.call("write", mapOf("bytes" to byteArrayOf(123, 125, 10), "epoch" to 1))
        check(reply.count == 1 && reply.code == "permissions_denied")
        check(gatt.disconnects == 1 && gatt.closes == 1)
    }
    test("permission-request failure does not retain a completed result") { f ->
        f.activity.granted = false; f.activity.permissionFailure = IllegalStateException("inert activity state")
        val reply = f.call("permissions"); check(reply.count == 1)
        f.ble.permissionResult(8401, intArrayOf(-1, -1)); check(reply.count == 1)
    }
    test("background cancels the one owned link and never reconnects") { f ->
        f.discover(); val (reply, gatt) = f.connect()
        f.ble.stopForBackground(); check(reply.code == "app_background")
        check(gatt.disconnects == 1 && gatt.closes == 1 && f.device.connects == 1)
        gatt.callback.onConnectionStateChange(gatt, 0, BluetoothProfile.STATE_CONNECTED); Handler.drain()
        check(reply.count == 1 && f.events.values.none { it["kind"] == "ready" })
    }
    test("native closure permission error is reported without crashing onStop") { f ->
        val (_, gatt, _) = f.ready(); gatt.closeFailure = SecurityException("inert permission revocation")
        f.ble.stopForBackground()
        check(gatt.closes == 1 && gatt.disconnects == 1)
        check(f.events.values.any { it["kind"] == "error" })
    }
    test("only one connection attempt is admitted") { f ->
        f.discover(); val (first, _) = f.connect()
        check(f.call("connect", mapOf("id" to f.device.address, "epoch" to 2)).code == "busy")
        check(first.count == 0 && f.device.connects == 1)
    }
    test("acknowledged chunk writes do not complete before all GATT replies") { f ->
        val (_, gatt, command) = f.ready()
        val bytes = ByteArray(321) { 65 }.also { it[it.lastIndex] = 10 }
        val reply = f.call("write", mapOf("bytes" to bytes, "epoch" to 1))
        check(reply.count == 0 && gatt.chunks.map { it.size } == listOf(160))
        check(f.call("write", mapOf("bytes" to bytes, "epoch" to 1)).code == "busy")
        repeat(3) { gatt.callback.onCharacteristicWrite(gatt, command, 0); Handler.drain() }
        check(reply.succeeded && reply.count == 1 && gatt.chunks.map { it.size } == listOf(160, 160, 1))
    }
    test("default MTU keeps every write within twenty bytes") { f ->
        val (_, gatt, command) = f.ready(mtu = 23)
        val reply = f.call("write", mapOf("bytes" to ByteArray(41) { if (it == 40) 10 else 65 }, "epoch" to 1))
        repeat(3) { gatt.callback.onCharacteristicWrite(gatt, command, 0); Handler.drain() }
        check(reply.succeeded && gatt.chunks.map { it.size } == listOf(20, 20, 1))
    }
    test("Android 7–11 location gate and pre-33 GATT APIs have valid and negative controls") { f ->
        Build.VERSION.SDK_INT = 30
        val location = f.activity.services[Context.LOCATION_SERVICE] as LocationManager
        location.enabled = false; check(f.call("scan").code == "location_off")
        location.enabled = true
        val (_, gatt, command) = f.ready(mtu = 23)
        val reply = f.call("write", mapOf("bytes" to byteArrayOf(65, 10), "epoch" to 1))
        check(reply.count == 0)
        gatt.callback.onCharacteristicWrite(gatt, command, 0); Handler.drain()
        check(reply.succeeded && gatt.chunks.single().contentEquals(byteArrayOf(65, 10)))
        val event = BluetoothGattCharacteristic(UUID.fromString(RoomBle.EVENT)).also { it.value = byteArrayOf(65, 10) }
        gatt.callback.onCharacteristicChanged(gatt, event); event.value!![0] = 66; Handler.drain()
        check((f.events.values.last { it["kind"] == "bytes" }["bytes"] as ByteArray).contentEquals(byteArrayOf(65, 10)))
    }
    test("a rejected chunk closes without retry or subsequent chunks") { f ->
        val (_, gatt, command) = f.ready()
        val reply = f.call("write", mapOf("bytes" to ByteArray(321) { if (it == 320) 10 else 65 }, "epoch" to 1))
        gatt.callback.onCharacteristicWrite(gatt, command, 5); Handler.drain()
        check(reply.code == "write_rejected" && gatt.chunks.size == 1 && gatt.closes == 1)
        gatt.callback.onCharacteristicWrite(gatt, command, 0); Handler.drain(); check(reply.count == 1)
    }
    test("obsolete GATT callbacks cannot update a replacement connection") { f ->
        val (_, old, _) = f.ready(); check(f.call("disconnect").succeeded)
        f.ready(epoch = 2)
        val before = f.events.values.size
        old.callback.onCharacteristicChanged(old, BluetoothGattCharacteristic(UUID.fromString(RoomBle.EVENT)), byteArrayOf(65, 10))
        old.callback.onConnectionStateChange(old, 8, BluetoothProfile.STATE_DISCONNECTED); Handler.drain()
        check(f.events.values.size == before)
    }
    test("malformed oversized and wrong-epoch writes never start") { f ->
        val (_, gatt, _) = f.ready()
        for (bytes in listOf(ByteArray(0), byteArrayOf(65), byteArrayOf(0, 10), ByteArray(770) { 10 }))
            check(f.call("write", mapOf("bytes" to bytes, "epoch" to 1)).code == "invalid_write")
        check(f.call("write", mapOf("bytes" to byteArrayOf(65, 10), "epoch" to 2)).code == "not_connected")
        check(gatt.chunks.isEmpty())
    }
    test("dispose cancels permission reply and denies future operations") { f ->
        f.activity.granted = false; val reply = f.call("permissions"); check(reply.count == 0)
        f.ble.dispose(); check(reply.code == "closed")
        check(f.call("scan").code == "closed"); f.ble.permissionResult(8401, intArrayOf(0, 0)); check(reply.count == 1)
    }
    println("RESULT $passed passed, $failed failed (JVM fixture, no Android radio)")
    check(failed == 0) { "Native adapter fixture failures" }
}

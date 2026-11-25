package com.example.smart_room

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import kotlin.math.min

/** Single owned GATT, no auto-connect/retry and no unbounded native write queue. */
class RoomBle(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        const val SERVICE = "6f875ca0-24ad-47e0-a36f-50f38e4d9301"
        const val COMMAND = "6f875ca0-24ad-47e0-a36f-50f38e4d9302"
        const val EVENT = "6f875ca0-24ad-47e0-a36f-50f38e4d9303"
        private const val PERMISSIONS = 8401
        private val CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private val handler = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "smart_room/ble")
    private val events = EventChannel(messenger, "smart_room/ble_events")
    private var sink: EventChannel.EventSink? = null
    private var permissionsPending: MethodChannel.Result? = null
    private var scanner: ScanCallback? = null
    private val discovered = linkedMapOf<String, android.bluetooth.BluetoothDevice>()
    private var gatt: BluetoothGatt? = null
    private var command: BluetoothGattCharacteristic? = null
    private var notifications: BluetoothGattCharacteristic? = null
    private var connectPending: MethodChannel.Result? = null
    private var writePending: MethodChannel.Result? = null
    private var writeBytes = ByteArray(0)
    private var writeOffset = 0
    private var chunkLength = 0
    private var mtu = 23
    private var epoch = 0
    private var ready = false
    private var disposed = false
    private val scanTimeout = Runnable { stopScan(); emit("scan_end") }
    private val connectTimeout = Runnable { failLink("connect_timeout", "انتهت مهلة الاقتران أو اكتشاف الخدمة") }
    private val writeTimeout = Runnable { failLink("write_timeout", "لم يكتمل تأكيد النقل؛ نتيجة الأمر غير معروفة") }

    init { methods.setMethodCallHandler(this); events.setStreamHandler(this) }

    private fun emit(kind: String, fields: Map<String, Any?> = emptyMap()) {
        if (!disposed) sink?.success(mapOf("kind" to kind, "epoch" to epoch) + fields)
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
    override fun onCancel(arguments: Any?) { stopForBackground(); sink = null }

    private fun permissions(): Array<String> = if (Build.VERSION.SDK_INT >= 31)
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)

    private fun havePermissions() = permissions().all {
        activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    private fun adapter(): BluetoothAdapter {
        if (!havePermissions()) throw SecurityException("Bluetooth permission required")
        val manager = activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter ?: throw IllegalStateException("Bluetooth LE unavailable")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) { result.error("closed", "Bluetooth adapter is closed", null); return }
        try {
            when (call.method) {
                "permissions" -> {
                    if (havePermissions()) result.success(null)
                    else if (permissionsPending != null) result.error("busy", "Permission request already active", null)
                    else { permissionsPending = result; activity.requestPermissions(permissions(), PERMISSIONS) }
                }
                "scan" -> {
                    if (gatt != null) { result.error("busy", "Disconnect before scanning", null); return }
                    val adapter = adapter()
                    if (!adapter.isEnabled) { result.error("bluetooth_off", "فعّل Bluetooth من إعدادات الهاتف", null); return }
                    if (Build.VERSION.SDK_INT < 31) {
                        val location = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
                        if (!location.isProviderEnabled(LocationManager.GPS_PROVIDER) && !location.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                            result.error("location_off", "في Android 7–11 يلزم تشغيل خدمة الموقع لبحث BLE؛ التطبيق لا يجمع موقعك", null); return
                        }
                    }
                    startScan(adapter); result.success(null)
                }
                "stopScan" -> { stopScan(); result.success(null) }
                "connect" -> {
                    val id = call.argument<String>("id")
                    val requestedEpoch = call.argument<Int>("epoch")
                    if (id == null || requestedEpoch == null || requestedEpoch < 1 || !discovered.containsKey(id)) {
                        result.error("device_not_scanned", "اختر جهازًا من نتيجة البحث الحالية", null); return
                    }
                    if (gatt != null || connectPending != null) { result.error("busy", "Only one app connection is permitted", null); return }
                    val adapter = adapter()
                    if (!adapter.isEnabled) { result.error("bluetooth_off", "فعّل Bluetooth", null); return }
                    stopScan(); epoch = requestedEpoch; mtu = 23; ready = false; connectPending = result
                    gatt = discovered.getValue(id).connectGatt(activity, false, callback(epoch), android.bluetooth.BluetoothDevice.TRANSPORT_LE)
                    if (gatt == null) { failLink("connect_failed", "تعذر بدء اتصال BLE"); return }
                    handler.postDelayed(connectTimeout, 90000)
                }
                "write" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val expectedEpoch = call.argument<Int>("epoch")
                    if (!ready || gatt == null || expectedEpoch != epoch) { result.error("not_connected", "No current ready link", null); return }
                    if (writePending != null) { result.error("busy", "Only one acknowledged write is allowed", null); return }
                    if (bytes == null || bytes.isEmpty() || bytes.size > 769 || bytes.last() != 10.toByte() || bytes.any { it == 0.toByte() }) {
                        result.error("invalid_write", "Malformed or oversized command", null); return
                    }
                    writePending = result; writeBytes = bytes.copyOf(); writeOffset = 0
                    handler.postDelayed(writeTimeout, 8000); writeChunk()
                }
                "disconnect" -> { closeLink("requested_disconnect"); result.success(null) }
                "dispose" -> { stopForBackground(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: SecurityException) {
            failMethod(result, "permissions_denied", "اسمح بصلاحيات Bluetooth / البحث من إعدادات التطبيق")
        } catch (_: IllegalArgumentException) {
            failMethod(result, "invalid_arguments", "Invalid Bluetooth arguments")
        } catch (_: IllegalStateException) {
            failMethod(result, "bluetooth_unavailable", "Bluetooth LE غير متاح على هذا الهاتف")
        }
    }

    private fun failMethod(result: MethodChannel.Result, code: String, message: String) {
        // A platform call may throw after its Result was retained. Detach that
        // same reply before cleanup so closeLink/permissionResult cannot submit
        // it a second time (Flutter rejects duplicate replies).
        if (permissionsPending === result) permissionsPending = null
        if (connectPending === result) connectPending = null
        if (writePending === result) writePending = null
        result.error(code, message, null)
        stopScan()
        closeLink(code)
    }

    fun permissionResult(code: Int, results: IntArray) {
        if (code != PERMISSIONS) return
        val pending = permissionsPending ?: return; permissionsPending = null
        if (results.size == permissions().size && results.all { it == PackageManager.PERMISSION_GRANTED } && havePermissions()) pending.success(null)
        else pending.error("permissions_denied", "لم تُمنح صلاحيات بحث/اتصال Bluetooth", null)
    }

    private fun startScan(adapter: BluetoothAdapter) {
        stopScan(); discovered.clear()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                handler.post {
                    if (scanner !== this || disposed) return@post
                    if (result.scanRecord?.serviceUuids?.contains(ParcelUuid(UUID.fromString(SERVICE))) != true) return@post
                    try {
                        val id = result.device.address
                        if (!discovered.containsKey(id) && discovered.size >= 32) return@post
                        discovered[id] = result.device
                        emit("scan_result", mapOf("id" to id, "name" to (result.scanRecord?.deviceName ?: "SmartRoom"), "rssi" to result.rssi))
                    } catch (_: SecurityException) {
                        stopScan(); emit("error", mapOf("code" to "permissions_revoked", "message" to "أُلغيت صلاحية Bluetooth أثناء قراءة نتيجة البحث"))
                    } catch (_: IllegalStateException) {
                        stopScan(); emit("error", mapOf("code" to "bluetooth_unavailable", "message" to "توقف Bluetooth أثناء البحث"))
                    }
                }
            }
            override fun onScanFailed(errorCode: Int) {
                handler.post { if (scanner === this) { stopScan(); emit("error", mapOf("code" to "scan_failed", "message" to "فشل البحث BLE ($errorCode)")) } }
            }
        }
        scanner = callback
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(UUID.fromString(SERVICE))).build()
        adapter.bluetoothLeScanner?.startScan(listOf(filter), ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback)
            ?: throw IllegalStateException("Scanner unavailable")
        handler.postDelayed(scanTimeout, 10000)
    }

    private fun stopScan() {
        handler.removeCallbacks(scanTimeout); val previous = scanner; scanner = null
        if (previous != null) {
            try { adapter().bluetoothLeScanner?.stopScan(previous) }
            catch (_: SecurityException) { emit("error", mapOf("code" to "permissions_revoked", "message" to "أُلغيت صلاحية Bluetooth أثناء البحث")) }
            catch (_: IllegalStateException) { emit("error", mapOf("code" to "bluetooth_unavailable", "message" to "Bluetooth غير متاح لإيقاف البحث")) }
        }
    }

    private fun callback(linkEpoch: Int) = object : BluetoothGattCallback() {
        private fun main(source: BluetoothGatt, action: () -> Unit) {
            handler.post {
                if (source !== gatt || linkEpoch != epoch || disposed) return@post
                try { action() }
                catch (_: SecurityException) { failLink("permissions_revoked", "أُلغيت صلاحيات Bluetooth") }
                catch (_: IllegalStateException) { failLink("gatt_unavailable", "توقف GATT أثناء العملية") }
            }
        }
        override fun onConnectionStateChange(source: BluetoothGatt, status: Int, newState: Int) = main(source) {
            if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) {
                failLink("link_lost", "انقطع BLE ($status)")
            } else if (newState == BluetoothProfile.STATE_CONNECTED && !source.discoverServices()) {
                failLink("service_discovery_failed", "تعذر بدء اكتشاف الخدمة")
            }
        }
        override fun onServicesDiscovered(source: BluetoothGatt, status: Int) = main(source) {
            val service = source.getService(UUID.fromString(SERVICE))
            command = service?.getCharacteristic(UUID.fromString(COMMAND))
            notifications = service?.getCharacteristic(UUID.fromString(EVENT))
            if (status != BluetoothGatt.GATT_SUCCESS || command == null || notifications?.getDescriptor(CCCD) == null) {
                failLink("service_missing", "الجهاز لا يوفّر بروتوكول SmartRoom الصحيح")
            } else if (!source.requestMtu(247)) { subscribe() }
        }
        override fun onMtuChanged(source: BluetoothGatt, negotiated: Int, status: Int) = main(source) {
            mtu = if (status == BluetoothGatt.GATT_SUCCESS) negotiated.coerceIn(23, 517) else 23
            subscribe()
        }
        override fun onDescriptorWrite(source: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) = main(source) {
            if (descriptor.uuid != CCCD || ready) return@main
            if (status != BluetoothGatt.GATT_SUCCESS) { failLink("pairing_or_subscription_failed", "لم يكتمل الاقتران الآمن / الإشعارات ($status)"); return@main }
            ready = true; handler.removeCallbacks(connectTimeout)
            val pending = connectPending; connectPending = null; pending?.success(null); emit("ready", mapOf("mtu" to mtu))
        }
        override fun onCharacteristicWrite(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) = main(source) {
            if (characteristic.uuid != UUID.fromString(COMMAND) || writePending == null) return@main
            if (status != BluetoothGatt.GATT_SUCCESS) { failLink("write_rejected", "رُفض تأكيد نقل GATT ($status)"); return@main }
            writeOffset += chunkLength
            if (writeOffset == writeBytes.size) {
                handler.removeCallbacks(writeTimeout); val pending = writePending; writePending = null
                writeBytes.fill(0); writeBytes = ByteArray(0); pending?.success(null)
            } else writeChunk()
        }
        override fun onCharacteristicChanged(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            if (value.size > 514) return
            val detached = value.copyOf()
            main(source) { if (characteristic.uuid == UUID.fromString(EVENT)) emit("bytes", mapOf("bytes" to detached)) }
        }
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < 33) {
                val value = characteristic.value?.copyOf() ?: return
                main(source) { if (characteristic.uuid == UUID.fromString(EVENT) && value.size <= 514) emit("bytes", mapOf("bytes" to value)) }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun subscribe() {
        if (ready) return
        val source = gatt ?: return; val event = notifications ?: return
        val descriptor = event.getDescriptor(CCCD) ?: return
        if (!source.setCharacteristicNotification(event, true)) { failLink("subscription_failed", "تعذر تفعيل الإشعارات"); return }
        val accepted = if (Build.VERSION.SDK_INT >= 33) source.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == BluetoothStatusCodes.SUCCESS
        else { descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE; source.writeDescriptor(descriptor) }
        if (!accepted) failLink("subscription_failed", "تعذر إرسال طلب الإشعارات الآمن")
    }

    @Suppress("DEPRECATION")
    private fun writeChunk() {
        val source = gatt ?: return; val target = command ?: return
        chunkLength = min(min(mtu - 3, 160), writeBytes.size - writeOffset)
        val chunk = writeBytes.copyOfRange(writeOffset, writeOffset + chunkLength)
        val accepted = if (Build.VERSION.SDK_INT >= 33) source.writeCharacteristic(target, chunk, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothStatusCodes.SUCCESS
        else { target.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT; target.value = chunk; source.writeCharacteristic(target) }
        if (!accepted) failLink("write_not_started", "لم يبدأ تأكيد النقل؛ لا تُعد المحاولة تلقائيًا")
    }

    private fun failLink(code: String, message: String) {
        emit("error", mapOf("code" to code, "message" to message))
        closeLink(code)
    }
    private fun closeLink(reason: String) {
        handler.removeCallbacks(connectTimeout); handler.removeCallbacks(writeTimeout)
        val source = gatt; gatt = null; command = null; notifications = null; ready = false
        val connecting = connectPending; connectPending = null; connecting?.error(reason, "Bluetooth link closed", null)
        val writing = writePending; writePending = null; writing?.error(reason, "Write result unknown; link closed", null)
        writeBytes.fill(0); writeBytes = ByteArray(0); writeOffset = 0
        if (source != null) {
            try { source.disconnect() } catch (_: SecurityException) { emit("error", mapOf("code" to "permissions_revoked", "message" to "تعذر طلب الفصل بعد سحب الصلاحية")) }
            catch (_: IllegalStateException) { emit("error", mapOf("code" to "gatt_unavailable", "message" to "تعذر طلب فصل GATT")) }
            try { source.close() } catch (_: SecurityException) { emit("error", mapOf("code" to "permissions_revoked", "message" to "تعذر تأكيد إغلاق GATT بعد سحب الصلاحية")) }
            catch (_: IllegalStateException) { emit("error", mapOf("code" to "gatt_unavailable", "message" to "تعذر تأكيد إغلاق GATT")) }
            emit("disconnected", mapOf("reason" to reason))
        }
    }
    fun stopForBackground() { stopScan(); closeLink("app_background") }
    fun dispose() {
        if (disposed) return
        stopForBackground(); permissionsPending?.error("closed", "Activity closed", null); permissionsPending = null
        disposed = true; handler.removeCallbacksAndMessages(null); sink = null
        methods.setMethodCallHandler(null); events.setStreamHandler(null)
    }
}

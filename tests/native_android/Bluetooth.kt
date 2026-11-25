package android.bluetooth

import android.app.Activity
import android.bluetooth.le.BluetoothLeScanner
import java.util.UUID

object BluetoothProfile { const val STATE_CONNECTED = 2; const val STATE_DISCONNECTED = 0 }
object BluetoothStatusCodes { const val SUCCESS = 0 }
class BluetoothManager(val adapter: BluetoothAdapter?)
class BluetoothAdapter(var isEnabled: Boolean = true) { val bluetoothLeScanner: BluetoothLeScanner? = BluetoothLeScanner() }
class BluetoothDevice(private val visibleAddress: String) {
    companion object { const val TRANSPORT_LE = 2 }
    var addressFailure: RuntimeException? = null
    val address: String get() { addressFailure?.let { throw it }; return visibleAddress }
    var failure: RuntimeException? = null
    var connects = 0
    var lastGatt: BluetoothGatt? = null
    fun connectGatt(activity: Activity, autoConnect: Boolean, callback: BluetoothGattCallback, transport: Int): BluetoothGatt? {
        ++connects; failure?.let { throw it }
        return BluetoothGatt(callback).also { lastGatt = it }
    }
}
open class BluetoothGattCallback {
    open fun onConnectionStateChange(source: BluetoothGatt, status: Int, newState: Int) {}
    open fun onServicesDiscovered(source: BluetoothGatt, status: Int) {}
    open fun onMtuChanged(source: BluetoothGatt, negotiated: Int, status: Int) {}
    open fun onDescriptorWrite(source: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {}
    open fun onCharacteristicWrite(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {}
    open fun onCharacteristicChanged(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {}
    open fun onCharacteristicChanged(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {}
}
class BluetoothGattDescriptor(val uuid: UUID) {
    companion object { val ENABLE_NOTIFICATION_VALUE = byteArrayOf(1, 0) }
    var value: ByteArray? = null
}
class BluetoothGattCharacteristic(val uuid: UUID) {
    companion object { const val WRITE_TYPE_DEFAULT = 2 }
    var writeType = 2
    var value: ByteArray? = null
    val descriptors = mutableMapOf<UUID, BluetoothGattDescriptor>()
    fun getDescriptor(uuid: UUID): BluetoothGattDescriptor? = descriptors[uuid]
}
class BluetoothGattService(val uuid: UUID) {
    val characteristics = mutableMapOf<UUID, BluetoothGattCharacteristic>()
    fun getCharacteristic(uuid: UUID): BluetoothGattCharacteristic? = characteristics[uuid]
}
class BluetoothGatt(val callback: BluetoothGattCallback) {
    companion object { const val GATT_SUCCESS = 0 }
    val services = mutableMapOf<UUID, BluetoothGattService>()
    val chunks = mutableListOf<ByteArray>()
    var descriptor: BluetoothGattDescriptor? = null
    var disconnects = 0
    var closes = 0
    var writeFailure: RuntimeException? = null
    var closeFailure: RuntimeException? = null
    fun getService(uuid: UUID): BluetoothGattService? = services[uuid]
    fun discoverServices(): Boolean = true
    fun requestMtu(value: Int): Boolean = true
    fun setCharacteristicNotification(characteristic: BluetoothGattCharacteristic, enabled: Boolean): Boolean = true
    fun writeDescriptor(descriptor: BluetoothGattDescriptor, value: ByteArray): Int {
        this.descriptor = descriptor; return 0
    }
    fun writeDescriptor(descriptor: BluetoothGattDescriptor): Boolean { this.descriptor = descriptor; return true }
    fun writeCharacteristic(characteristic: BluetoothGattCharacteristic, value: ByteArray, kind: Int): Int {
        writeFailure?.let { throw it }; chunks.add(value.copyOf()); return 0
    }
    fun writeCharacteristic(characteristic: BluetoothGattCharacteristic): Boolean {
        writeFailure?.let { throw it }; chunks.add(characteristic.value!!.copyOf()); return true
    }
    fun disconnect() { ++disconnects }
    fun close() { ++closes; closeFailure?.let { throw it } }
}

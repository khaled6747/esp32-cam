package android.bluetooth.le

import android.bluetooth.BluetoothDevice
import android.os.ParcelUuid

open class ScanCallback {
    open fun onScanResult(callbackType: Int, result: ScanResult) {}
    open fun onScanFailed(errorCode: Int) {}
}
class ScanRecord(val serviceUuids: List<ParcelUuid>, val deviceName: String? = "SmartRoom")
class ScanResult(val device: BluetoothDevice, val scanRecord: ScanRecord?, val rssi: Int = -55)
class ScanFilter(val service: ParcelUuid?) {
    class Builder {
        private var service: ParcelUuid? = null
        fun setServiceUuid(value: ParcelUuid): Builder { service = value; return this }
        fun build() = ScanFilter(service)
    }
}
class ScanSettings {
    companion object { const val SCAN_MODE_LOW_LATENCY = 2 }
    class Builder {
        fun setScanMode(value: Int) = this
        fun build() = ScanSettings()
    }
}
class BluetoothLeScanner {
    var callback: ScanCallback? = null
    var starts = 0
    var stops = 0
    var filters: List<ScanFilter> = emptyList()
    fun startScan(filters: List<ScanFilter>, settings: ScanSettings, callback: ScanCallback) {
        ++starts; this.filters = filters; this.callback = callback
    }
    fun stopScan(callback: ScanCallback) { ++stops; if (this.callback === callback) this.callback = null }
}

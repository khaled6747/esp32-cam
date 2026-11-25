package android.location

class LocationManager {
    companion object { const val GPS_PROVIDER = "gps"; const val NETWORK_PROVIDER = "network" }
    var enabled = true
    fun isProviderEnabled(provider: String): Boolean = enabled
}

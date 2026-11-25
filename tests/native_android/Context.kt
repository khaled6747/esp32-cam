package android.content

open class Context {
    companion object {
        const val BLUETOOTH_SERVICE = "bluetooth"
        const val LOCATION_SERVICE = "location"
    }
    val services = mutableMapOf<String, Any>()
    open fun getSystemService(name: String): Any? = services[name]
}

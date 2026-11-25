package android.app

import android.content.Context

open class Activity : Context() {
    var granted = true
    var permissionFailure: RuntimeException? = null
    var permissionRequests = 0
    fun checkSelfPermission(permission: String): Int = if (granted) 0 else -1
    fun requestPermissions(permissions: Array<String>, code: Int) {
        ++permissionRequests
        permissionFailure?.let { throw it }
    }
}

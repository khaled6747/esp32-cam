package io.flutter.plugin.common

interface BinaryMessenger
class MethodCall(val method: String, val arguments: Any? = null) {
    @Suppress("UNCHECKED_CAST")
    fun <T> argument(key: String): T? = (arguments as? Map<String, Any?>)?.get(key) as T?
}
class MethodChannel(messenger: BinaryMessenger, name: String) {
    interface Result {
        fun success(value: Any?)
        fun error(code: String, message: String?, details: Any?)
        fun notImplemented()
    }
    interface MethodCallHandler { fun onMethodCall(call: MethodCall, result: Result) }
    fun setMethodCallHandler(handler: MethodCallHandler?) {}
}
class EventChannel(messenger: BinaryMessenger, name: String) {
    interface EventSink { fun success(value: Any?) }
    interface StreamHandler {
        fun onListen(arguments: Any?, eventSink: EventSink)
        fun onCancel(arguments: Any?)
    }
    fun setStreamHandler(handler: StreamHandler?) {}
}

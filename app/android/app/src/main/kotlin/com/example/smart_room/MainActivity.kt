package com.example.smart_room

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var ble: RoomBle? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ble = RoomBle(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        ble?.permissionResult(code, results)
    }

    override fun onStop() {
        // Do not use onPause: Android's system pairing/permission dialogs may
        // temporarily pause the Activity while it is still visible.
        ble?.stopForBackground()
        super.onStop()
    }

    override fun onDestroy() {
        ble?.dispose()
        ble = null
        super.onDestroy()
    }
}

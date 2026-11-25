import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';
import 'protocol.dart';

class RoomDevice {
  const RoomDevice(this.id, this.name, this.rssi);
  final String id, name;
  final int rssi;
}

abstract interface class BleTransport {
  Stream<Map<String, Object?>> get events;
  Future<void> permissions();
  Future<void> scan();
  Future<void> stopScan();
  Future<void> connect(String id, int epoch);
  Future<void> write(Uint8List bytes, int epoch);
  Future<void> disconnect();
  Future<void> close();
}

class AndroidBleTransport implements BleTransport {
  AndroidBleTransport({MethodChannel? methodChannel, EventChannel? eventChannel})
      : _methods = methodChannel ?? const MethodChannel('smart_room/ble'),
        _events = eventChannel ?? const EventChannel('smart_room/ble_events');
  final MethodChannel _methods;
  final EventChannel _events;
  @override
  Stream<Map<String, Object?>> get events => _events.receiveBroadcastStream().map((value) {
    if (value is! Map) { throw const FormatException('Invalid native BLE event'); }
    final event = Map<String, Object?>.from(value);
    readString(event, 'kind', 32);
    readInt(event, 'epoch', 0, 2147483647);
    return event;
  });
  @override
  Future<void> permissions() => _methods.invokeMethod<void>('permissions');
  @override
  Future<void> scan() => _methods.invokeMethod<void>('scan');
  @override
  Future<void> stopScan() => _methods.invokeMethod<void>('stopScan');
  @override
  Future<void> connect(String id, int epoch) => _methods.invokeMethod<void>('connect', {'id': id, 'epoch': epoch});
  @override
  Future<void> write(Uint8List bytes, int epoch) => _methods.invokeMethod<void>('write', {'bytes': bytes, 'epoch': epoch});
  @override
  Future<void> disconnect() => _methods.invokeMethod<void>('disconnect');
  @override
  Future<void> close() => _methods.invokeMethod<void>('dispose');
}

abstract interface class OwnerVault {
  Future<Uint8List?> read(String device);
  Future<void> write(String device, Uint8List key);
}

class SecureOwnerVault implements OwnerVault {
  SecureOwnerVault({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false, migrateOnAlgorithmChange: false,
      migrateWithBackup: false, storageNamespace: 'smart_room_owner_v1'));
  final FlutterSecureStorage _storage;
  String _name(String device) {
    if (!validHex(device, 6)) { throw ArgumentError('Invalid owner device ID'); }
    return 'owner_$device';
  }
  @override
  Future<Uint8List?> read(String device) async {
    final value = await _storage.read(key: _name(device));
    return value == null ? null : decodeKey(value);
  }
  @override
  Future<void> write(String device, Uint8List key) async {
    // Preserve the key before claiming the MCU. A lost claim acknowledgment
    // must not leave an owner key present only in process memory.
    await _storage.write(key: _name(device), value: encodeKey(key));
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:smart_room/ble_transport.dart';
import 'package:smart_room/models.dart';

const fakeSuccessCodes = {'set_mode': 'policy_saved', 'lights': 'requested_no_feedback',
  'send_slot': 'queued', 'ac': 'queued', 'configure': 'configuration_saved',
  'learn_start': 'press_original_remote', 'learn_cancel': 'learning_cancelled',
  'erase_slot': 'slot_erased', 'storage_init': 'storage_ready'};

const fakeDeviceId = 'f024f91080a4';
const fakeSession = '000102030405060708090a0b0c0d0e0f';
const fakeChallenge = '101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f';
const fakeDevice = RoomDevice('F0:24:F9:10:80:A6', 'SmartRoom', -55);

class MemoryVault implements OwnerVault {
  final values = <String, Uint8List>{};
  bool failWrite = false;
  Completer<void>? readGate;
  final actions = <String>[];
  @override
  Future<Uint8List?> read(String device) async {
    final gate = readGate; readGate = null;
    await gate?.future;
    return values[device] == null ? null : Uint8List.fromList(values[device]!);
  }
  @override
  Future<void> write(String device, Uint8List key) async {
    if (failWrite) { throw const FormatException('inert storage failure'); }
    actions.add('persist'); values[device] = Uint8List.fromList(key);
  }
}

Map<String, Object?> fakeProfile(int slot) => {'slot': slot, 'label': 'COOL 23 HIGH',
  'temperature': 23, 'fan': 3, 'mode': 1, 'power': true, 'sleep': false,
  'hz': 38000, 'pulses': 67};

Map<String, Object?> fakeStatus({int id = 0, int people = 2, bool hardware = true,
  String boot = '0011223344556677', Map<String, Object?> change = const {}}) => {
  'v': 1, 'type': 'status', 'id': id, 'device': fakeDeviceId, 'boot': boot,
  'people': people, 'presence': people < 0 ? 'unknown' : people == 0 ? 'empty' : 'occupied',
  'mode': 'auto', 'scene': 'quiet', 'lights': true, 'requested_slot': 1, 'sent_slot': 1,
  'ir_result': hardware ? 'pulses_sent_unconfirmed' : 'disabled',
  'relay_enabled': hardware, 'ir_rx_enabled': hardware, 'ir_tx_enabled': hardware,
  'oled_ready': hardware, 'camera_ready': true, 'storage_ready': true,
  'override_ms': 0, 'empty_remaining_ms': 0, 'learn_slot': 0,
  'config': const RuleConfig().toJson(), ...change,
};

class FakeBle implements BleTransport {
  final stream = StreamController<Map<String, Object?>>.broadcast(sync: true);
  final commands = <Map<String, Object?>>[];
  bool owned = true, claimOpen = true, autoAuth = true, hardware = true;
  int activeEpoch = 0, disconnects = 0, scans = 0, stopScans = 0, people = 2;
  String? rejectedOp;
  String? authSuccessCode;
  String rejection = 'unlearned_state';
  List<Map<String, Object?>> profileItems = [fakeProfile(7)];
  Completer<void>? connectGate;
  Completer<void>? permissionGate;
  bool failStopScan = false;
  int closes = 0;
  void Function(Map<String, Object?>)? observeWrite;
  @override
  Stream<Map<String, Object?>> get events => stream.stream;
  @override
  Future<void> permissions() async {
    final gate = permissionGate; permissionGate = null;
    await gate?.future;
  }
  @override
  Future<void> scan() async { ++scans; }
  @override
  Future<void> stopScan() async {
    ++stopScans;
    if (failStopScan) { failStopScan = false; throw PlatformException(code: 'permissions_revoked'); }
  }
  @override
  Future<void> connect(String id, int epoch) async { activeEpoch = epoch; await connectGate?.future; }
  @override
  Future<void> write(Uint8List bytes, int epoch) async {
    final command = Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
    commands.add(command); observeWrite?.call(command);
    final op = command['op'], id = command['id'];
    if (op == 'hello') {
      emit({'v': 1, 'type': 'hello', 'id': id, 'device': fakeDeviceId,
        'session': fakeSession, 'challenge': fakeChallenge, 'owned': owned, 'claim_open': claimOpen});
    } else if (op == 'auth' && !autoAuth) { return; }
    else if (op == 'profiles') { emit({'v': 1, 'type': 'profiles', 'id': id, 'items': profileItems}); }
    else if (op == 'status') { emit(fakeStatus(id: id! as int, people: people, hardware: hardware)); }
    else {
      if (op == 'claim' && rejectedOp != 'claim') { owned = true; }
      emit({'v': 1, 'type': 'ack', 'id': id, 'ok': op != rejectedOp,
        'code': op == rejectedOp ? rejection : op == 'auth' ? (authSuccessCode ?? 'authenticated')
          : op == 'claim' ? 'claimed' : fakeSuccessCodes[op] ?? 'unknown_operation_or_fields'});
    }
  }
  void emit(Map<String, Object?> event, {int? epoch}) {
    final bytes = [...utf8.encode(jsonEncode(event)), 10];
    for (var offset = 0; offset < bytes.length; offset += 160) {
      final end = offset + 160 < bytes.length ? offset + 160 : bytes.length;
      stream.add({'kind': 'bytes', 'epoch': epoch ?? activeEpoch,
        'bytes': Uint8List.fromList(bytes.sublist(offset, end))});
    }
  }
  @override
  Future<void> disconnect() async { ++disconnects; }
  @override
  Future<void> close() async { ++closes; await stream.close(); }
}

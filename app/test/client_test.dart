import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_room/models.dart';
import 'package:smart_room/protocol.dart';
import 'package:smart_room/room_client.dart';
import 'fakes.dart';

void main() {
  late FakeBle ble;
  late MemoryVault vault;
  late RoomClient client;
  var now = 0;
  setUp(() {
    ble = FakeBle(); vault = MemoryVault();
    vault.values[fakeDeviceId] = Uint8List.fromList(List.generate(32, (i) => i));
    now = 0;
    client = RoomClient(transport: ble, vault: vault, clock: () => now,
      newKey: () => Uint8List.fromList(List.filled(32, 22)), startTimers: false,
      requestTimeout: const Duration(milliseconds: 100));
  });
  tearDown(() async { await client.close(); client.dispose(); });

  test('link subscription alone never authorizes control; owner proof is needed', () async {
    ble.autoAuth = false;
    final connecting = client.connect(fakeDevice);
    await Future<void>.delayed(Duration.zero);
    expect(client.authenticated, isFalse); expect(client.canControl, isFalse);
    final auth = ble.commands.singleWhere((c) => c['op'] == 'auth');
    expect(auth['proof'], '453984446bfe4f6b72ee762c6c8ed4ee53a2ad939576d11e3a33a606988bb9a2');
    ble.emit({'v': 1, 'type': 'ack', 'id': auth['id'], 'ok': true, 'code': 'authenticated'});
    expect(await connecting, isTrue);
    expect(client.authenticated, isTrue); expect(client.canControl, isTrue);
    expect(client.currentPeople, 2);
  });
  test('owned unit with no local key remains locked and never tries claim', () async {
    vault.values.clear(); expect(await client.connect(fakeDevice), isFalse);
    expect(client.phase, RoomPhase.locked); expect(client.canControl, isFalse);
    expect(ble.commands.map((c) => c['op']), ['hello']);
  });
  test('unowned unit requires explicit claim; key is persisted before write', () async {
    ble.owned = false; vault.values.clear();
    expect(await client.connect(fakeDevice), isTrue);
    expect(client.phase, RoomPhase.needsClaim); expect(client.canControl, isFalse);
    expect(ble.commands.any((c) => c['op'] == 'claim'), isFalse);
    ble.observeWrite = (command) {
      if (command['op'] == 'claim') {
        expect(vault.actions, ['persist']);
        expect(encodeKey(vault.values[fakeDeviceId]!), command['key']);
      }
    };
    expect(await client.claim(), isTrue); expect(client.canControl, isTrue);
  });
  test('secure storage failure prohibits transmitting a claim', () async {
    ble.owned = false; vault.values.clear(); vault.failWrite = true;
    await client.connect(fakeDevice); expect(await client.claim(), isFalse);
    expect(ble.commands.any((c) => c['op'] == 'claim'), isFalse);
    expect(client.authenticated, isFalse); expect(ble.disconnects, 1);
  });
  test('closed claim window never generates or persists a key', () async {
    ble.owned = false; ble.claimOpen = false; vault.values.clear();
    await client.connect(fakeDevice); expect(await client.claim(), isFalse);
    expect(vault.values, isEmpty); expect(ble.commands, hasLength(1));
  });
  test('auth denial closes link; no profile/status/control requests follow', () async {
    ble.rejectedOp = 'auth'; ble.rejection = 'bad_proof';
    expect(await client.connect(fakeDevice), isFalse);
    expect(client.authenticated, isFalse); expect(ble.disconnects, 1);
    expect(ble.commands.map((c) => c['op']), ['hello', 'auth']);
  });
  test('generic positive ack is not a specific authentication success', () async {
    ble.authSuccessCode = 'queued';
    expect(await client.connect(fakeDevice), isFalse);
    expect(client.authenticated, isFalse);
    expect(ble.commands.map((c) => c['op']), ['hello', 'auth']);
  });
  test('unknown occupancy stays null; it is never rendered as zero', () async {
    ble.people = -1; await client.connect(fakeDevice);
    expect(client.currentPeople, isNull); expect(client.snapshot!.people, -1);
    expect(client.canControl, isTrue); // Manual control is allowed with fresh device status.
  });
  test('stale device status disables controls without a synthetic current count', () async {
    await client.connect(fakeDevice); final writes = ble.commands.length;
    now = 3501; client.checkFreshness();
    expect(client.currentPeople, isNull); expect(client.canControl, isFalse);
    expect(await client.lights(false, 60000), isFalse); expect(ble.commands, hasLength(writes));
    ble.emit(fakeStatus(people: 4)); expect(client.currentPeople, 4); expect(client.canControl, isTrue);
  });
  test('explicit read-only refresh can recover stale status without a control write', () async {
    await client.connect(fakeDevice); now = 3501; client.checkFreshness();
    ble.people = 5; final before = ble.commands.length;
    expect(await client.refresh(), isTrue);
    expect(ble.commands.skip(before).map((c) => c['op']), ['profiles', 'status']);
    expect(client.canControl, isTrue); expect(client.currentPeople, 5);
  });
  test('disconnect also stops the owned scan', () async {
    await client.scan(); expect(client.phase, RoomPhase.scanning);
    await client.disconnect(); expect(ble.stopScans, 1); expect(client.phase, RoomPhase.idle);
  });
  test('scan stop failure still attempts disconnect and reports the error', () async {
    await client.connect(fakeDevice); ble.failStopScan = true;
    await client.disconnect();
    expect(ble.disconnects, 1); expect(client.authenticated, isFalse);
    expect(client.lastError, contains('Bluetooth'));
  });
  test('close releases the native link even if stopping scan fails', () async {
    final ownedBle = FakeBle();
    final ownedClient = RoomClient(transport: ownedBle, vault: vault, startTimers: false);
    try {
      await ownedClient.connect(fakeDevice); ownedBle.failStopScan = true;
      await expectLater(ownedClient.close(), throwsA(isA<PlatformException>()));
      expect(ownedBle.disconnects, 1); expect(ownedBle.closes, 1);
      expect(ownedClient.currentPeople, isNull);
    } finally { ownedClient.dispose(); await ownedBle.stream.close(); }
  });
  test('obsolete permission denial cannot overwrite a replacement ready connection', () async {
    final gate = Completer<void>(); ble.permissionGate = gate;
    final scan = client.scan(); await Future<void>.delayed(Duration.zero);
    await client.disconnect(); expect(await client.connect(fakeDevice), isTrue);
    gate.completeError(PlatformException(code: 'permissions_denied'));
    expect(await scan, isFalse); expect(client.phase, RoomPhase.ready);
    expect(client.canControl, isTrue); expect(client.lastError, isNull);
  });
  test('old storage read cannot authenticate the replacement connection', () async {
    final gate = Completer<void>(); vault.readGate = gate;
    final first = client.connect(fakeDevice);
    await Future<void>.delayed(Duration.zero);
    await client.disconnect(); ble.autoAuth = false;
    final replacement = client.connect(fakeDevice);
    await Future<void>.delayed(Duration.zero);
    final auth = ble.commands.singleWhere((c) => c['op'] == 'auth');
    ble.emit({'v': 1, 'type': 'ack', 'id': auth['id'], 'ok': true, 'code': 'authenticated'});
    expect(await replacement, isTrue);
    final before = ble.commands.length; gate.complete();
    expect(await first, isFalse); expect(ble.commands, hasLength(before));
    expect(client.canControl, isTrue);
  });
  test('old link notification cannot overwrite current device count', () async {
    await client.connect(fakeDevice); final old = client.epoch;
    await client.disconnect(); expect(client.currentPeople, isNull);
    await client.connect(fakeDevice); ble.emit(fakeStatus(people: 99), epoch: old);
    expect(client.currentPeople, 2);
  });
  test('new MCU boot invalidates authentication and old snapshots', () async {
    await client.connect(fakeDevice); ble.emit(fakeStatus(people: 0, boot: '8888888888888888'));
    await Future<void>.delayed(Duration.zero);
    expect(client.authenticated, isFalse); expect(client.currentPeople, isNull); expect(ble.disconnects, 1);
  });
  test('unlearned full AC state never falls back to another temperature', () async {
    await client.connect(fakeDevice); final writes = ble.commands.length;
    expect(await client.sendAc(IrState(temperature: 24, fan: 3), 60000), isFalse);
    expect(ble.commands, hasLength(writes)); expect(client.lastError, contains('غير متعلّمة'));
    expect(await client.sendAc(IrState(temperature: 23, fan: 3), 60000), isTrue);
    expect(ble.commands.where((c) => c['op'] == 'ac').single['temperature'], 23);
    expect(client.lastMessage, contains('ليس تأكيدًا'));
  });
  test('disabled relay and IR reject hardware commands without transmitting', () async {
    ble.hardware = false; await client.connect(fakeDevice); final writes = ble.commands.length;
    expect(await client.lights(true, 60000), isFalse);
    expect(await client.sendAc(IrState(temperature: 23, fan: 3), 60000), isFalse);
    expect(await client.learn(Profile(slot: 1, label: 'TEST', state: IrState())), isFalse);
    expect(ble.commands, hasLength(writes));
  });
  test('simultaneous app connects are rejected without replacing current attempt', () async {
    ble.connectGate = Completer<void>(); final first = client.connect(fakeDevice);
    await Future<void>.delayed(Duration.zero);
    expect(await client.connect(fakeDevice), isFalse);
    expect(client.phase, RoomPhase.connecting);
    ble.connectGate!.complete(); expect(await first, isTrue);
  });
  test('request timeout closes link once, no automatic write retry', () async {
    ble.autoAuth = false; expect(await client.connect(fakeDevice), isFalse);
    expect(ble.commands.map((c) => c['op']), ['hello', 'auth']);
    expect(ble.disconnects, 1); expect(client.lastError, contains('غير معروفة'));
  });
  test('typed peer error cannot masquerade as success', () async {
    await client.connect(fakeDevice); ble.rejectedOp = 'lights'; ble.rejection = 'hardware_disabled';
    expect(await client.lights(false, 60000), isFalse);
    expect(client.canControl, isTrue); expect(client.lastError, contains('معطّل'));
  });
  test('inconsistent peer occupancy closes link rather than treating it as empty', () async {
    await client.connect(fakeDevice); ble.emit(fakeStatus(people: 0, change: {'presence': 'occupied'}));
    await Future<void>.delayed(Duration.zero);
    expect(client.authenticated, isFalse); expect(client.currentPeople, isNull);
  });
  test('erase requires a human confirmation and request ids are increasing', () async {
    await client.connect(fakeDevice); final before = ble.commands.length;
    expect(await client.eraseSlot(7, confirmed: false), isFalse); expect(ble.commands, hasLength(before));
    expect(await client.eraseSlot(7, confirmed: true), isTrue);
    final ids = ble.commands.map((c) => c['id']! as int).toList();
    expect(ids, List.generate(ids.length, (i) => i + 1));
  });
}

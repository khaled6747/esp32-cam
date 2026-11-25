// Uses actual encoders/models. The fixed sample key is an inert public oracle,
// not phone storage, a generated owner key, a BLE link or appliance feedback.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:smart_room/models.dart';
import 'package:smart_room/protocol.dart';

String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
List<int> unhex(String value) {
  if (value.length > 8190 || value.isEmpty || value.length.isOdd || !RegExp(r'^[0-9a-f]+$').hasMatch(value)) {
    throw const FormatException('Fixture byte bound');
  }
  return List.generate(value.length ~/ 2, (i) => int.parse(value.substring(i * 2, i * 2 + 2), radix: 16));
}

void emitCommands() {
  const session = '000102030405060708090a0b0c0d0e0f';
  const challenge = '101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f';
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final proof = ownerProof(key, 'f024f91080a4', session, challenge);
  final commands = <String, String>{};
  void command(String name, String op, [Map<String, Object?> payload = const {}, int id = 3]) {
    commands[name] = hex(encodeCommand(id, op, session: op == 'hello' ? null : session, payload: payload));
  }
  command('hello', 'hello', {}, 1);
  command('auth', 'auth', {'proof': proof}, 2);
  command('claim', 'claim', {'key': encodeKey(key)}, 2);
  command('status', 'status'); command('profiles', 'profiles');
  command('set_auto', 'set_mode', {'mode': 'auto', 'lease_ms': 0});
  command('set_manual', 'set_mode', {'mode': 'manual', 'lease_ms': 60000});
  command('set_sleep', 'set_mode', {'mode': 'sleep', 'lease_ms': 60000});
  command('lights', 'lights', {'on': true, 'lease_ms': 60000});
  command('send_slot', 'send_slot', {'slot': 1, 'lease_ms': 60000});
  final state = IrState();
  command('ac', 'ac', {...state.toJson(), 'lease_ms': 60000});
  command('configure', 'configure', const RuleConfig().toJson());
  command('learn_start', 'learn_start', {'slot': 1, 'label': 'هادئ 😀', ...state.toJson(), 'hz': 38000});
  command('learn_cancel', 'learn_cancel', {}, 4);
  command('erase_slot', 'erase_slot', {'slot': 1, 'confirm': true});
  command('storage_init', 'storage_init', {'confirm': 'INIT_UNMOUNTED_STORAGE'});
  stdout.writeln(jsonEncode({'commands': commands, 'proof': proof, 'state': state.toJson(),
    'config': const RuleConfig().toJson(), 'inert_public_key': true}));
}

Future<void> verifyEvents() async {
  final input = await stdin.fold<List<int>>(<int>[], (all, chunk) {
    if (all.length + chunk.length > 1048576) { throw const FormatException('Fixture input size'); }
    all.addAll(chunk); return all;
  });
  final rows = jsonDecode(utf8.decode(input));
  if (rows is! List || rows.isEmpty || rows.length > 512) { throw const FormatException('Fixture event count'); }
  var valid = 0, negative = 0;
  for (final row in rows) {
    if (row is! Map || row['valid'] is! bool || row['wire'] is! String || row['name'] is! String) {
      throw const FormatException('Fixture event schema');
    }
    final bytes = unhex(row['wire'] as String), expected = row['valid'] as bool;
    var accepted = false;
    try {
      final event = parseEvent(bytes);
      switch (event['type']) {
        case 'status': RoomSnapshot.fromJson(event);
        case 'profiles':
          if (event['items'] is! List) { throw const FormatException('Profile list'); }
          for (final item in event['items']! as List) { Profile.fromJson(Map<String, Object?>.from(item as Map)); }
        case 'hello':
          if (!validHex(readString(event, 'device', 12), 6) || !validHex(readString(event, 'session', 32), 16)) {
            throw const FormatException('Hello identity');
          }
          if (event.containsKey('challenge') && (!validHex(readString(event, 'challenge', 64), 32)
              || event['owned'] is! bool || event['claim_open'] is! bool)) { throw const FormatException('BLE hello'); }
        case 'ack':
          readInt(event, 'id', 0, 2147483647); readBool(event, 'ok'); readString(event, 'code', 64);
          if (event.containsKey('session') && !validHex(readString(event, 'session', 32), 16)) {
            throw const FormatException('USB ack session');
          }
        default: throw const FormatException('Unexpected fixture event');
      }
      final lines = JsonLines(); final delivered = <Map<String, Object?>>[];
      final framed = [...bytes, 10];
      for (var offset = 0; offset < framed.length;) {
        final end = (offset + 7).clamp(0, framed.length);
        delivered.addAll(lines.add(framed.sublist(offset, end))); offset = end;
      }
      if (delivered.length != 1 || lines.errors != 0) { throw StateError('Fragmented valid event was lost'); }
      accepted = true;
    } on FormatException { accepted = false; }
    if (accepted != expected) { throw StateError('Cross-language event mismatch: ${row['name']}'); }
    if (expected) { ++valid; } else { ++negative; }
  }
  stdout.writeln(jsonEncode({'valid_events': valid, 'negative_events': negative, 'checks': valid + negative}));
}

Future<void> main(List<String> args) async {
  if (args.length != 1) { throw ArgumentError('emit or verify only'); }
  if (args.single == 'emit') { emitCommands(); }
  else if (args.single == 'verify') { await verifyEvents(); }
  else { throw ArgumentError('Unknown fixture operation'); }
}

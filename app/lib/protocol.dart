import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

const serviceUuid = '6f875ca0-24ad-47e0-a36f-50f38e4d9301';
const commandUuid = '6f875ca0-24ad-47e0-a36f-50f38e4d9302';
const eventUuid = '6f875ca0-24ad-47e0-a36f-50f38e4d9303';

class ProtocolException implements Exception {
  ProtocolException(this.code);
  final String code;
  @override
  String toString() => code;
}

bool validHex(String value, int bytes) => RegExp('^[0-9a-f]{${bytes * 2}}\$').hasMatch(value);
Uint8List decodeKey(String text) {
  if (!validHex(text, 32)) { throw ArgumentError('Malformed owner key'); }
  return Uint8List.fromList(List.generate(32, (i) => int.parse(text.substring(i * 2, i * 2 + 2), radix: 16)));
}
String encodeKey(Uint8List key) {
  if (key.length != 32) { throw ArgumentError('Owner key must have 32 bytes'); }
  return key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
String ownerProof(Uint8List key, String device, String session, String challenge) {
  if (key.length != 32 || !validHex(device, 6) || !validHex(session, 16) || !validHex(challenge, 32)) {
    throw ArgumentError('Invalid authentication context');
  }
  return Hmac(sha256, key).convert(utf8.encode('smart-room/v1|$device|$session|$challenge')).toString();
}
Uint8List encodeCommand(int id, String op, {String? session,
  Map<String, Object?> payload = const {}}) {
  if (id < 1 || id > 2147483647 || !RegExp(r'^[a-z_]{1,24}$').hasMatch(op)
    || (op != 'hello' && (session == null || !validHex(session, 16)))
    || (op == 'hello' && session != null) || payload.length > 28) {
    throw ArgumentError('Invalid command envelope');
  }
  for (final entry in payload.entries) {
    final value = entry.value;
    if (['v', 'id', 'op', 'session'].contains(entry.key) || !RegExp(r'^[a-z][a-z0-9_]{0,23}$').hasMatch(entry.key)
      || !(value is String || value is bool || value is int)
      || (value is int && (value < -2147483648 || value > 4294967295))
      || (value is String && value.runes.any((r) => r == 0 || r >= 0xd800 && r <= 0xdfff))) {
      throw ArgumentError('Commands must contain bounded flat scalar fields');
    }
  }
  final bytes = utf8.encode(jsonEncode({'v': 1, 'id': id, 'op': op,
    'session': ?session, ...payload}));
  if (bytes.length > 768) { throw ArgumentError('Command exceeds 768 UTF8 bytes'); }
  return Uint8List.fromList([...bytes, 10]);
}

void _depthGuard(List<int> bytes) {
  var depth = 0, quoted = false, escaped = false;
  for (final byte in bytes) {
    if (quoted) {
      if (escaped) { escaped = false; }
      else if (byte == 92) { escaped = true; }
      else if (byte == 34) { quoted = false; }
    } else if (byte == 34) { quoted = true; }
    else if (byte == 91 || byte == 123) { if (++depth > 6) { throw const FormatException('Event nesting limit'); } }
    else if (byte == 93 || byte == 125) { if (--depth < 0) { throw const FormatException('Event nesting mismatch'); } }
  }
  if (depth != 0 || quoted) { throw const FormatException('Incomplete event'); }
}
class _Keys {
  _Keys(bool object) : keys = object ? <String>{} : null;
  final Set<String>? keys;
  bool expecting = true;
}
void _uniqueKeys(String text) {
  final frames = <_Keys>[];
  for (var i = 0; i < text.length; ++i) {
    final code = text.codeUnitAt(i);
    if (code == 123 || code == 91) { frames.add(_Keys(code == 123)); }
    else if (code == 125 || code == 93) { if (frames.isNotEmpty) { frames.removeLast(); } }
    else if (code == 44 && frames.isNotEmpty && frames.last.keys != null) { frames.last.expecting = true; }
    else if (code == 34) {
      final start = i; var escaped = false;
      for (++i; i < text.length; ++i) {
        final c = text.codeUnitAt(i);
        if (escaped) { escaped = false; }
        else if (c == 92) { escaped = true; }
        else if (c == 34) { break; }
      }
      if (i == text.length) { throw const FormatException('Incomplete event string'); }
      if (frames.isNotEmpty && frames.last.keys != null && frames.last.expecting) {
        final key = jsonDecode(text.substring(start, i + 1));
        final frame = frames.last;
        if (key is! String || !frame.keys!.add(key) || frame.keys!.length > 64) {
          throw const FormatException('Duplicate or oversized event keys');
        }
        frame.expecting = false;
      }
    }
  }
}
Map<String, Object?> parseEvent(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > 4095) { throw const FormatException('Event size limit'); }
  _depthGuard(bytes);
  final text = utf8.decode(bytes, allowMalformed: false);
  _uniqueKeys(text);
  final value = jsonDecode(text);
  var nodes = 0;
  void bounded(Object? node) {
    if (++nodes > 256) { throw const FormatException('Event node limit'); }
    if (node is Map) {
      if (node.length > 64) { throw const FormatException('Event field limit'); }
      for (final entry in node.entries) {
        if (entry.key is! String || (entry.key as String).isEmpty || (entry.key as String).length > 64) { throw const FormatException('Invalid event key'); }
        bounded(entry.value);
      }
    } else if (node is List) {
      if (node.length > 32) { throw const FormatException('Event list limit'); }
      for (final item in node) { bounded(item); }
    } else if (node is String && (utf8.encode(node).length > 1024 || node.runes.any((r) => r == 0 || r >= 0xd800 && r <= 0xdfff))) { throw const FormatException('Event string limit'); }
    else if (node is num && (node is! int || node < -2147483648 || node > 4294967295)) { throw const FormatException('Event number limit'); }
  }
  bounded(value);
  if (value is! Map<String, dynamic> || value['v'] is! int || value['v'] != 1
    || value['type'] is! String || !RegExp(r'^[a-z_]{1,32}$').hasMatch(value['type'] as String)) {
    throw const FormatException('Invalid event envelope');
  }
  return Map<String, Object?>.from(value);
}
class JsonLines {
  int errors = 0;
  final _bytes = <int>[];
  bool _dropping = false;
  List<Map<String, Object?>> add(List<int> bytes) {
    if (bytes.length > 8192) { reset(); ++errors; _dropping = true; return []; }
    final complete = <Map<String, Object?>>[];
    for (final byte in bytes) {
      if (byte < 0 || byte > 255) { reset(); _dropping = true; ++errors; continue; }
      if (byte == 10) {
        if (_dropping) { _dropping = false; _bytes.clear(); continue; }
        if (_bytes.isEmpty) { continue; }
        try { complete.add(parseEvent(_bytes)); }
        on FormatException { ++errors; }
        _bytes.clear();
      } else if (!_dropping) {
        if (_bytes.length == 4095) { _bytes.clear(); _dropping = true; ++errors; }
        else { _bytes.add(byte); }
      }
    }
    return complete;
  }
  void reset() { _bytes.clear(); _dropping = false; }
}

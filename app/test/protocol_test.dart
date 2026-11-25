import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_room/models.dart';
import 'package:smart_room/protocol.dart';

void main() {
  const session = '000102030405060708090a0b0c0d0e0f';
  const challenge = '101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f';
  test('HMAC agrees with independent Python SHA256 oracle', () {
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    expect(ownerProof(key, 'f024f91080a4', session, challenge),
      '453984446bfe4f6b72ee762c6c8ed4ee53a2ad939576d11e3a33a606988bb9a2');
  });
  test('proof binds link nonce and rejects malformed input', () {
    final key = Uint8List(32);
    expect(ownerProof(key, 'f024f91080a4', session, challenge),
      isNot(ownerProof(key, 'f024f91080a4', '100102030405060708090a0b0c0d0e0f', challenge)));
    expect(() => ownerProof(Uint8List(2), 'f024f91080a4', session, challenge), throwsArgumentError);
  });
  test('commands have flat versioned envelope and exactly one newline', () {
    final encoded = utf8.decode(encodeCommand(7, 'lights', session: session,
      payload: {'on': false, 'lease_ms': 60000}));
    expect(encoded.endsWith('\n'), isTrue);
    expect(jsonDecode(encoded), {'v': 1, 'id': 7, 'op': 'lights',
      'session': session, 'on': false, 'lease_ms': 60000});
  });
  test('reserved fields nesting floats and byte overflow are denied', () {
    expect(() => encodeCommand(1, 'lights', session: session, payload: {'id': 9}), throwsArgumentError);
    expect(() => encodeCommand(1, 'configure', session: session, payload: {'x': {}}), throwsArgumentError);
    expect(() => encodeCommand(1, 'lights', session: session, payload: {'lease_ms': 1.0}), throwsArgumentError);
    expect(() => encodeCommand(1, 'learn_start', session: session, payload: {'label': 'ا' * 400}), throwsArgumentError);
  });
  test('command values reject null and unpaired Unicode before transport', () {
    for (final label in ['bad\u0000label', '\ud800', '\udc00']) {
      expect(() => encodeCommand(1, 'learn_start', session: session, payload: {'label': label}), throwsArgumentError);
    }
    final bytes = encodeCommand(1, 'learn_start', session: session, payload: {'label': 'نوم 😀'});
    expect((jsonDecode(utf8.decode(bytes)) as Map)['label'], 'نوم 😀');
  });
  test('notification bytes split in middle of Arabic UTF8 decode once', () {
    final parser = JsonLines();
    final bytes = utf8.encode('{"v":1,"type":"profiles","items":[{"label":"نوم"}]}\n');
    final messages = <Map<String, Object?>>[];
    for (final byte in bytes) { messages.addAll(parser.add([byte])); }
    expect(messages, hasLength(1));
    expect(((messages.single['items'] as List).single as Map)['label'], 'نوم');
    expect(parser.errors, 0);
  });
  test('multiple responses in one notification remain distinct', () {
    final messages = JsonLines().add(utf8.encode('{"v":1,"type":"ack","id":1}\n{"v":1,"type":"ack","id":2}\n'));
    expect(messages.map((m) => m['id']), [1, 2]);
  });
  test('overflow discards truncated suffix and recovers at newline', () {
    final parser = JsonLines();
    parser.add(List.filled(5000, 65));
    final messages = parser.add(utf8.encode('{}\n{"v":1,"type":"ack","id":3}\n'));
    expect(parser.errors, 1); expect(messages.single['id'], 3);
  });
  test('invalid version UTF8 and deeply nested events are not accepted', () {
    final parser = JsonLines();
    parser.add(utf8.encode('{"v":true,"type":"ack"}\n'));
    parser.add([0xff, 10]);
    parser.add(utf8.encode('{"v":1,"type":"status","x":${'[' * 12}0${']' * 12}}\n'));
    expect(parser.errors, 3);
  });
  test('duplicate plain and escaped peer keys are not normalized to success', () {
    final parser = JsonLines();
    expect(parser.add(utf8.encode('{"v":1,"type":"ack","ok":false,"ok":true}\n')), isEmpty);
    expect(parser.add(utf8.encode('{"v":1,"type":"ack","ok":false,"o\\u006b":true}\n')), isEmpty);
    expect(parser.errors, 2);
  });
  test('IR fields are typed and retain an exact full state', () {
    final state = IrState(temperature: 23, fan: 3, mode: 1, power: true, sleep: false);
    expect(state.toJson(), {'temperature': 23, 'fan': 3, 'mode': 1, 'power': true, 'sleep': false});
    expect(() => IrState(temperature: 31), throwsArgumentError);
    expect(() => IrState(fan: 4), throwsArgumentError);
    expect(() => IrState(mode: -1), throwsArgumentError);
  });
  test('unlearned combinations never fall back to a different profile', () {
    final profile = Profile(slot: 7, label: 'COOL 23 HIGH', state: IrState(temperature: 23, fan: 3));
    expect(findProfile([profile], IrState(temperature: 23, fan: 3))?.slot, 7);
    expect(findProfile([profile], IrState(temperature: 24, fan: 3)), isNull);
    expect(findProfile([profile], IrState(temperature: 23, fan: 3, sleep: true)), isNull);
  });
  test('slot label limit is UTF8 bytes, not glyph count', () {
    expect(() => Profile(slot: 17, label: 'invalid', state: IrState()), throwsArgumentError);
    expect(() => Profile(slot: 1, label: 'ا' * 24, state: IrState()), throwsArgumentError);
    expect(() => Profile(slot: 1, label: 'bad\nlabel', state: IrState()), throwsArgumentError);
    expect(() => Profile(slot: 1, label: '\ud800', state: IrState()), throwsArgumentError);
  });
  test('rule config matches firmware bounds and field names', () {
    final config = RuleConfig(); expect(config.valid, isTrue); expect(config.toJson(), hasLength(11));
    expect(config.toJson()['empty_ms'], 120000);
    expect(RuleConfig(emptyMs: 9999).valid, isFalse);
    expect(RuleConfig(quietMax: 4, normalMax: 4).valid, isFalse);
    expect(RuleConfig(sleepSlot: 17).valid, isFalse);
    expect(RuleConfig(manualMs: 43200001).valid, isFalse);
  });
  test('boolean values cannot masquerade as integers from peer', () {
    expect(() => readInt({'id': true}, 'id', 1, 10), throwsFormatException);
    expect(() => readBool({'power': 1}, 'power'), throwsFormatException);
  });
}

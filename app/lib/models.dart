import 'dart:convert';

int readInt(Map<String, Object?> data, String key, int low, int high) {
  final value = data[key];
  if (value is! int || value < low || value > high) { throw FormatException('Invalid $key'); }
  return value;
}
bool readBool(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! bool) { throw FormatException('Invalid $key'); }
  return value;
}
String readString(Map<String, Object?> data, String key, int maximum) {
  final value = data[key];
  if (value is! String || value.isEmpty || utf8.encode(value).length > maximum) {
    throw FormatException('Invalid $key');
  }
  return value;
}

class IrState {
  IrState({this.temperature = 26, this.fan = 0, this.mode = 1,
    this.power = true, this.sleep = false}) {
    if (temperature < 16 || temperature > 30 || fan < 0 || fan > 3 || mode < 0 || mode > 4) {
      throw ArgumentError('Invalid complete IR state');
    }
  }
  final int temperature, fan, mode;
  final bool power, sleep;
  IrState copyWith({int? temperature, int? fan, int? mode, bool? power, bool? sleep}) => IrState(
    temperature: temperature ?? this.temperature, fan: fan ?? this.fan, mode: mode ?? this.mode,
    power: power ?? this.power, sleep: sleep ?? this.sleep);
  Map<String, Object?> toJson() => {'temperature': temperature, 'fan': fan,
    'mode': mode, 'power': power, 'sleep': sleep};
  static IrState fromJson(Map<String, Object?> data) => IrState(
    temperature: readInt(data, 'temperature', 16, 30), fan: readInt(data, 'fan', 0, 3),
    mode: readInt(data, 'mode', 0, 4), power: readBool(data, 'power'), sleep: readBool(data, 'sleep'));
  @override
  bool operator ==(Object other) => other is IrState && temperature == other.temperature
    && fan == other.fan && mode == other.mode && power == other.power && sleep == other.sleep;
  @override
  int get hashCode => Object.hash(temperature, fan, mode, power, sleep);
}

class Profile {
  Profile({required this.slot, required this.label, required this.state,
    this.hz = 38000, this.pulses = 17}) {
    if (slot < 1 || slot > 16 || label.isEmpty || labelBytes(label) > 47
      || label.runes.any((r) => r < 32 || r >= 0xd800 && r <= 0xdfff)
      || ![36000, 38000, 40000, 56000].contains(hz)
      || pulses < 16 || pulses > 1024) { throw ArgumentError('Invalid recorded IR profile'); }
  }
  final int slot, hz, pulses;
  final String label;
  final IrState state;
  static Profile fromJson(Map<String, Object?> data) {
    if (data.length != 9) { throw const FormatException('Invalid profile fields'); }
    try {
      return Profile(slot: readInt(data, 'slot', 1, 16), label: readString(data, 'label', 47),
        state: IrState.fromJson(data), hz: readInt(data, 'hz', 36000, 56000),
        pulses: readInt(data, 'pulses', 16, 1024));
    } on ArgumentError { throw const FormatException('Invalid profile fields'); }
  }
}

Profile? findProfile(List<Profile> profiles, IrState requested) {
  for (final profile in profiles) { if (profile.state == requested) { return profile; } }
  return null;
}

class RuleConfig {
  const RuleConfig({this.ttlMs = 2000, this.emptyMs = 120000, this.settleMs = 5000,
    this.manualMs = 1800000, this.irGapMs = 15000, this.quietMax = 2,
    this.normalMax = 4, this.quietSlot = 1, this.normalSlot = 2,
    this.busySlot = 3, this.sleepSlot = 4});
  final int ttlMs, emptyMs, settleMs, manualMs, irGapMs, quietMax, normalMax;
  final int quietSlot, normalSlot, busySlot, sleepSlot;
  bool get valid => ttlMs >= 1000 && ttlMs <= 10000 && emptyMs >= 10000 && emptyMs <= 3600000
    && emptyMs > ttlMs && settleMs >= 1000 && settleMs <= 60000
    && manualMs >= 60000 && manualMs <= 43200000 && irGapMs >= 5000 && irGapMs <= 300000
    && quietMax >= 1 && quietMax < normalMax && normalMax <= 50
    && [quietSlot, normalSlot, busySlot, sleepSlot].every((v) => v >= 1 && v <= 16);
  Map<String, Object?> toJson() {
    if (!valid) { throw ArgumentError('Invalid occupancy configuration'); }
    return {'ttl_ms': ttlMs, 'empty_ms': emptyMs, 'settle_ms': settleMs,
      'manual_ms': manualMs, 'ir_gap_ms': irGapMs, 'quiet_max': quietMax,
      'normal_max': normalMax, 'quiet_slot': quietSlot, 'normal_slot': normalSlot,
      'busy_slot': busySlot, 'sleep_slot': sleepSlot};
  }
  static RuleConfig fromJson(Map<String, Object?> data) {
    final config = RuleConfig(ttlMs: readInt(data, 'ttl_ms', 1000, 10000),
      emptyMs: readInt(data, 'empty_ms', 10000, 3600000), settleMs: readInt(data, 'settle_ms', 1000, 60000),
      manualMs: readInt(data, 'manual_ms', 60000, 43200000), irGapMs: readInt(data, 'ir_gap_ms', 5000, 300000),
      quietMax: readInt(data, 'quiet_max', 1, 49), normalMax: readInt(data, 'normal_max', 2, 50),
      quietSlot: readInt(data, 'quiet_slot', 1, 16), normalSlot: readInt(data, 'normal_slot', 1, 16),
      busySlot: readInt(data, 'busy_slot', 1, 16), sleepSlot: readInt(data, 'sleep_slot', 1, 16));
    if (!config.valid || data.length != 11) { throw const FormatException('Invalid occupancy configuration'); }
    return config;
  }
}

int labelBytes(String text) => utf8.encode(text).length;

class RoomSnapshot {
  RoomSnapshot._({required this.people, required this.mode, required this.scene,
    required this.lights, required this.relayEnabled, required this.irRxEnabled,
    required this.irTxEnabled, required this.oledReady, required this.cameraReady,
    required this.storageReady, required this.requestedSlot, required this.sentSlot,
    required this.irResult, required this.overrideMs, required this.emptyRemainingMs,
    required this.config, required this.boot, required this.device, required this.learnSlot});
  final int people, requestedSlot, sentSlot, overrideMs, emptyRemainingMs, learnSlot;
  final String mode, scene, irResult, device, boot;
  final bool lights, relayEnabled, irRxEnabled, irTxEnabled, oledReady, cameraReady, storageReady;
  final RuleConfig config;
  static RoomSnapshot fromJson(Map<String, Object?> data) {
    final people = readInt(data, 'people', -1, 100);
    final mode = readString(data, 'mode', 12), scene = readString(data, 'scene', 12);
    final presence = readString(data, 'presence', 12);
    if (!['auto', 'manual', 'sleep'].contains(mode) || !['none', 'quiet', 'normal', 'busy', 'sleep', 'manual'].contains(scene)
      || presence != (people < 0 ? 'unknown' : people == 0 ? 'empty' : 'occupied')) {
      throw const FormatException('Inconsistent occupancy snapshot');
    }
    final device = readString(data, 'device', 12), boot = readString(data, 'boot', 16);
    if (!RegExp(r'^[0-9a-f]{12}$').hasMatch(device) || !RegExp(r'^[0-9a-f]{16}$').hasMatch(boot)
      || data['config'] is! Map) { throw const FormatException('Invalid device/config identity'); }
    return RoomSnapshot._(people: people, mode: mode, scene: scene, device: device, boot: boot,
      lights: readBool(data, 'lights'), relayEnabled: readBool(data, 'relay_enabled'),
      irRxEnabled: readBool(data, 'ir_rx_enabled'), irTxEnabled: readBool(data, 'ir_tx_enabled'),
      oledReady: readBool(data, 'oled_ready'), cameraReady: readBool(data, 'camera_ready'),
      storageReady: readBool(data, 'storage_ready'), requestedSlot: readInt(data, 'requested_slot', 0, 16),
      sentSlot: readInt(data, 'sent_slot', 0, 16), irResult: readString(data, 'ir_result', 64),
      overrideMs: readInt(data, 'override_ms', 0, 43200000), emptyRemainingMs: readInt(data, 'empty_remaining_ms', 0, 3600000),
      learnSlot: readInt(data, 'learn_slot', 0, 16),
      config: RuleConfig.fromJson(Map<String, Object?>.from(data['config']! as Map)));
  }
}

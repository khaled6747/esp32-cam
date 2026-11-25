import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'ble_transport.dart';
import 'models.dart';
import 'protocol.dart';

enum RoomPhase { idle, scanning, connecting, needsClaim, locked, ready, error }

class RoomFailure implements Exception {
  const RoomFailure(this.code);
  final String code;
  @override
  String toString() => code;
}
class CommandRejected extends RoomFailure {
  const CommandRejected(super.code);
}
const _successCodes = {'auth': 'authenticated', 'claim': 'claimed',
  'set_mode': 'policy_saved', 'lights': 'requested_no_feedback', 'send_slot': 'queued',
  'ac': 'queued', 'configure': 'configuration_saved', 'learn_start': 'press_original_remote',
  'learn_cancel': 'learning_cancelled', 'erase_slot': 'slot_erased', 'storage_init': 'storage_ready'};
class _Pending {
  _Pending(this.type, this.epoch, this.operation);
  final String type;
  final String operation;
  final int epoch;
  final completer = Completer<Map<String, Object?>>();
  Timer? deadline;
}

String roomMessage(String code) => switch (code) {
  'hardware_disabled' => 'المخرج معطّل في إعدادات الفيرموير حتى مراجعة الهاردوير.',
  'unlearned_state' => 'الحالة الكاملة غير متعلّمة. تعلّمها من الريموت الأصلي أولًا؛ لا نرسل حالة بديلة.',
  'storage_unmounted' => 'مساحة ملفات IR غير مجهزة. التهيئة تحتاج تأكيدًا صريحًا.',
  'storage_failed' => 'لم ينجح حفظ البيانات؛ لم تُعتبر العملية محفوظة.',
  'learning_busy' => 'التعلّم جارٍ؛ انتظر الإشارة أو ألغِ العملية.',
  'press_original_remote' => 'اضغط الزر مرة واحدة على الريموت الأصلي خلال 30 ثانية.',
  'saved_raw_unverified' => 'حُفظت نبضات IR خام. اكتمال حالة التكييف وصحة الحامل يحتاجان اختبارًا فعليًا.',
  'incomplete_or_noise' => 'إشارة قصيرة / مشوشة أو خارج الحدود؛ لم يتم الحفظ.',
  'learning_timeout' => 'لم تصل إشارة خلال 30 ثانية؛ أعد التعلّم باختيارك.',
  'queued' => 'تم قبول الطلب للجدولة؛ هذا ليس تأكيدًا بأن التكييف استجاب.',
  'requested_no_feedback' => 'تم تسجيل طلب الإضاءة؛ لا يوجد حساس يؤكد حالة المصباح.',
  'owner_missing' => 'الوحدة لها مالك، لكن مفتاحه غير موجود على هذا الهاتف. استخدم الهاتف المالك أو إجراء إعادة الملكية المحلي عبر USB.',
  'claim_denied' => 'التسجيل غير مسموح الآن. يلزم اقتران آمن وشاشة عاملة ونافذة تسجيل محلية.',
  'bad_proof' || 'auth_required' => 'لم ينجح إثبات الملكية؛ لا توجد صلاحية للتحكم.',
  'claim_window_closed' => 'نافذة تسجيل المالك مغلقة. افتحها محليًا من اللاب بعد مراجعة الهاردوير.',
  'not_connected' => 'اتصل بالوحدة وأثبت الملكية قبل التحكم.',
  'stale_status' => 'بيانات الوحدة قديمة؛ التحكم متوقف حتى وصول حالة حديثة.',
  'busy' => 'هناك عملية واحدة جارية. انتظرها أو افصل الاتصال.',
  'command_result_unknown' => 'انتهت مهلة الرد / النقل. نتيجة الأمر غير معروفة؛ فُصل الاتصال ولا توجد إعادة تلقائية.',
  'device_restarted' => 'أُعيد تشغيل الوحدة أو تغيرت هويتها؛ أعد الاتصال وإثبات الملكية.',
  'invalid_peer_event' => 'رد غير صالح من الوحدة؛ أُغلق الاتصال بدل استخدام بيانات ملتبسة.',
  'bluetooth_off' => 'فعّل Bluetooth من إعدادات الهاتف.',
  'permissions_denied' || 'permissions_revoked' => 'اسمح بصلاحيات الأجهزة القريبة / Bluetooth من إعدادات التطبيق.',
  'location_off' => 'في Android 7–11 يجب تشغيل خدمة الموقع للبحث عن BLE؛ التطبيق لا يجمع موقعك.',
  'secure_storage_failed' => 'تعذر فتح / حفظ مفتاح الملكية بأمان. لم نُسجّل مالكًا جديدًا ولم نمسح المفاتيح.',
  'link_lost' || 'disconnected' => 'انقطع الاتصال. العدد والحالة الحالية غير معروفين؛ لا توجد إعادة اتصال تلقائية.',
  'configuration_saved' => 'حُفظت قواعد الإشغال على الوحدة.',
  'policy_saved' => 'حُفظ وضع التحكم المؤقت؛ المخارج المعطلة تظل معطلة.',
  'learning_cancelled' => 'أُلغي التعلّم.',
  'slot_erased' => 'حُذف ملف هذه الخانة بعد التأكيد.',
  'storage_ready' => 'أصبحت مساحة ملفات IR جاهزة.',
  'claimed' => 'سُجّل هذا الهاتف مالكًا للوحدة.',
  _ => 'تعذر إتمام العملية ($code). لا نفترض أن الأجهزة استجابت.',
};

class RoomClient extends ChangeNotifier {
  RoomClient({required this.transport, required this.vault, int Function()? clock,
    Uint8List Function()? newKey, bool startTimers = true,
    this.requestTimeout = const Duration(seconds: 12)}) {
    _watch.start();
    _clock = clock ?? () => _watch.elapsedMilliseconds;
    _newKey = newKey ?? () { final random = Random.secure(); return Uint8List.fromList(List.generate(32, (_) => random.nextInt(256))); };
    _subscription = transport.events.listen(_nativeEvent, onError: _nativeStreamError);
    if (startTimers) { _timer = Timer.periodic(const Duration(seconds: 1), (_) => checkFreshness()); }
  }
  final BleTransport transport;
  final OwnerVault vault;
  final Duration requestTimeout;
  final _watch = Stopwatch();
  late final int Function() _clock;
  late final Uint8List Function() _newKey;
  late final StreamSubscription<Map<String, Object?>> _subscription;
  final _parser = JsonLines();
  final _pending = <int, _Pending>{};
  final _devices = <String, RoomDevice>{};
  Timer? _timer;
  Future<void>? _closeFuture;
  Future<void>? _dropInFlight;
  RoomPhase phase = RoomPhase.idle;
  RoomSnapshot? snapshot;
  List<Profile> profiles = const [];
  String? lastError, lastMessage;
  String? deviceId;
  String? _session, _boot;
  int _epoch = 0, _request = 0, _statusAt = 0;
  bool _busy = false, _stale = true, _closed = false, _authenticated = false;
  bool claimOpen = false, _refreshNeeded = false;
  int learningSlot = 0;
  List<RoomDevice> get devices => List.unmodifiable(_devices.values);
  bool get busy => _busy;
  bool get stale => _stale;
  bool get authenticated => _authenticated;
  bool get canControl => phase == RoomPhase.ready && _authenticated && !_stale && !_busy && !_closed;
  int? get currentPeople => !_stale ? (snapshot?.people == -1 ? null : snapshot?.people) : null;
  int get epoch => _epoch;
  void _changed() { if (!_closed) { notifyListeners(); } }

  Future<bool> scan() async {
    if (_closed || _busy || _authenticated || phase == RoomPhase.connecting || phase == RoomPhase.scanning) { return _localFailure('busy'); }
    if (phase == RoomPhase.needsClaim || phase == RoomPhase.locked) { await disconnect(); }
    final attempt = _epoch;
    _devices.clear(); lastError = null; phase = RoomPhase.scanning; _busy = true; _changed();
    try {
      await transport.permissions();
      if (_closed || attempt != _epoch) { return false; }
      await transport.scan(); return !_closed && attempt == _epoch;
    }
    on PlatformException catch (error) {
      if (attempt != _epoch || _closed) { return false; }
      phase = RoomPhase.error; lastError = roomMessage(error.code); _changed(); return false;
    }
    finally { if (attempt == _epoch) { _busy = false; _changed(); } }
  }

  Future<bool> connect(RoomDevice device) async {
    if (_closed || _busy || _authenticated) { return _localFailure('busy'); }
    final attempt = ++_epoch;
    _request = 0; _parser.reset(); _resetData(); phase = RoomPhase.connecting; _busy = true; lastError = null; lastMessage = null; _changed();
    try {
      await transport.permissions();
      if (attempt != _epoch || _closed) { return false; }
      await transport.connect(device.id, attempt);
      if (attempt != _epoch || _closed) { return false; }
      final hello = await _hello();
      if (attempt != _epoch || _closed) { return false; }
      if (readBool(hello, 'owned')) {
        final ownerDevice = deviceId!, ownerSession = _session!;
        Uint8List? key;
        try { key = await vault.read(ownerDevice); }
        on Exception { throw const RoomFailure('secure_storage_failed'); }
        if (attempt != _epoch || _closed) { key?.fillRange(0, key.length, 0); return false; }
        if (key == null) { phase = RoomPhase.locked; lastError = roomMessage('owner_missing'); return false; }
        try {
          final response = await _ask('auth', {'proof': ownerProof(key, ownerDevice, ownerSession, readString(hello, 'challenge', 64))});
          if (readString(response, 'code', 64) != 'authenticated') { throw const RoomFailure('invalid_peer_event'); }
        } finally { key.fillRange(0, key.length, 0); }
        _authenticated = true; phase = RoomPhase.ready;
        await _refresh(); return true;
      }
      claimOpen = readBool(hello, 'claim_open'); phase = RoomPhase.needsClaim;
      if (!claimOpen) { lastError = roomMessage('claim_window_closed'); }
      return true;
    } catch (error, stack) {
      return await _connectionFailure(error, stack, attempt);
    } finally { if (attempt == _epoch) { _busy = false; _changed(); } }
  }

  Future<Map<String, Object?>> _hello() async {
    final event = await _ask('hello', const {}, expected: 'hello');
    final device = readString(event, 'device', 12), session = readString(event, 'session', 32);
    final challenge = readString(event, 'challenge', 64);
    if (!validHex(device, 6) || !validHex(session, 16) || !validHex(challenge, 32)
      || (deviceId != null && deviceId != device)) { throw const RoomFailure('invalid_peer_event'); }
    readBool(event, 'owned'); readBool(event, 'claim_open');
    deviceId = device; _session = session;
    return event;
  }

  Future<bool> claim() async {
    if (_closed || _busy || phase != RoomPhase.needsClaim || !claimOpen) { return _localFailure('claim_denied'); }
    final attempt = _epoch; _busy = true; lastError = null; _changed();
    Uint8List? key;
    try {
      // Refresh the one-use 30 s challenge after the human confirmation dialog.
      final hello = await _hello();
      if (attempt != _epoch || _closed) { return false; }
      if (readBool(hello, 'owned') || !readBool(hello, 'claim_open')) { throw const RoomFailure('claim_denied'); }
      final ownerDevice = deviceId!;
      try {
        key = await vault.read(ownerDevice);
        if (attempt != _epoch || _closed) { return false; }
        key ??= _newKey();
        if (key.length != 32) { throw ArgumentError('Invalid random key length'); }
        await vault.write(ownerDevice, key);
      } on Exception { throw const RoomFailure('secure_storage_failed'); }
      if (attempt != _epoch || _closed) { return false; }
      final response = await _ask('claim', {'key': encodeKey(key)});
      if (readString(response, 'code', 64) != 'claimed') { throw const RoomFailure('invalid_peer_event'); }
      _authenticated = true; claimOpen = false; phase = RoomPhase.ready;
      lastMessage = roomMessage(readString(response, 'code', 64));
      await _refresh(); return true;
    } catch (error, stack) { return await _connectionFailure(error, stack, attempt); }
    finally {
      key?.fillRange(0, key.length, 0);
      if (attempt == _epoch) { _busy = false; _changed(); }
    }
  }

  Future<Map<String, Object?>> _ask(String op, Map<String, Object?> payload, {String expected = 'ack'}) async {
    if (_closed || _pending.isNotEmpty || _request == 2147483647) { throw const RoomFailure('busy'); }
    final id = ++_request, attempt = _epoch;
    final bytes = encodeCommand(id, op, session: op == 'hello' ? null : _session, payload: payload);
    final pending = _Pending(expected, attempt, op); _pending[id] = pending;
    pending.deadline = Timer(requestTimeout, () {
      if (!pending.completer.isCompleted) { pending.completer.completeError(const RoomFailure('command_result_unknown')); }
    });
    try {
      final completed = await Future.wait<Object?>([
        Future<void>.sync(() => transport.write(bytes, attempt)), pending.completer.future,
      ], eagerError: true);
      if (attempt != _epoch || _closed) { throw const RoomFailure('disconnected'); }
      return completed[1]! as Map<String, Object?>;
    } finally {
      pending.deadline?.cancel(); _pending.remove(id); bytes.fillRange(0, bytes.length, 0);
      if (!pending.completer.isCompleted) { pending.completer.completeError(const RoomFailure('disconnected')); }
    }
  }

  Future<void> _refresh() async {
    await _ask('profiles', const {}, expected: 'profiles');
    await _ask('status', const {}, expected: 'status');
    _refreshNeeded = false;
  }
  Future<bool> refresh() => _perform(() async { await _refresh(); }, allowStale: true);
  Future<bool> setMode(String mode, int leaseMs) => _perform(() async {
    if (!['auto', 'manual', 'sleep'].contains(mode) || (mode != 'auto' && (leaseMs < 60000 || leaseMs > 43200000))) {
      throw ArgumentError('Invalid mode/lease');
    }
    await _action('set_mode', {'mode': mode, 'lease_ms': mode == 'auto' ? 0 : leaseMs});
  });
  Future<bool> lights(bool on, int leaseMs) => _perform(() async {
    if (!snapshot!.relayEnabled) { throw const CommandRejected('hardware_disabled'); }
    await _action('lights', {'on': on, 'lease_ms': leaseMs});
  });
  Future<bool> sendAc(IrState state, int leaseMs) => _perform(() async {
    if (findProfile(profiles, state) == null) { throw const CommandRejected('unlearned_state'); }
    if (!snapshot!.irTxEnabled) { throw const CommandRejected('hardware_disabled'); }
    await _action('ac', {...state.toJson(), 'lease_ms': leaseMs});
  });
  Future<bool> sendSlot(int slot, int leaseMs) => _perform(() async {
    if (!profiles.any((p) => p.slot == slot)) { throw const CommandRejected('unlearned_state'); }
    if (!snapshot!.irTxEnabled) { throw const CommandRejected('hardware_disabled'); }
    await _action('send_slot', {'slot': slot, 'lease_ms': leaseMs});
  });
  Future<bool> configure(RuleConfig config) => _perform(() async {
    await _action('configure', config.toJson());
  });
  Future<bool> learn(Profile description) => _perform(() async {
    if (!snapshot!.irRxEnabled) { throw const CommandRejected('hardware_disabled'); }
    if (!snapshot!.storageReady) { throw const CommandRejected('storage_unmounted'); }
    if (learningSlot != 0) { throw const CommandRejected('learning_busy'); }
    await _action('learn_start', {'slot': description.slot, 'label': description.label,
      ...description.state.toJson(), 'hz': description.hz});
  });
  Future<bool> cancelLearning() => _perform(() async { await _action('learn_cancel', const {}); });
  Future<bool> eraseSlot(int slot, {required bool confirmed}) => _perform(() async {
    if (!confirmed) { throw const CommandRejected('confirmation_required'); }
    await _action('erase_slot', {'slot': slot, 'confirm': true}); await _ask('profiles', const {}, expected: 'profiles');
  });
  Future<bool> initializeStorage({required bool confirmed}) => _perform(() async {
    if (!confirmed) { throw const CommandRejected('confirmation_required'); }
    await _action('storage_init', {'confirm': 'INIT_UNMOUNTED_STORAGE'});
  });
  Future<void> _action(String op, Map<String, Object?> payload) async {
    final lease = payload['lease_ms'];
    if (lease is int && lease != 0 && (lease < 60000 || lease > 43200000)) { throw ArgumentError('Invalid manual lease'); }
    final response = await _ask(op, payload);
    lastMessage = roomMessage(readString(response, 'code', 64));
    await _ask('status', const {}, expected: 'status');
  }

  Future<bool> _perform(Future<void> Function() operation, {bool allowStale = false}) async {
    final permitted = phase == RoomPhase.ready && _authenticated && !_busy && !_closed && (allowStale || !_stale);
    if (!permitted) { return _localFailure(_busy ? 'busy' : _stale && _authenticated ? 'stale_status' : 'not_connected'); }
    final attempt = _epoch; _busy = true; lastError = null; _changed();
    try { await operation(); return attempt == _epoch && !_closed; }
    on CommandRejected catch (error) { lastError = roomMessage(error.code); return false; }
    on ArgumentError { lastError = 'قيم الأمر خارج الحدود. لم نرسل حالة بديلة.'; return false; }
    catch (error, stack) { return await _connectionFailure(error, stack, attempt); }
    finally { if (attempt == _epoch) { _busy = false; _changed(); } }
  }
  bool _localFailure(String code) { lastError = roomMessage(code); _changed(); return false; }

  Future<bool> _connectionFailure(Object error, StackTrace stack, int attempt) async {
    if (attempt != _epoch || _closed) { return false; }
    final code = error is RoomFailure ? error.code : error is PlatformException ? error.code
      : error is FormatException || error is ArgumentError ? 'invalid_peer_event' : null;
    if (code == null) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'smart_room'));
      Error.throwWithStackTrace(error, stack);
    }
    await _drop(code); return false;
  }

  void _nativeEvent(Map<String, Object?> event) {
    if (_closed) { return; }
    try {
      final kind = readString(event, 'kind', 32);
      if (kind == 'scan_result' && phase == RoomPhase.scanning) {
        final id = readString(event, 'id', 32), name = readString(event, 'name', 80);
        if (!_devices.containsKey(id) && _devices.length == 32) { return; }
        _devices[id] = RoomDevice(id, name, readInt(event, 'rssi', -127, 20)); _changed(); return;
      }
      if (kind == 'scan_end' && phase == RoomPhase.scanning) { phase = RoomPhase.idle; _changed(); return; }
      if (readInt(event, 'epoch', 0, 2147483647) != _epoch) { return; }
      if (kind == 'bytes') {
        final bytes = event['bytes'];
        if (bytes is! Uint8List || bytes.length > 514) { throw const FormatException('Invalid native notification'); }
        final errors = _parser.errors;
        final messages = _parser.add(bytes);
        if (_parser.errors != errors) { throw const FormatException('Invalid peer notification'); }
        for (final message in messages) { _event(message); }
      } else if (kind == 'disconnected') {
        _resetData(); _cancelPending(const RoomFailure('disconnected')); ++_epoch; _busy = false;
        if (phase != RoomPhase.error) { phase = RoomPhase.idle; lastError = roomMessage('disconnected'); } _changed();
      } else if (kind == 'error') {
        final code = readString(event, 'code', 64);
        unawaited(_drop(code));
      }
    } on FormatException { unawaited(_drop('invalid_peer_event')); }
  }
  void _nativeStreamError(Object error, StackTrace stack) {
    final code = error is PlatformException ? error.code : 'invalid_peer_event';
    unawaited(_drop(code));
  }

  void _event(Map<String, Object?> event) {
    final type = event['type'];
    if (type == 'status' && _authenticated) {
      final state = RoomSnapshot.fromJson(event);
      if (state.device != deviceId || (_boot != null && state.boot != _boot)) {
        unawaited(_drop('device_restarted')); return;
      }
      _boot = state.boot; snapshot = state; _statusAt = _clock(); _stale = false; learningSlot = state.learnSlot;
    } else if (type == 'profiles' && _authenticated) {
      final items = event['items'];
      if (items is! List || items.length > 16) { throw const FormatException('Invalid profile list'); }
      final parsed = items.map((item) {
        if (item is! Map) { throw const FormatException('Invalid profile'); }
        return Profile.fromJson(Map<String, Object?>.from(item));
      }).toList();
      if (parsed.map((p) => p.slot).toSet().length != parsed.length) { throw const FormatException('Duplicate profile slot'); }
      profiles = List.unmodifiable(parsed);
    } else if (type == 'learned' && _authenticated) {
      readBool(event, 'ok'); lastMessage = roomMessage(readString(event, 'code', 64)); learningSlot = 0; _refreshNeeded = true;
    } else if (type == 'ir_sent' && _authenticated) {
      readInt(event, 'slot', 1, 16);
      if (readBool(event, 'confirmed_by_ac')) { throw const FormatException('Unsupported appliance feedback'); }
      lastMessage = 'أُرسلت نبضات IR؛ استجابة التكييف غير مؤكدة.';
    }
    final id = event['id'];
    if (id is int && id > 0) {
      final pending = _pending[id];
      if (pending != null && pending.epoch == _epoch && !pending.completer.isCompleted) {
        if (type == 'ack') {
          final ok = readBool(event, 'ok'), code = readString(event, 'code', 64);
          if (!ok) { pending.completer.completeError(CommandRejected(code)); }
          else if (pending.type != type || _successCodes[pending.operation] != code) { pending.completer.completeError(const RoomFailure('invalid_peer_event')); }
          else { pending.completer.complete(event); }
        } else if (type != pending.type) { pending.completer.completeError(const RoomFailure('invalid_peer_event')); }
        else { pending.completer.complete(event); }
      }
    }
    _changed();
  }
  void checkFreshness() {
    if (_closed) { return; }
    if (_authenticated && snapshot != null && _clock() - _statusAt > 3500 && !_stale) { _stale = true; _changed(); }
    if (_refreshNeeded && canControl) { unawaited(refresh()); }
  }
  void _cancelPending(RoomFailure error) {
    for (final pending in _pending.values) {
      pending.deadline?.cancel();
      if (!pending.completer.isCompleted) { pending.completer.completeError(error); }
    }
    _pending.clear();
  }
  void _resetData() {
    _authenticated = false; _stale = true; snapshot = null; profiles = const [];
    _session = _boot = deviceId = null; learningSlot = 0; claimOpen = false; _refreshNeeded = false;
  }
  Future<void> _drop(String? code) {
    if (_dropInFlight != null) { return _dropInFlight!; }
    final future = _doDrop(code);
    _dropInFlight = future;
    return future.whenComplete(() => _dropInFlight = null);
  }
  Future<void> _doDrop(String? code) async {
    ++_epoch; _cancelPending(RoomFailure(code ?? 'disconnected')); _parser.reset(); _resetData(); _busy = true;
    phase = code == null ? RoomPhase.idle : RoomPhase.error; lastError = code == null ? null : roomMessage(code); _changed();
    try { await _cleanupAll([transport.stopScan, transport.disconnect]); }
    on PlatformException catch (error) { lastError = roomMessage(error.code); _changed(); }
    finally { _busy = false; _changed(); }
  }
  Future<void> disconnect() => _drop(null);
  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closed = true; ++_epoch; _timer?.cancel(); _cancelPending(const RoomFailure('disconnected')); _resetData();
    await _cleanupAll([_subscription.cancel, () async { await _dropInFlight; },
      transport.stopScan, transport.disconnect, transport.close]);
  }
  Future<void> _cleanupAll(List<Future<void> Function()> actions) async {
    Object? firstError;
    StackTrace? firstStack;
    for (final action in actions) {
      try { await action(); }
      catch (error, stack) {
        if (firstError == null) { firstError = error; firstStack = stack; }
        else { FlutterError.reportError(FlutterErrorDetails(exception: error,
          stack: stack, library: 'smart_room additional cleanup failure')); }
      }
    }
    if (firstError != null) { Error.throwWithStackTrace(firstError, firstStack!); }
  }
  @override
  void dispose() {
    if (_closeFuture == null) {
      unawaited(close().catchError((Object error, StackTrace stack) {
        FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'smart_room cleanup'));
      }));
    }
    super.dispose();
  }
}

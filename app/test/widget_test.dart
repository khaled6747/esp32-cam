import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_room/main.dart';
import 'package:smart_room/room_client.dart';
import 'fakes.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  late FakeBle ble;
  late MemoryVault vault;
  late RoomClient client;
  var now = 0;
  setUp(() {
    ble = FakeBle(); vault = MemoryVault(); now = 0;
    vault.values[fakeDeviceId] = Uint8List.fromList(List.generate(32, (i) => i));
    client = RoomClient(transport: ble, vault: vault, clock: () => now, startTimers: false);
  });
  tearDown(() async { await client.close(); client.dispose(); });

  testWidgets('Arabic room UI replaces demo counter', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(client: client));
    expect(find.text('الغرفة الذكية'), findsOneWidget);
    expect(find.text('غير معروف'), findsWidgets);
    expect(find.text('0'), findsNothing);
    expect(find.text('تعلّم IR'), findsOneWidget);
    expect(find.text('المشاهد'), findsOneWidget);
  });
  testWidgets('disconnected screen does not invent a temperature sensor', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(client: client));
    expect(find.textContaining('لا يوجد حساس حرارة'), findsOneWidget);
    expect(find.textContaining('البحث عن الوحدة'), findsOneWidget);
  });
  testWidgets('unknown count and stale status never display a current zero', (tester) async {
    ble.people = -1; await client.connect(fakeDevice);
    await tester.pumpWidget(MyApp(client: client));
    expect(tester.widget<Text>(find.byKey(const ValueKey('people-count'))).data, 'غير معروف');
    ble.emit(fakeStatus(people: 0)); await tester.pump();
    expect(tester.widget<Text>(find.byKey(const ValueKey('people-count'))).data, '0');
    now = 3501; client.checkFreshness(); await tester.pump();
    expect(tester.widget<Text>(find.byKey(const ValueKey('people-count'))).data, 'غير معروف');
  });
  testWidgets('disabled hardware controls are visibly disabled', (tester) async {
    ble.hardware = false; await client.connect(fakeDevice);
    await tester.pumpWidget(MyApp(client: client));
    await tester.tap(find.text('تحكم')); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('lights-on'))).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('send-ac'))).onPressed, isNull);
    expect(find.textContaining('مخرج الريلاي معطّل'), findsOneWidget);
    await tester.tap(find.text('تعلّم IR')); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('learn-start'))).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unlearned complete state has no fallback and sends no command', (tester) async {
    await client.connect(fakeDevice); final before = ble.commands.length;
    await tester.pumpWidget(MyApp(client: client));
    await tester.tap(find.text('تحكم')); await tester.pumpAndSettle();
    expect(find.textContaining('الحالة غير متعلّمة'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('send-ac'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-ac'))); await tester.pumpAndSettle();
    expect(ble.commands.length, before); expect(client.lastError, contains('غير متعلّمة'));
  });
  testWidgets('scene drafts survive status refresh and invalid thresholds do not write', (tester) async {
    await client.connect(fakeDevice); final before = ble.commands.length;
    await tester.pumpWidget(MyApp(client: client));
    await tester.tap(find.text('المشاهد')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('scene-quiet')));
    await tester.enterText(find.byKey(const ValueKey('scene-quiet')), '8');
    ble.emit(fakeStatus(people: 3)); await tester.pump();
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('scene-quiet'))).controller!.text, '8');
    await tester.ensureVisible(find.byKey(const ValueKey('save-scenes'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-scenes'))); await tester.pumpAndSettle();
    expect(ble.commands.length, before); expect(find.byKey(const ValueKey('scene-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Arabic IR label byte limit is checked before learning', (tester) async {
    await client.connect(fakeDevice); final before = ble.commands.length;
    await tester.pumpWidget(MyApp(client: client));
    await tester.tap(find.text('تعلّم IR')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('learn-label')));
    await tester.enterText(find.byKey(const ValueKey('learn-label')), 'م' * 24);
    FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('learn-start'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('learn-start'))); await tester.pumpAndSettle();
    expect(ble.commands.length, before); expect(find.textContaining('في حدود 47 بايت'), findsOneWidget);
  });
  testWidgets('claim is not automatic; cancelling human confirmation sends nothing', (tester) async {
    ble.owned = false; vault.values.clear(); await client.connect(fakeDevice);
    await tester.pumpWidget(MyApp(client: client));
    await tester.ensureVisible(find.text('تسجيل الملكية بعد التأكيد')); await tester.pumpAndSettle();
    await tester.tap(find.text('تسجيل الملكية بعد التأكيد')); await tester.pumpAndSettle();
    expect(find.text('تسجيل هذا الهاتف مالكًا؟'), findsOneWidget);
    await tester.tap(find.text('إلغاء')); await tester.pumpAndSettle();
    expect(ble.commands.map((c) => c['op']), ['hello']); expect(vault.values, isEmpty);
  });
}

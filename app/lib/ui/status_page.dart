import 'package:flutter/material.dart';
import '../room_client.dart';
import 'common.dart';

String _phase(RoomClient client) => switch (client.phase) {
  RoomPhase.idle => 'غير متصل', RoomPhase.scanning => 'بحث لمدة 10 ثوانٍ',
  RoomPhase.connecting => 'اقتران آمن وإثبات ملكية', RoomPhase.needsClaim => 'بانتظار تسجيل المالك',
  RoomPhase.locked => 'وحدة مملوكة — الهاتف غير مخوّل', RoomPhase.error => 'العملية لم تكتمل',
  RoomPhase.ready => client.stale ? 'حالة الوحدة قديمة' : 'اتصال مالك واحد — حالة حديثة',
};

class StatusPage extends StatelessWidget {
  const StatusPage({super.key, required this.client});
  final RoomClient client;
  String _slot(int? slot) {
    if (slot == null || slot == 0) { return 'لا يوجد'; }
    for (final profile in client.profiles) { if (profile.slot == slot) { return '#$slot — ${profile.label}'; } }
    return '#$slot — غير متعلّمة / غير متاحة';
  }
  @override
  Widget build(BuildContext context) {
    final state = client.stale ? null : client.snapshot;
    final people = client.currentPeople;
    return RoomPage(children: [
      RoomPanel(title: 'رؤية الغرفة الآن', icon: Icons.groups_outlined, children: [
        Semantics(liveRegion: true, label: 'عدد الأشخاص', child: Text(
          people == null ? 'غير معروف' : '$people', key: const ValueKey('people-count'),
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.displayMedium)),
        const SizedBox(height: 10),
        Text(people == null ? 'لا توجد نتيجة رؤية حديثة موثوقة؛ لا نعاملها كصفر.'
          : 'عدد الأشخاص الظاهرين في الصورة التي حلّلها اللاب، وليس ضمانًا لوجود كل الأشخاص.', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        const Text('لا يوجد حساس حرارة أو تأكيد من التكييف في هذه النسخة.'),
        if (state != null && state.emptyRemainingMs > 0)
          Text('صفر حديث ومستمر: متبقٍ ${(state.emptyRemainingMs / 1000).ceil()} ثانية قبل مشهد الخلو.'),
      ]),
      RoomPanel(title: 'Bluetooth والملكية', icon: Icons.bluetooth, children: [
        Text(_phase(client), key: const ValueKey('link-state')),
        if (client.deviceId != null) SelectableText('Device: ${client.deviceId}', textDirection: TextDirection.ltr),
        const SizedBox(height: 12),
        const Text('البحث مفلتر بخدمة SmartRoom. اتصال هاتف واحد فقط؛ لا إعادة اتصال أو إرسال تلقائي بعد الانقطاع.'),
        const SizedBox(height: 12),
        if ([RoomPhase.idle, RoomPhase.scanning, RoomPhase.error].contains(client.phase))
          FilledButton.icon(key: const ValueKey('scan'), onPressed: client.busy || client.phase == RoomPhase.scanning
            ? null : () => client.scan(), icon: const Icon(Icons.radar), label: const Text('البحث عن الوحدة')),
        if (client.phase != RoomPhase.idle && client.phase != RoomPhase.error)
          OutlinedButton.icon(onPressed: () => client.disconnect(), icon: const Icon(Icons.bluetooth_disabled), label: const Text('فصل / إيقاف البحث')),
        for (final device in client.devices)
          ListTile(contentPadding: EdgeInsets.zero, title: Text(device.name),
            subtitle: Text('${device.id} • ${device.rssi} dBm', textDirection: TextDirection.ltr),
            trailing: FilledButton(onPressed: client.busy || client.authenticated ? null : () => client.connect(device), child: const Text('اتصال'))),
        if (client.phase == RoomPhase.needsClaim) ...[
          const Text('أدخل رمز الشاشة في نافذة اقتران Android. التسجيل يحتاج شاشة مُراجعة ونافذة محلية مفتوحة لمدة دقيقتين.'),
          FilledButton(onPressed: client.claimOpen && !client.busy ? () async {
            final confirmed = await confirmRoom(context, 'تسجيل هذا الهاتف مالكًا؟',
              'سيُحفظ مفتاح الملكية في تخزين Android المشفّر قبل إرساله عبر BLE الآمن. '
              'لا تشاركه ولا نعرضه. فقدان الهاتف/مفاتيحه يتطلب إجراء إعادة ملكية صريحًا عبر USB محلي.', accept: 'تسجيل الملكية');
            if (confirmed) { await client.claim(); }
          } : null, child: const Text('تسجيل الملكية بعد التأكيد')),
        ],
      ]),
      RoomPanel(title: 'طلبات التحكم — ليست قياسات من الأجهزة', icon: Icons.info_outline, children: [
        Text('الوضع: ${controlModeName(state?.mode)}'),
        Text('المشهد: ${sceneName(state?.scene)}'),
        Text('آخر طلب إضاءة: ${state == null ? 'غير معروف' : state.lights ? 'تشغيل' : 'إطفاء'} — غير مؤكد'),
        Text('خانة IR المطلوبة: ${_slot(state?.requestedSlot)}'),
        Text('آخر خانة أُرسلت نبضاتها: ${_slot(state?.sentSlot)}'),
        if (state != null) Text('حالة IR البرمجية: ${state.irResult}', textDirection: TextDirection.ltr),
        if (state != null && state.overrideMs > 0) Text('مدة التجاوز المتبقية: ${(state.overrideMs / 60000).ceil()} دقيقة'),
        const SizedBox(height: 12),
        Text('المخارج: ${state == null ? 'غير معروفة' : state.relayEnabled && state.irTxEnabled ? 'مفعّلة لاختبار مراجَع' : 'معطّلة كليًا أو جزئيًا حتى مراجعة القطع'}'),
      ]),
    ]);
  }
}

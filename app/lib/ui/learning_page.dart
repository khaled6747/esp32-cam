import 'package:flutter/material.dart';
import '../models.dart';
import '../room_client.dart';
import 'ac_editor.dart';
import 'common.dart';

class LearningPage extends StatefulWidget {
  const LearningPage({super.key, required this.client});
  final RoomClient client;
  @override
  State<LearningPage> createState() => _LearningPageState();
}
class _LearningPageState extends State<LearningPage> {
  final form = GlobalKey<FormState>();
  final label = TextEditingController();
  IrState state = IrState();
  int slot = 1, hz = 38000;
  @override
  void dispose() { label.dispose(); super.dispose(); }
  Future<void> start() async {
    if (!form.currentState!.validate()) { return; }
    final client = widget.client;
    final description = Profile(slot: slot, label: label.text.trim(), state: state, hz: hz);
    if (client.profiles.any((p) => p.slot == slot)) {
      if (!await confirmRoom(context, 'استبدال الخانة #$slot؟',
        'ستُستبدل الإشارة بعد التقاط إشارة صالحة وحفظها فقط. قد تكون الخانة مستخدمة في مشهد تلقائي.', accept: 'تعلّم واستبدال')) { return; }
    }
    await client.learn(description);
  }
  @override
  Widget build(BuildContext context) {
    final client = widget.client, current = client.stale ? null : client.snapshot;
    return RoomPage(children: [
      RoomPanel(title: 'تعلّم الريموت الأصلي', icon: Icons.sensors, children: [
        const Text('1. اضبط الريموت الأصلي على الحالة الكاملة التي تريد حفظها.\n'
          '2. طابق وصف الحرارة والمروحة والوضع والتشغيل وSleep أدناه.\n'
          '3. ابدأ التعلّم، ثم اضغط زرًا واحدًا مرة واحدة باتجاه المستقبل خلال 30 ثانية.\n'
          '4. جرّب الإشارة مع التكييف بعد اعتماد التوصيل؛ التخزين وحده لا يثبت اكتمالها.'),
        const SizedBox(height: 12),
        if (current?.irRxEnabled != true) const Text('مستقبل IR معطّل / غير متاح حتى مراجعة صور القطعة وجهد OUT.'),
        if (current?.storageReady == false) ...[
          const Text('مساحة ملفات IR غير مجهزة. التهيئة لا تمسح ملفات mounted سليمة، لكنها تهيئ القسم غير القابل للقراءة بعد تأكيدك.'),
          OutlinedButton(onPressed: client.canControl ? () async {
            if (await confirmRoom(context, 'تهيئة مساحة IR غير المجهزة؟',
              'قد تُفقد بيانات غير قابلة للقراءة في قسم الملفات. لا حاجة لهذا الزر إذا كانت المساحة جاهزة. لا يعيد ضبط ملكية الهاتف.', accept: 'تهيئة بعد التأكيد')) {
              await client.initializeStorage(confirmed: true);
            }
          } : null, child: const Text('تهيئة ملفات IR بعد التأكيد')),
        ],
      ]),
      RoomPanel(title: 'وصف الإشارة — ليس فكًا مؤكدًا للبروتوكول', children: [
        Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<int>(initialValue: slot, decoration: const InputDecoration(labelText: 'خانة الحفظ (1–16)'),
            items: List.generate(16, (i) => DropdownMenuItem(value: i + 1, child: Text('#${i + 1}'))),
            onChanged: (value) { if (value != null) { setState(() => slot = value); } }),
          const SizedBox(height: 16),
          TextFormField(key: const ValueKey('learn-label'), controller: label, maxLength: 47,
            decoration: const InputDecoration(labelText: 'اسم الحالة', helperText: 'حتى 47 بايت UTF-8؛ الأحرف العربية قد تستخدم أكثر من بايت.'),
            validator: (value) {
              final text = (value ?? '').trim();
              return text.isEmpty || labelBytes(text) > 47 || text.runes.any((r) => r < 32)
                ? 'أدخل اسمًا بلا محارف تحكم وفي حدود 47 بايت.' : null;
            }),
          AcEditor(state: state, onChanged: (value) => setState(() => state = value)),
          DropdownButtonFormField<int>(initialValue: hz, decoration: const InputDecoration(labelText: 'حامل IR المختار (Hz)'),
            items: [36000, 38000, 40000, 56000].map((value) => DropdownMenuItem(value: value, child: Text('$value Hz'))).toList(),
            onChanged: (value) { if (value != null) { setState(() => hz = value); } }),
          const SizedBox(height: 12),
          const Text('المستقبل المفكّك للحامل لا يقيس تردد الحامل؛ 38 kHz افتراض يحتاج تحققًا، لا قياس.'),
          const SizedBox(height: 12),
          FilledButton.icon(key: const ValueKey('learn-start'), icon: const Icon(Icons.fiber_manual_record),
            onPressed: client.canControl && current?.irRxEnabled == true && current?.storageReady == true && client.learningSlot == 0
              ? start : null, label: const Text('ابدأ تعلّم الإشارة')),
          if (client.learningSlot != 0) ...[
            Text('بانتظار الريموت — الخانة #${client.learningSlot}. لا إرسال IR أثناء التعلّم.'),
            OutlinedButton(onPressed: client.canControl ? () => client.cancelLearning() : null, child: const Text('إلغاء التعلّم')),
          ],
        ])),
      ]),
      RoomPanel(title: 'الحالات المحفوظة على الوحدة', icon: Icons.inventory_2_outlined, children: [
        if (client.profiles.isEmpty) const Text('لا حالات متعلّمة متاحة الآن. القائمة تُقرأ بعد إثبات الملكية.'),
        for (final profile in client.profiles) Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('#${profile.slot} — ${profile.label}', style: Theme.of(context).textTheme.titleSmall),
            Text('${profile.state.temperature}°C • ${fanName(profile.state.fan)} • ${acModeName(profile.state.mode)}\n'
              '${profile.state.power ? 'تشغيل' : 'إطفاء'} • Sleep: ${profile.state.sleep ? 'نعم' : 'لا'} • ${profile.hz} Hz • ${profile.pulses} نبضة'),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: client.canControl && current?.irTxEnabled == true ? () async {
                if (await confirmRoom(context, 'اختبار الخانة #${profile.slot}؟',
                  'سيرسل نبضات الحالة الكاملة وقد يشغّل التكييف فعليًا إن كان المرسل مفعّلًا. تجاوز تلقائي لمدة 5 دقائق؛ لا تأكيد من الجهاز.', accept: 'إرسال للاختبار')) {
                  await client.sendSlot(profile.slot, 300000);
                }
              } : null, child: const Text('اختبار بإرسال صريح')),
              TextButton(onPressed: client.canControl ? () async {
                if (await confirmRoom(context, 'حذف الخانة #${profile.slot}؟',
                  'سيُحذف ملف الإشارة. المشاهد التي تشير للخانة ستظهر غير متعلّمة، ولن تختار بديلًا.', accept: 'حذف الخانة')) {
                  await client.eraseSlot(profile.slot, confirmed: true);
                }
              } : null, child: const Text('حذف بعد التأكيد')),
            ]),
          ])),
      ]),
    ]);
  }
}

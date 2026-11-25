import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../room_client.dart';
import 'common.dart';

class ScenesPage extends StatefulWidget {
  const ScenesPage({super.key, required this.client});
  final RoomClient client;
  @override
  State<ScenesPage> createState() => _ScenesPageState();
}
class _ScenesPageState extends State<ScenesPage> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  int quietSlot = 1, normalSlot = 2, busySlot = 3, sleepSlot = 4;
  bool seeded = false;
  String? error;
  @override
  void initState() {
    super.initState();
    for (final key in ['quiet', 'normal', 'ttl', 'empty', 'settle', 'manual', 'gap']) { fields[key] = TextEditingController(); }
    seed(const RuleConfig());
  }
  void seed(RuleConfig config) {
    fields['quiet']!.text = '${config.quietMax}'; fields['normal']!.text = '${config.normalMax}';
    fields['ttl']!.text = '${config.ttlMs ~/ 1000}'; fields['empty']!.text = '${config.emptyMs ~/ 1000}';
    fields['settle']!.text = '${config.settleMs ~/ 1000}'; fields['manual']!.text = '${config.manualMs ~/ 60000}';
    fields['gap']!.text = '${config.irGapMs ~/ 1000}'; quietSlot = config.quietSlot;
    normalSlot = config.normalSlot; busySlot = config.busySlot; sleepSlot = config.sleepSlot;
  }
  @override
  void dispose() { for (final field in fields.values) { field.dispose(); } super.dispose(); }
  Widget numberField(String key, String title, int low, int high) => Padding(
    padding: const EdgeInsets.only(bottom: 16), child: TextFormField(
      key: ValueKey('scene-$key'), controller: fields[key], keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 4,
      decoration: InputDecoration(labelText: title, helperText: '$low–$high (أرقام 0–9)'),
      validator: (value) { final number = int.tryParse(value ?? ''); return number == null || number < low || number > high ? 'قيمة بين $low و$high مطلوبة.' : null; },
    ));
  Widget slotField(String title, int value, ValueChanged<int> change) => Padding(
    padding: const EdgeInsets.only(bottom: 16), child: DropdownButtonFormField<int>(
      key: ValueKey('slot-$title-$value'), initialValue: value, isExpanded: true,
      decoration: InputDecoration(labelText: title),
      items: List.generate(16, (i) {
        final slot = i + 1;
        final found = widget.client.profiles.where((p) => p.slot == slot);
        return DropdownMenuItem(value: slot, child: Text('#$slot — ${found.isEmpty ? 'غير متعلّمة' : found.first.label}', overflow: TextOverflow.ellipsis));
      }),
      onChanged: (value) { if (value != null) { setState(() => change(value)); } },
    ));
  Future<void> save() async {
    if (!form.currentState!.validate()) { return; }
    int value(String key) => int.parse(fields[key]!.text);
    final config = RuleConfig(quietMax: value('quiet'), normalMax: value('normal'),
      ttlMs: value('ttl') * 1000, emptyMs: value('empty') * 1000, settleMs: value('settle') * 1000,
      manualMs: value('manual') * 60000, irGapMs: value('gap') * 1000,
      quietSlot: quietSlot, normalSlot: normalSlot, busySlot: busySlot, sleepSlot: sleepSlot);
    if (!config.valid) { setState(() => error = 'حد الإشغال المتوسط يجب أن يتجاوز القليل، ومهلة الخلو أكبر من TTL. لم نرسل الإعدادات.'); return; }
    final missing = [quietSlot, normalSlot, busySlot, sleepSlot].where((slot) => !widget.client.profiles.any((p) => p.slot == slot)).toSet();
    if (missing.isNotEmpty) {
      if (!await confirmRoom(context, 'مشاهد بخانات غير متعلّمة',
        'الخانات ${missing.join(', ')} لا تحتوي إشارة. يمكن حفظ القواعد الآن، لكن IR سيظهر غير متعلّم دون بديل إلى أن تتعلّمها.', accept: 'حفظ القواعد فقط')) { return; }
    }
    setState(() => error = null);
    await widget.client.configure(config);
  }
  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    if (!seeded && client.snapshot != null) { seed(client.snapshot!.config); seeded = true; }
    return RoomPage(children: [
      RoomPanel(title: 'قواعد تُنفّذ على ESP32', icon: Icons.auto_awesome, children: [
        const Text('الإضاءة تُطلب عند وجود أشخاص. التكييف يختار إحدى 3 خانات بعد استقرار العدد. '
          'الصفر يجب أن يبقى حديثًا ومستمرًا طوال مهلة الخلو قبل إطفاء الإضاءة واختيار خانة النوم/الخلو. '
          'فقدان الرؤية يجمّد التغييرات التلقائية؛ ليس صفرًا ولا نومًا.'),
        if (!client.authenticated) const Text('الإعدادات أدناه افتراضية حتى الاتصال وإثبات الملكية.'),
      ]),
      RoomPanel(title: 'حدود العدد والخانات', children: [
        Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          numberField('quiet', 'أعلى عدد للإشغال القليل', 1, 49),
          numberField('normal', 'أعلى عدد للإشغال المتوسط (المرتفع أكبر منه)', 2, 50),
          slotField('خانة الإشغال القليل', quietSlot, (value) => quietSlot = value),
          slotField('خانة الإشغال المتوسط', normalSlot, (value) => normalSlot = value),
          slotField('خانة الإشغال المرتفع', busySlot, (value) => busySlot = value),
          slotField('خانة النوم الصريح / الخلو المستمر', sleepSlot, (value) => sleepSlot = value),
          numberField('ttl', 'صلاحية صورة المصدر (ثوانٍ)', 1, 10),
          numberField('empty', 'مهلة صفر مستمر قبل مشهد الخلو (ثوانٍ)', 10, 3600),
          numberField('settle', 'استقرار فئة العدد قبل تغيير IR (ثوانٍ)', 1, 60),
          numberField('gap', 'أقل فاصل بين إرسالَي IR (ثوانٍ)', 5, 300),
          numberField('manual', 'مدة يدوي افتراضية للوحدة (دقائق)', 1, 720),
          if (error != null) Text(error!, key: const ValueKey('scene-error')),
          FilledButton.icon(key: const ValueKey('save-scenes'), onPressed: client.canControl ? save : null,
            icon: const Icon(Icons.save_outlined), label: const Text('حفظ القواعد على الوحدة')),
          OutlinedButton(onPressed: client.canControl ? () => setState(() { seed(client.snapshot!.config); error = null; }) : null,
            child: const Text('استعادة القيم المقروءة من الوحدة')),
        ])),
      ]),
    ]);
  }
}

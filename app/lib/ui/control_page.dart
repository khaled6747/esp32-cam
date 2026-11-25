import 'package:flutter/material.dart';
import '../models.dart';
import '../room_client.dart';
import 'ac_editor.dart';
import 'common.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key, required this.client});
  final RoomClient client;
  @override
  State<ControlPage> createState() => _ControlPageState();
}
class _ControlPageState extends State<ControlPage> {
  IrState state = IrState();
  int lease = 1800000;
  @override
  Widget build(BuildContext context) {
    final client = widget.client, current = client.stale ? null : client.snapshot;
    final profile = findProfile(client.profiles, state);
    return RoomPage(children: [
      RoomPanel(title: 'مدة التحكم المؤقت', icon: Icons.timer_outlined, children: [
        LeasePicker(value: lease, onChanged: (value) => setState(() => lease = value)),
        const SizedBox(height: 12),
        const Text('أي أمر يدوي يوقف الأتمتة لهذه المدة، ثم ترجع للوضع التلقائي. النوم اختيار صريح، وليس كشفًا من قلة الحركة.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: client.canControl ? () => client.setMode('auto', 0) : null, child: const Text('العودة للتلقائي')),
          OutlinedButton(onPressed: client.canControl ? () => client.setMode('manual', lease) : null, child: const Text('تجميد تلقائي مؤقت')),
          FilledButton.tonalIcon(key: const ValueKey('sleep-policy'), icon: const Icon(Icons.bedtime_outlined),
            onPressed: client.canControl ? () => client.setMode('sleep', lease) : null, label: const Text('مشهد نوم مؤقت')),
        ]),
      ]),
      RoomPanel(title: 'إضاءة الغرفة', icon: Icons.lightbulb_outline, children: [
        Text(current?.relayEnabled == true ? 'طلب يدوي — لا يوجد حساس يؤكد حالة اللمبة.' : 'مخرج الريلاي معطّل / غير متاح. لا توصيل كهرباء عمومية الآن.'),
        const SizedBox(height: 12),
        Wrap(spacing: 12, children: [
          FilledButton(key: const ValueKey('lights-on'), onPressed: client.canControl && current?.relayEnabled == true
            ? () => client.lights(true, lease) : null, child: const Text('طلب تشغيل الإضاءة')),
          OutlinedButton(key: const ValueKey('lights-off'), onPressed: client.canControl && current?.relayEnabled == true
            ? () => client.lights(false, lease) : null, child: const Text('طلب إطفاء الإضاءة')),
        ]),
      ]),
      RoomPanel(title: 'حالة التكييف الكاملة', icon: Icons.ac_unit, children: [
        AcEditor(state: state, onChanged: (value) => setState(() => state = value)),
        const SizedBox(height: 12),
        Text(profile == null ? 'الحالة غير متعلّمة — لن نختار حرارة أو مروحة بديلة.' : 'مطابقة كاملة للخانة #${profile.slot}: ${profile.label}',
          key: const ValueKey('state-match')),
        if (current?.irTxEnabled != true) const Text('إرسال IR معطّل حتى مراجعة المرسل ودائرة النبضات.'),
        const SizedBox(height: 12),
        FilledButton.icon(key: const ValueKey('send-ac'), onPressed: client.canControl && current?.irTxEnabled == true
          ? () => client.sendAc(state, lease) : null, icon: const Icon(Icons.send_outlined), label: const Text('إرسال الحالة المتعلّمة')),
        const Text('نجاح الإرسال يعني نبضات خرجت فقط، وليس أن التكييف استجاب. الحقول الوصفية تأتي من ضبطك للريموت الأصلي أثناء التعلّم.'),
      ]),
    ]);
  }
}

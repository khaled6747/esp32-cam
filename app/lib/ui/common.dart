import 'package:flutter/material.dart';

class RoomPanel extends StatelessWidget {
  const RoomPanel({super.key, required this.title, required this.children, this.icon});
  final String title;
  final List<Widget> children;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(padding: const EdgeInsets.all(20), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Row(children: [if (icon != null) ...[Icon(icon, size: 22), const SizedBox(width: 10)],
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium))]),
        const SizedBox(height: 16), ...children],
    )),
  );
}

class RoomPage extends StatelessWidget {
  const RoomPage({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
    )),
  );
}

Future<bool> confirmRoom(BuildContext context, String title, String message,
    {String accept = 'تأكيد'}) async => await showDialog<bool>(context: context,
  builder: (context) => AlertDialog(title: Text(title), content: Text(message),
    actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(accept))]),
) ?? false;

String fanName(int fan) => const ['تلقائي', 'منخفض', 'متوسط', 'عالي'][fan];
String acModeName(int mode) => const ['Auto', 'Cool — تبريد', 'Dry — تجفيف', 'Fan — مروحة', 'Heat — تدفئة'][mode];
String controlModeName(String? mode) => switch (mode) { 'auto' => 'تلقائي', 'manual' => 'يدوي مؤقت', 'sleep' => 'نوم مؤقت', _ => 'غير معروف' };
String sceneName(String? scene) => switch (scene) {
  'quiet' => 'إشغال قليل', 'normal' => 'إشغال متوسط', 'busy' => 'إشغال مرتفع',
  'sleep' => 'مشهد النوم / الخلو', 'manual' => 'تحكم يدوي', _ => 'لا مشهد حالي',
};

class LeasePicker extends StatelessWidget {
  const LeasePicker({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    key: ValueKey('lease-$value'), initialValue: value, isExpanded: true,
    decoration: const InputDecoration(labelText: 'مدة التجاوز اليدوي / النوم'),
    items: const [5, 15, 30, 60, 120, 240, 480, 720].map((minutes) => DropdownMenuItem(
      value: minutes * 60000, child: Text(minutes < 60 ? '$minutes دقيقة' : '${minutes ~/ 60} ساعة'))).toList(),
    onChanged: (value) { if (value != null) { onChanged(value); } },
  );
}

import 'package:flutter/material.dart';
import '../models.dart';
import 'common.dart';

class AcEditor extends StatelessWidget {
  const AcEditor({super.key, required this.state, required this.onChanged, this.compact = false});
  final IrState state;
  final ValueChanged<IrState> onChanged;
  final bool compact;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton.filledTonal(tooltip: 'تقليل الحرارة المضبوطة', onPressed: state.temperature > 16
        ? () => onChanged(state.copyWith(temperature: state.temperature - 1)) : null,
        icon: const Icon(Icons.remove)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Text('${state.temperature}°C', style: Theme.of(context).textTheme.displaySmall)),
      IconButton.filledTonal(tooltip: 'زيادة الحرارة المضبوطة', onPressed: state.temperature < 30
        ? () => onChanged(state.copyWith(temperature: state.temperature + 1)) : null,
        icon: const Icon(Icons.add)),
    ]),
    const Text('درجة مضبوطة في الأمر، وليست قراءة حرارة الغرفة.', textAlign: TextAlign.center),
    const SizedBox(height: 20),
    DropdownButtonFormField<int>(key: ValueKey('fan-${state.fan}'), initialValue: state.fan,
      isExpanded: true, decoration: const InputDecoration(labelText: 'سرعة المروحة في الحالة الكاملة'),
      items: List.generate(4, (i) => DropdownMenuItem(value: i, child: Text(fanName(i)))),
      onChanged: (value) { if (value != null) { onChanged(state.copyWith(fan: value)); } }),
    const SizedBox(height: 16),
    DropdownButtonFormField<int>(key: ValueKey('ac-mode-${state.mode}'), initialValue: state.mode,
      isExpanded: true, decoration: const InputDecoration(labelText: 'وضع التكييف'),
      items: List.generate(5, (i) => DropdownMenuItem(value: i, child: Text(acModeName(i)))),
      onChanged: (value) { if (value != null) { onChanged(state.copyWith(mode: value)); } }),
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('أمر التشغيل'),
      subtitle: Text(state.power ? 'الحالة المتعلّمة تطلب تشغيل التكييف' : 'الحالة المتعلّمة تطلب إطفاء التكييف'),
      value: state.power, onChanged: (value) => onChanged(state.copyWith(power: value))),
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Sleep داخل إشارة الريموت'),
      subtitle: const Text('هذه خانة في الحالة المتعلّمة، وليست استنتاجًا بأن شخصًا نائم.'),
      value: state.sleep, onChanged: (value) => onChanged(state.copyWith(sleep: value))),
  ]);
}

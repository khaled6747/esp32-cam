import 'package:flutter/material.dart';
import '../room_client.dart';
import 'common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.client});
  final RoomClient client;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('الإعدادات وحدود التشغيل')),
    body: RoomPage(children: [
      RoomPanel(title: 'نسخة اللاب — Android أولًا', icon: Icons.developer_board_outlined, children: [
        const Text('Smart Room 0.1.0 • نموذج أولي محلي\nلا تسجيل صور، لا إنترنت مطلوب للتشغيل، ولا خدمة BLE في الخلفية. '
          'اللاب يحلّل صورة ESP32-CAM؛ الوحدة تحفظ القواعد وIR. غلق التطبيق يفصل BLE، وليس رؤية اللاب.'),
        const SizedBox(height: 12),
        const Text('المخارج في الفيرموير معطّلة افتراضيًا. صور الريلاي ومستقبل IR والترانزستور وظهر OLED مطلوبة قبل اختيار الجهد والقطبية والتوصيل والفلاش. '
          'البروتوبورد وأسلاك Jumper ليست توصيلًا آمنًا لكهرباء عمومية.'),
      ]),
      RoomPanel(title: 'خطوات الاقتران بعد اعتماد الهاردوير', icon: Icons.lock_outline, children: [
        const Text('1. شغّل الوحدة وشاشة OLED المُراجعة.\n2. ابحث هنا عن خدمة SmartRoom واختر الوحدة.\n'
          '3. أدخل رمز الشاشة في نافذة Android؛ لا توافق على اقتران بلا رمز.\n'
          '4. سجّل هذا الهاتف إذا كانت الوحدة بلا مالك، ثم اقرأ الحالة.\n'
          'النافذة المحلية دقيقتان بعد الإقلاع أو أمر USB صريح. لا توجد ملكية تلقائية أو نقل ملكية عن بُعد.'),
        const SizedBox(height: 12),
        const Text('الوحدة المملوكة بلا مفتاح على الهاتف تبقى مقفلة. حذف التطبيق/فقدان التخزين قد يفقد المفتاح. '
          'إعادة الملكية فقط بإجراء USB محلي مؤكد؛ ليس زرًا يحاول مسح مالك آخر. تطبيقات BLE العامة قد ترى الإعلان، لكنها ليست مخوّلة للتحكم.'),
      ]),
      RoomPanel(title: 'فهم النتائج', icon: Icons.fact_check_outlined, children: [
        const Text('«غير معروف» لا يعني صفرًا. Sleep في الريموت حالة متعلّمة، ومشهد النوم اختيار مؤقت من الشخص. '
          'لا نقيس حرارة الغرفة، ولا نعرف استجابة التكييف أو المصباح. «قبول للجدولة» غير «إرسال نبضات»، وكلاهما غير تأكيد من الجهاز.'),
        const SizedBox(height: 12),
        Text('هوية الوحدة المقروءة: ${client.deviceId ?? 'غير متاحة'}'),
        OutlinedButton(onPressed: () => showLicensePage(context: context, applicationName: 'Smart Room', applicationVersion: '0.1.0'),
          child: const Text('رخص مكونات التطبيق')),
      ]),
    ]));
}

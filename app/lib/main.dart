import 'dart:async';
import 'package:flutter/material.dart';
import 'ble_transport.dart';
import 'room_client.dart';
import 'ui/control_page.dart';
import 'ui/learning_page.dart';
import 'ui/scenes_page.dart';
import 'ui/settings_page.dart';
import 'ui/status_page.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const MyApp()); }

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.client});
  final RoomClient? client;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final RoomClient client;
  @override
  void initState() {
    super.initState();
    client = widget.client ?? RoomClient(transport: AndroidBleTransport(), vault: SecureOwnerVault());
    WidgetsBinding.instance.addObserver(this);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android permission/pairing dialogs can cause "inactive". Only actual
    // backgrounding is terminal for this foreground-owned BLE connection.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(client.disconnect());
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.client == null) { client.dispose(); }
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(seedColor: const Color(0xff54ceb7), brightness: Brightness.dark);
    return MaterialApp(title: 'Smart Room', debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xff10191f),
        cardTheme: CardThemeData(color: const Color(0xff192730), elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      ),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: RoomHome(client: client));
  }
}

class RoomHome extends StatefulWidget {
  const RoomHome({super.key, required this.client});
  final RoomClient client;
  @override
  State<RoomHome> createState() => _RoomHomeState();
}

class _RoomHomeState extends State<RoomHome> {
  int selected = 0;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.client,
    builder: (context, _) {
      final client = widget.client;
      return Scaffold(
        appBar: AppBar(title: const Text('الغرفة الذكية'), actions: [
          if (client.authenticated) IconButton(tooltip: 'تحديث بيانات الوحدة',
            onPressed: !client.busy ? () => client.refresh() : null, icon: const Icon(Icons.refresh)),
          IconButton(tooltip: 'الإعدادات وحدود التشغيل', icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => SettingsPage(client: client)))),
        ]),
        body: SafeArea(child: Column(children: [
          if (client.busy) const LinearProgressIndicator(minHeight: 2),
          if (client.lastError != null || client.lastMessage != null)
            Semantics(liveRegion: true, child: Container(
              constraints: const BoxConstraints(maxHeight: 135), width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: client.lastError != null ? Theme.of(context).colorScheme.errorContainer : const Color(0xff1d403c),
              child: SingleChildScrollView(child: Text(client.lastError ?? client.lastMessage!)))),
          Expanded(child: IndexedStack(index: selected, children: [
            StatusPage(client: client), ControlPage(client: client), LearningPage(client: client),
            ScenesPage(key: ValueKey('scenes-${client.epoch}'), client: client),
          ])),
        ])),
        bottomNavigationBar: NavigationBar(selectedIndex: selected,
          onDestinationSelected: (index) => setState(() => selected = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'الحالة'),
            NavigationDestination(icon: Icon(Icons.settings_remote_outlined), selectedIcon: Icon(Icons.settings_remote), label: 'تحكم'),
            NavigationDestination(icon: Icon(Icons.sensors), label: 'تعلّم IR'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'المشاهد'),
          ]),
      );
    });
}

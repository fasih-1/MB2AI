import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';

import 'screens/dashboard.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await localNotifier.setup(
    appName: 'MB2AI Command Center',
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );
  runApp(const Mb2AiApp());
}

class Mb2AiApp extends StatelessWidget {
  const Mb2AiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MB2AI',
      theme: buildAppTheme(),
      home: DashboardScreen(apiService: apiService),
    );
  }
}

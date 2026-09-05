import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';

import 'screens/dashboard.dart';
import 'services/api_service.dart';
import 'theme/accent_color_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await localNotifier.setup(
    appName: 'MB2AI Command Center',
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );

  final accentController = AccentColorController();
  await accentController.load();

  runApp(Mb2AiApp(accentController: accentController));
}

class Mb2AiApp extends StatelessWidget {
  const Mb2AiApp({super.key, required this.accentController});

  final AccentColorController accentController;

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService();

    return ListenableBuilder(
      listenable: accentController,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'MB2AI',
          theme: buildAppTheme(accentController.accent),
          home: DashboardScreen(
            apiService: apiService,
            accentController: accentController,
          ),
        );
      },
    );
  }
}

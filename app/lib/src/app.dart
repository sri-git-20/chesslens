import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_info.dart';
import 'home/home_screen.dart';
import 'navigation.dart';
import 'report/crash_prompt.dart';
import 'settings/settings_controller.dart';
import 'theme/app_theme.dart';

class ChessLensApp extends ConsumerWidget {
  const ChessLensApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(trueBlack: settings.trueBlack),
      themeMode: settings.themeMode,
      navigatorObservers: [appRouteObserver],
      home: const CrashReportPrompt(child: HomeScreen()),
    );
  }
}

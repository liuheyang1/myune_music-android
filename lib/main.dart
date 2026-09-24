import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:provider/provider.dart';

import 'mobile/mobile_app.dart';
import 'layout/navigation_notifier.dart';
import 'page/playlist/playlist_content_notifier.dart';
import 'page/setting/settings_provider.dart';
import 'page/statistics_page/statistics_manager.dart';
import 'services/notification_service.dart';
import 'src/rust/frb_generated.dart';
import 'theme/theme_provider.dart';

/// Android entry point.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 20 * 1024 * 1024;

  MpvAudioKit.ensureInitialized();
  await RustLib.init();

  final themeProvider = ThemeProvider();
  await themeProvider.initialize();

  final statisticsManager = StatisticsManager();
  await statisticsManager.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider(
          create: (context) => PlaylistContentNotifier(
            context.read<SettingsProvider>(),
            context.read<ThemeProvider>(),
            context.read<NotificationService>(),
          ),
        ),
        ChangeNotifierProvider<StatisticsManager>.value(
          value: statisticsManager,
        ),
        ChangeNotifierProvider(create: (_) => NavigationNotifier()),
      ],
      child: const MobileApp(),
    ),
  );
}

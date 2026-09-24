import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../page/mobile/mobile_home.dart';
import '../theme/theme_provider.dart';
import '../widgets/playing_queue_drawer.dart';
import '../widgets/toast_overlay.dart';

class MobileApp extends StatelessWidget {
  const MobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'MyuneMusic',
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CH'), Locale('en', 'US')],
          locale: const Locale('zh', 'CH'),
          theme: themeProvider.lightThemeData,
          darkTheme: themeProvider.darkThemeData,
          themeMode: themeProvider.themeMode,
          home: const _MobileShell(),
        );
      },
    );
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      endDrawer: PlayingQueueDrawer(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Material(color: Colors.transparent, child: MobileHome()),
          ),
          ToastOverlay(),
        ],
      ),
    );
  }
}

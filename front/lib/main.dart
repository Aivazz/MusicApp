import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ses/firebase_options.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/core/widgets/main_layout.dart';
import 'package:ses/features/auth/screens/login_screen.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/core/utils/cover_service.dart';
import 'package:ses/features/import_export/services/pirate_service.dart';
import 'package:ses/features/player/services/lyrics_service.dart';
import 'package:ses/features/player/services/audio_handler.dart';
import 'package:ses/core/network/firebase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Limit Flutter image cache to 30MB and 120 images to optimize RAM usage (OZU)
  PaintingBinding.instance.imageCache.maximumSizeBytes = 30 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 120;

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Preload cover art, stream URL cache and lyrics cache on startup in background
  CoverService.preload();
  PirateService.loadCache();
  LyricsService.loadCache();

  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.ses.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
      artDownscaleWidth: 300,
      artDownscaleHeight: 300,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()..init()),
        ChangeNotifierProxyProvider<UserProvider, PlayerProvider>(
          create: (_) => PlayerProvider(),
          update: (_, user, player) => player!..setDependency(user),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class CupertinoScrollBehavior extends MaterialScrollBehavior {
  const CupertinoScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ses Music',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const CupertinoScrollBehavior(),
      home: StreamBuilder<User?>(
        stream: FirebaseService.authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: CircularProgressIndicator(
                  color: AppColors.accentBlue,
                ),
              ),
            );
          }
          final user = snapshot.data;
          final isLoggedIn = user != null && !user.isAnonymous;

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                  ),
                  child: child,
                ),
              );
            },
            child: isLoggedIn
                ? const MainLayout(key: ValueKey('main'))
                : const LoginScreen(key: ValueKey('login')),
          );
        },
      ),
    );
  }
}

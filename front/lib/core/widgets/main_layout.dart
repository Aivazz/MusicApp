import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/player/widgets/mini_player.dart';
import 'package:ses/features/player/widgets/wide_player_bar.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/screens/library_screen.dart';
import 'package:ses/features/library/screens/settings_screen.dart';
import 'package:ses/core/widgets/profile_sheet.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/cinema/screens/cinema_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with TickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _musicNavigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _cinemaNavigatorKey = GlobalKey<NavigatorState>();
  final ValueNotifier<bool> _isKeyboardVisible = ValueNotifier<bool>(false);

  late final AnimationController _transitionController;
  String _prevAppMode = 'music';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialMode = context.read<UserProvider>().appMode;
    _prevAppMode = initialMode;
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: initialMode == 'music' ? 0.0 : 1.0,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isKeyboardVisible.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isNotEmpty) {
      final isVisible = views.first.viewInsets.bottom > 0;
      if (_isKeyboardVisible.value != isVisible) {
        _isKeyboardVisible.value = isVisible;
      }
    }
  }

  Widget _buildSidebar(BuildContext context, UserProvider user, String appMode) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(
          right: BorderSide(color: Colors.white10, width: 0.8),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.white, Color(0xFF888888)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                "SES PLAY",
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Section: Media Library
          _buildSidebarSectionTitle("МЕДИАТЕКА"),
          _buildSidebarItem(
            icon: Iconsax.music,
            label: "Музыка",
            isActive: appMode == 'music',
            onTap: () {
              if (appMode != 'music') {
                user.setAppMode('music');
              }
            },
          ),
          _buildSidebarItem(
            icon: Iconsax.video_play,
            label: "Кино",
            isActive: appMode == 'cinema',
            onTap: () {
              if (appMode != 'cinema') {
                user.setAppMode('cinema');
              }
            },
          ),
          
          const Spacer(),
          
          // Section: Settings & Account
          _buildSidebarSectionTitle("АККАУНТ И НАСТРОЙКИ"),
          _buildSidebarItem(
            icon: Iconsax.user,
            label: "Профиль",
            isActive: false,
            onTap: () => ProfileSheet.show(context),
          ),
          _buildSidebarItem(
            icon: Iconsax.setting_2,
            label: "Настройки",
            isActive: false,
            onTap: () {
              final activeNavigatorKey = appMode == 'music' ? _musicNavigatorKey : _cinemaNavigatorKey;
              activeNavigatorKey.currentState?.push(
                AppPageRoute.create(context, const SettingsScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSidebarSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 12, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white30,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive ? AppColors.accentGreen : Colors.white60,
              size: 20,
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: isActive ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCurrentSong = context.select<PlayerProvider, bool>((p) => p.currentSong != null);
    final showMiniPlayer = context.select<PlayerProvider, bool>((p) => p.showMiniPlayer);
    final appMode = context.select<UserProvider, String>((u) => u.appMode);
    final isWide = MediaQuery.of(context).size.width >= 800;

    if (appMode != _prevAppMode) {
      if (appMode == 'music') {
        _transitionController.reverse();
      } else {
        _transitionController.forward();
      }
      _prevAppMode = appMode;
    }

    final activeNavigatorKey = appMode == 'music' ? _musicNavigatorKey : _cinemaNavigatorKey;

    final musicAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _transitionController, curve: Curves.easeInOutCubic),
    );
    final cinemaAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _transitionController, curve: Curves.easeInOutCubic),
    );

    final musicSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.06, 0.0),
    ).animate(CurvedAnimation(parent: _transitionController, curve: Curves.easeInOutCubic));

    final cinemaSlide = Tween<Offset>(
      begin: const Offset(0.06, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _transitionController, curve: Curves.easeInOutCubic));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = activeNavigatorKey.currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: AppColors.background,
        body: ValueListenableBuilder<bool>(
          valueListenable: _isKeyboardVisible,
          builder: (context, isKeyboardVisible, child) {
            return Stack(
              children: [
                // ── SIDEBAR (Left panel for wide screens) ──
                if (isWide)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: (hasCurrentSong && showMiniPlayer && !isKeyboardVisible) ? 88 : 0,
                    width: 240,
                    child: _buildSidebar(context, Provider.of<UserProvider>(context, listen: false), appMode),
                  ),

                // ── NESTED NAVIGATORS ──
                Positioned(
                  left: isWide ? 240 : 0,
                  right: 0,
                  top: 0,
                  bottom: isWide ? ((hasCurrentSong && showMiniPlayer && !isKeyboardVisible) ? 88 : 0) : 0,
                  child: Stack(
                    children: [
                      // Вкладка Музыка
                      IgnorePointer(
                        ignoring: appMode != 'music',
                        child: FadeTransition(
                          opacity: musicAnimation,
                          child: SlideTransition(
                            position: musicSlide,
                            child: Navigator(
                              key: _musicNavigatorKey,
                              onGenerateRoute: (settings) {
                                return MaterialPageRoute(
                                  builder: (_) => const LibraryScreen(),
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      // Вкладка Кино
                      IgnorePointer(
                        ignoring: appMode != 'cinema',
                        child: FadeTransition(
                          opacity: cinemaAnimation,
                          child: SlideTransition(
                            position: cinemaSlide,
                            child: Navigator(
                              key: _cinemaNavigatorKey,
                              onGenerateRoute: (settings) {
                                return MaterialPageRoute(
                                  builder: (_) => const CinemaScreen(),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── PERSISTENT MINI-PLAYER OR WIDE PLAYER BAR ──
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: (hasCurrentSong && showMiniPlayer && !isKeyboardVisible)
                        ? (isWide
                            ? const WidePlayerBar(key: ValueKey('wide_player'))
                            : (appMode == 'music'
                                ? Hero(
                                    key: const ValueKey('miniplayer_visible'),
                                    tag: 'miniplayer',
                                    child: Material(
                                      color: Colors.transparent,
                                      child: const MiniPlayer(),
                                    ),
                                  )
                                : const SizedBox.shrink(key: ValueKey('miniplayer_hidden_cinema'))))
                        : const SizedBox.shrink(key: ValueKey('player_hidden')),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

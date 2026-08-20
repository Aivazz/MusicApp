import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:ses/core/network/firebase_service.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/player/providers/player_provider.dart';

class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) => const ProfileSheet(),
    );
  }

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  bool _isSigningIn = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isSigningIn = true);
    try {
      final user = await FirebaseService.signInWithGoogle();
      if (user != null && mounted) {
        AppTheme.showSnackBar(context, 'Успешный вход: ${user.displayName}');
      } else if (mounted) {
        AppTheme.showSnackBar(context, 'Вход отменен или произошла ошибка');
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showSnackBar(context, 'Ошибка входа: $e');
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Выйти из аккаунта?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Вы действительно хотите выйти? Скачанные офлайн-песни будут удалены с устройства, но вся медиатека останется в облаке.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти', style: TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 1. Мгновенно закрываем шторку профиля, не дожидаясь сетевого запроса
      if (mounted) {
        Navigator.pop(context);
      }

      // 2. Мгновенная остановка плеера и скрытие слайдера
      try {
        Provider.of<PlayerProvider>(context, listen: false).stopAndReset();
      } catch (e) {
        print("Ошибка при мгновенном сбросе плеера: $e");
      }

      await FirebaseService.signOut();
      if (mounted) {
        AppTheme.showSnackBar(context, 'Вы вышли из аккаунта');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseService.authStateChanges,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final isAnonymous = user == null || user.isAnonymous;

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF141414),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
          ),
          padding: EdgeInsets.only(
            top: 12,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handlebar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'Профиль и Синхронизация',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Резервное копирование и синхронизация вашей библиотеки в облаке',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: Colors.white38,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // User Info card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white.withOpacity(0.05),
                      backgroundImage: (user?.photoURL != null)
                          ? NetworkImage(user!.photoURL!)
                          : null,
                      child: (user?.photoURL == null)
                          ? const Icon(Icons.person, color: Colors.white54, size: 28)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAnonymous
                                ? 'Временный аккаунт'
                                : (user.displayName ?? 'Пользователь Google'),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAnonymous
                                ? 'Данные синхронизируются анонимно'
                                : (user.email ?? 'Синхронизировано с облаком'),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: isAnonymous ? Colors.white38 : AppColors.accentGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (isAnonymous) ...[
                // Google Login Button
                GestureDetector(
                  onTap: _isSigningIn ? null : _handleGoogleSignIn,
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: _isSigningIn
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.network(
                                  'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                                  height: 20,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.g_mobiledata_rounded,
                                    color: Colors.black,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Войти через Google',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ] else ...[
                // Sign out Button
                GestureDetector(
                  onTap: _isSigningIn ? null : _handleSignOut,
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.accentRed.withOpacity(0.2)),
                    ),
                    child: const Center(
                      child: Text(
                        'Выйти из аккаунта',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.accentRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

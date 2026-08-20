import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/import_export/widgets/spotify_import_sheet.dart';
import 'package:ses/features/import_export/widgets/screenshot_import_sheet.dart';
import 'package:ses/core/widgets/profile_sheet.dart';
import 'package:ses/core/network/firebase_service.dart';
import 'package:ses/features/import_export/screens/qr_scan_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _kOcrApiKey = 'K87895432188957';
  late PlayerProvider _playerProvider;
  String _currentVersion = '';
  bool _isLightTheme = false;

  @override
  void initState() {
    super.initState();
    _playerProvider = Provider.of<PlayerProvider>(context, listen: false);
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _currentVersion = info.version);
    }).catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playerProvider.setShowMiniPlayer(false);
    });
  }

  @override
  void dispose() {
    _playerProvider.setShowMiniPlayer(true);
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  void _showSelectionBottomSheet<T>({
    required BuildContext context,
    required String title,
    required List<T> options,
    required T selectedValue,
    required String Function(T) labelBuilder,
    required ValueChanged<T> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF151515),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: EdgeInsets.only(
            top: 12,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 20),
              Text(
                title,
                style: AppText.sectionTitle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 16),
              ...options.map((opt) {
                final isSelected = opt == selectedValue;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? Colors.white.withOpacity(0.06) 
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      labelBuilder(opt),
                      style: AppText.trackTitle.copyWith(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? Colors.white : Colors.white38,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                        : null,
                    onTap: () {
                      onSelected(opt);
                      Navigator.pop(context);
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer2<UserProvider, PlayerProvider>(
        builder: (context, user, player, child) {
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Header ──
              SliverSafeArea(
                bottom: false,
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        const AppBackButton(),
                        const SizedBox(width: 16),
                        Text(
                          "Настройки",
                          style: AppText.sectionTitle.copyWith(fontSize: 22),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Content ──
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── Section: Account ──
                    _buildSectionGroup(
                      label: "Аккаунт",
                      children: [
                        _buildAccountTile(context),
                      ],
                    ),

                    // ── Section: App Mode ──
                    _buildSectionGroup(
                      label: "Режим приложения",
                      children: [
                        _buildInteractiveTile(
                          icon: user.appMode == 'cinema' ? Iconsax.video_play : Iconsax.music,
                          title: "Текущий режим",
                          subtitle: user.appMode == 'cinema' ? "Кино (Фильмы, Сериалы, Дорамы, Аниме)" : "Музыка",
                          onTap: () => _showSelectionBottomSheet<String>(
                            context: context,
                            title: "Режим приложения",
                            options: ['music', 'cinema'],
                            selectedValue: user.appMode,
                            labelBuilder: (val) => val == 'cinema' ? 'Кино' : 'Музыка',
                            onSelected: (val) => user.setAppMode(val),
                          ),
                        ),
                      ],
                    ),

                    // ── Section: Import ──
                    _buildSectionGroup(
                      label: "Импорт музыки",
                      children: [
                        _buildActionTile(
                          icon: Iconsax.document_download,
                          title: "Универсальный импорт",
                          subtitle: "Импорт из Spotify, Яндекс Музыки или списком",
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              isScrollControlled: true,
                              useRootNavigator: true,
                              barrierColor: Colors.black.withOpacity(0.7),
                              builder: (context) => const SpotifyImportSheet(),
                            );
                          },
                        ),
                        _buildActionTile(
                          icon: Iconsax.camera,
                          title: "Импорт по скриншоту",
                          subtitle: "Распознавание списка треков по фото",
                          onTap: () => _importFromScreenshot(),
                        ),
                        _buildActionTile(
                          icon: Iconsax.scan_barcode,
                          title: "Импорт по QR-коду",
                          subtitle: "Сканируйте QR-код плейлиста",
                          onTap: () => _importFromQR(),
                        ),
                      ],
                    ),

                    // ── Section: Sound & Playback ──
                    _buildSectionGroup(
                      label: "Звук и воспроизведение",
                      children: [
                        _buildSwitchTile(
                          icon: Iconsax.wifi_square,
                          title: "Режим офлайн",
                          subtitle: "Показывать только скачанную музыку",
                          value: user.isOfflineMode,
                          onChanged: (val) => user.setIsOfflineMode(val),
                        ),
                        _buildInteractiveTile(
                          icon: Iconsax.music_play,
                          title: "Качество аудио",
                          subtitle: _getQualityLabel(user.audioQuality),
                          onTap: () => _showSelectionBottomSheet<String>(
                            context: context,
                            title: "Качество аудио",
                            options: ['High', 'Medium', 'Low'],
                            selectedValue: user.audioQuality,
                            labelBuilder: _getQualityLabel,
                            onSelected: (val) => user.setAudioQuality(val),
                          ),
                        ),
                        _buildInteractiveTile(
                          icon: Iconsax.search_status,
                          title: "Приоритетный источник",
                          subtitle: _getSourceLabel(user.preferredSource),
                          onTap: () => _showSelectionBottomSheet<String>(
                            context: context,
                            title: "Приоритетный источник",
                            options: ['Auto', 'Agugai', 'Sefon', 'DriveMusic', 'RuMusic', 'MP3Party'],
                            selectedValue: user.preferredSource,
                            labelBuilder: _getSourceLabel,
                            onSelected: (val) => user.setPreferredSource(val),
                          ),
                        ),
                        _buildInteractiveTile(
                          icon: Iconsax.timer_1,
                          title: "Таймер сна",
                          subtitle: player.sleepDurationRemaining != null
                              ? "Осталось: ${_formatDuration(player.sleepDurationRemaining!)}"
                              : "Выкл",
                          onTap: () => _showSelectionBottomSheet<int?>(
                            context: context,
                            title: "Таймер сна",
                            options: [null, 15, 30, 45, 60],
                            selectedValue: player.sleepDurationRemaining?.inMinutes,
                            labelBuilder: (val) => val == null ? "Выкл" : "$val мин",
                            onSelected: (val) {
                              if (val == null) {
                                player.setSleepTimer(null);
                              } else {
                                player.setSleepTimer(Duration(minutes: val));
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    // ── Section: Storage & Cache ──
                    _buildSectionGroup(
                      label: "Управление хранилищем",
                      children: [
                        _buildStorageUsageCard(context, user),
                        _buildSwitchTile(
                          icon: Iconsax.cloud_change,
                          title: "Умный офлайн-кэш",
                          subtitle: "Авто-скачивание любимых и последних треков",
                          value: user.smartCacheEnabled,
                          onChanged: (val) => user.toggleSmartCache(val),
                        ),
                        if (user.smartCacheEnabled)
                          _buildSwitchTile(
                            icon: Iconsax.wifi,
                            title: "Только по Wi-Fi",
                            subtitle: "Скачивать только при беспроводном подключении",
                            value: user.wifiOnly,
                            onChanged: (val) => user.toggleWifiOnly(val),
                          ),
                        _buildSwitchTile(
                          icon: Iconsax.music_play,
                          title: "Кэшировать при прослушивании",
                          subtitle: "Сохранять треки во время онлайн-воспроизведения",
                          value: user.cacheOnPlay,
                          onChanged: (val) => user.setCacheOnPlay(val),
                        ),
                        _buildInteractiveTile(
                          icon: Iconsax.chart_2,
                          title: "Лимит размера кэша",
                          subtitle: _getCacheLimitLabel(user.cacheSizeLimit),
                          onTap: () => _showSelectionBottomSheet<String>(
                            context: context,
                            title: "Лимит размера кэша",
                            options: ['500MB', '1GB', '2GB', '5GB', 'Unlimited'],
                            selectedValue: user.cacheSizeLimit,
                            labelBuilder: _getCacheLimitLabel,
                            onSelected: (val) => user.setCacheSizeLimit(val),
                          ),
                        ),
                        _buildSwitchTile(
                          icon: Iconsax.trash,
                          title: "Авто-очистка",
                          subtitle: "Удалять старые треки при переполнении лимита",
                          value: user.autoCleanCache,
                          onChanged: (val) => user.setAutoCleanCache(val),
                        ),
                        _buildActionTile(
                          icon: Iconsax.folder_minus,
                          title: "Очистить кэш треков",
                          subtitle: "Удалить все сохраненные и скачанные аудиофайлы",
                          textColor: AppColors.accentRed,
                          onTap: () => _showClearConfirmationBottomSheet(
                            context: context,
                            title: "Очистить кэш треков?",
                            message: "Все скачанные аудиофайлы будут физически удалены с устройства. Вы потеряете доступ к прослушиванию без интернета.",
                            onConfirm: () => user.clearAllDownloads(),
                          ),
                        ),
                        _buildActionTile(
                          icon: Iconsax.document_text,
                          title: "Очистить историю",
                          subtitle: "Удалить историю поиска и прослушиваний",
                          onTap: () => _showClearConfirmationBottomSheet(
                            context: context,
                            title: "Очистить историю?",
                            message: "Вся история ваших поисковых запросов и недавних прослушиваний будет стерта.",
                            onConfirm: () => user.clearMetadataCache(),
                          ),
                        ),
                      ],
                    ),

                    // ── Section: Interface & Customization ──
                    _buildSectionGroup(
                      label: "Интерфейс",
                      children: [
                        _buildSwitchTile(
                          icon: _isLightTheme ? Iconsax.sun_1 : Iconsax.moon,
                          title: "Тема оформления",
                          subtitle: _isLightTheme ? "Светлая тема (заглушка)" : "Темная тема (заглушка)",
                          value: _isLightTheme,
                          onChanged: (val) {
                            setState(() => _isLightTheme = val);
                            AppTheme.showSnackBar(
                              context,
                              val ? "Переключение на светлую тему (заглушка)" : "Переключение на темную тему (заглушка)",
                            );
                          },
                        ),
                        _buildInteractiveTile(
                          icon: Iconsax.repeat,
                          title: "Анимация переходов",
                          subtitle: _getTransitionLabel(user.pageTransition),
                          onTap: () => _showSelectionBottomSheet<String>(
                            context: context,
                            title: "Анимация переходов",
                            options: ['iOS', 'Slide', 'Fade', 'Zoom'],
                            selectedValue: user.pageTransition,
                            labelBuilder: _getTransitionLabel,
                            onSelected: (val) => user.setPageTransition(val),
                          ),
                        ),
                         _buildInteractiveTile(
                           icon: Iconsax.music_dashboard,
                          title: "Стиль мини-плеера",
                          subtitle: _getMiniPlayerStyleLabel(user.miniPlayerStyle),
                          onTap: () => _showSelectionBottomSheet<String>(
                            context: context,
                            title: "Стиль мини-плеера",
                            options: ['Docked', 'Floating'],
                            selectedValue: user.miniPlayerStyle,
                            labelBuilder: _getMiniPlayerStyleLabel,
                            onSelected: (val) => user.setMiniPlayerStyle(val),
                          ),
                        ),
                        _buildSwitchTile(
                          icon: Iconsax.gallery,
                          title: "Размытие фона плеера",
                          subtitle: "Отображать размытую обложку на фоне плеера",
                          value: user.enableBlurBackground,
                          onChanged: (val) => user.setEnableBlurBackground(val),
                        ),
                        _buildSwitchTile(
                          icon: Iconsax.text,
                          title: "Строчка текста под обложкой",
                          subtitle: "Отображать превью текста песни в плеере",
                          value: user.showLyricPreview,
                          onChanged: (val) => user.setShowLyricPreview(val),
                        ),
                      ],
                    ),

                    // ── Section: App Info ──
                    _buildSectionGroup(
                      label: "О приложении",
                      children: [
                        _buildActionTile(
                          icon: Iconsax.info_circle,
                          title: "Версия приложения",
                          subtitle: _currentVersion.isNotEmpty
                              ? "v$_currentVersion"
                              : "v1.0.0",
                          onTap: () {},
                        ),
                      ],
                    ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Helper display label maps ──

  String _getMiniPlayerStyleLabel(String style) {
    switch (style) {
      case 'Docked':
        return "Закрепленный";
      case 'Floating':
        return "Плавающий";
      default:
        return "Закрепленный";
    }
  }

  String _getTransitionLabel(String t) {
    switch (t) {
      case 'iOS':
        return "iOS";
      case 'Slide':
        return "Slide";
      case 'Fade':
        return "Fade";
      case 'Zoom':
        return "Zoom";
      default:
        return "iOS";
    }
  }

  String _getQualityLabel(String q) {
    switch (q) {
      case 'High':
        return "Высокое (320k)";
      case 'Medium':
        return "Среднее (192k)";
      case 'Low':
        return "Низкое (96k)";
      default:
        return q;
    }
  }

  String _getSourceLabel(String s) {
    switch (s) {
      case 'Auto':
        return "Авто";
      case 'Agugai':
        return "Agugai.kz";
      case 'Sefon':
        return "Sefon.pro";
      case 'DriveMusic':
        return "DriveMusic";
      case 'RuMusic':
        return "RuMusic";
      case 'MP3Party':
        return "MP3Party";
      default:
        return s;
    }
  }

  String _getCacheLimitLabel(String limit) {
    if (limit == 'Unlimited') return "Без лимита";
    return limit;
  }

  Widget _buildSectionGroup({
    required String label,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.015),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.035)),
          ),
          child: Column(
            children: List.generate(children.length * 2 - 1, (index) {
              if (index.isOdd) {
                return Divider(
                  color: Colors.white.withOpacity(0.03),
                  height: 1,
                  indent: 52,
                );
              }
              return children[index ~/ 2];
            }),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStorageUsageCard(BuildContext context, UserProvider user) {
    final limit = user.cacheSizeLimit;
    double limitMb = 0.0;
    if (limit == '500MB') limitMb = 500.0;
    else if (limit == '1GB') limitMb = 1000.0;
    else if (limit == '2GB') limitMb = 2000.0;
    else if (limit == '5GB') limitMb = 5000.0;

    final usedMb = user.totalCacheSizeMb;
    final percent = limitMb > 0 ? (usedMb / limitMb).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Использовано памяти",
                style: AppText.trackTitle.copyWith(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              Text(
                "${usedMb.toStringAsFixed(1)} МБ" + (limitMb > 0 ? " / $limit" : ""),
                style: AppText.caption.copyWith(
                  color: AppColors.accentGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: limitMb > 0 ? percent : 0.05,
              minHeight: 4,
              backgroundColor: Colors.white.withOpacity(0.05),
              valueColor: AlwaysStoppedAnimation<Color>(
                limitMb > 0 && percent > 0.9
                    ? Colors.redAccent
                    : limitMb > 0 && percent > 0.7
                        ? Colors.orangeAccent
                        : AppColors.accentGreen,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            limitMb > 0 
                ? "Лимит хранилища заполнен на ${(percent * 100).toInt()}%"
                : "Лимит хранилища: без ограничений",
            style: AppText.caption.copyWith(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  void _showClearConfirmationBottomSheet({
    required BuildContext context,
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 280),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF151515),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: AppText.sectionTitle.copyWith(fontSize: 18, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: AppText.trackArtist.copyWith(fontSize: 14, color: Colors.white60),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: BorderSide(color: Colors.white.withOpacity(0.1)),
                            ),
                          ),
                          child: Text(
                            "Отмена",
                            style: AppText.trackTitle.copyWith(fontSize: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            onConfirm();
                            Navigator.pop(context);
                            AppTheme.showSnackBar(context, "Очищено!");
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentRed,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: Text(
                            "Очистить",
                            style: AppText.trackTitle.copyWith(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: AppText.caption.copyWith(
          color: Colors.white.withOpacity(0.3),
          fontSize: 10,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildAccountTile(BuildContext context) {
    return Builder(
      builder: (context) {
        final currentUser = FirebaseService.currentUser;
        final isLoggedIn = currentUser != null && !currentUser.isAnonymous;
        return ListTile(
          onTap: () => ProfileSheet.show(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: isLoggedIn
                ? AppColors.accentGreen.withOpacity(0.1)
                : Colors.white.withOpacity(0.05),
            backgroundImage: (isLoggedIn && currentUser.photoURL != null)
                ? NetworkImage(currentUser.photoURL!)
                : null,
            child: (isLoggedIn && currentUser.photoURL != null)
                ? null
                : Icon(
                    isLoggedIn ? Iconsax.user_tick : Iconsax.user,
                    color: isLoggedIn ? AppColors.accentGreen : Colors.white60,
                    size: 18,
                  ),
          ),
          title: Text(
            isLoggedIn
                ? (currentUser.displayName ?? "Пользователь Google")
                : "Резервное копирование",
            style: AppText.trackTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            isLoggedIn
                ? (currentUser.email ?? "Сессия активна")
                : "Войдите в Google для синхронизации библиотеки",
            style: AppText.trackArtist.copyWith(fontSize: 11, color: Colors.white38),
          ),
          trailing: const Icon(Iconsax.arrow_right_3, color: Colors.white24, size: 14),
        );
      },
    );
  }

  Widget _buildInteractiveTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: Colors.white60, size: 20),
      title: Text(
        title,
        style: AppText.trackTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: Colors.white.withOpacity(0.35),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Iconsax.arrow_right_3, color: Colors.white24, size: 14),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: textColor ?? Colors.white60, size: 20),
      title: Text(
        title,
        style: AppText.trackTitle.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textColor ?? Colors.white,
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: AppText.trackArtist.copyWith(fontSize: 11, color: Colors.white38),
            )
          : null,
      trailing: const Icon(Iconsax.arrow_right_3, color: Colors.white24, size: 14),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: Colors.white60, size: 20),
      title: Text(
        title,
        style: AppText.trackTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: AppText.trackArtist.copyWith(fontSize: 11, color: Colors.white38),
            )
          : null,
      trailing: AppSwitch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  // ── Screenshot import ──
  Future<void> _importFromScreenshot() async {
    bool dialogShown = false;
    try {
      final picker = ImagePicker();
      final XFile? image =
          await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) {
          return Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.accentGreen),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Распознаем текст на скриншоте...",
                    style: AppText.trackTitle.copyWith(
                        fontSize: 14, decoration: TextDecoration.none),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Это займет всего несколько секунд",
                    style: AppText.trackArtist.copyWith(
                        fontSize: 12, decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
          );
        },
      );
      dialogShown = true;

      final uri = Uri.parse("https://api.ocr.space/parse/image");
      final request = http.MultipartRequest("POST", uri);
      request.fields['apikey'] = _kOcrApiKey;
      request.fields['language'] = 'auto';
      request.fields['OCREngine'] = '2';
      request.files
          .add(await http.MultipartFile.fromPath('file', image.path));

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      dialogShown = false;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['ParsedResults'] as List?;
        if (results != null && results.isNotEmpty) {
          final rawText = results[0]['ParsedText'] as String?;
          if (rawText != null && rawText.trim().isNotEmpty) {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              useRootNavigator: true,
              barrierColor: Colors.black.withOpacity(0.7),
              builder: (context) =>
                  ScreenshotImportSheet(rawText: rawText),
            );
            return;
          }
        }
        AppTheme.showSnackBar(
            context, "Текст на скриншоте не обнаружен.");
      } else {
        AppTheme.showSnackBar(context,
            "Ошибка сервера распознавания: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        if (dialogShown) {
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (_) {}
        }
        AppTheme.showSnackBar(
            context, "Не удалось распознать скриншот: $e");
      }
    }
  }

  // ── QR import ──
  Future<void> _importFromQR() async {
    final code = await Navigator.push<String>(
      context,
      AppPageRoute.create(context, const QRScanScreen()),
    );
    if (code != null && code.isNotEmpty && mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        useRootNavigator: true,
        barrierColor: Colors.black.withOpacity(0.7),
        builder: (context) => SpotifyImportSheet(prefilledText: code),
      );
    }
  }
}

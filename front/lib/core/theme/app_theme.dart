import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/library/widgets/playlist_selection_sheet.dart';
import 'package:ses/core/utils/cover_service.dart';

// ─── COLOR TOKENS ─────────────────────────────────────────────────────────────
class AppColors {
  static const background = Color(0xFF101010);
  static const surface    = Color(0xFF1A1A1A);
  static const surface2   = Color(0xFF222222);
  static const border     = Color(0xFF2A2A2A);

  // Aliases used in legacy screens
  static const bg           = background;
  static const surfaceLight = surface2;
  static const primary      = Colors.white;
  static const secondary    = Color(0xFFCCCCCC);
  static const tertiary     = Color(0xFF888888);

  static const textPrimary   = Colors.white;
  static const textSecondary = Color(0xFF888888);
  static const textMuted     = Color(0xFF444444);

  static const accentRed   = Color(0xFFFF4550);
  static const accentGreen = Colors.white;
  static Color? get customAccentColor => Colors.white;
  static set customAccentColor(Color? val) {}
  static const accentBlue  = Color(0xFF007AFF);
}

// ─── TEXT STYLES ──────────────────────────────────────────────────────────────
class AppText {
  static const _f = 'Inter';

  static const screenTitle = TextStyle(
    fontFamily: _f, fontWeight: FontWeight.w900,
    color: Colors.white, fontSize: 38, letterSpacing: -1.5, height: 1.0,
  );
  static const sectionTitle = TextStyle(
    fontFamily: _f, fontWeight: FontWeight.w800, color: Colors.white, fontSize: 20,
  );
  static const trackTitle = TextStyle(
    fontFamily: _f, fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16,
  );
  static const trackTitleActive = TextStyle(
    fontFamily: _f, fontWeight: FontWeight.w800, color: Colors.white, fontSize: 16,
  );
  static const trackArtist = TextStyle(
    fontFamily: _f, fontWeight: FontWeight.w500, color: Color(0xFF888888), fontSize: 13,
  );
  static const caption = TextStyle(
    fontFamily: _f, fontWeight: FontWeight.w500, color: Color(0xFF888888), fontSize: 12,
  );
  static const label = TextStyle(
    fontFamily: _f, fontWeight: FontWeight.w900, color: Colors.white, fontSize: 10, letterSpacing: 1.5,
  );
}

// ─── BORDER RADII ─────────────────────────────────────────────────────────────
class AppRadius {
  static const double xsVal = 4.0;
  static const double smVal = 8.0;
  static const double mdVal = 12.0;
  static const double lgVal = 16.0;

  static const modal  = BorderRadius.all(Radius.circular(36));
  static const card   = BorderRadius.all(Radius.circular(16));
  static const cover  = BorderRadius.all(Radius.circular(12));
  static const cover2 = BorderRadius.all(Radius.circular(10));
  static const tag    = BorderRadius.all(Radius.circular(6));
  static const input  = BorderRadius.all(Radius.circular(14));

  // Legacy compat getters (doubles)
  static double get xs => xsVal;
  static double get sm => smVal;
  static double get md => mdVal;
  static double get lg => lgVal;
}

// ─── ICON MAPPING ─────────────────────────────────────────────────────────────
class AppIcons {
  // Navigation
  static IconData get back          => Iconsax.arrow_left_3;
  static IconData get forward       => Iconsax.arrow_right_3;
  static IconData get angleRight    => Iconsax.arrow_right_3;
  static IconData get close         => Iconsax.close_circle;
  static IconData get chevronDown   => Iconsax.arrow_down_1;

  // Player controls
  static IconData get play          => Iconsax.play;
  static IconData get pause         => Iconsax.pause;
  static IconData get skipPrev      => Iconsax.previous;
  static IconData get skipNext      => Iconsax.next;
  static IconData get shuffle       => Iconsax.shuffle;
  static IconData get repeat        => Iconsax.repeat;
  static IconData get volumeHigh    => Iconsax.volume_high;

  // Actions
  static IconData get heart         => Iconsax.heart;
  static IconData get heartFilled   => Iconsax.heart_copy;
  static IconData get plus          => Iconsax.add;
  static IconData get trash         => Iconsax.trash;
  static IconData get download      => Iconsax.document_download;
  static IconData get downloadDone  => Iconsax.tick_circle_copy;
  static IconData get camera        => Iconsax.camera;
  static IconData get dotsVertical  => Iconsax.more;

  // UI Elements
  static IconData get search        => Iconsax.search_normal;
  static IconData get music         => Iconsax.music;
  static IconData get playlist      => Iconsax.music_playlist;
  static IconData get library       => Iconsax.book;
  static IconData get user          => Iconsax.user;
  static IconData get queue         => Iconsax.menu;
  static IconData get drag          => Iconsax.sort;
  static IconData get check         => Iconsax.tick_circle;
  static IconData get settings      => Iconsax.setting_2;
  static IconData get edit          => Iconsax.edit_2;
  static IconData get lyrics        => Iconsax.microphone;
  static IconData get lyricsFilled  => Iconsax.microphone_copy;
}

// ─── COVER WIDGET ─────────────────────────────────────────────────────────────
class AppCover extends StatefulWidget {
  final String url;
  final double? size;
  final double radius;
  final String? artist;
  final String? title;

  const AppCover({
    super.key,
    required this.url,
    this.size,
    this.radius = 12,
    this.artist,
    this.title,
  });

  @override
  State<AppCover> createState() => _AppCoverState();
}

class _AppCoverState extends State<AppCover> {
  String? _fetchedUrl;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _checkAndFetch();
  }

  @override
  void didUpdateWidget(covariant AppCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.artist != widget.artist || oldWidget.title != widget.title) {
      _checkAndFetch();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _checkAndFetch() {
    _debounceTimer?.cancel();
    final hasMetadata = widget.artist != null && widget.artist!.isNotEmpty &&
                       widget.title != null && widget.title!.isNotEmpty;

    // Check if the current URL is the default placeholder or empty, and we have metadata to query
    final needsFetch = (widget.url.isEmpty || widget.url.contains("unsplash.com") || widget.url == CoverService.defaultMusicCover) && hasMetadata;

    if (!needsFetch) {
      setState(() {
        _fetchedUrl = null;
      });
      return;
    }

    // Check memory cache first
    final cached = CoverService.getCachedCover(widget.artist!, widget.title!);
    if (cached != null) {
      setState(() {
        _fetchedUrl = cached;
      });
      return;
    }

    // Debounce background API calls by 250ms during scrolling
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      CoverService.getCoverUrl(widget.artist!, widget.title!).then((resolvedUrl) {
        if (mounted) {
          setState(() {
            _fetchedUrl = resolvedUrl;
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeUrl = _fetchedUrl ?? widget.url;
    final isLocal = activeUrl.isNotEmpty && !activeUrl.startsWith('http');

    final placeholder = Container(
      width: widget.size,
      height: widget.size,
      color: AppColors.surface,
      child: Center(
        child: Icon(
          AppIcons.music,
          color: Colors.white10,
          size: (widget.size != null && widget.size!.isFinite) ? widget.size! * 0.35 : 24,
        ),
      ),
    );

    Widget imageWidget;
    if (activeUrl.isEmpty) {
      imageWidget = placeholder;
    } else if (isLocal) {
      imageWidget = Image.file(
        File(activeUrl),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => placeholder,
      );
    } else {
      final int? cacheSize = (widget.size != null && widget.size!.isFinite)
          ? (widget.size! * 2.0).toInt().clamp(100, 1000)
          : null;

      imageWidget = CachedNetworkImage(
        imageUrl: activeUrl,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        memCacheWidth: cacheSize,
        placeholder: (c, u) => placeholder,
        errorWidget: (c, u, e) => placeholder,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: imageWidget,
      ),
    );
  }
}

// ─── PLAY BUTTON ──────────────────────────────────────────────────────────────
class AppPlayButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final bool loading;
  final String? text;
  final IconData? icon;
  final bool expanded;

  const AppPlayButton({
    super.key,
    required this.onTap,
    this.size = 64,
    this.loading = false,
    this.text,
    this.icon,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: size,
        width: expanded ? double.infinity : null,
        padding: text != null ? const EdgeInsets.symmetric(horizontal: 24) : null,
        decoration: BoxDecoration(
          borderRadius: text != null ? BorderRadius.circular(size / 2) : null,
          shape: text != null ? BoxShape.rectangle : BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFDDDDDD), Color(0xFFFFFFFF)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
        child: text != null
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.black, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(text!, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                ],
              )
            : SizedBox(
                width: size,
                child: Center(
                  child: loading
                      ? SizedBox(
                          width: size * 0.32, height: size * 0.32,
                          child: const CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : Icon(icon ?? AppIcons.play, color: Colors.black, size: size * 0.34),
                ),
              ),
      ),
    );
  }
}

// ─── ICON BUTTON ──────────────────────────────────────────────────────────────
class AppCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? bgColor;
  final double size;
  final double iconSize;

  const AppCircleButton({
    super.key, required this.icon, required this.onTap,
    this.iconColor, this.bgColor, this.size = 52, this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final isTransparent = bgColor == Colors.transparent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: bgColor ?? AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: isTransparent
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                  width: 1,
                ),
        ),
        child: Center(child: Icon(icon, color: iconColor ?? Colors.white.withValues(alpha: 0.9), size: iconSize)),
      ),
    );
  }
}

// ─── SEARCH BAR ───────────────────────────────────────────────────────────────
class AppSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  const AppSearchBar({
    super.key, required this.controller, required this.focusNode,
    this.hint = 'Поиск', this.onChanged, this.onSubmitted, this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: AppRadius.input,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(AppIcons.search, color: Colors.white.withOpacity(0.35), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller, focusNode: focusNode, onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), fontFamily: 'Inter'),
                border: InputBorder.none, isDense: true,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, child) {
              if (value.text.isEmpty) return const SizedBox(width: 14);
              return GestureDetector(
                onTap: () {
                  controller.clear();
                  if (onClear != null) onClear!();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Icon(AppIcons.close, color: Colors.white30, size: 16),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── TRACK ROW ────────────────────────────────────────────────────────────────
class AppTrackRow extends StatelessWidget {
  final String title;
  final String artist;
  final String coverUrl;
  final bool isCurrent;
  final bool isLiked;
  final bool isDownloaded;
  final VoidCallback onTap;
  final VoidCallback? onLike;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final Color? actionColor;
  final Song? song;

  const AppTrackRow({
    super.key,
    required this.title, required this.artist, required this.coverUrl,
    required this.isCurrent, required this.isLiked, this.isDownloaded = false,
    required this.onTap, this.onLike,
    this.onAction, this.actionIcon, this.actionColor,
    this.song,
  });

  void _showActionsBottomSheet(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final user = Provider.of<UserProvider>(context, listen: false);

    final effectiveSong = song ?? Song(
      id: title + artist,
      videoId: title + artist,
      title: title,
      artist: artist,
      coverUrl: coverUrl,
    );

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
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  AppCover(
                    url: coverUrl,
                    size: 60,
                    radius: 12,
                    artist: artist,
                    title: title,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppText.trackTitleActive.copyWith(fontSize: 18),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          artist,
                          style: AppText.trackArtist.copyWith(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 12),
              _buildActionRow(
                context: context,
                icon: AppIcons.play,
                title: "Воспроизвести",
                onTap: () {
                  Navigator.pop(context);
                  onTap();
                },
              ),
              _buildActionRow(
                context: context,
                icon: AppIcons.queue,
                title: "Добавить в очередь",
                onTap: () {
                  Navigator.pop(context);
                  player.addToQueue(effectiveSong);
                  AppTheme.showSnackBar(context, 'Добавлено в очередь: $title');
                },
              ),
              _buildActionRow(
                context: context,
                icon: isLiked ? AppIcons.heartFilled : AppIcons.heart,
                iconColor: isLiked ? AppColors.accentRed : null,
                title: isLiked ? "В избранном" : "Добавить в избранное",
                onTap: () {
                  Navigator.pop(context);
                  if (onLike != null) {
                    onLike!();
                  } else {
                    user.toggleLike(effectiveSong);
                  }
                },
              ),
              _buildActionRow(
                context: context,
                icon: isDownloaded ? AppIcons.downloadDone : AppIcons.download,
                iconColor: isDownloaded ? AppColors.accentGreen : null,
                title: isDownloaded ? "Скачано (Удалить)" : "Скачать",
                onTap: () {
                  Navigator.pop(context);
                  if (isDownloaded) {
                    user.removeDownload(effectiveSong.id);
                    AppTheme.showSnackBar(context, 'Загрузка удалена');
                  } else {
                    user.downloadSong(effectiveSong);
                    AppTheme.showSnackBar(context, 'Загрузка началась...');
                  }
                },
              ),
              _buildActionRow(
                context: context,
                icon: AppIcons.plus,
                title: "Добавить в плейлист",
                onTap: () {
                  Navigator.pop(context);
                  showPlaylistSelectionSheet(context, effectiveSong);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor ?? Colors.white.withOpacity(0.7),
              size: 22,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                color: iconColor ?? Colors.white.withOpacity(0.9),
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () => _showActionsBottomSheet(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isCurrent ? Colors.white.withOpacity(0.05) : Colors.transparent,
            borderRadius: AppRadius.card,
          ),
          child: Row(
            children: [
              AppCover(
                url: coverUrl,
                size: 52,
                radius: 10,
                artist: artist,
                title: title,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                      style: isCurrent 
                          ? AppText.trackTitleActive.copyWith(color: AppColors.accentGreen) 
                          : AppText.trackTitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(artist, style: AppText.trackArtist,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (isCurrent)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Icon(AppIcons.volumeHigh, color: AppColors.accentGreen, size: 14),
                ),
              if (isDownloaded)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Icon(AppIcons.downloadDone, color: AppColors.accentGreen, size: 16),
                ),
              if (onLike != null)
                GestureDetector(
                  onTap: onLike,
                  child: Icon(
                    isLiked ? AppIcons.heartFilled : AppIcons.heart,
                    color: isLiked ? AppColors.accentRed : Colors.white12,
                    size: 18,
                  ),
                ),
              if (onAction != null) ...[
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: onAction,
                  child: Icon(actionIcon ?? AppIcons.plus, color: actionColor ?? Colors.white24, size: 22),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── BACK BUTTON ──────────────────────────────────────────────────────────────
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(AppIcons.back, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

// ─── SECTION HEADER ───────────────────────────────────────────────────────────
class AppSectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const AppSectionHeader({super.key, required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppText.sectionTitle),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text("Все",
                style: AppText.caption.copyWith(color: Colors.white.withOpacity(0.5))),
            ),
        ],
      ),
    );
  }
}

// ─── SPACING ──────────────────────────────────────────────────────────────────
class AppSpacing {
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 20;
  static const double xxl = 28;
  static const double xxxl = 40;
}

// ─── BORDER RADIUS EXTRAS (for legacy usage with double values) ───────────────
extension AppRadiusExt on AppRadius {
  static double get sm => 8.0;
  static double get md => 12.0;
  static double get lg => 16.0;
}

// ─── TAG / BADGE ─────────────────────────────────────────────────────────────
class AppTag extends StatelessWidget {
  final String text;
  final Color? color;
  final Color? textColor;

  const AppTag({super.key, required this.text, this.color, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? Colors.white.withValues(alpha: 0.06),
        borderRadius: AppRadius.tag,
      ),
      child: Text(
        text,
        style: AppText.label.copyWith(
          color: textColor ?? Colors.white.withValues(alpha: 0.7),
          fontSize: 9,
        ),
      ),
    );
  }
}

// ─── PREMIUM TOGGLE SWITCH ────────────────────────────────────────────────────
class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 44,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: value ? AppColors.accentGreen : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: value ? AppColors.accentGreen : Colors.white.withValues(alpha: 0.04),
            width: 1,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: AppColors.accentGreen.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        padding: const EdgeInsets.all(2),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── APP THEME ────────────────────────────────────────────────────────────────
class AppTheme {
  static ThemeData get theme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Inter',
    colorScheme: const ColorScheme.dark(
      surface: AppColors.surface,
      primary: Colors.white,
      secondary: Color(0xFF888888),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        fontFamily: 'Inter', color: Colors.white,
        fontSize: 20, fontWeight: FontWeight.w700,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: Colors.white,
      inactiveTrackColor: Colors.white.withOpacity(0.15),
      thumbColor: Colors.white,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.modal,
      ),
    ),
  );

  static void showSnackBar(BuildContext context, String message) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final hasMiniPlayer = player.currentSong != null && player.showMiniPlayer;

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final bottomMargin = hasMiniPlayer ? (88.0 + bottomPadding) : (16.0 + bottomPadding);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppText.trackTitle.copyWith(fontSize: 14, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        duration: const Duration(seconds: 2),
        margin: EdgeInsets.only(
          left: 24,
          right: 24,
          bottom: bottomMargin,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
    );
  }
}

// ─── SHIMMER SKELETON WIDGETS ──────────────────────────────────────────────────
class AppShimmer extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const AppShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.04, end: 0.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          color: Colors.white,
        ),
      ),
    );
  }
}

class AppTrackRowShimmer extends StatelessWidget {
  const AppTrackRowShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const AppShimmer(width: 52, height: 52, borderRadius: 10),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppShimmer(width: 140, height: 16, borderRadius: 4),
                const SizedBox(height: 8),
                const AppShimmer(width: 80, height: 12, borderRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const AppShimmer(width: 18, height: 18, borderRadius: 9),
        ],
      ),
    );
  }
}

class AppAlbumCardShimmer extends StatelessWidget {
  const AppAlbumCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppShimmer(width: 140, height: 140, borderRadius: 16),
          const SizedBox(height: 12),
          const AppShimmer(width: 110, height: 14, borderRadius: 4),
          const SizedBox(height: 6),
          const AppShimmer(width: 70, height: 10, borderRadius: 4),
        ],
      ),
    );
  }
}

class AppArtistCardShimmer extends StatelessWidget {
  const AppArtistCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          const AppShimmer(width: 90, height: 90, borderRadius: 45),
          const SizedBox(height: 10),
          const AppShimmer(width: 70, height: 12, borderRadius: 4),
        ],
      ),
    );
  }
}

// ─── PREMIUM CUSTOM PAGE TRANSITION ROUTE ─────────────────────────────────────
class AppPageRoute {
  static Route<T> create<T>(BuildContext context, Widget page) {
    final user = Provider.of<UserProvider>(context, listen: false);
    final transition = user.pageTransition;
    final wrappedPage = RepaintBoundary(child: page);

    if (transition == 'iOS') {
      return CupertinoPageRoute<T>(
        builder: (context) => wrappedPage,
      );
    } else if (transition == 'Fade') {
      return PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => wrappedPage,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
      );
    } else if (transition == 'Zoom') {
      return PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => wrappedPage,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
      );
    } else {
      // Slide transition (default)
      return PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => wrappedPage,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 280),
      );
    }
  }
}


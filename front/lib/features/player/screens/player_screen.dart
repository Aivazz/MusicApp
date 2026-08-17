import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/player/screens/queue_screen.dart';
import 'package:ses/features/library/widgets/playlist_selection_sheet.dart';
import 'package:ses/features/player/services/lyrics_service.dart';
import 'package:ses/features/player/widgets/marquee_text.dart';
import 'package:ses/features/library/screens/artist_detail_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  String? _currentSongId;
  bool _isTransitioning = true;
  Animation<double>? _routeAnimation;

  bool _showLyrics = false;
  LyricsData? _lyricsData;
  bool _lyricsLoading = false;
  String? _lyricsError;

  @override
  void initState() {
    super.initState();
  }

  PlayerProvider? _playerProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Store provider reference to clean up in dispose()
    _playerProvider = Provider.of<PlayerProvider>(context, listen: false);
    _playerProvider?.setHighPrecision(true);

    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null && _routeAnimation == null) {
      _routeAnimation = modalRoute.animation;
      _routeAnimation?.addStatusListener(_onAnimationStatusChanged);
      _isTransitioning = _routeAnimation?.isCompleted == false;
    }
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    final transitioning = status != AnimationStatus.completed;
    if (transitioning != _isTransitioning) {
      setState(() {
        _isTransitioning = transitioning;
      });
    }
  }

  void _triggerHaptic() {
    final user = Provider.of<UserProvider>(context, listen: false);
    if (user.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _loadLyrics(Song song) async {
    setState(() {
      _lyricsLoading = true;
      _lyricsData = null;
      _lyricsError = null;
    });
    try {
      final data = await LyricsService.fetchLyrics(song.artist, song.title);
      if (mounted && song.id == _currentSongId) {
        setState(() {
          _lyricsData = data;
          _lyricsLoading = false;
        });
      }
    } catch (e) {
      if (mounted && song.id == _currentSongId) {
        setState(() {
          _lyricsError = e.toString();
          _lyricsLoading = false;
        });
      }
    }
  }

  Widget _buildLyricsView(PlayerProvider player) {
    if (_lyricsLoading) {
      return const _LyricsSkeletonLoader();
    }

    if (_lyricsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Colors.white30,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                "Ошибка загрузки текста песни:\n$_lyricsError",
                style: AppText.trackArtist.copyWith(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  final song = player.currentSong;
                  if (song != null) _loadLyrics(song);
                },
                child: Text(
                  "Повторить",
                  style: TextStyle(
                    color: AppColors.accentGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_lyricsData == null || !_lyricsData!.hasLyrics) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notes_rounded, color: Colors.white24, size: 48),
            const SizedBox(height: 16),
            Text(
              "Текст песни отсутствует",
              style: AppText.trackArtist.copyWith(color: Colors.white38),
            ),
          ],
        ),
      );
    }

    if (_lyricsData!.isInstrumental) {
      return Center(
        child: Text(
          "♪ Инструментальная композиция ♪",
          style: AppText.sectionTitle.copyWith(color: Colors.white54),
        ),
      );
    }

    if (_lyricsData!.hasSynced) {
      final lines = _lyricsData!.syncedLines!;
      return _SyncedLyricsView(lines: lines, player: player);
    }

    // Fallback: Plain lyrics
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _lyricsData!.plainLyrics!,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: Colors.white70,
            height: 1.8,
          ),
          textAlign: TextAlign.left,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onAnimationStatusChanged);
    _playerProvider?.setHighPrecision(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context);
    final user = Provider.of<UserProvider>(context);
    final song = player.currentSong;

    if (song == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text("Ничего не играет", style: AppText.trackArtist),
        ),
      );
    }

    if (song.id != _currentSongId) {
      _currentSongId = song.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadLyrics(song);
      });
    }

    final isLiked = user.isLiked(song.id);
    final isDownloaded = user.isDownloaded(song.id);
    final isDownloading = user.isDownloading(song.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Blurred background cover art matching modern premium players
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(color: AppColors.background),
                  ),
                  if (!_isTransitioning && user.enableBlurBackground)
                    Positioned.fill(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.0, end: 0.18),
                        duration: const Duration(milliseconds: 350),
                        builder: (context, value, child) {
                          return Opacity(opacity: value, child: child);
                        },
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: 30,
                            sigmaY: 30,
                            tileMode: TileMode.mirror,
                          ),
                          child: AppCover(
                            url: song.coverUrl,
                            size: double.infinity,
                            radius: 0,
                            artist: song.artist,
                            title: song.title,
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.4),
                            Colors.black.withValues(alpha: 0.85),
                            Colors.black,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isLandscape =
                    constraints.maxWidth > constraints.maxHeight;
                if (isLandscape) {
                  return _buildLandscapeLayout(
                    context,
                    player,
                    user,
                    song,
                    isLiked,
                    isDownloaded,
                    isDownloading,
                  );
                } else {
                  return _buildPortraitLayout(
                    context,
                    player,
                    user,
                    song,
                    isLiked,
                    isDownloaded,
                    isDownloading,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout(
    BuildContext context,
    PlayerProvider player,
    UserProvider user,
    Song song,
    bool isLiked,
    bool isDownloaded,
    bool isDownloading,
  ) {
    return Column(
      children: [
        // ── 1. HEADER ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Icon(AppIcons.back, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppCircleButton(
                    icon: _showLyrics ? AppIcons.lyricsFilled : AppIcons.lyrics,
                    size: 40,
                    iconSize: 20,
                    onTap: () {
                      setState(() {
                        _showLyrics = !_showLyrics;
                      });
                      _triggerHaptic();
                    },
                    bgColor: Colors.transparent,
                    iconColor: _showLyrics
                        ? AppColors.accentGreen
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  AppCircleButton(
                    icon: AppIcons.queue,
                    size: 40,
                    iconSize: 20,
                    onTap: () => Navigator.push(
                      context,
                      AppPageRoute.create(context, const QueueScreen()),
                    ),
                    bgColor: Colors.transparent,
                    iconColor: Colors.white.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 2. ARTWORK or LYRICS ──
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: _showLyrics,
                child: Column(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              decoration: const BoxDecoration(
                                borderRadius: AppRadius.cover,
                              ),
                              child: ClipRRect(
                                borderRadius: AppRadius.cover,
                                child: AppCover(
                                  url: song.coverUrl,
                                  artist: song.artist,
                                  title: song.title,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (user.showLyricPreview)
                      SizedBox(
                        height: 60,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                            child: _buildLyricPreviewSnippet(player),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Offstage(offstage: !_showLyrics, child: _buildLyricsView(player)),
            ],
          ),
        ),

        if (player.errorMessage != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
            ),
            child: Text(
              player.errorMessage!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),

        // ── 3. SONG INFO ──
        if (!_showLyrics) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarqueeText(
                        text: song.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context, rootNavigator: true).push(
                            AppPageRoute.create(
                              context,
                              ArtistDetailScreen(
                                artistName: song.artist,
                                coverUrl: song.coverUrl,
                              ),
                            ),
                          );
                        },
                        child: Text(
                          song.artist,
                          style: AppText.trackArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Like
                GestureDetector(
                  onTap: () {
                    user.toggleLike(song);
                    AppTheme.showSnackBar(
                      context,
                      isLiked
                          ? 'Удалено из избранного'
                          : 'Добавлено в избранное',
                    );
                  },
                  child: Icon(
                    isLiked ? AppIcons.heartFilled : AppIcons.heart,
                    color: isLiked ? AppColors.accentRed : Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 20),

                // Add to Playlist
                GestureDetector(
                  onTap: () => showPlaylistSelectionSheet(context, song),
                  child: Icon(AppIcons.plus, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 20),

                // Download
                GestureDetector(
                  onTap: () {
                    if (isDownloading) return;
                    isDownloaded
                        ? user.removeDownload(song.id)
                        : user.downloadSong(song);
                  },
                  child: isDownloading
                      ? (() {
                          final progress = user.getDownloadProgress(song.id);
                          return SizedBox(
                            width: 24,
                            height: 24,
                            child: progress > 0.0
                                ? Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        value: progress,
                                        color: AppColors.accentGreen,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.15),
                                        strokeWidth: 2,
                                      ),
                                      Text(
                                        "${(progress * 100).toInt()}%",
                                        style: const TextStyle(
                                          fontSize: 7,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                : const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                          );
                        })()
                      : Icon(
                          isDownloaded
                              ? AppIcons.downloadDone
                              : AppIcons.download,
                          color: isDownloaded
                              ? AppColors.accentGreen
                              : Colors.white,
                          size: 22,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ] else ...[
          const SizedBox(height: 12),
        ],

        // ── 4. PROGRESS BAR ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: PlaybackProgressBar(player: player),
        ),

        const SizedBox(height: 16),

        // ── 5. CONTROLS ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Shuffle
              GestureDetector(
                onTap: () => player.toggleShuffle(),
                child: Icon(
                  AppIcons.shuffle,
                  color: player.isShuffle ? Colors.white : Colors.white38,
                  size: 20,
                ),
              ),

              // Skip Previous
              GestureDetector(
                onTap: () => player.previous(),
                child: Icon(AppIcons.skipPrev, color: Colors.white, size: 30),
              ),

              // Play / Pause
              GestureDetector(
                onTap: () => player.togglePlayPause(),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      player.isPlaying ? AppIcons.pause : AppIcons.play,
                      color: AppColors.background,
                      size: 26,
                    ),
                  ),
                ),
              ),

              // Skip Next
              GestureDetector(
                onTap: () => player.next(),
                child: Icon(AppIcons.skipNext, color: Colors.white, size: 30),
              ),

              // Repeat
              GestureDetector(
                onTap: () => player.toggleRepeat(),
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Icon(
                      AppIcons.repeat,
                      color: player.repeatMode == 0
                          ? Colors.white38
                          : Colors.white,
                      size: 20,
                    ),
                    if (player.repeatMode == 2)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: MediaQuery.of(context).padding.bottom + 32),
      ],
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context,
    PlayerProvider player,
    UserProvider user,
    Song song,
    bool isLiked,
    bool isDownloaded,
    bool isDownloading,
  ) {
    return Row(
      children: [
        // Left Column: Header and Artwork
        Expanded(
          flex: 4,
          child: Column(
            children: [
              // Small Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AppCircleButton(
                      icon: AppIcons.chevronDown,
                      size: 36,
                      iconSize: 20,
                      onTap: () => Navigator.pop(context),
                      bgColor: Colors.transparent,
                    ),
                    AppCircleButton(
                      icon: AppIcons.queue,
                      size: 36,
                      iconSize: 18,
                      onTap: () => Navigator.push(
                        context,
                        AppPageRoute.create(context, const QueueScreen()),
                      ),
                      bgColor: Colors.transparent,
                      iconColor: Colors.white.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
              // Artwork
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 4, 28, 20),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: const BoxDecoration(
                          borderRadius: AppRadius.cover,
                        ),
                        child: ClipRRect(
                          borderRadius: AppRadius.cover,
                          child: AppCover(
                            url: song.coverUrl,
                            artist: song.artist,
                            title: song.title,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Vertical Divider
        Container(
          width: 1,
          color: Colors.white.withValues(alpha: 0.05),
          margin: const EdgeInsets.symmetric(vertical: 24),
        ),

        // Right Column: Controls and Info
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (player.errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      player.errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                if (!_showLyrics) ...[_buildLyricPreviewSnippet(player)],

                // Song Info Row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MarqueeText(
                            text: song.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Inter',
                            ),
                          ),
                          const SizedBox(height: 2),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context, rootNavigator: true).push(
                                AppPageRoute.create(
                                  context,
                                  ArtistDetailScreen(
                                    artistName: song.artist,
                                    coverUrl: song.coverUrl,
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              song.artist,
                              style: AppText.trackArtist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Like
                    GestureDetector(
                      onTap: () {
                        user.toggleLike(song);
                        AppTheme.showSnackBar(
                          context,
                          isLiked
                              ? 'Удалено из избранного'
                              : 'Добавлено в избранное',
                        );
                      },
                      child: Icon(
                        isLiked ? AppIcons.heartFilled : AppIcons.heart,
                        color: isLiked ? AppColors.accentRed : Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Add to Playlist
                    GestureDetector(
                      onTap: () => showPlaylistSelectionSheet(context, song),
                      child: Icon(AppIcons.plus, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 16),

                    // Download
                    GestureDetector(
                      onTap: () {
                        if (isDownloading) return;
                        isDownloaded
                            ? user.removeDownload(song.id)
                            : user.downloadSong(song);
                      },
                      child: isDownloading
                          ? (() {
                              final progress = user.getDownloadProgress(
                                song.id,
                              );
                              return SizedBox(
                                width: 20,
                                height: 20,
                                child: progress > 0.0
                                    ? Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          CircularProgressIndicator(
                                            value: progress,
                                            color: AppColors.accentGreen,
                                            backgroundColor: Colors.white
                                                .withValues(alpha: 0.15),
                                            strokeWidth: 2,
                                          ),
                                          Text(
                                            "${(progress * 100).toInt()}%",
                                            style: const TextStyle(
                                              fontSize: 6,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                              );
                            })()
                          : Icon(
                              isDownloaded
                                  ? AppIcons.downloadDone
                                  : AppIcons.download,
                              color: isDownloaded
                                  ? AppColors.accentGreen
                                  : Colors.white,
                              size: 20,
                            ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Progress Bar
                PlaybackProgressBar(player: player),

                const SizedBox(height: 20),

                // Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Shuffle
                    GestureDetector(
                      onTap: () {
                        _triggerHaptic();
                        player.toggleShuffle();
                      },
                      child: Icon(
                        AppIcons.shuffle,
                        color: player.isShuffle ? Colors.white : Colors.white38,
                        size: 18,
                      ),
                    ),

                    // Skip Previous
                    GestureDetector(
                      onTap: () {
                        _triggerHaptic();
                        player.previous();
                      },
                      child: Icon(
                        AppIcons.skipPrev,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),

                    // Play / Pause
                    GestureDetector(
                      onTap: () {
                        _triggerHaptic();
                        player.togglePlayPause();
                      },
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: player.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: AppColors.background,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  player.isPlaying
                                      ? AppIcons.pause
                                      : AppIcons.play,
                                  color: AppColors.background,
                                  size: 22,
                                ),
                        ),
                      ),
                    ),

                    // Skip Next
                    GestureDetector(
                      onTap: () {
                        _triggerHaptic();
                        player.next();
                      },
                      child: Icon(
                        AppIcons.skipNext,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),

                    // Repeat
                    GestureDetector(
                      onTap: () {
                        _triggerHaptic();
                        player.toggleRepeat();
                      },
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Icon(
                            AppIcons.repeat,
                            color: player.repeatMode == 0
                                ? Colors.white38
                                : Colors.white,
                            size: 18,
                          ),
                          if (player.repeatMode == 2)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLyricPreviewSnippet(PlayerProvider player) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showLyrics = true;
        });
        _triggerHaptic();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        child: Align(
          alignment: Alignment.centerLeft,
          child: _LyricPreviewText(
            lyricsData: _lyricsData,
            isLoading: _lyricsLoading,
            player: player,
          ),
        ),
      ),
    );
  }
}

class PlaybackProgressBar extends StatefulWidget {
  final PlayerProvider player;

  const PlaybackProgressBar({super.key, required this.player});

  @override
  State<PlaybackProgressBar> createState() => _PlaybackProgressBarState();
}

class _PlaybackProgressBarState extends State<PlaybackProgressBar>
    with SingleTickerProviderStateMixin {
  double? _dragValue;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = widget.player.isLoading;

    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      initialData: widget.player.currentPosition,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = widget.player.totalDuration;

        final maxVal = duration.inMilliseconds.toDouble() > 0
            ? duration.inMilliseconds.toDouble()
            : 1000.0;

        final displayPosition = _dragValue != null
            ? Duration(milliseconds: _dragValue!.toInt())
            : position;

        return Column(
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: isLoading ? 3.5 : 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: isLoading
                        ? AppColors.accentGreen.withValues(
                            alpha: _pulseAnimation.value,
                          )
                        : Colors.white,
                    inactiveTrackColor: isLoading
                        ? Colors.white.withValues(
                            alpha: _pulseAnimation.value * 0.4,
                          )
                        : Colors.white.withValues(alpha: 0.15),
                    thumbColor: isLoading
                        ? AppColors.accentGreen.withValues(
                            alpha: _pulseAnimation.value,
                          )
                        : Colors.white,
                    overlayColor: Colors.white12,
                  ),
                  child: Slider(
                    value: displayPosition.inMilliseconds.toDouble().clamp(
                      0.0,
                      maxVal,
                    ),
                    max: maxVal,
                    onChangeStart: (v) {
                      setState(() {
                        _dragValue = v;
                      });
                    },
                    onChanged: (v) {
                      setState(() {
                        _dragValue = v;
                      });
                      widget.player.updateDragPosition(
                        Duration(milliseconds: v.toInt()),
                      );
                    },
                    onChangeEnd: (v) {
                      widget.player.seek(Duration(milliseconds: v.toInt()));
                      setState(() {
                        _dragValue = null;
                      });
                    },
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(displayPosition), style: AppText.caption),
                  Text(_fmt(duration), style: AppText.caption),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LyricsSkeletonLoader extends StatefulWidget {
  const _LyricsSkeletonLoader();

  @override
  State<_LyricsSkeletonLoader> createState() => _LyricsSkeletonLoaderState();
}

class _LyricsSkeletonLoaderState extends State<_LyricsSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.08,
      end: 0.25,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final widths = [0.85, 0.55, 0.72, 0.45, 0.78, 0.6, 0.52, 0.75, 0.4];
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(left: 28, right: 28, top: 40),
          itemCount: widths.length,
          itemBuilder: (context, index) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                width: MediaQuery.of(context).size.width * widths[index],
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: _animation.value),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SyncedLyricsView extends StatefulWidget {
  final List<LyricLine> lines;
  final PlayerProvider player;

  const _SyncedLyricsView({required this.lines, required this.player});

  @override
  State<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<_SyncedLyricsView> {
  late ScrollController _scrollController;
  int _activeIndex = -1;
  dynamic _positionSubscription;
  bool _isUserScrolling = false;
  Timer? _userScrollTimeout;
  List<GlobalKey> _keys = [];
  late List<LyricLine> _processedLines;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _processedLines = _preprocessLines(widget.lines);
    _keys = List.generate(_processedLines.length, (index) => GlobalKey());

    // Initial active index based on current player position
    _activeIndex = _calculateActiveIndex(widget.player.currentPosition);

    // Subscribe to position changes
    _positionSubscription = widget.player.positionStream.listen((position) {
      if (!mounted) return;
      final newIndex = _calculateActiveIndex(position);
      if (newIndex != _activeIndex) {
        setState(() {
          _activeIndex = newIndex;
        });
        _scrollToActive();
      }
    });

    // Scroll to the active lyric line immediately upon opening
    _scrollToActive(immediate: true);
  }

  @override
  void didUpdateWidget(_SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines != oldWidget.lines) {
      _processedLines = _preprocessLines(widget.lines);
      _keys = List.generate(_processedLines.length, (index) => GlobalKey());
      _activeIndex = _calculateActiveIndex(widget.player.currentPosition);
      _scrollToActive(immediate: true);
    }
  }

  void _handleUserScroll() {
    _userScrollTimeout?.cancel();
    _isUserScrolling = true;
    _userScrollTimeout = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _isUserScrolling = false;
        _scrollToActive();
      }
    });
  }

  List<LyricLine> _preprocessLines(List<LyricLine> originalLines) {
    if (originalLines.isEmpty) return originalLines;
    final List<LyricLine> processed = [];

    // Check if there is an initial gap of 5+ seconds at the start of the song
    final first = originalLines.first;
    if (first.time.inSeconds >= 5) {
      processed.add(LyricLine(time: Duration.zero, text: '•••'));
    }

    for (int i = 0; i < originalLines.length; i++) {
      processed.add(originalLines[i]);

      if (i < originalLines.length - 1) {
        final current = originalLines[i];
        final next = originalLines[i + 1];
        final gap = next.time - current.time;

        // If the gap between lyrics is 6 seconds or more, we insert a break indicator
        if (gap.inSeconds >= 6) {
          // Delay before starting the break (e.g. 3s or 20% of the gap, max 5s)
          final delay = Duration(
            milliseconds: math.min(
              math.max(3000, (gap.inMilliseconds * 0.2).toInt()),
              5000,
            ),
          );

          final breakTime = current.time + delay;
          if (breakTime < next.time - const Duration(seconds: 2)) {
            processed.add(LyricLine(time: breakTime, text: '•••'));
          }
        }
      }
    }
    return processed;
  }

  int _calculateActiveIndex(Duration position) {
    if (_processedLines.isEmpty) return -1;

    // Fast path: check if current active index is still active (O(1) in 99.9% of updates)
    if (_activeIndex >= 0 && _activeIndex < _processedLines.length) {
      final currentLineTime = _processedLines[_activeIndex].time;
      final nextLineTime = _activeIndex < _processedLines.length - 1
          ? _processedLines[_activeIndex + 1].time
          : null;

      if (position >= currentLineTime &&
          (nextLineTime == null || position < nextLineTime)) {
        return _activeIndex;
      }
    }

    // Fallback: binary search (O(log N))
    int low = 0;
    int high = _processedLines.length - 1;
    int index = -1;

    while (low <= high) {
      int mid = (low + high) >> 1;
      if (_processedLines[mid].time <= position) {
        index = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return index;
  }

  void _scrollToActive({bool immediate = false}) {
    if (_activeIndex != -1 &&
        _activeIndex < _keys.length &&
        !_isUserScrolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final keyContext = _keys[_activeIndex].currentContext;
        if (keyContext != null) {
          if (immediate) {
            Scrollable.ensureVisible(keyContext, alignment: 0.4);
          } else {
            Scrollable.ensureVisible(
              keyContext,
              alignment:
                  0.4, // Keep active lyric slightly above the absolute center
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
            );
          }
        } else {
          // If active item is not yet rendered by ListView (e.g. lyrics reopened far into song),
          // jump/animate scroll controller to estimated offset so ListView inflates the active item.
          final maxScroll = _scrollController.position.maxScrollExtent;
          final estimatedTarget = (_activeIndex * 56.0 - 150.0).clamp(
            0.0,
            maxScroll,
          );

          if (immediate) {
            _scrollController.jumpTo(estimatedTarget);
          } else {
            _scrollController.animateTo(
              estimatedTarget,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
            );
          }

          // Post-frame retry to ensure exact alignment once item is inflated
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _isUserScrolling) return;
            final retryContext = _keys[_activeIndex].currentContext;
            if (retryContext != null) {
              Scrollable.ensureVisible(
                retryContext,
                alignment: 0.4,
                duration: immediate
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              );
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _userScrollTimeout?.cancel();
    _positionSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewHeight = constraints.maxHeight;
        final topPad = viewHeight * 0.4;
        final bottomPad = viewHeight * 0.55;

        return ShaderMask(
          shaderCallback: (rect) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.15, 0.85, 1.0],
            ).createShader(rect);
          },
          blendMode: BlendMode.dstIn,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is UserScrollNotification) {
                if (notification.direction != ScrollDirection.idle) {
                  _handleUserScroll();
                }
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 28,
                right: 28,
                top: topPad,
                bottom: bottomPad,
              ),
              itemCount: _processedLines.length,
              itemBuilder: (context, index) {
                final line = _processedLines[index];
                final isActive = index == _activeIndex;
                final isPast = _activeIndex != -1 && index < _activeIndex;
                final nextLine = index + 1 < _processedLines.length
                    ? _processedLines[index + 1]
                    : null;

                double opacity;
                if (isActive) {
                  opacity = 1.0;
                } else if (isPast) {
                  final distance = _activeIndex - index;
                  if (distance == 1) {
                    opacity = 0.22;
                  } else if (distance == 2) {
                    opacity = 0.10;
                  } else {
                    opacity = 0.05;
                  }
                } else {
                  opacity = 0.35;
                }

                if (line.text == '•••') {
                  return GestureDetector(
                    onTap: () {
                      widget.player.seek(line.time);
                      final user = Provider.of<UserProvider>(
                        context,
                        listen: false,
                      );
                      if (user.hapticFeedback) {
                        HapticFeedback.lightImpact();
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _InstrumentalBreakWidget(
                        key: _keys[index],
                        isActive: isActive,
                      ),
                    ),
                  );
                }

                return _SyncedLyricLine(
                  key: _keys[index],
                  line: line,
                  nextLine: nextLine,
                  isActive: isActive,
                  opacity: opacity,
                  player: widget.player,
                  onTap: () {
                    widget.player.seek(line.time);
                    final user = Provider.of<UserProvider>(
                      context,
                      listen: false,
                    );
                    if (user.hapticFeedback) {
                      HapticFeedback.lightImpact();
                    }
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class SpringCurve extends Curve {
  final double damping;
  final double stiffness;

  const SpringCurve({this.damping = 7.0, this.stiffness = 6.0});

  @override
  double transformInternal(double t) {
    if (t == 0.0) return 0.0;
    if (t == 1.0) return 1.0;
    // Damped spring oscillation equation: 1 - e^(-damping * t) * cos(stiffness * t)
    return 1.0 - math.pow(2.71828, -damping * t) * math.cos(stiffness * t);
  }
}

class _InstrumentalBreakWidget extends StatefulWidget {
  final bool isActive;
  const _InstrumentalBreakWidget({super.key, required this.isActive});

  @override
  State<_InstrumentalBreakWidget> createState() =>
      _InstrumentalBreakWidgetState();
}

class _InstrumentalBreakWidgetState extends State<_InstrumentalBreakWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _InstrumentalBreakWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double opacity = widget.isActive ? 1.0 : 0.35;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              double scale = 1.0;
              double dotOpacity = opacity;
              if (widget.isActive) {
                // Staggered pulsing wave for each dot
                double t = _controller.value - (index * 0.2);
                if (t < 0) t += 1.0;
                final sine = math.sin(t * math.pi * 2);

                scale = 1.0 + (sine.clamp(0.0, 1.0) * 0.3);
                dotOpacity = 0.4 + 0.6 * ((sine.clamp(-1.0, 1.0) + 1.0) / 2.0);
              }
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 10,
                height: 10,
                transform: Matrix4.identity()..scale(scale),
                transformAlignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: dotOpacity),
                  boxShadow: widget.isActive
                      ? [
                          BoxShadow(
                            color: Colors.white.withValues(
                              alpha: 0.3 * dotOpacity,
                            ),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

class _SyncedLyricLine extends StatelessWidget {
  final LyricLine line;
  final LyricLine? nextLine;
  final bool isActive;
  final double opacity;
  final PlayerProvider player;
  final VoidCallback onTap;

  const _SyncedLyricLine({
    super.key,
    required this.line,
    required this.nextLine,
    required this.isActive,
    required this.opacity,
    required this.player,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: AnimatedScale(
            scale: 0.846,
            alignment: Alignment.centerLeft,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            child: AnimatedSlide(
              offset: const Offset(0, 0.08),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              child: Text(
                line.text,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 26.0,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: opacity),
                  height: 1.35,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: AnimatedScale(
          scale: 1.0,
          alignment: Alignment.centerLeft,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: AnimatedSlide(
            offset: Offset.zero,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            child: Text(
              line.text,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 26.0,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.35,
                letterSpacing: -0.3,
                shadows: [
                  Shadow(
                    color: Colors.white.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: Offset.zero,
                  ),
                  Shadow(
                    color: Colors.white.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: Offset.zero,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricPreviewText extends StatelessWidget {
  final LyricsData? lyricsData;
  final bool isLoading;
  final PlayerProvider player;

  const _LyricPreviewText({
    required this.lyricsData,
    required this.isLoading,
    required this.player,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Text(
        "Загрузка текста...",
        textAlign: TextAlign.left,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.38),
        ),
      );
    }

    if (lyricsData == null || !lyricsData!.hasLyrics) {
      if (lyricsData?.isInstrumental == true) {
        return Text(
          "♪ Инструментальная композиция ♪",
          textAlign: TextAlign.left,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    if (lyricsData!.hasSynced) {
      final lines = lyricsData!.syncedLines!;
      return StreamBuilder<Duration>(
        stream: player.positionStream,
        initialData: player.currentPosition,
        builder: (context, snapshot) {
          final position = snapshot.data ?? player.currentPosition;
          String activeText = '';

          int activeIndex = -1;
          for (int i = 0; i < lines.length; i++) {
            if (lines[i].time <= position) {
              activeIndex = i;
            } else {
              break;
            }
          }

          if (activeIndex >= 0 && activeIndex < lines.length) {
            activeText = lines[activeIndex].text;
          } else if (lines.isNotEmpty) {
            activeText = lines.first.text;
          }

          if (activeText.trim().isEmpty || activeText == '•••') {
            if (activeIndex >= 0 &&
                activeIndex + 1 < lines.length &&
                lines[activeIndex + 1].text != '•••') {
              activeText = lines[activeIndex + 1].text;
            } else if (lines.isNotEmpty) {
              final found = lines.firstWhere(
                (l) => l.text.isNotEmpty && l.text != '•••',
                orElse: () => lines.first,
              );
              activeText = found.text;
            }
          }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (Widget child, Animation<double> animation) {
              final isIncoming = (child.key == ValueKey<String>(activeText));
              final inTween = Tween<Offset>(
                begin: const Offset(0.0, 0.6),
                end: Offset.zero,
              );
              final outTween = Tween<Offset>(
                begin: const Offset(0.0, -0.6),
                end: Offset.zero,
              );

              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: (isIncoming ? inTween : outTween).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeInOutCubic,
                    ),
                  ),
                  child: child,
                ),
              );
            },
            child: SizedBox(
              key: ValueKey<String>(activeText),
              width: double.infinity,
              child: Text(
                activeText,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.35,
                  letterSpacing: -0.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      );
    }

    // Plain lyrics fallback
    if (lyricsData!.plainLyrics != null &&
        lyricsData!.plainLyrics!.isNotEmpty) {
      final plainLines = lyricsData!.plainLyrics!
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('['))
          .toList();

      final firstLine = plainLines.isNotEmpty
          ? plainLines.first
          : lyricsData!.plainLyrics!;
      return SizedBox(
        width: double.infinity,
        child: Text(
          firstLine,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.35,
            letterSpacing: -0.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

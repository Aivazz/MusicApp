import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isTransitionCompleted = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = ModalRoute.of(context);
      if (route != null && route.animation != null) {
        if (route.animation!.isCompleted) {
          if (mounted) setState(() => _isTransitionCompleted = true);
        } else {
          void listener(AnimationStatus status) {
            if (status == AnimationStatus.completed) {
              route.animation!.removeStatusListener(listener);
              if (mounted) {
                setState(() => _isTransitionCompleted = true);
              }
            }
          }
          route.animation!.addStatusListener(listener);
        }
      } else {
        if (mounted) setState(() => _isTransitionCompleted = true);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context);
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final currentSong = context.select<PlayerProvider, Song?>((p) => p.currentSong);

    final query = _searchController.text.trim().toLowerCase();
    final queueSongs = user.downloadQueue.where((s) =>
        query.isEmpty ||
        s.title.toLowerCase().contains(query) ||
        s.artist.toLowerCase().contains(query)).toList();

    final allSongs = user.downloadedSongs;
    final displayedSongs = query.isEmpty
        ? allSongs
        : allSongs.where((s) =>
            s.title.toLowerCase().contains(query) ||
            s.artist.toLowerCase().contains(query)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            stretch: true,
            leading: const AppBackButton(),
            backgroundColor: AppColors.background,
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground, StretchMode.fadeTitle],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0F3A20), Color(0xFF081E11), AppColors.background],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40, right: 28,
                    child: Icon(AppIcons.download,
                      size: 130, color: Colors.white.withOpacity(0.04)),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.background.withOpacity(0.95),
                          AppColors.background,
                        ],
                        stops: const [0.5, 0.85, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 28, left: 24, right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Скачано", style: AppText.screenTitle),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            AppTag(
                              text: "ОФЛАЙН",
                              color: AppColors.accentGreen.withOpacity(0.2),
                              textColor: AppColors.accentGreen,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "${allSongs.length} треков",
                              style: AppText.caption.copyWith(color: Colors.white.withOpacity(0.5)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: AppSearchBar(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      hint: "Поиск скачанного",
                    ),
                  ),
                  const SizedBox(width: 16),
                  AppPlayButton(
                    size: 56,
                    onTap: () {
                      if (displayedSongs.isNotEmpty) {
                        player.setQueueAndPlay(displayedSongs, startIndex: 0);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          (_isTransitionCompleted && queueSongs.isEmpty && displayedSongs.isEmpty)
              ? SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          Icon(AppIcons.download, size: 48, color: Colors.white.withOpacity(0.06)),
                          const SizedBox(height: 16),
                          Text(
                            query.isEmpty ? "Нет скачанных песен" : "Ничего не найдено",
                            style: AppText.trackArtist.copyWith(color: Colors.white.withOpacity(0.2)),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : SliverFixedExtentList(
                  itemExtent: 74.0,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (!_isTransitionCompleted) {
                        return const AppTrackRowShimmer();
                      }

                      final isQueueItem = index < queueSongs.length;
                      if (isQueueItem) {
                        final song = queueSongs[index];
                        final isActivelyDownloading = user.isActivelyDownloading(song.id);
                        final progress = user.getDownloadProgress(song.id);
                        return _buildQueueItem(context, user, song, progress, isActivelyDownloading);
                      }

                      final song = displayedSongs[index - queueSongs.length];
                      final isCurrent = currentSong?.id == song.id || (currentSong?.title == song.title && currentSong?.artist == song.artist);
                      final isLiked = user.isLiked(song.id);

                      final trackRow = AppTrackRow(
                        title: song.title,
                        artist: song.artist,
                        coverUrl: song.coverUrl,
                        isCurrent: isCurrent,
                        isLiked: isLiked,
                        isDownloaded: true,
                        onTap: () {
                          _searchFocusNode.unfocus();
                          player.setQueueAndPlay(displayedSongs, startIndex: index - queueSongs.length);
                        },
                        onLike: () => user.toggleLike(song),
                        onAction: () => user.removeDownload(song.id),
                        actionIcon: AppIcons.trash,
                        actionColor: Colors.white.withOpacity(0.2),
                        song: song,
                      );

                      final animationIndex = index;
                      if (animationIndex >= 10) {
                        return trackRow;
                      }

                      return TweenAnimationBuilder<double>(
                        duration: Duration(milliseconds: 200 + (animationIndex * 30).clamp(0, 150)),
                        tween: Tween<double>(begin: 0.0, end: 1.0),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 8 * (1.0 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: trackRow,
                      );
                    },
                    childCount: !_isTransitionCompleted ? 8 : (queueSongs.length + displayedSongs.length),
                  ),
                ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 150)),
        ],
      ),
    );
  }

  Widget _buildQueueItem(BuildContext context, UserProvider user, Song song, double progress, bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: AppRadius.card,
      ),
      child: Row(
        children: [
          Stack(
            children: [
              AppCover(
                url: song.coverUrl,
                size: 52,
                radius: 10,
                artist: song.artist,
                title: song.title,
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: isActive ? progress : null,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  song.title,
                  style: AppText.trackTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      isActive 
                          ? "Загрузка... ${(progress * 100).toInt()}%" 
                          : "В очереди...",
                      style: AppText.trackArtist.copyWith(
                        color: isActive ? AppColors.accentGreen : Colors.white30,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text("•", style: AppText.trackArtist),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        song.artist,
                        style: AppText.trackArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () {
              user.cancelDownload(song.id);
              AppTheme.showSnackBar(context, "Загрузка отменена");
            },
            child: Icon(
              AppIcons.close,
              color: Colors.white.withOpacity(0.3),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

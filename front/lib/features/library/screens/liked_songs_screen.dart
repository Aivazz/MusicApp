import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';

class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
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
    final allSongs = user.likedSongs;
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
                        colors: [Color(0xFF6E0D25), Color(0xFF2B050D), AppColors.background],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40, right: 28,
                    child: Icon(AppIcons.heartFilled,
                      size: 130, color: AppColors.accentRed.withOpacity(0.04)),
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
                        Text("Любимые треки", style: AppText.screenTitle),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accentRed.withOpacity(0.2),
                                borderRadius: AppRadius.tag,
                              ),
                              child: Text("ИЗБРАННОЕ", 
                                style: AppText.label.copyWith(
                                  color: AppColors.accentRed,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                )),
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
                      hint: "Поиск в избранном",
                    ),
                  ),
                  const SizedBox(width: 16),
                  AppCircleButton(
                    icon: allSongs.isNotEmpty && allSongs.every((s) => user.isDownloaded(s.id))
                        ? AppIcons.downloadDone
                        : AppIcons.download,
                    onTap: () {
                      if (allSongs.isNotEmpty) {
                        final toDownload = allSongs.where((s) => !user.isDownloaded(s.id) && !user.downloadQueue.any((q) => q.id == s.id)).toList();
                        user.downloadPlaylist(allSongs);
                        if (toDownload.isEmpty) {
                          AppTheme.showSnackBar(context, 'Все любимые треки уже скачаны или скачиваются');
                        } else {
                          AppTheme.showSnackBar(context, 'Загрузка ${toDownload.length} любимых треков...');
                        }
                      }
                    },
                    iconColor: allSongs.isNotEmpty && allSongs.every((s) => user.isDownloaded(s.id))
                        ? AppColors.accentGreen
                        : null,
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

          (_isTransitionCompleted && displayedSongs.isEmpty)
              ? SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          Icon(AppIcons.heart, size: 48, color: Colors.white.withOpacity(0.06)),
                          const SizedBox(height: 16),
                          Text(
                            query.isEmpty ? "Нет любимых песен" : "Ничего не найдено",
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

                      final song = displayedSongs[index];
                      final isCurrent = currentSong?.id == song.id || (currentSong?.title == song.title && currentSong?.artist == song.artist);
                      final isLiked = user.isLiked(song.id);

                      final trackRow = AppTrackRow(
                        title: song.title,
                        artist: song.artist,
                        coverUrl: song.coverUrl,
                        isCurrent: isCurrent,
                        isLiked: isLiked,
                        isDownloaded: user.isDownloaded(song.id),
                        onTap: () {
                          _searchFocusNode.unfocus();
                          player.setQueueAndPlay(displayedSongs, startIndex: index);
                        },
                        onLike: () {
                          user.toggleLike(song);
                          AppTheme.showSnackBar(
                            context,
                            isLiked ? 'Удалено из избранного' : 'Добавлено в избранное',
                          );
                        },
                        song: song,
                      );

                      if (index >= 10) {
                        return trackRow;
                      }

                      return TweenAnimationBuilder<double>(
                        duration: Duration(milliseconds: 200 + (index * 30).clamp(0, 150)),
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
                    childCount: !_isTransitionCompleted ? 8 : displayedSongs.length,
                  ),
                ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 150)),
        ],
      ),
    );
  }
}

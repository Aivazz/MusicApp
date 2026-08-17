import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/player/screens/player_screen.dart';
import 'package:ses/features/player/widgets/marquee_text.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/screens/artist_detail_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final user = Provider.of<UserProvider>(context);
    final song = context.select<PlayerProvider, Song?>((p) => p.currentSong);
    final isPlaying = context.select<PlayerProvider, bool>((p) => p.isPlaying);


    if (song == null) return const SizedBox.shrink();

    final isFloating = user.miniPlayerStyle == 'Floating';

    final playerBody = Stack(
      children: [
        SafeArea(
          top: false,
          bottom: !isFloating,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // Cover Art — isolated repaint
                RepaintBoundary(
                  child: AppCover(
                    url: song.coverUrl,
                    size: 44,
                    radius: 8,
                    artist: song.artist,
                    title: song.title,
                  ),
                ),
                const SizedBox(width: 12),

                // Title & Artist — marquee for long titles
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarqueeText(
                        text: song.title,
                        style: AppText.trackTitle.copyWith(fontSize: 14),
                        scrollSpeed: 25.0,
                      ),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            AppPageRoute.create(
                              context,
                              ArtistDetailScreen(
                                artistName: song.artist,
                                coverUrl: song.coverUrl,
                              ),
                            ),
                          );
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          song.artist,
                          style: AppText.trackArtist.copyWith(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Play / Pause Button — smooth animated icon transition
                GestureDetector(
                  onTap: () => player.togglePlayPause(),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        isPlaying ? AppIcons.pause : AppIcons.play,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Next Track Button
                GestureDetector(
                  onTap: () => player.next(),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Icon(
                        AppIcons.skipNext,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: isFloating ? null : 0,
          bottom: isFloating ? 0 : null,
          left: 0,
          right: 0,
          child: const RepaintBoundary(
            child: MiniPlayerProgressBar(),
          ),
        ),
      ],
    );

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.5),
          builder: (context) => const PlayerScreen(),
        );
      },
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < -200) {
            player.next();
          } else if (details.primaryVelocity! > 200) {
            player.previous();
          }
        }
      },
      behavior: HitTestBehavior.opaque,
      child: isFloating
          ? SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                height: 64,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: playerBody,
                ),
              ),
            )
          : Container(
              height: 72 + MediaQuery.of(context).padding.bottom,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: playerBody,
            ),
    );
  }
}

class MiniPlayerProgressBar extends StatefulWidget {
  const MiniPlayerProgressBar({super.key});

  @override
  State<MiniPlayerProgressBar> createState() => _MiniPlayerProgressBarState();
}

class _MiniPlayerProgressBarState extends State<MiniPlayerProgressBar> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context);
    final isLoading = player.isLoading;

    if (isLoading) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
            height: 2.5,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.accentGreen.withValues(alpha: _pulseAnimation.value),
                  Colors.white.withValues(alpha: _pulseAnimation.value * 0.9),
                  AppColors.accentGreen.withValues(alpha: _pulseAnimation.value),
                ],
              ),
            ),
          );
        },
      );
    }

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? player.currentPosition;
        final total = player.totalDuration;
        final double progress = total.inMilliseconds > 0
            ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return Container(
          height: 2,
          width: double.infinity,
          color: Colors.white.withValues(alpha: 0.05),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress,
            child: Container(
              color: AppColors.accentGreen,
            ),
          ),
        );
      },
    );
  }
}

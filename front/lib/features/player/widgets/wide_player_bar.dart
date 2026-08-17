import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/player/widgets/marquee_text.dart';
import 'package:ses/features/player/screens/player_screen.dart';
import 'package:ses/features/library/screens/artist_detail_screen.dart';

class WidePlayerBar extends StatelessWidget {
  const WidePlayerBar({super.key});

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return "$minutes:${twoDigits(seconds)}";
  }

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context);
    final user = Provider.of<UserProvider>(context);
    final song = player.currentSong;

    if (song == null) return const SizedBox.shrink();

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 88,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF161616).withOpacity(0.85),
            border: const Border(
              top: BorderSide(color: Colors.white10, width: 0.8),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              // ── LEFT: SONG INFO & LIKE ──
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useRootNavigator: true,
                          backgroundColor: Colors.transparent,
                          barrierColor: Colors.black.withOpacity(0.5),
                          builder: (context) => const PlayerScreen(),
                        );
                      },
                      child: AppCover(
                        url: song.coverUrl,
                        size: 52,
                        radius: 10,
                        artist: song.artist,
                        title: song.title,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                useRootNavigator: true,
                                backgroundColor: Colors.transparent,
                                barrierColor: Colors.black.withOpacity(0.5),
                                builder: (context) => const PlayerScreen(),
                              );
                            },
                            child: MarqueeText(
                              text: song.title,
                              style: AppText.trackTitle.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
                              scrollSpeed: 25.0,
                            ),
                          ),
                          const SizedBox(height: 3),
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
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        user.toggleLike(song);
                        AppTheme.showSnackBar(
                          context,
                          user.isLiked(song.id) ? 'Удалено из избранного' : 'Добавлено в избранное',
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          user.isLiked(song.id) ? AppIcons.heartFilled : AppIcons.heart,
                          color: user.isLiked(song.id) ? AppColors.accentRed : Colors.white38,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── CENTER: PLAYBACK CONTROLS & TIMELINE ──
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Shuffle
                        IconButton(
                          icon: Icon(
                            AppIcons.shuffle,
                            color: player.isShuffle ? AppColors.accentGreen : Colors.white38,
                            size: 18,
                          ),
                          onPressed: () => player.toggleShuffle(),
                          splashRadius: 20,
                        ),
                        const SizedBox(width: 8),
                        // Previous
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 24),
                          onPressed: () => player.previous(),
                          splashRadius: 20,
                        ),
                        const SizedBox(width: 12),
                        // Play/Pause
                        GestureDetector(
                          onTap: () => player.togglePlayPause(),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: player.isLoading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        color: Colors.black,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      player.isPlaying ? AppIcons.pause : AppIcons.play,
                                      color: Colors.black,
                                      size: 18,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Next
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 24),
                          onPressed: () => player.next(),
                          splashRadius: 20,
                        ),
                        const SizedBox(width: 8),
                        // Repeat
                        IconButton(
                          icon: Icon(
                            AppIcons.repeat,
                            color: player.repeatMode == 0
                                ? Colors.white38
                                : (player.repeatMode == 1 ? AppColors.accentGreen : Colors.amber),
                            size: 18,
                          ),
                          onPressed: () => player.toggleRepeat(),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Progress Slider
                    StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? player.currentPosition;
                        final total = player.totalDuration;
                        final posMs = position.inMilliseconds.toDouble();
                        final totalMs = total.inMilliseconds.toDouble();

                        return Row(
                          children: [
                            Text(
                              _formatDuration(position),
                              style: AppText.caption.copyWith(fontSize: 10, color: Colors.white38),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                                  activeTrackColor: AppColors.accentGreen,
                                  inactiveTrackColor: Colors.white10,
                                  thumbColor: Colors.white,
                                  trackShape: const RectangularSliderTrackShape(),
                                ),
                                child: Slider(
                                  value: posMs.clamp(0.0, totalMs > 0 ? totalMs : 1.0),
                                  min: 0.0,
                                  max: totalMs > 0 ? totalMs : 1.0,
                                  onChanged: (val) {
                                    player.updateDragPosition(Duration(milliseconds: val.toInt()));
                                  },
                                  onChangeEnd: (val) {
                                    player.seek(Duration(milliseconds: val.toInt()));
                                  },
                                ),
                              ),
                            ),
                            Text(
                              _formatDuration(total),
                              style: AppText.caption.copyWith(fontSize: 10, color: Colors.white38),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ── RIGHT: VOLUME CONTROLS ──
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    StreamBuilder<double>(
                      stream: player.volumeStream,
                      builder: (context, snapshot) {
                        final vol = snapshot.data ?? player.volume;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (vol > 0) {
                                  player.setVolume(0.0);
                                } else {
                                  player.setVolume(1.0);
                                }
                              },
                              child: Icon(
                                vol == 0
                                    ? Icons.volume_off_rounded
                                    : (vol < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                                color: Colors.white60,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 80,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                                  activeTrackColor: Colors.white70,
                                  inactiveTrackColor: Colors.white10,
                                  thumbColor: Colors.white,
                                  trackShape: const RectangularSliderTrackShape(),
                                ),
                                child: Slider(
                                  value: vol.clamp(0.0, 1.0),
                                  min: 0.0,
                                  max: 1.0,
                                  onChanged: (val) {
                                    player.setVolume(val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

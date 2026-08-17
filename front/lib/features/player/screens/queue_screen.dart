import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/library/models/song.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final currentSong = context.select<PlayerProvider, Song?>((p) => p.currentSong);
    final queue = context.select<PlayerProvider, List<Song>>((p) => p.queue);

    if (currentSong == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.queue, size: 48, color: Colors.white.withOpacity(0.06)),
              const SizedBox(height: 16),
              Text("Очередь пуста",
                  style: AppText.trackArtist.copyWith(color: Colors.white.withOpacity(0.2))),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── HEADER with cover blur ──
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("ДАЛЕЕ",
                          style: AppText.trackArtist.copyWith(
                            color: Colors.white.withOpacity(0.4), fontSize: 11, letterSpacing: 1)),
                        Text(currentSong.title,
                          style: AppText.trackTitle,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  AppCover(url: currentSong.coverUrl, size: 40, radius: 8, artist: currentSong.artist, title: currentSong.title),
                ],
              ),
            ),
          ),

          // Queue label
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Text("Очередь", style: AppText.sectionTitle),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: AppRadius.tag,
                  ),
                  child: Text("${queue.length}",
                    style: AppText.caption.copyWith(color: Colors.white.withOpacity(0.6))),
                ),
              ],
            ),
          ),

          // ── REORDERABLE LIST ──
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(canvasColor: AppColors.background),
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(top: 8, bottom: 120),
                itemCount: queue.length,
                onReorder: (oldIndex, newIndex) =>
                    player.reorderQueue(oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final song = queue[index];
                  final isPlaying = song.id == currentSong.id;
                  return _QueueItem(
                    key: ValueKey('${song.id}_$index'),
                    song: song,
                    index: index,
                    player: player,
                    isPlaying: isPlaying,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueItem extends StatelessWidget {
  final Song song;
  final int index;
  final PlayerProvider player;
  final bool isPlaying;

  const _QueueItem({
    super.key,
    required this.song, required this.index,
    required this.player, required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(song.id),
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isPlaying ? AppColors.surface.withOpacity(0.6) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isPlaying ? Colors.white.withOpacity(0.04) : Colors.transparent),
        ),
        child: Row(
          children: [
            // Drag handle
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, left: 4),
                child: Icon(AppIcons.drag, color: Colors.white.withOpacity(0.2), size: 16),
              ),
            ),

            // Cover
            GestureDetector(
              onTap: () => player.playSong(song),
              child: AppCover(
                url: song.coverUrl,
                size: 46,
                radius: 10,
                artist: song.artist,
                title: song.title,
              ),
            ),
            const SizedBox(width: 14),

            // Title + artist
            Expanded(
              child: GestureDetector(
                onTap: () => player.playSong(song),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                      style: isPlaying ? AppText.trackTitleActive : AppText.trackTitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(song.artist, style: AppText.trackArtist,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),

            if (isPlaying)
              Icon(AppIcons.volumeHigh, color: Colors.white, size: 16)
            else
              const SizedBox(width: 16),

            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

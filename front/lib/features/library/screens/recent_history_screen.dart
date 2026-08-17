import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/core/theme/app_theme.dart';

class HistoryListItem {
  final String? header;
  final PlayHistoryEntry? entry;

  HistoryListItem.header(this.header) : entry = null;
  HistoryListItem.entry(this.entry) : header = null;

  bool get isHeader => header != null;
}

class RecentHistoryScreen extends StatelessWidget {
  const RecentHistoryScreen({super.key});

  List<HistoryListItem> _buildFlatHistoryList(List<PlayHistoryEntry> history) {
    final List<HistoryListItem> flatList = [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    
    // Начало текущей недели (понедельник)
    final startOfWeek = today.subtract(Duration(days: now.weekday - 1));

    final List<PlayHistoryEntry> todayItems = [];
    final List<PlayHistoryEntry> yesterdayItems = [];
    final List<PlayHistoryEntry> weekItems = [];
    final List<PlayHistoryEntry> olderItems = [];

    for (var entry in history) {
      final date = DateTime(entry.playedAt.year, entry.playedAt.month, entry.playedAt.day);
      if (date == today) {
        todayItems.add(entry);
      } else if (date == yesterday) {
        yesterdayItems.add(entry);
      } else if (date.isAfter(startOfWeek) || date == startOfWeek) {
        weekItems.add(entry);
      } else {
        olderItems.add(entry);
      }
    }

    if (todayItems.isNotEmpty) {
      flatList.add(HistoryListItem.header("Сегодня"));
      flatList.addAll(todayItems.map((e) => HistoryListItem.entry(e)));
    }
    if (yesterdayItems.isNotEmpty) {
      flatList.add(HistoryListItem.header("Вчера"));
      flatList.addAll(yesterdayItems.map((e) => HistoryListItem.entry(e)));
    }
    if (weekItems.isNotEmpty) {
      flatList.add(HistoryListItem.header("На этой неделе"));
      flatList.addAll(weekItems.map((e) => HistoryListItem.entry(e)));
    }
    if (olderItems.isNotEmpty) {
      flatList.add(HistoryListItem.header("Ранее"));
      flatList.addAll(olderItems.map((e) => HistoryListItem.entry(e)));
    }

    return flatList;
  }

  void _showClearHistoryDialog(BuildContext context, PlayerProvider player) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Очистить историю?",
          style: AppText.sectionTitle.copyWith(fontSize: 18),
        ),
        content: Text(
          "Это действие удалит все недавно прослушанные треки из истории.",
          style: AppText.trackArtist.copyWith(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Отмена", style: AppText.caption.copyWith(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              player.clearPlayHistory();
              Navigator.pop(ctx);
            },
            child: Text("Очистить", style: AppText.caption.copyWith(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final user = Provider.of<UserProvider>(context);
    final currentSong = context.select<PlayerProvider, Song?>((p) => p.currentSong);
    final history = context.select<PlayerProvider, List<PlayHistoryEntry>>((p) => p.playHistory);

    final flatList = _buildFlatHistoryList(history);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── HEADER ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "Недавно прослушано",
                      style: AppText.screenTitle.copyWith(fontSize: 24, letterSpacing: -0.5),
                    ),
                  ),
                  if (history.isNotEmpty)
                    GestureDetector(
                      onTap: () => _showClearHistoryDialog(context, player),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: const Icon(
                          Iconsax.trash,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── LIST / EMPTY STATE ──
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Iconsax.music_playlist,
                            size: 64,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "История прослушиваний пуста",
                            style: AppText.sectionTitle.copyWith(color: Colors.white54, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Ваши прослушанные треки появятся здесь",
                            style: AppText.trackArtist.copyWith(fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ListView.builder(
                        padding: EdgeInsets.only(bottom: currentSong != null ? 100 : 20),
                        itemCount: flatList.length,
                        itemBuilder: (context, index) {
                          final item = flatList[index];

                          if (item.isHeader) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                              child: Text(
                                item.header!,
                                style: AppText.sectionTitle.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accentGreen,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            );
                          }

                          final entry = item.entry!;
                          final song = entry.song;
                          final isLiked = user.isLiked(song.id);
                          final isCurrent = currentSong?.id == song.id || 
                              (currentSong?.title == song.title && currentSong?.artist == song.artist);

                          return AppTrackRow(
                            title: song.title,
                            artist: song.artist,
                            coverUrl: song.coverUrl,
                            isCurrent: isCurrent,
                            isLiked: isLiked,
                            isDownloaded: user.isDownloaded(song.id),
                            onTap: () {
                              final songsList = history.map((e) => e.song).toList();
                              final startIndex = songsList.indexWhere((s) => s.id == song.id);
                              player.setQueueAndPlay(
                                songsList,
                                startIndex: startIndex != -1 ? startIndex : 0,
                              );
                            },
                            onLike: () => user.toggleLike(song),
                            song: song,
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

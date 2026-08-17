import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/screens/album_detail_screen.dart';

class PlaylistsHistoryListItem {
  final String? header;
  final RecentPlaylistEntry? entry;

  PlaylistsHistoryListItem.header(this.header) : entry = null;
  PlaylistsHistoryListItem.entry(this.entry) : header = null;

  bool get isHeader => header != null;
}

class RecentPlaylistsScreen extends StatelessWidget {
  const RecentPlaylistsScreen({super.key});

  LinearGradient _getPlaylistGradient(String name) {
    final int hash = name.hashCode;
    final List<List<Color>> palettes = [
      [const Color(0xFF3A1C71), const Color(0xFFD76D77), const Color(0xFFFFAF7B)],
      [const Color(0xFF2C5364), const Color(0xFF203A43), const Color(0xFF0F2027)],
      [const Color(0xFF1A2A6C), const Color(0xFFB21F1F), const Color(0xFFFDBB2D)],
      [const Color(0xFF00C6FF), const Color(0xFF0072FF)],
      [const Color(0xFF11998E), const Color(0xFF38EF7D)],
      [const Color(0xFFAA076B), const Color(0xFF61045F)],
      [const Color(0xFF833AB4), const Color(0xFFFD1D1D), const Color(0xFFFCB045)],
      [const Color(0xFF4E54C8), const Color(0xFF8F94FB)],
      [const Color(0xFF00F260), const Color(0xFF0575E6)],
    ];
    final palette = palettes[hash.abs() % palettes.length];
    return LinearGradient(
      colors: palette,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  List<PlaylistsHistoryListItem> _buildFlatHistoryList(List<RecentPlaylistEntry> history) {
    final List<PlaylistsHistoryListItem> flatList = [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final startOfWeek = today.subtract(Duration(days: now.weekday - 1));

    final List<RecentPlaylistEntry> todayItems = [];
    final List<RecentPlaylistEntry> yesterdayItems = [];
    final List<RecentPlaylistEntry> weekItems = [];
    final List<RecentPlaylistEntry> olderItems = [];

    for (var entry in history) {
      final date = DateTime(entry.viewedAt.year, entry.viewedAt.month, entry.viewedAt.day);
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
      flatList.add(PlaylistsHistoryListItem.header("Сегодня"));
      flatList.addAll(todayItems.map((e) => PlaylistsHistoryListItem.entry(e)));
    }
    if (yesterdayItems.isNotEmpty) {
      flatList.add(PlaylistsHistoryListItem.header("Вчера"));
      flatList.addAll(yesterdayItems.map((e) => PlaylistsHistoryListItem.entry(e)));
    }
    if (weekItems.isNotEmpty) {
      flatList.add(PlaylistsHistoryListItem.header("На этой неделе"));
      flatList.addAll(weekItems.map((e) => PlaylistsHistoryListItem.entry(e)));
    }
    if (olderItems.isNotEmpty) {
      flatList.add(PlaylistsHistoryListItem.header("Ранее"));
      flatList.addAll(olderItems.map((e) => PlaylistsHistoryListItem.entry(e)));
    }

    return flatList;
  }

  void _showClearHistoryDialog(BuildContext context, UserProvider user) {
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
          "Это действие удалит все недавно просмотренные плейлисты и альбомы из истории.",
          style: AppText.trackArtist.copyWith(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Отмена", style: AppText.caption.copyWith(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              user.clearRecentPlaylists();
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
    final user = Provider.of<UserProvider>(context);
    final history = user.recentPlaylists;
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
                      "Недавние подборки",
                      style: AppText.screenTitle.copyWith(fontSize: 22, letterSpacing: -0.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (history.isNotEmpty)
                    AppCircleButton(
                      icon: AppIcons.trash,
                      size: 40,
                      onTap: () => _showClearHistoryDialog(context, user),
                    ),
                ],
              ),
            ),

            // ── LIST ──
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Text(
                        "История подборок пуста",
                        style: AppText.trackArtist,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 40),
                      itemCount: flatList.length,
                      itemBuilder: (context, index) {
                        final item = flatList[index];
                        if (item.isHeader) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                            child: Text(
                              item.header!,
                              style: AppText.sectionTitle.copyWith(
                                fontSize: 16,
                                color: AppColors.accentGreen,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        } else {
                          return RecentPlaylistRow(
                            entry: item.entry!,
                            gradientHelper: _getPlaylistGradient,
                          );
                        }
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecentPlaylistRow extends StatelessWidget {
  final RecentPlaylistEntry entry;
  final LinearGradient Function(String) gradientHelper;

  const RecentPlaylistRow({
    super.key,
    required this.entry,
    required this.gradientHelper,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = entry.playlistMetadata;
    final cover = metadata.coverUrl;
    final name = metadata.title;
    final artist = metadata.artist;
    final type = entry.playlistType;

    final coverWidget = cover.isEmpty
        ? Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: gradientHelper(name),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                AppIcons.music,
                color: Colors.white,
                size: 20,
              ),
            ),
          )
        : AppCover(url: cover, size: 56, radius: 12);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          AppPageRoute.create(
            context,
            AlbumDetailScreen(
              albumMetadata: metadata,
              type: type,
            ),
          ),
        );
      },
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            coverWidget,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppText.trackTitle.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type == "CustomPlaylist" 
                        ? "Плейлист • $artist" 
                        : (type == "Album" ? "Альбом • $artist" : "Подборка • $artist"),
                    style: AppText.trackArtist.copyWith(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              AppIcons.angleRight,
              color: Colors.white.withValues(alpha: 0.2),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

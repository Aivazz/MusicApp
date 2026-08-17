import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/screens/album_detail_screen.dart';

class ViewAllScreen extends StatelessWidget {
  final String title;
  final List<Song> items;

  const ViewAllScreen({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final user = Provider.of<UserProvider>(context);
    final currentSong = context.select<PlayerProvider, Song?>((p) => p.currentSong);

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
                      title,
                      style: AppText.screenTitle.copyWith(fontSize: 24, letterSpacing: -0.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── LIST ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ListView.builder(
                  padding: EdgeInsets.only(bottom: currentSong != null ? 100 : 20),
                  itemExtent: 74.0,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isPlaylist = item.type == 'playlist' || item.type == 'album';
                    final isLiked = user.isLiked(item.id);

                    return AppTrackRow(
                      title: item.title,
                      artist: isPlaylist ? (item.type == 'album' ? 'Альбом' : 'Плейлист') : item.artist,
                      coverUrl: item.coverUrl,
                      isCurrent: !isPlaylist && (currentSong?.id == item.id || (currentSong?.title == item.title && currentSong?.artist == item.artist)),
                      isLiked: isLiked,
                      isDownloaded: !isPlaylist && user.isDownloaded(item.id),
                      onTap: () {
                        if (isPlaylist) {
                          Navigator.push(
                            context,
                            AppPageRoute.create(
                              context,
                              AlbumDetailScreen(
                                albumMetadata: item,
                                type: item.type == 'album' ? "Album" : "Playlist",
                              ),
                            ),
                          );
                        } else {
                          final songsOnly = items.where((s) => s.type == 'song').toList();
                          final startIndex = songsOnly.indexOf(item);
                          player.setQueueAndPlay(
                            songsOnly,
                            startIndex: startIndex != -1 ? startIndex : 0,
                          );
                        }
                      },
                      onLike: isPlaylist ? null : () => user.toggleLike(item),
                      song: isPlaylist ? null : item,
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/widgets/create_playlist_sheet.dart';

void showPlaylistSelectionSheet(BuildContext context, Song song) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.8),
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (context) {
      return _PlaylistSelectionContent(song: song);
    },
  );
}

class _PlaylistSelectionContent extends StatelessWidget {
  final Song song;
  const _PlaylistSelectionContent({required this.song});

  void _showCreatePlaylistDialog(BuildContext context, UserProvider user) {
    showCreatePlaylistSheet(context, user);
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context);
    final playlists = user.playlists;

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.03))),
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      child: Column(
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
          Text(
            "Добавить в плейлист",
            style: AppText.sectionTitle.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: playlists.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(AppIcons.plus, size: 48, color: Colors.white.withValues(alpha: 0.05)),
                        const SizedBox(height: 12),
                        Text("У вас пока нет плейлистов", style: AppText.trackArtist),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final p = playlists[index];
                      final cover = p['coverUrl'] as String? ?? '';
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: AppRadius.card,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: AppCover(url: cover, size: 48, radius: 10),
                          title: Text(p['name'] ?? 'Плейлист', style: AppText.trackTitle),
                          subtitle: Text("${(p['songs'] as List).length} песен", style: AppText.trackArtist),
                          trailing: Icon(AppIcons.angleRight, color: Colors.white12, size: 16),
                          onTap: () {
                            user.addSongToPlaylist(p['id'], song);
                            Navigator.pop(context);
                            AppTheme.showSnackBar(context, 'Добавлено в ${p['name']}');
                          },
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: AppPlayButton(
              size: 60,
              expanded: true,
              text: "Создать новый плейлист",
              onTap: () => _showCreatePlaylistDialog(context, user),
              icon: AppIcons.plus,
            ),
          )
        ],
      ),
    );
  }
}

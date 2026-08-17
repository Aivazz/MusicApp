import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/core/theme/app_theme.dart';

class ArtistsScreen extends StatelessWidget {
  const ArtistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context);
    final artists = user.followedArtists;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── HEADER ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 16),
                  Text("Исполнители", style: AppText.screenTitle.copyWith(fontSize: 26, letterSpacing: -0.5)),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── COUNT ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                "${artists.length} подписок",
                style: AppText.caption.copyWith(color: Colors.white38),
              ),
            ),

            const SizedBox(height: 16),

            // ── LIST ──
            Expanded(
              child: artists.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: artists.length,
                      itemBuilder: (context, index) {
                        final artist = artists[index];
                        return TweenAnimationBuilder<double>(
                          duration: Duration(milliseconds: 300 + (index * 50).clamp(0, 200)),
                          tween: Tween<double>(begin: 0.0, end: 1.0),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 15 * (1.0 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.02)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: AppCover(
                                  url: artist.coverUrl,
                                  size: 60,
                                  radius: 30,
                                  artist: artist.title,
                                  title: artist.title,
                                ),
                              ),
                              title: Text(
                                artist.title,
                                style: AppText.trackTitle.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                "Артист",
                                style: AppText.trackArtist.copyWith(fontSize: 13, color: Colors.white38),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.user, size: 64, color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 16),
          Text(
            "Вы еще не подписались ни на одного артиста",
            style: AppText.trackArtist.copyWith(color: Colors.white38),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Вернуться назад", style: AppText.caption.copyWith(color: AppColors.accentGreen)),
          ),
        ],
      ),
    );
  }
}

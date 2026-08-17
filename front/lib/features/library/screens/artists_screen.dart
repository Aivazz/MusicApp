import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/library/screens/artist_detail_screen.dart';
import 'package:ses/features/library/models/song.dart';

class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showArtistMenu(BuildContext context, UserProvider user, Song artist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ClipOval(
                      child: AppCover(
                        url: artist.coverUrl,
                        size: 48,
                        radius: 24,
                        artist: artist.title,
                        title: artist.title,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        artist.title,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Iconsax.user_search_copy, color: Colors.white),
                  title: const Text(
                    "Открыть страницу артиста",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      AppPageRoute.create(
                        context,
                        ArtistDetailScreen(
                          artistName: artist.title,
                          artistId: artist.id,
                          coverUrl: artist.coverUrl,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Iconsax.profile_remove_copy, color: AppColors.accentRed),
                  title: const Text(
                    "Отписаться от исполнителя",
                    style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    user.toggleFollow(artist.id, artist.title, artist.coverUrl);
                    AppTheme.showSnackBar(context, 'Вы отписались от ${artist.title}');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context);
    final player = Provider.of<PlayerProvider>(context);
    final currentSong = player.currentSong;
    final hasMiniPlayer = currentSong != null && player.showMiniPlayer;

    final allArtists = user.followedArtists;
    final query = _searchController.text.trim().toLowerCase();
    final artists = query.isEmpty
        ? allArtists
        : allArtists.where((a) => a.title.toLowerCase().contains(query)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── HEADER ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Подписки",
                          style: AppText.screenTitle.copyWith(fontSize: 26, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${allArtists.length} исполнителей",
                          style: AppText.caption.copyWith(color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── SEARCH BAR (IF > 3 ARTISTS) ──
            if (allArtists.length > 3) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "Поиск среди подписок...",
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
                      prefixIcon: Icon(Iconsax.search_normal_1_copy, color: Colors.white.withValues(alpha: 0.3), size: 18),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),

            // ── ARTIST CIRCLE GRID ──
            Expanded(
              child: allArtists.isEmpty
                  ? _buildEmptyState(context)
                  : artists.isEmpty
                      ? _buildNoSearchResults()
                      : GridView.builder(
                          padding: EdgeInsets.fromLTRB(20, 12, 20, hasMiniPlayer ? 100 : 20),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 24,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: artists.length,
                          itemBuilder: (context, index) {
                            final artist = artists[index];
                            return TweenAnimationBuilder<double>(
                              duration: Duration(milliseconds: 250 + (index * 40).clamp(0, 200)),
                              tween: Tween<double>(begin: 0.0, end: 1.0),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.scale(
                                    scale: 0.85 + (0.15 * value),
                                    child: child,
                                  ),
                                );
                              },
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    AppPageRoute.create(
                                      context,
                                      ArtistDetailScreen(
                                        artistName: artist.title,
                                        artistId: artist.id,
                                        coverUrl: artist.coverUrl,
                                      ),
                                    ),
                                  );
                                },
                                onLongPress: () => _showArtistMenu(context, user, artist),
                                child: Column(
                                  children: [
                                    AspectRatio(
                                      aspectRatio: 1.0,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                        ),
                                        child: ClipOval(
                                          child: AppCover(
                                            url: artist.coverUrl,
                                            size: double.infinity,
                                            radius: 1000,
                                            artist: artist.title,
                                            title: artist.title,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      artist.title,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        height: 1.2,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
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

  Widget _buildNoSearchResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Iconsax.search_status_copy, size: 54, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 14),
          Text(
            "Ничего не найдено",
            style: AppText.trackTitle.copyWith(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            "Попробуйте изменить поисковый запрос",
            style: AppText.trackArtist.copyWith(fontSize: 13, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Iconsax.profile_2user, size: 40, color: Colors.white38),
            ),
            const SizedBox(height: 20),
            Text(
              "Вы пока не подписались на артистов",
              style: AppText.trackTitle.copyWith(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Открывайте страницы исполнителей и нажимайте «Подписаться», чтобы не потерять их",
              style: AppText.trackArtist.copyWith(color: Colors.white38, fontSize: 13, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text("Назад в медиатеку", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

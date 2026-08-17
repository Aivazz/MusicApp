import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/player/widgets/mini_player.dart';
import 'package:ses/features/search/services/search_service.dart';
import 'package:ses/features/library/screens/album_detail_screen.dart';

class ArtistDetailScreen extends StatefulWidget {
  final String artistName;
  final String? artistId;
  final String? coverUrl;

  const ArtistDetailScreen({
    super.key,
    required this.artistName,
    this.artistId,
    this.coverUrl,
  });

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  List<Song> _tracks = [];
  List<Song> _albums = [];
  bool _isLoading = true;
  String _avatarUrl = '';
  String _bannerUrl = '';
  String _statsText = 'Исполнитель • SoundCloud';

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.coverUrl ?? '';
    _bannerUrl = widget.coverUrl ?? '';
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _loadArtistData();
    });
  }

  Future<void> _loadArtistData() async {
    setState(() {
      _isLoading = true;
    });

    final name = widget.artistName;
    final id = widget.artistId ?? '';

    try {
      final results = await Future.wait([
        SearchService.getArtistSongs(id, name),
        SearchService.getArtistAlbums(id, name),
        SearchService.getArtistDetails(id, name),
      ]);

      if (mounted) {
        final songs = results[0] as List<Song>;
        final albums = results[1] as List<Song>;
        final details = results[2] as Map<String, dynamic>?;

        String avatar = details?['avatarUrl']?.toString() ?? _avatarUrl;
        String banner = details?['bannerUrl']?.toString() ?? '';

        if (avatar.isEmpty && songs.isNotEmpty) {
          avatar = songs.first.coverUrl;
        }

        final count = details?['followersCount'] as int? ?? 0;
        String stats = 'Исполнитель';
        if (count >= 1000000) {
          stats = 'Исполнитель • ${(count / 1000000).toStringAsFixed(1)}M Подписчиков';
        } else if (count >= 1000) {
          stats = 'Исполнитель • ${(count / 1000).toStringAsFixed(1)}K Подписчиков';
        } else if (count > 0) {
          stats = 'Исполнитель • $count Подписчиков';
        }

        setState(() {
          _tracks = songs;
          _albums = albums;
          _avatarUrl = avatar;
          _bannerUrl = banner;
          _statsText = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context);
    final player = Provider.of<PlayerProvider>(context);
    final currentSong = player.currentSong;
    final hasMiniPlayer = currentSong != null && player.showMiniPlayer;

    final isFollowing = user.followedArtists.any(
      (a) => a.title.toLowerCase().trim() == widget.artistName.toLowerCase().trim(),
    );

    final artistIdForFollow = widget.artistId ?? 'sc_artist_${widget.artistName}';

    // Pinned Spotlight items (top 3 albums or tracks)
    final spotlightItems = _albums.isNotEmpty ? _albums.take(3).toList() : _tracks.take(3).toList();
    // Popular tracks (top 5)
    final popularTracks = _tracks.take(5).toList();
    // Remaining tracks
    final remainingTracks = _tracks.length > 5 ? _tracks.sublist(5) : <Song>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── HERO HEADER WITH BANNER & OVERLAPPING AVATAR ──
          SliverToBoxAdapter(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Banner Image
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF181818),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_bannerUrl.isNotEmpty && _bannerUrl != _avatarUrl)
                        // Real wide banner: crisp full resolution
                        AppCover(
                          url: _bannerUrl,
                          size: double.infinity,
                          radius: 0,
                          artist: widget.artistName,
                          title: widget.artistName,
                        )
                      else if (_avatarUrl.isNotEmpty)
                        // Fallback square cover: blurred backdrop to prevent aspect distortion
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                          child: Transform.scale(
                            scale: 1.2,
                            child: AppCover(
                              url: _avatarUrl,
                              size: double.infinity,
                              radius: 0,
                              artist: widget.artistName,
                              title: widget.artistName,
                            ),
                          ),
                        ),

                      // Dark gradient overlays
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.6),
                              Colors.transparent,
                              AppColors.background.withValues(alpha: 0.85),
                              AppColors.background,
                            ],
                            stops: const [0.0, 0.35, 0.85, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Back Button (Top Left)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  child: const AppBackButton(),
                ),

                // Overlapping Circular Avatar (Bottom Left)
                Positioned(
                  bottom: -40,
                  left: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.background, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: AppCover(
                      url: _avatarUrl,
                      size: 104,
                      radius: 52,
                      artist: widget.artistName,
                      title: widget.artistName,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── ARTIST INFO & ACTIONS ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Artist Name & Verified Badge
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.artistName,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1DA1F2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Artist type info
                  Text(
                    _statsText,
                    style: AppText.caption.copyWith(color: Colors.white38),
                  ),

                  const SizedBox(height: 20),

                  // Action Buttons Row (Play All, Follow)
                  Row(
                    children: [
                      // Play All Button
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_tracks.isNotEmpty) {
                              player.setQueueAndPlay(_tracks, startIndex: 0);
                            }
                          },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Iconsax.play, color: Colors.black, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  "Слушать всё",
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      // Follow / Unfollow Button
                      GestureDetector(
                        onTap: () {
                          user.toggleFollow(
                            artistIdForFollow,
                            widget.artistName,
                            _avatarUrl,
                          );
                          AppTheme.showSnackBar(
                            context,
                            isFollowing ? 'Вы отписались от артиста' : 'Вы подписались на артиста',
                          );
                        },
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: isFollowing
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isFollowing
                                  ? AppColors.accentGreen.withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isFollowing ? Iconsax.user_tick : Iconsax.user_add,
                                color: isFollowing ? AppColors.accentGreen : Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isFollowing ? "Вы подписаны" : "Подписаться",
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: isFollowing ? AppColors.accentGreen : Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── LOADING INDICATOR ──
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.accentGreen,
                ),
              ),
            )
          else ...[
            // ── PINNED TO SPOTLIGHT (В фокусе) ──
            if (spotlightItems.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 14),
                      child: Text(
                        "В фокусе",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: spotlightItems.length,
                        itemBuilder: (context, index) {
                          final item = spotlightItems[index];
                          final isAlbum = item.type == 'Album';

                          return GestureDetector(
                            onTap: () {
                              if (isAlbum) {
                                Navigator.push(
                                  context,
                                  AppPageRoute.create(
                                    context,
                                    AlbumDetailScreen(
                                      albumMetadata: item,
                                      type: "Album",
                                    ),
                                  ),
                                );
                              } else {
                                player.setQueueAndPlay(_tracks, startIndex: index);
                              }
                            },
                            child: Container(
                              width: 145,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Stacked artwork effect for albums
                                  Stack(
                                    children: [
                                      if (isAlbum)
                                        Positioned(
                                          top: -4,
                                          left: 8,
                                          right: 8,
                                          child: Container(
                                            height: 140,
                                            decoration: BoxDecoration(
                                              color: Colors.white10,
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                          ),
                                        ),
                                      AppCover(
                                        url: item.coverUrl,
                                        size: 145,
                                        radius: 14,
                                        artist: item.artist,
                                        title: item.title,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isAlbum ? "Альбом" : item.artist,
                                    style: AppText.caption.copyWith(color: Colors.white38),
                                    maxLines: 1,
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
            ],

            // ── POPULAR TRACKS (Популярные треки) ──
            if (popularTracks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Популярные треки",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        "Все",
                        style: AppText.caption.copyWith(color: Colors.white38),
                      ),
                    ],
                  ),
                ),
              ),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = popularTracks[index];
                    final isCurrent = currentSong?.id == song.id ||
                        (currentSong?.title == song.title && currentSong?.artist == song.artist);

                    return AppTrackRow(
                      title: song.title,
                      artist: song.artist,
                      coverUrl: song.coverUrl,
                      isCurrent: isCurrent,
                      isLiked: user.isLiked(song.id),
                      isDownloaded: user.isDownloaded(song.id),
                      song: song,
                      onTap: () {
                        player.setQueueAndPlay(_tracks, startIndex: index);
                      },
                      onLike: () => user.toggleLike(song),
                    );
                  },
                  childCount: popularTracks.length,
                ),
              ),
            ],

            // ── ALBUMS SECTION (Альбомы) ──
            if (_albums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 28, 20, 14),
                      child: Text(
                        "Альбомы и плейлисты",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 195,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: _albums.length,
                        itemBuilder: (context, index) {
                          final album = _albums[index];
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                AppPageRoute.create(
                                  context,
                                  AlbumDetailScreen(
                                    albumMetadata: album,
                                    type: "Album",
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              width: 140,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppCover(
                                    url: album.coverUrl,
                                    size: 140,
                                    radius: 12,
                                    artist: album.artist,
                                    title: album.title,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    album.title,
                                    style: AppText.trackTitle.copyWith(fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Релиз",
                                    style: AppText.caption.copyWith(color: Colors.white38),
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
            ],

            // ── ALL TRACKS SECTION (Все треки) ──
            if (remainingTracks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                  child: Text(
                    "Все треки",
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = remainingTracks[index];
                    final fullIndex = 5 + index;
                    final isCurrent = currentSong?.id == song.id ||
                        (currentSong?.title == song.title && currentSong?.artist == song.artist);

                    return AppTrackRow(
                      title: song.title,
                      artist: song.artist,
                      coverUrl: song.coverUrl,
                      isCurrent: isCurrent,
                      isLiked: user.isLiked(song.id),
                      isDownloaded: user.isDownloaded(song.id),
                      song: song,
                      onTap: () {
                        player.setQueueAndPlay(_tracks, startIndex: fullIndex);
                      },
                      onLike: () => user.toggleLike(song),
                    );
                  },
                  childCount: remainingTracks.length,
                ),
              ),
            ],

            // Empty State
            if (_tracks.isEmpty && _albums.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    "Нет доступных треков или альбомов",
                    style: AppText.caption.copyWith(color: Colors.white38),
                  ),
                ),
              ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 120),
            ),
          ],
        ],
      ),
      bottomNavigationBar: hasMiniPlayer ? const MiniPlayer() : null,
    );
  }
}

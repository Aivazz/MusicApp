import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/search/services/search_service.dart';
import 'package:ses/core/network/backend_service.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/core/widgets/profile_sheet.dart';
import 'package:ses/features/library/screens/album_detail_screen.dart';
import 'package:ses/features/library/screens/view_all_screen.dart';

final List<Map<String, dynamic>> dailyMixes = [
  {
    'id': 'mix_spotify',
    'title': 'Spotify Mix',
    'platform': 'Spotify',
    'query': 'pop indie alternative hits',
    'description': 'Поп, Инди и Альтернатива на основе Spotify',
    'coverUrl': 'https://images.unsplash.com/photo-1614680376593-902f74fa0d41?q=80&w=500',
    'color': const Color(0xFF1DB954),
    'gradient': const [Color(0xFF0F3010), Color(0xFF1DB954)],
  },
  {
    'id': 'mix_soundcloud',
    'title': 'SoundCloud Mix',
    'platform': 'SoundCloud',
    'query': 'electronic house techno underground synthwave',
    'description': 'Электроника и андеграунд на основе SoundCloud',
    'coverUrl': 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?q=80&w=500',
    'color': const Color(0xFFFF5500),
    'gradient': const [Color(0xFF3E1F0F), Color(0xFFFF5500)],
  },
  {
    'id': 'mix_applemusic',
    'title': 'Apple Music Mix',
    'platform': 'Apple Music',
    'query': 'dance pop charts rock classics',
    'description': 'Классический рок и поп-чарты из Apple Music',
    'coverUrl': 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?q=80&w=500',
    'color': const Color(0xFFFA243C),
    'gradient': const [Color(0xFF3F0F20), Color(0xFFFA243C)],
  },
  {
    'id': 'mix_ytmusic',
    'title': 'YouTube Music Mix',
    'platform': 'YouTube Music',
    'query': 'lofi hip hop chill beats rap',
    'description': 'Лоу-фай хип-хоп и чилаут из YouTube Music',
    'coverUrl': 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?q=80&w=500',
    'color': const Color(0xFFFF0000),
    'gradient': const [Color(0xFF3F0A0A), Color(0xFFFF0000)],
  },
];

final List<Song> popularAlbums = [
  Song(id: 'a1', videoId: '', title: 'Starboy', artist: 'The Weeknd',
      coverUrl: 'https://i.scdn.co/image/ab67616d0000b2734718e2b124f79258be7bc452', type: 'album'),
  Song(id: 'a2', videoId: '', title: '1989', artist: 'Taylor Swift',
      coverUrl: 'https://i.scdn.co/image/ab67616d0000b27390fd9741e1838115cd90b3b6', type: 'album'),
  Song(id: 'a3', videoId: '', title: 'Scorpion', artist: 'Drake',
      coverUrl: 'https://i.scdn.co/image/ab67616d0000b273f907de96b9a4fbc04accc0d5', type: 'album'),
  Song(id: 'a4', videoId: '', title: 'After Hours', artist: 'The Weeknd',
      coverUrl: 'https://i.scdn.co/image/ab67616d0000b2738863bc11d2aa12b54f5aeb36', type: 'album'),
  Song(id: 'a5', videoId: '', title: 'Divide', artist: 'Ed Sheeran',
      coverUrl: 'https://i.scdn.co/image/ab67616d0000b273ba5db46f4b838ef6027e6f96', type: 'album'),
  Song(id: 'a6', videoId: '', title: 'Future Nostalgia', artist: 'Dua Lipa',
      coverUrl: 'https://i.scdn.co/image/ab67616d0000b273bd26ede1ae69327010d49946', type: 'album'),
  Song(id: 'a7', videoId: '', title: 'ASTROWORLD', artist: 'Travis Scott',
      coverUrl: 'https://i.scdn.co/image/ab67616d0000b273072e9faef2ef7b6db63834a3', type: 'album'),
  Song(id: 'a8', videoId: '', title: 'SOUR', artist: 'Olivia Rodrigo',
      coverUrl: 'https://i.scdn.co/image/ab67616d0000b273a91c10d3f733158b4da28b40', type: 'album'),
  Song(id: 'a9', videoId: '', title: '24K Magic', artist: 'Bruno Mars',
      coverUrl: 'https://i.scdn.co/image/ab67616d0000b273c36dd9eb55fb073c65cece44', type: 'album'),
  Song(id: 'a10', videoId: '', title: 'Justice', artist: 'Justin Bieber',
      coverUrl: 'https://i.scdn.co/image/ab67616d0000b273e6f407c7f3a0ec98845e4431', type: 'album'),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Song> _trendingArtists = [];
  bool _isLoadingTrending = true;
  List<Song> _recommendedSongs = [];
  bool _isLoadingRecommendations = true;

  @override
  void initState() {
    super.initState();
    _loadTrending();
    _loadRecommendations();
  }

  Future<void> _loadTrending() async {
    try {
      final artists = await SearchService.getTrendingArtists();
      if (mounted) {
        setState(() {
          _trendingArtists = artists;
          _isLoadingTrending = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTrending = false);
    }
  }

  Future<void> _loadRecommendations() async {
    try {
      final topArtists = await BackendService.getTopArtists();
      if (topArtists.isNotEmpty) {
        final topArtist = topArtists.first;
        final songs = await SearchService.search(topArtist);
        if (mounted) {
          setState(() {
            _recommendedSongs = songs;
            _isLoadingRecommendations = false;
          });
          return;
        }
      }
    } catch (_) {}

    // Резервный список при пустом списке или ошибке
    final fallback = [
      Song(id: 'f1', videoId: 'pirate:search:The Weeknd - Blinding Lights', title: 'Blinding Lights', artist: 'The Weeknd',
          coverUrl: 'https://i.scdn.co/image/ab67616d0000b2738863bc11d2aa12b54f5aeb36', duration: const Duration(seconds: 200)),
      Song(id: 'f2', videoId: 'pirate:search:Billie Eilish - Bad Guy', title: 'Bad Guy', artist: 'Billie Eilish',
          coverUrl: 'https://i.scdn.co/image/ab67616d0000b27350a943a5b03512b5368a4176', duration: const Duration(seconds: 194)),
      Song(id: 'f3', videoId: 'pirate:search:Eminem - Without Me', title: 'Without Me', artist: 'Eminem',
          coverUrl: 'https://i.scdn.co/image/ab67616d0000b2736ca26e4088024e27eb478ecb', duration: const Duration(seconds: 290)),
      Song(id: 'f4', videoId: 'pirate:search:Drake - Hotline Bling', title: 'Hotline Bling', artist: 'Drake',
          coverUrl: 'https://i.scdn.co/image/ab67616d0000b273c5cf81451f28b4c09d57a419', duration: const Duration(seconds: 267)),
      Song(id: 'f5', videoId: 'pirate:search:Dua Lipa - Levitating', title: 'Levitating', artist: 'Dua Lipa',
          coverUrl: 'https://i.scdn.co/image/ab67616d0000b273bd26ede1ae69327010d49946', duration: const Duration(seconds: 203)),
    ];
    if (mounted) {
      setState(() {
        _recommendedSongs = fallback;
        _isLoadingRecommendations = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final user = Provider.of<UserProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── APP BAR ──
            SliverAppBar(
              pinned: false,
              floating: true,
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              title: const Text(
                "Ses Music",
                style: TextStyle(
                  fontFamily: 'Inter', color: Colors.white,
                  fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5,
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: AppCircleButton(
                    icon: AppIcons.user,
                    onTap: () => ProfileSheet.show(context),
                    size: 40,
                    iconSize: 18,
                  ),
                ),
              ],
            ),

            if (user.isOfflineMode) ...[
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3F0A0A), Color(0xFFFA243C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFA243C).withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.wifi_off_rounded, color: Colors.white, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            "Офлайн-режим",
                            style: AppText.sectionTitle.copyWith(color: Colors.white, fontSize: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Интернет отключен. Вы можете слушать только скачанную музыку в высоком качестве.",
                        style: AppText.caption.copyWith(color: Colors.white.withOpacity(0.85)),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: AppSectionHeader(
                    title: "Скачанные треки",
                  ),
                ),
              ),
              if (user.downloadedSongs.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text(
                        "У вас нет скачанных песен",
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final song = user.downloadedSongs[i];
                      final currentSong = context.select<PlayerProvider, Song?>((p) => p.currentSong);
                      final isCurrent = currentSong?.id == song.id || (currentSong?.title == song.title && currentSong?.artist == song.artist);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: AppTrackRow(
                          title: song.title,
                          artist: song.artist,
                          coverUrl: song.coverUrl,
                          isCurrent: isCurrent,
                          isLiked: user.isLiked(song.id),
                          isDownloaded: true,
                          onTap: () {
                            player.playSong(song);
                          },
                          onLike: () {
                            user.toggleLike(song);
                          },
                          song: song,
                        ),
                      );
                    },
                    childCount: user.downloadedSongs.length,
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 150)),
            ] else ...[
              // ── AI DAILY MIXES ──
              SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const AppSectionHeader(
                    title: "Персональные плейлисты дня",
                  ),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: dailyMixes.length,
                      itemBuilder: (context, index) {
                        final mix = dailyMixes[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              AppPageRoute.create(
                                context,
                                AlbumDetailScreen(
                                  albumMetadata: Song(
                                    id: mix['id']!,
                                    videoId: mix['query']!,
                                    title: mix['title']!,
                                    artist: mix['description']!,
                                    coverUrl: mix['coverUrl']!,
                                    type: 'playlist',
                                  ),
                                  type: "DailyMix",
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 280,
                            margin: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: (mix['color'] as Color).withOpacity(0.15),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Stack(
                                children: [
                                  // Background Cover
                                  Positioned.fill(
                                    child: Image.network(
                                      mix['coverUrl']!,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  // Gradient Overlay
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            (mix['gradient'] as List<Color>)[0].withOpacity(0.3),
                                            Colors.black.withOpacity(0.85),
                                          ],
                                          stops: const [0.0, 0.8],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Content
                                  Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Top row: Platform Tag & Logo/Name
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: (mix['color'] as Color).withOpacity(0.85),
                                                borderRadius: BorderRadius.circular(30),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    mix['platform'] == 'Spotify'
                                                        ? Icons.music_note
                                                        : (mix['platform'] == 'SoundCloud'
                                                            ? Icons.cloud
                                                            : (mix['platform'] == 'Apple Music'
                                                                ? Icons.apple
                                                                : Icons.play_circle_fill)),
                                                    color: Colors.white,
                                                    size: 13,
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    mix['platform']!,
                                                    style: const TextStyle(
                                                      fontFamily: 'Inter',
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w800,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.08),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.auto_awesome,
                                                color: Colors.amberAccent,
                                                size: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Bottom details
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    mix['title']!,
                                                    style: const TextStyle(
                                                      fontFamily: 'Inter',
                                                      color: Colors.white,
                                                      fontSize: 20,
                                                      fontWeight: FontWeight.w900,
                                                      letterSpacing: -0.5,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    mix['description']!,
                                                    style: const TextStyle(
                                                      fontFamily: 'Inter',
                                                      color: Colors.white70,
                                                      fontSize: 11,
                                                      height: 1.3,
                                                    ),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Container(
                                              width: 38,
                                              height: 38,
                                              decoration: const BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Center(
                                                child: Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: Colors.black,
                                                  size: 22,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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

            // ── RECOMMENDATIONS ──
            if (!_isLoadingRecommendations && _recommendedSongs.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: AppSectionHeader(
                  title: "Рекомендовано для вас",
                  onSeeAll: () => Navigator.push(context, AppPageRoute.create(context, 
                      ViewAllScreen(title: "Рекомендовано для вас", items: _recommendedSongs))),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 204,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _recommendedSongs.length,
                    itemBuilder: (context, i) {
                      final song = _recommendedSongs[i];
                      return GestureDetector(
                        onTap: () {
                          player.playSong(song);
                        },
                        child: Container(
                          width: 144,
                          margin: const EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.02)),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppCover(
                                url: song.coverUrl,
                                size: 128,
                                radius: 14,
                                artist: song.artist,
                                title: song.title,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                song.title,
                                style: AppText.trackTitle.copyWith(fontSize: 12, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist,
                                style: AppText.trackArtist.copyWith(fontSize: 10, color: Colors.white38),
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
              ),
            ],

            // ── TRENDING ARTISTS ──
            if (!_isLoadingTrending && _trendingArtists.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: AppSectionHeader(
                  title: "Популярные артисты",
                  onSeeAll: () => Navigator.push(context, AppPageRoute.create(context, 
                      ViewAllScreen(title: "Популярные артисты", items: _trendingArtists))),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 184,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _trendingArtists.length,
                    itemBuilder: (context, i) {
                      final artist = _trendingArtists[i];
                      return Container(
                        width: 126,
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.02)),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            AppCover(
                              url: artist.coverUrl,
                              size: 110,
                              radius: 55,
                              artist: artist.title,
                              title: artist.title,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              artist.title,
                              style: AppText.trackTitle.copyWith(fontSize: 12, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],

            // ── POPULAR ALBUMS ──
            if (popularAlbums.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: AppSectionHeader(
                  title: "Популярные альбомы",
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 204,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: popularAlbums.length,
                    itemBuilder: (context, i) {
                      final album = popularAlbums[i];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(context, AppPageRoute.create(context, 
                              AlbumDetailScreen(albumMetadata: album, type: "Album")));
                        },
                        child: Container(
                          width: 144,
                          margin: const EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.02)),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppCover(
                                url: album.coverUrl,
                                size: 128,
                                radius: 14,
                                artist: album.artist,
                                title: album.title,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                album.title,
                                style: AppText.trackTitle.copyWith(fontSize: 12, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                album.artist,
                                style: AppText.trackArtist.copyWith(fontSize: 10, color: Colors.white38),
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
              ),
            ],

            const SliverPadding(padding: EdgeInsets.only(bottom: 150)),
          ]
        ],
      ),
    ),
  );
}
}

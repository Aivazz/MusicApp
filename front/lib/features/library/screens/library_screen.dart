import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/search/services/search_service.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/screens/liked_songs_screen.dart';
import 'package:ses/features/import_export/screens/downloads_screen.dart';
import 'package:ses/features/library/screens/playlists_screen.dart';
import 'package:ses/features/library/screens/view_all_screen.dart';
import 'package:ses/features/library/screens/recent_history_screen.dart';
import 'package:ses/features/library/screens/album_detail_screen.dart';
import 'package:ses/features/library/screens/recent_playlists_screen.dart';
import 'package:ses/features/library/screens/settings_screen.dart';
import 'package:ses/features/import_export/services/soundcloud_service.dart';
import 'package:ses/features/library/screens/artist_detail_screen.dart';
import 'package:ses/features/library/screens/artists_screen.dart';


final List<Song> searchRecommendations = [
  Song(id: 'sr1', videoId: 'qj5z4S3_048', title: 'Махаббат бер маған', artist: 'Кайрат Нуртас', coverUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?q=80&w=200', type: 'song'),
  Song(id: 'sr2', videoId: 'hYgqN8HshdE', title: 'Девочка в платьице белом', artist: 'Шахзода', coverUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?q=80&w=200', type: 'song'),
  Song(id: 'sr3', videoId: '3O1_3zBUWY8', title: 'Где ты', artist: 'Три дня дождя', coverUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?q=80&w=200', type: 'song'),
  Song(id: 'sr4', videoId: 't2pZ18h16-c', title: 'Сен маған кересің', artist: 'Ерке Есмахан', coverUrl: 'https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?q=80&w=200', type: 'song'),
];

final List<Map<String, dynamic>> searchRecommendedPlaylists = [
  {
    'id': '37i9dQZF1DX4Y467yv74Qx',
    'title': 'Казахский Вайб',
    'query': '',
    'description': 'Qazaqsha Mix на Spotify',
    'coverUrl': 'https://images.unsplash.com/photo-1465847899084-d164df4dedc6?q=80&w=400',
    'color': const Color(0xFF00ADB5),
    'gradient': [const Color(0xFF072A2C), const Color(0xFF00ADB5)],
  },
  {
    'id': '37i9dQZF1DXcBWIG4256J4',
    'title': 'Мировые Хиты',
    'query': '',
    'description': 'Today\'s Top Hits на Spotify',
    'coverUrl': 'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?q=80&w=400',
    'color': const Color(0xFFE91E63),
    'gradient': [const Color(0xFF350A1A), const Color(0xFFE91E63)],
  },
  {
    'id': '37i9dQZF1DWWQRwui0ExPn',
    'title': 'Lofi Chillout',
    'query': '',
    'description': 'Lofi Beats на Spotify',
    'coverUrl': 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?q=80&w=400',
    'color': const Color(0xFFFF9800),
    'gradient': [const Color(0xFF352003), const Color(0xFFFF9800)],
  },
];

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  bool _isSearchMode = false;
  bool _isLoading = false;
  int _selectedCategoryIndex = 0; // 0: All, 1: Tracks, 2: People, 3: Playlists, 4: Albums
  List<Song> _searchResults = [];
  Timer? _debounceTimer;
  final Set<String> _followedArtistIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus && !_isSearchMode) {
        setState(() => _isSearchMode = true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<UserProvider>().loadSearchHistory();
      }
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _debounceTimer?.cancel();
    
    if (query.isEmpty) {
      if (mounted) setState(() { _searchResults = []; _isLoading = false; });
      return;
    }
    
    if (mounted) setState(() => _isLoading = true);
    _debounceTimer = Timer(const Duration(milliseconds: 250), () => _doSearch(query));
  }

  Future<void> _doSearch(String query) async {
    final user = context.read<UserProvider>();
    if (user.isOfflineMode) {
      final results = user.downloadedSongs.where((song) {
        final titleMatch = song.title.toLowerCase().contains(query.toLowerCase());
        final artistMatch = song.artist.toLowerCase().contains(query.toLowerCase());
        return titleMatch || artistMatch;
      }).toList();
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
      return;
    }

    List<Song> results = [];
    try {
      if (_selectedCategoryIndex == 0) {
        results = await SearchService.searchMixed(query, offset: 0, limit: 35);
      } else if (_selectedCategoryIndex == 1) {
        results = await SoundcloudService.search(query, offset: 0, limit: 35);
      } else if (_selectedCategoryIndex == 2) {
        results = await SearchService.searchArtists(query);
      } else if (_selectedCategoryIndex == 3) {
        results = await SearchService.searchPlaylists(query, offset: 0, limit: 25);
      } else if (_selectedCategoryIndex == 4) {
        results = await SearchService.searchAlbums(query, offset: 0, limit: 25);
      }
    } catch (e) {
      print("Error doing search in LibraryScreen: $e");
    }

    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isLoading = false;
    });
  }

  void _exitSearchMode() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() {
      _isSearchMode = false;
      _searchResults = [];
      _isLoading = false;
      _selectedCategoryIndex = 0;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context);
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final currentSong = context.select<PlayerProvider, Song?>((p) => p.currentSong);
    final recentEntries = context.select<PlayerProvider, List<PlayHistoryEntry>>((p) => p.playHistory);
    final recentSongs = recentEntries.map((e) => e.song).toList();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── HEADER ──
            RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: AppSearchBar(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      hint: "Поиск в медиатеке",
                    ),
                  ),
                  _isSearchMode
                      ? Row(
                          key: const ValueKey('cancel_btn'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: _exitSearchMode,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text("Отмена", style: AppText.caption.copyWith(color: Colors.white70)),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          key: const ValueKey('settings_and_download_btn'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (user.downloadQueue.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () => _showDownloadQueueSheet(context, user),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.03)),
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Icon(
                                        AppIcons.download,
                                        color: AppColors.accentGreen,
                                        size: 20,
                                      ),
                                      Positioned(
                                        right: -4,
                                        top: -4,
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: AppColors.accentGreen,
                                            shape: BoxShape.circle,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 10,
                                            minHeight: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () async {
                                Provider.of<PlayerProvider>(context, listen: false).setShowMiniPlayer(false);
                                await Navigator.push(
                                  context,
                                  AppPageRoute.create(context, const SettingsScreen()),
                                );
                                if (context.mounted) {
                                  Provider.of<PlayerProvider>(context, listen: false).setShowMiniPlayer(true);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.03)),
                                ),
                                child: Icon(
                                  AppIcons.settings,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ),

            if (_isSearchMode && _searchController.text.trim().isNotEmpty)
              _buildCategoryTabs(),

            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SpotifyImportLoader(
                  progressText: user.importProgressText,
                ),
              ),
              crossFadeState: user.isImportingSpotify
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
              sizeCurve: Curves.easeInOutCubic,
              firstCurve: Curves.easeInOutCubic,
              secondCurve: Curves.easeInOutCubic,
            ),

            // ── CONTENT ──
            Expanded(
              child: _isSearchMode
                  ? RepaintBoundary(child: _buildSearchContent(player, user, currentSong))
                  : _buildLibraryContent(player, user, recentSongs, currentSong),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryContent(PlayerProvider player, UserProvider user, List<Song> recentSongs, Song? currentSong) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      children: [
        // ── QUICK NAVIGATION ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _QuickAction(
                icon: AppIcons.heart,
                label: "Любимые",
                count: user.likedSongs.length,
                onTap: () => Navigator.push(context, AppPageRoute.create(context, const LikedSongsScreen())),
              ),
              const SizedBox(width: 6),
              _QuickAction(
                icon: AppIcons.playlist,
                label: "Плейлисты",
                count: user.playlists.length,
                onTap: () => Navigator.push(context, AppPageRoute.create(context, const PlaylistsScreen())),
              ),
              const SizedBox(width: 6),
              _QuickAction(
                icon: AppIcons.download,
                label: "Офлайн",
                count: user.downloadedSongs.length,
                onTap: () => Navigator.push(context, AppPageRoute.create(context, const DownloadsScreen())),
              ),
              const SizedBox(width: 6),
              _QuickAction(
                icon: Iconsax.profile_2user_copy,
                label: "Подписки",
                count: user.followedArtists.length,
                onTap: () => Navigator.push(context, AppPageRoute.create(context, const ArtistsScreen())),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── RECENT PLAYLISTS ──
        _buildRecentPlaylistsSection(user),

        // ── RECENTLY PLAYED ──
        AppSectionHeader(
          title: "Недавно прослушано",
          onSeeAll: recentSongs.isEmpty ? null : () => Navigator.push(
            context,
            AppPageRoute.create(context, const RecentHistoryScreen()),
          ),
        ),

        if (recentSongs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text("История прослушиваний появится здесь", style: AppText.trackArtist),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Builder(
              builder: (context) {
                final displayedSongs = recentSongs.take(10).toList();
                return SizedBox(
                  height: displayedSongs.length * 74.0,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: List.generate(displayedSongs.length, (index) {
                      final song = displayedSongs[index];
                      return AnimatedPositioned(
                        key: ValueKey(song.id),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeInOutCubic,
                        top: index * 74.0,
                        left: 0,
                        right: 0,
                        height: 74.0,
                        child: AppTrackRow(
                          title: song.title,
                          artist: song.artist,
                          coverUrl: song.coverUrl,
                          isCurrent: currentSong?.id == song.id || (currentSong?.title == song.title && currentSong?.artist == song.artist),
                          isLiked: user.isLiked(song.id),
                          isDownloaded: user.isDownloaded(song.id),
                          onTap: () => player.playSong(song),
                          onLike: () => user.toggleLike(song),
                          song: song,
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
          ),
        
        // Bottom padding for miniplayer
        if (currentSong != null) const SizedBox(height: 80),
      ],
    );
  }

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

  Widget _buildRecentPlaylistsSection(UserProvider user) {
    final recents = user.recentPlaylists;
    if (recents.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: "Недавние подборки",
          onSeeAll: () => Navigator.push(
            context,
            AppPageRoute.create(
              context,
              const RecentPlaylistsScreen(),
            ),
          ),
        ),
        SizedBox(
          height: 165,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: recents.length,
            itemBuilder: (context, index) {
              final entry = recents[index];
              final metadata = entry.playlistMetadata;
              final cover = metadata.coverUrl;
              final name = metadata.title;
              final artist = metadata.artist;
              
              final coverWidget = cover.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: _getPlaylistGradient(name),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Icon(
                          AppIcons.music,
                          color: Colors.white.withValues(alpha: 0.85),
                          size: 36,
                        ),
                      ),
                    )
                  : AppCover(url: cover, size: 110, radius: 16);

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    AppPageRoute.create(
                      context,
                      AlbumDetailScreen(
                        albumMetadata: metadata,
                        type: entry.playlistType,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 110,
                  margin: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: coverWidget,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        style: AppText.trackTitle.copyWith(fontSize: 13, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.playlistType == "CustomPlaylist" 
                            ? "Плейлист • $artist" 
                            : (entry.playlistType == "Album" ? "Альбом • $artist" : "Подборка • $artist"),
                        style: AppText.trackArtist.copyWith(fontSize: 11, color: Colors.white38),
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
        const SizedBox(height: 8),
      ],
    );
  }

  String _formatCount(int? count) {
    if (count == null || count <= 0) return '';
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return '$count';
  }

  String _formatYearOrTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr);
      final diffDays = DateTime.now().difference(dt).inDays;
      if (diffDays >= 365) {
        final years = (diffDays / 365).floor();
        return '${years}y';
      } else if (diffDays >= 30) {
        final months = (diffDays / 30).floor();
        return '${months}m';
      } else if (diffDays >= 1) {
        return '${diffDays}d';
      }
      return dt.year.toString();
    } catch (_) {}
    if (dateStr.length >= 4) {
      return dateStr.substring(0, 4);
    }
    return '';
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds <= 0) return '';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  void _navigateToArtist(BuildContext context, Song song) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push(
      context,
      AppPageRoute.create(
        context,
        ArtistDetailScreen(
          artistName: song.title,
          artistId: song.id,
          coverUrl: song.coverUrl,
        ),
      ),
    );
  }

  void _navigateToAlbum(BuildContext context, Song song) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push(
      context,
      AppPageRoute.create(
        context,
        AlbumDetailScreen(
          albumMetadata: song,
          type: song.type,
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    final categories = ['Все', 'Треки', 'Артисты', 'Плейлисты', 'Альбомы'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(categories.length, (index) {
          final isSelected = _selectedCategoryIndex == index;
          return GestureDetector(
            onTap: () {
              if (_selectedCategoryIndex != index) {
                setState(() {
                  _selectedCategoryIndex = index;
                  _searchResults = [];
                  _isLoading = true;
                });
                if (_searchController.text.trim().isNotEmpty) {
                  _doSearch(_searchController.text.trim());
                }
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  categories[index],
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.white54,
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 2.5,
                  width: isSelected ? 18 : 0,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.accentGreen : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSearchContent(PlayerProvider player, UserProvider user, Song? currentSong) {
    if (_isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.only(top: 8),
        itemCount: 8,
        itemBuilder: (context, index) => const AppTrackRowShimmer(),
      );
    }

    final query = _searchController.text.trim();

    if (query.isEmpty) {
      if (user.searchHistory.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.search, size: 48, color: Colors.white24),
              const SizedBox(height: 12),
              Text(
                "Ищите песни, артистов и плейлисты",
                style: AppText.trackArtist.copyWith(color: Colors.white38),
              ),
            ],
          ),
        );
      }

      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("История поиска", style: AppText.sectionTitle.copyWith(fontSize: 18)),
              GestureDetector(
                onTap: () => user.clearHistory(),
                child: Text("Очистить", style: AppText.caption.copyWith(color: AppColors.accentRed.withOpacity(0.7))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: user.searchHistory.map((entry) => _buildHistoryItem(context, entry, user)).toList(),
          ),
          const SizedBox(height: 120),
        ],
      );
    }

    if (_searchResults.isEmpty) {
      return Center(child: Text("Ничего не найдено", style: AppText.trackArtist));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 120),
      itemCount: _searchResults.length,
      itemBuilder: (context, i) {
        final item = _searchResults[i];
        if (item.type == 'artist') {
          return _buildArtistRow(context, item);
        } else if (item.type == 'Album' || item.type == 'Playlist') {
          return _buildPlaylistOrAlbumRow(context, item);
        } else {
          return _buildTrackRow(context, item, player, user, currentSong);
        }
      },
    );
  }

  Widget _buildArtistRow(BuildContext context, Song song) {
    final isFollowed = _followedArtistIds.contains(song.id);
    final followersText = _formatCount(song.followersCount);
    final subtitle = followersText.isNotEmpty ? '👤 $followersText Подписчиков' : 'Артист';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _navigateToArtist(context, song),
            child: Container(
              decoration: const BoxDecoration(shape: BoxShape.circle),
              clipBehavior: Clip.antiAlias,
              child: AppCover(
                url: song.coverUrl,
                size: 54,
                radius: 27,
                artist: song.title,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: () => _navigateToArtist(context, song),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white54,
                      fontSize: 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              setState(() {
                if (isFollowed) {
                  _followedArtistIds.remove(song.id);
                } else {
                  _followedArtistIds.add(song.id);
                }
              });
              AppTheme.showSnackBar(
                context,
                isFollowed ? 'Вы отписались от ${song.title}' : 'Вы подписались на ${song.title}',
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: isFollowed ? Colors.white10 : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: isFollowed ? Border.all(color: Colors.white24) : null,
              ),
              child: Text(
                isFollowed ? 'Вы подписаны' : 'Подписаться',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: isFollowed ? Colors.white70 : Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistOrAlbumRow(BuildContext context, Song song) {
    final isAlbum = song.type == 'Album';
    final countText = _formatCount(song.playCount);
    final year = _formatYearOrTime(song.yearText);

    List<String> metaParts = [song.artist];
    if (countText.isNotEmpty) {
      metaParts.add(isAlbum ? '$countText треков' : '► $countText');
    }
    if (year.isNotEmpty) {
      metaParts.add(year);
    }
    metaParts.add(isAlbum ? 'Альбом' : 'Плейлист');

    return GestureDetector(
      onTap: () => _navigateToAlbum(context, song),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            AppCover(
              url: song.coverUrl,
              size: 54,
              radius: 10,
              title: song.title,
              artist: song.artist,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metaParts.join(' · '),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white30,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackRow(BuildContext context, Song song, PlayerProvider player, UserProvider user, Song? currentSong) {
    final isCurrent = currentSong?.id == song.id ||
        (currentSong?.title == song.title && currentSong?.artist == song.artist);

    final playsText = _formatCount(song.playCount);
    final durationText = _formatDuration(song.duration);
    final yearText = _formatYearOrTime(song.yearText);

    List<String> metaParts = [song.artist];
    if (playsText.isNotEmpty) metaParts.add('► $playsText');
    if (durationText.isNotEmpty) metaParts.add(durationText);
    if (yearText.isNotEmpty) metaParts.add(yearText);

    return AppTrackRow(
      title: song.title,
      artist: metaParts.join(' · '),
      coverUrl: song.coverUrl,
      isCurrent: isCurrent,
      isLiked: user.isLiked(song.id),
      isDownloaded: user.isDownloaded(song.id),
      onTap: () {
        _searchFocusNode.unfocus();
        user.addToHistory(SearchHistoryEntry(
          id: song.id,
          title: song.title,
          subtitle: 'Песня • ${song.artist}',
          coverUrl: song.coverUrl,
          type: 'song',
        ));
        player.playSong(song);
      },
      onLike: () {
        final wasLiked = user.isLiked(song.id);
        user.toggleLike(song);
        AppTheme.showSnackBar(
          context,
          wasLiked ? 'Удалено из избранного' : 'Добавлено в избранное',
        );
      },
      song: song,
    );
  }

  Widget _buildHistoryItem(BuildContext context, SearchHistoryEntry entry, UserProvider user) {
    final isArtist = entry.type == 'artist';
    String artistName = entry.subtitle;
    if (artistName.startsWith('Песня • ')) {
      artistName = artistName.replaceFirst('Песня • ', '');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          AppCover(
            url: entry.coverUrl,
            size: 44,
            radius: isArtist ? 22 : 8,
            artist: isArtist ? entry.title : artistName,
            title: isArtist ? null : entry.title,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (isArtist) {
                  _searchController.text = entry.title;
                  _doSearch(entry.title);
                } else {
                  final player = Provider.of<PlayerProvider>(context, listen: false);
                  final song = Song(
                    id: entry.id,
                    videoId: entry.id.startsWith('pirate:search:') 
                        ? entry.id 
                        : (entry.id.startsWith('http') ? entry.id : 'pirate:search:$artistName - ${entry.title}'),
                    title: entry.title,
                    artist: artistName,
                    coverUrl: entry.coverUrl,
                    type: 'song',
                  );
                  player.playSong(song);
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title, style: AppText.trackTitle, maxLines: 1),
                  Text(entry.subtitle, style: AppText.trackArtist, maxLines: 1),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => user.removeFromHistory(entry.id),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(AppIcons.close, color: Colors.white30, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  void _showDownloadQueueSheet(BuildContext context, UserProvider user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          snap: true,
          expand: false,
          builder: (context, scrollController) {
            return Consumer<UserProvider>(
              builder: (context, userProvider, child) {
                final queue = userProvider.downloadQueue;
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.03))),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Очередь загрузок",
                        style: AppText.sectionTitle.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        queue.isEmpty
                            ? "Нет активных загрузок"
                            : "Скачивание треков в фоновом режиме",
                        style: AppText.caption.copyWith(color: Colors.white38),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: queue.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      AppIcons.download,
                                      size: 48,
                                      color: Colors.white.withOpacity(0.05),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      "Все треки успешно скачаны",
                                      style: AppText.trackArtist.copyWith(color: Colors.white24),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: queue.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final song = queue[index];
                                  final isActivelyDownloading = userProvider.isActivelyDownloading(song.id);
                                  final progress = userProvider.getDownloadProgress(song.id);

                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.02),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white.withOpacity(0.01)),
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: song.coverUrl.startsWith('http')
                                              ? Image.network(
                                                  song.coverUrl,
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => Container(
                                                    width: 44,
                                                    height: 44,
                                                    color: Colors.white12,
                                                    child: const Icon(Icons.music_note, color: Colors.white24),
                                                  ),
                                                )
                                              : (song.coverUrl.isNotEmpty
                                                  ? Image.file(
                                                      File(song.coverUrl),
                                                      width: 44,
                                                      height: 44,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => Container(
                                                        width: 44,
                                                        height: 44,
                                                        color: Colors.white12,
                                                        child: const Icon(Icons.music_note, color: Colors.white24),
                                                      ),
                                                )
                                                  : Container(
                                                      width: 44,
                                                      height: 44,
                                                      color: Colors.white12,
                                                      child: const Icon(Icons.music_note, color: Colors.white24),
                                                    )),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                song.title,
                                                style: AppText.trackTitle.copyWith(fontSize: 14),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              if (isActivelyDownloading) ...[
                                                TweenAnimationBuilder<double>(
                                                  duration: const Duration(milliseconds: 250),
                                                  curve: Curves.easeOut,
                                                  tween: Tween<double>(begin: 0, end: progress),
                                                  builder: (context, value, child) {
                                                    return Row(
                                                      children: [
                                                        Expanded(
                                                          child: ClipRRect(
                                                            borderRadius: BorderRadius.circular(2),
                                                            child: LinearProgressIndicator(
                                                              value: value,
                                                              backgroundColor: Colors.white10,
                                                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                                                              minHeight: 4,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          "${(value * 100).toInt()}%",
                                                          style: AppText.caption.copyWith(
                                                            color: AppColors.accentGreen,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ] else ...[
                                                Text(
                                                  "В очереди",
                                                  style: AppText.caption.copyWith(color: Colors.white38),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        IconButton(
                                          icon: const Icon(Icons.close_rounded, color: Colors.white38),
                                          iconSize: 20,
                                          onPressed: () => userProvider.cancelDownload(song.id),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 98,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const Spacer(),
              Text(
                label,
                style: AppText.trackTitle.copyWith(fontSize: 11, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                "$count объектов",
                style: AppText.trackArtist.copyWith(fontSize: 10, color: Colors.white38),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SpotifyImportLoader extends StatefulWidget {
  final String progressText;
  
  const SpotifyImportLoader({super.key, required this.progressText});

  @override
  State<SpotifyImportLoader> createState() => _SpotifyImportLoaderState();
}

class _SpotifyImportLoaderState extends State<SpotifyImportLoader> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.accentGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentGreen.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentGreen.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.progressText.isNotEmpty
                      ? widget.progressText
                      : "Импорт плейлиста...",
                  style: AppText.trackTitle.copyWith(
                    fontSize: 13,
                    color: AppColors.accentGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white.withOpacity(0.06),
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


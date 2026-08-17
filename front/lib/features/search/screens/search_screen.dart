import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/search/services/search_service.dart';
import 'package:ses/features/import_export/services/soundcloud_service.dart';
import 'package:ses/features/library/screens/artist_detail_screen.dart';
import 'package:ses/features/library/screens/album_detail_screen.dart';
import 'package:ses/core/theme/app_theme.dart';

final List<Map<String, dynamic>> searchCategories = [
  {
    'title': 'Казахские хиты',
    'query': 'Казахские песни',
    'color': const Color(0xFF00ADB5),
    'gradient': [const Color(0xFF0F3E42), const Color(0xFF00ADB5)],
    'icon': Icons.star_border_rounded,
  },
  {
    'title': 'Поп-музыка',
    'query': 'pop hits 2026',
    'color': const Color(0xFFE91E63),
    'gradient': [const Color(0xFF420F24), const Color(0xFFE91E63)],
    'icon': Icons.music_note_rounded,
  },
  {
    'title': 'Хип-хоп / Рэп',
    'query': 'hip hop rap underground',
    'color': const Color(0xFF9C27B0),
    'gradient': [const Color(0xFF320F3E), const Color(0xFF9C27B0)],
    'icon': Icons.mic_external_on_rounded,
  },
  {
    'title': 'Лоу-фай для учебы',
    'query': 'lofi study chill beats',
    'color': const Color(0xFFFF9800),
    'gradient': [const Color(0xFF3E280F), const Color(0xFFFF9800)],
    'icon': Icons.coffee_rounded,
  },
  {
    'title': 'Рок классика',
    'query': 'rock classic metal rock',
    'color': const Color(0xFFF44336),
    'gradient': [const Color(0xFF3E0F0F), const Color(0xFFF44336)],
    'icon': Icons.bolt_rounded,
  },
  {
    'title': 'Клубный микс',
    'query': 'electronic house techno edm',
    'color': const Color(0xFF2196F3),
    'gradient': [const Color(0xFF0F263E), const Color(0xFF2196F3)],
    'icon': Icons.album_rounded,
  },
];

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  int _searchSequence = 0;
  int _selectedCategoryIndex = 0; // 0: Все, 1: Треки, 2: Исполнители, 3: Плейлисты, 4: Альбомы
  String _currentQuery = '';
  List<Song> _results = [];
  Timer? _debounceTimer;
  final Set<String> _followedArtistIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadSearchHistory();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 450) {
      _loadMore();
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      _debounceTimer?.cancel();
      if (mounted) {
        setState(() {
          _results = [];
          _isLoading = false;
          _currentQuery = '';
          _offset = 0;
          _hasMore = true;
        });
      }
      return;
    }

    if (query == _currentQuery && _results.isNotEmpty) {
      return;
    }

    _debounceTimer?.cancel();

    // Fast 250ms debounce for network calls
    _debounceTimer = Timer(
      const Duration(milliseconds: 250),
      () {
        if (mounted) {
          _doSearch(query);
        }
      },
    );
  }

  Future<void> _doSearch(String query) async {
    final currentSequence = ++_searchSequence;
    _currentQuery = query;
    _offset = 0;
    _hasMore = true;

    if (_results.isEmpty) {
      setState(() {
        _isLoading = true;
      });
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
      print("Error doing category search: $e");
    }

    if (!mounted || currentSequence != _searchSequence) return;

    setState(() {
      _results = results;
      _isLoading = false;
      _hasMore = results.length >= 25;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _currentQuery.isEmpty) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final newOffset = _offset + 25;
      List<Song> newResults = [];
      if (_selectedCategoryIndex == 0) {
        newResults = await SearchService.searchMixed(_currentQuery, offset: newOffset, limit: 25);
      } else if (_selectedCategoryIndex == 1) {
        newResults = await SoundcloudService.search(_currentQuery, offset: newOffset, limit: 25);
      } else if (_selectedCategoryIndex == 3) {
        newResults = await SearchService.searchPlaylists(_currentQuery, offset: newOffset, limit: 25);
      } else if (_selectedCategoryIndex == 4) {
        newResults = await SearchService.searchAlbums(_currentQuery, offset: newOffset, limit: 25);
      }

      if (newResults.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
      } else {
        final existingIds = _results.map((s) => s.id).toSet();
        final unique = newResults.where((s) => !existingIds.contains(s.id)).toList();

        setState(() {
          _results.addAll(unique);
          _offset = newOffset;
          _isLoadingMore = false;
          _hasMore = newResults.length >= 25;
        });
      }
    } catch (e) {
      print("Error loading more search results: $e");
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context);
    final isSearching = _searchController.text.isNotEmpty;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── HEADER WITH SEARCH & CANCEL BUTTON ──
            RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: AppSearchBar(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        hint: "Найти песни, артистов...",
                        onChanged: (val) {
                          if (mounted) setState(() {});
                        },
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            _doSearch(val.trim());
                          }
                        },
                        onClear: () {
                          setState(() {
                            _results = [];
                            _isLoading = false;
                            _currentQuery = '';
                            _offset = 0;
                            _hasMore = true;
                          });
                        },
                      ),
                    ),
                  if (isSearching || _searchFocusNode.hasFocus) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _searchFocusNode.unfocus();
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _results = [];
                          _isLoading = false;
                          _currentQuery = '';
                          _selectedCategoryIndex = 0;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text(
                          "Отмена",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

            // ── CATEGORY TABS BAR ──
            if (isSearching || _searchFocusNode.hasFocus) _buildCategoryTabs(),

            // ── CONTENT ──
            Expanded(
              child: RepaintBoundary(
                child: _isLoading && _results.isEmpty
                    ? ListView.builder(
                        padding: const EdgeInsets.only(top: 8),
                        itemCount: 8,
                        itemBuilder: (context, index) => const AppTrackRowShimmer(),
                      )
                    : isSearching
                        ? _buildResults(context)
                        : _buildHistory(context, user),
              ),
            ),
          ],
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
                  _results = [];
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

  Widget _buildResults(BuildContext context) {
    if (_results.isEmpty) {
      return Center(
        child: Text(
          "Ничего не найдено",
          style: AppText.trackArtist.copyWith(fontSize: 15),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      itemCount: _results.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _results.length) {
          return SizedBox(
            height: 60.0,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.accentGreen,
                ),
              ),
            ),
          );
        }

        final item = _results[i];
        if (item.type == 'artist') {
          return _buildArtistRow(context, item);
        } else if (item.type == 'Album' || item.type == 'Playlist') {
          return _buildPlaylistOrAlbumRow(context, item);
        } else {
          return _buildTrackRow(context, item);
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

  Widget _buildTrackRow(BuildContext context, Song song) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final user = Provider.of<UserProvider>(context);
    final currentSong = context.select<PlayerProvider, Song?>((p) => p.currentSong);
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
        FocusScope.of(context).unfocus();
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

  Widget _buildHistory(BuildContext context, UserProvider user) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        if (user.searchHistory.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("История поиска", style: AppText.sectionTitle.copyWith(fontSize: 18)),
              GestureDetector(
                onTap: () => user.clearHistory(),
                child: Text("Очистить", style: AppText.caption.copyWith(color: AppColors.accentRed.withValues(alpha: 0.7))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...user.searchHistory.take(3).map((entry) => _buildHistoryItem(context, entry, user)),
          const SizedBox(height: 16),
        ],

        // ── RECOMMENDED CATEGORIES ──
        const SizedBox(height: 8),
        Text("Рекомендуемые категории", style: AppText.sectionTitle.copyWith(fontSize: 18)),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 1200
                ? 5
                : (constraints.maxWidth > 800
                    ? 4
                    : (constraints.maxWidth > 550 ? 3 : 2));
            final itemWidth = (constraints.maxWidth - (crossAxisCount - 1) * 14) / crossAxisCount;
            final itemHeight = itemWidth / 1.6;

            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: searchCategories.map((cat) {
                return SizedBox(
                  width: itemWidth,
                  height: itemHeight,
                  child: GestureDetector(
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      _searchFocusNode.unfocus();
                      _searchController.text = cat['title']!;
                      _doSearch(cat['query']!);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: cat['gradient'] as List<Color>,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (cat['color'] as Color).withValues(alpha: 0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Positioned(
                            bottom: -15,
                            right: -15,
                            child: Opacity(
                              opacity: 0.15,
                              child: Icon(
                                cat['icon'] as IconData,
                                size: 72,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Icon(
                                  cat['icon'] as IconData,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  size: 20,
                                ),
                                Text(
                                  cat['title']!,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildHistoryItem(BuildContext context, SearchHistoryEntry entry, UserProvider user) {
    final isArtist = entry.type == 'artist';
    final isAlbumOrPlaylist = entry.type == 'Album' || entry.type == 'Playlist';
    String artistName = entry.subtitle;
    if (artistName.startsWith('Песня • ')) {
      artistName = artistName.replaceFirst('Песня • ', '');
    }

    final currentSong = context.select<PlayerProvider, Song?>((p) => p.currentSong);
    final isPlaying = context.select<PlayerProvider, bool>((p) => p.isPlaying);
    final isCurrent = currentSong != null &&
        (currentSong.id == entry.id ||
         (currentSong.title.toLowerCase() == entry.title.toLowerCase() &&
          (currentSong.artist.toLowerCase() == artistName.toLowerCase() || isArtist)));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AppCover(
                url: entry.coverUrl,
                size: 44,
                radius: isArtist ? 22 : 8,
                artist: isArtist ? entry.title : artistName,
                title: isArtist ? null : entry.title,
              ),
              if (isCurrent)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(isArtist ? 22 : 8),
                  ),
                  child: Icon(
                    isPlaying ? AppIcons.pause : AppIcons.play,
                    color: AppColors.accentGreen,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: () {
                FocusScope.of(context).unfocus();
                _searchFocusNode.unfocus();
                if (isArtist) {
                  _navigateToArtist(
                    context,
                    Song(
                      id: entry.id,
                      videoId: '',
                      title: entry.title,
                      artist: 'Артист',
                      coverUrl: entry.coverUrl,
                      type: 'artist',
                    ),
                  );
                } else if (isAlbumOrPlaylist) {
                  _navigateToAlbum(
                    context,
                    Song(
                      id: entry.id,
                      videoId: entry.id,
                      title: entry.title,
                      artist: artistName,
                      coverUrl: entry.coverUrl,
                      type: entry.type,
                    ),
                  );
                } else {
                  final player = Provider.of<PlayerProvider>(context, listen: false);
                  if (isCurrent) {
                    player.togglePlayPause();
                  } else {
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
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          style: isCurrent
                              ? AppText.trackTitleActive.copyWith(color: AppColors.accentGreen)
                              : AppText.trackTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 6),
                        Icon(
                          AppIcons.music,
                          color: AppColors.accentGreen,
                          size: 14,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.subtitle,
                    style: isCurrent
                        ? AppText.trackArtist.copyWith(color: AppColors.accentGreen.withValues(alpha: 0.8))
                        : AppText.trackArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
}

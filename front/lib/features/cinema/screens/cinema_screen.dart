import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/screens/settings_screen.dart';
import 'package:ses/features/cinema/models/movie_item.dart';
import 'package:ses/features/cinema/services/kinogo_service.dart';
import 'package:ses/features/cinema/screens/movie_detail_screen.dart';
import 'package:ses/features/cinema/screens/downloaded_cinema_screen.dart';
import 'package:ses/core/widgets/scale_button.dart';

class CinemaScreen extends StatefulWidget {
  const CinemaScreen({super.key});

  @override
  State<CinemaScreen> createState() => _CinemaScreenState();
}

class _CinemaScreenState extends State<CinemaScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final PageController _carouselController = PageController();
  bool _isSearchMode = false;
  final ValueNotifier<int> _carouselIndexNotifier = ValueNotifier<int>(0);

  // Бесконечный список фильмов
  List<MovieItem> _movies = [];
  List<MovieItem> _latestMovies = []; // Для карусели трендов
  int _currentPage = 1;
  bool _isLoadingMovies = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _latestError;

  // Показ всех категорий вперемешку
  String _selectedTabType = "Все";

  // Экран поиска
  List<MovieItem> _searchResults = [];
  bool _isLoadingSearch = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _loadTrendingForTab(_selectedTabType);
    _resetAndLoadMovies();

    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus && !_isSearchMode) {
        setState(() => _isSearchMode = true);
      }
    });

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
        _loadNextPage();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _carouselController.dispose();
    _carouselIndexNotifier.dispose();
    super.dispose();
  }

  String _determineFetchPath() {
    return "/";
  }

  bool _applyFilters(MovieItem item) {
    return true;
  }

  Future<void> _loadTrendingForTab(String tab) async {
    try {
      final movies = await KinogoService.fetchMoviesByCategory('/');
      if (mounted) {
        setState(() {
          _latestMovies = movies;
        });
      }
    } catch (e) {
      print("Error loading trends: $e");
    }
  }

  Future<void> _resetAndLoadMovies() async {
    if (!mounted) return;
    setState(() {
      _currentPage = 1;
      _movies = [];
      _hasMore = true;
      _isLoadingMovies = true;
      _latestError = null;
    });

    try {
      final fetchPath = _determineFetchPath();
      List<MovieItem> accumulated = [];
      int pageToFetch = 1;
      bool remoteHasMore = true;

      // Запрашиваем страницы, пока не наберем хотя бы 6 отфильтрованных результатов (или не превысим лимит 4 страниц)
      while (accumulated.length < 6 && remoteHasMore && pageToFetch <= 4) {
        final fetched = await KinogoService.fetchMoviesWithFilter(
          path: fetchPath,
          page: pageToFetch,
        );
        if (fetched.isEmpty) {
          remoteHasMore = false;
          break;
        }
        
        final filtered = fetched.where(_applyFilters).toList();
        accumulated.addAll(filtered);
        
        pageToFetch++;
        if (fetched.length < 5) {
          remoteHasMore = false;
        }
      }

      if (mounted) {
        setState(() {
          _movies = accumulated;
          _currentPage = pageToFetch - 1;
          _isLoadingMovies = false;
          _hasMore = remoteHasMore;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _latestError = "Не удалось загрузить фильмы. Проверьте интернет-подключение.";
          _isLoadingMovies = false;
        });
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore || _isLoadingMovies) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final fetchPath = _determineFetchPath();
      int nextPage = _currentPage + 1;
      List<MovieItem> accumulated = [];
      bool remoteHasMore = true;
      int pagesFetchedCount = 0;

      while (accumulated.length < 3 && remoteHasMore && pagesFetchedCount < 3) {
        final results = await KinogoService.fetchMoviesWithFilter(
          path: fetchPath,
          page: nextPage,
        );
        pagesFetchedCount++;
        
        if (results.isEmpty) {
          remoteHasMore = false;
          break;
        }

        final filtered = results.where(_applyFilters).toList();
        accumulated.addAll(filtered);
        
        nextPage++;
        if (results.length < 5) {
          remoteHasMore = false;
        }
      }

      if (mounted) {
        setState(() {
          _currentPage = nextPage - 1;
          _movies.addAll(accumulated);
          _isLoadingMore = false;
          _hasMore = remoteHasMore;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Timer? _searchDebounce;

  // Выполнение поиска фильмов
  Future<void> _performSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoadingSearch = false;
      });
      return;
    }

    setState(() {
      _isLoadingSearch = true;
      _searchError = null;
      _isSearchMode = true;
      _searchResults = [];
    });

    try {
      final results = await KinogoService.searchMovies(cleanQuery);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoadingSearch = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = "Не удалось выполнить поиск. Проверьте сеть.";
          _isLoadingSearch = false;
        });
      }
    }
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    final cleanVal = val.trim();
    if (cleanVal.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoadingSearch = false;
      });
      return;
    }

    setState(() {
      _isLoadingSearch = true;
      _isSearchMode = true;
      _searchResults = [];
    });

    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted && _searchController.text.trim() == cleanVal) {
        _performSearch(cleanVal);
      }
    });
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 6;
    if (width > 800) return 5;
    if (width > 550) return 4;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── HEADER (Поиск + Настройки + Скачанные) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: AppSearchBar(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      hint: "Поиск фильмов и сериалов",
                      onChanged: (val) => _onSearchChanged(val),
                      onSubmitted: (query) => _performSearch(query),
                      onClear: () {
                        setState(() {
                          _searchResults = [];
                          _isLoadingSearch = false;
                          _searchError = null;
                        });
                      },
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          axis: Axis.horizontal,
                          axisAlignment: -1.0,
                          sizeFactor: animation,
                          child: child,
                        ),
                      );
                    },
                    child: (_isSearchMode || _searchFocusNode.hasFocus)
                        ? Row(
                            key: const ValueKey('search_active_cancel'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  _searchFocusNode.unfocus();
                                  FocusScope.of(context).unfocus();
                                  setState(() {
                                    _isSearchMode = false;
                                    _searchResults = [];
                                    _isLoadingSearch = false;
                                    _searchError = null;
                                  });
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                          )
                        : Row(
                            key: const ValueKey('search_idle_buttons'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 12),
                              ScaleButton(
                                onTap: () {
                                  Provider.of<PlayerProvider>(context, listen: false).setShowMiniPlayer(false);
                                  Navigator.push(
                                    context,
                                    AppPageRoute.create(context, const DownloadedCinemaScreen()),
                                  ).then((_) {
                                    if (context.mounted) {
                                      Provider.of<PlayerProvider>(context, listen: false).setShowMiniPlayer(true);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.03)),
                                  ),
                                  child: Icon(
                                    Iconsax.document_download,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ScaleButton(
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
                  ),
                ],
              ),
            ),

            // ── CONTENT ──
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _isSearchMode ? _buildSearchContent() : _buildMainContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _currentFilterTitle {
    return "Новинки и тренды";
  }

  Widget _buildMainContent() {
    if (_isLoadingMovies && _movies.isEmpty) {
      return KeyedSubtree(
        key: ValueKey('main_content_$_selectedTabType'),
        child: _buildSkeletonGrid(),
      );
    }

    if (_latestError != null && _movies.isEmpty) {
      return KeyedSubtree(
        key: ValueKey('main_content_$_selectedTabType'),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: Colors.white24),
                const SizedBox(height: 16),
                Text(
                  _latestError!,
                  style: AppText.trackArtist,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _resetAndLoadMovies(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text("Повторить", style: AppText.trackTitle.copyWith(fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_movies.isEmpty) {
      return KeyedSubtree(
        key: ValueKey('main_content_$_selectedTabType'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_creation_outlined, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              "Ничего не найдено",
              style: AppText.trackArtist,
            ),
          ],
        ),
      );
    }

    return KeyedSubtree(
      key: ValueKey('main_content_$_selectedTabType'),
      child: RefreshIndicator(
      onRefresh: () => _resetAndLoadMovies(),
      color: AppColors.accentGreen,
      backgroundColor: AppColors.surface,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. Карусель Трендов (показываем всегда)
          if (_latestMovies.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildFeaturedCarousel(),
                  const SizedBox(height: 16),
                ],
              ),
            ),

          // 2. Секция заголовка
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _currentFilterTitle,
                      style: AppText.sectionTitle.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Бесконечная сетка фильмов
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _getCrossAxisCount(context),
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.58,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _buildGridMovieCard(_movies[index]);
                },
                childCount: _movies.length,
              ),
            ),
          ),

          // 4. Загрузка снизу при пагинации
          if (_isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                  ),
                ),
              ),
            ),

          // Запасной отступ снизу
          const SliverToBoxAdapter(
            child: SizedBox(height: 80),
          ),
        ],
      ),
    ),
  );
}



  // Компонент: Карусель популярных фильмов
  Widget _buildFeaturedCarousel() {
    if (_latestMovies.isEmpty) return const SizedBox.shrink();
    final featuredList = _latestMovies.take(5).toList();

    return Column(
      children: [
        SizedBox(
          height: 230,
          child: PageView.builder(
            controller: _carouselController,
            onPageChanged: (index) {
              _carouselIndexNotifier.value = index;
            },
            itemCount: featuredList.length,
            itemBuilder: (context, index) {
              final item = featuredList[index];
              return ScaleButton(
                scaleFactor: 0.98,
                onTap: () => _showMovieDetail(item),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        // Постер во весь баннер
                        Positioned.fill(
                          child: CachedNetworkImage(
                            imageUrl: item.bannerUrl,
                            httpHeaders: KinogoService.imageHeaders,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: AppColors.surface,
                              child: const Center(
                                child: Icon(Icons.movie_creation_outlined, color: Colors.white10, size: 40),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppColors.surface,
                              child: const Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 40),
                            ),
                          ),
                        ),
                        // Градиентное затемнение снизу и сверху
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withOpacity(0.95),
                                  Colors.black.withOpacity(0.3),
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.3),
                                ],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                stops: const [0.0, 0.4, 0.7, 1.0],
                              ),
                            ),
                          ),
                        ),
                        // Инфо-блок на баннере
                        Positioned(
                          left: 20,
                          bottom: 20,
                          right: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.accentGreen.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  "В ТРЕНДЕ",
                                  style: AppText.caption.copyWith(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.title,
                                style: AppText.sectionTitle.copyWith(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.rating,
                                    style: AppText.caption.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      "${item.year} • ${item.genre}",
                                      style: AppText.caption.copyWith(color: Colors.white60),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
        // Индикаторы страниц (точки)
        ValueListenableBuilder<int>(
          valueListenable: _carouselIndexNotifier,
          builder: (context, currentIndex, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(featuredList.length, (index) {
                final isCurrent = currentIndex == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 6,
                  width: isCurrent ? 18 : 6,
                  decoration: BoxDecoration(
                    color: isCurrent ? AppColors.accentGreen : Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }



  Widget _buildGridMovieCard(MovieItem item) {
    return RepaintBoundary(
      child: ScaleButton(
        scaleFactor: 0.96,
        onTap: () => _showMovieDetail(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.04)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: CachedNetworkImage(
                          imageUrl: item.coverUrl,
                          httpHeaders: KinogoService.imageHeaders,
                          fit: BoxFit.cover,
                          memCacheWidth: 300,
                          memCacheHeight: 450,
                          placeholder: (context, url) => Container(
                            color: AppColors.surface,
                            child: const Center(
                              child: Icon(Icons.movie_creation_outlined, color: Colors.white10, size: 30),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: AppColors.surface,
                            child: const Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 40),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Rating badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          color: Colors.black.withOpacity(0.55),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 10),
                              const SizedBox(width: 2),
                              Text(
                                item.rating,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: AppText.trackTitle.copyWith(fontSize: 13, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              "${item.year} • ${item.genre.split(',').first.trim()}",
              style: AppText.caption.copyWith(fontSize: 11, color: Colors.white38),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }







  Widget _buildSearchResultsList() {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ScaleButton(
            scaleFactor: 0.98,
            onTap: () => _showMovieDetail(item),
            child: Container(
              height: 110,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              child: Row(
                children: [
                  // Постер фильма
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 70,
                      height: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: item.coverUrl,
                        httpHeaders: KinogoService.imageHeaders,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        memCacheHeight: 300,
                        placeholder: (context, url) => Container(
                          color: Colors.white.withOpacity(0.05),
                          child: const Center(
                            child: Icon(Icons.movie_creation_outlined, color: Colors.white10, size: 24),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.white.withOpacity(0.05),
                          child: const Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Информация о фильме
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title,
                          style: AppText.trackTitle.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accentGreen.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.type,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accentGreen,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                            const SizedBox(width: 2),
                            Text(
                              item.rating,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              item.year,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.description,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 12,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchContentWrapper() {
    return _buildSearchResultsList();
  }

  Widget _buildSearchContent() {
    final query = _searchController.text.trim();
    Widget child;

    if (query.isEmpty) {
      child = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Iconsax.search_status, size: 54, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              "Введите название фильма, сериала или мультфильма",
              style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    } else if (_isLoadingSearch) {
      child = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
            ),
            const SizedBox(height: 16),
            Text(
              "Ищем «$query»...",
              style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    } else if (_searchError != null) {
      child = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _searchError!,
            style: const TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (_searchResults.isEmpty) {
      child = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Iconsax.video_remove, size: 56, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              "Ничего не найдено по запросу «$query»",
              style: const TextStyle(
                fontFamily: 'Inter',
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Проверьте опечатки или введите другое название",
              style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.white30,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    } else {
      child = _buildSearchResultsList();
    }

    return KeyedSubtree(
      key: const ValueKey('search_content'),
      child: child,
    );
  }

  void _showMovieDetail(MovieItem item) {
    Navigator.push(
      context,
      AppPageRoute.create(
        context,
        MovieDetailScreen(movie: item),
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _getCrossAxisCount(context),
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.58,
      ),
      itemCount: 9,
      itemBuilder: (context, index) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: SkeletonBox(
                width: double.infinity,
                height: double.infinity,
                borderRadius: 18,
              ),
            ),
            const SizedBox(height: 8),
            const SkeletonBox(width: 80, height: 12, borderRadius: 4),
            const SizedBox(height: 4),
            const SkeletonBox(width: 50, height: 10, borderRadius: 4),
          ],
        );
      },
    );
  }
}

class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.04, end: 0.14).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_animation.value),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

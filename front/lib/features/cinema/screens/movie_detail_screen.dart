import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/cinema/screens/custom_video_player_screen.dart';
import 'package:ses/features/cinema/screens/translation_selection_screen.dart';
import 'package:ses/features/cinema/models/movie_item.dart';
import 'package:ses/features/cinema/services/kinogo_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/core/widgets/scale_button.dart';

class MovieDetailScreen extends StatefulWidget {
  final MovieItem movie;

  const MovieDetailScreen({super.key, required this.movie});

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> with SingleTickerProviderStateMixin {
  String? _playerUrl;
  bool _isLoadingPlayer = true;
  String? _playerError;

  // Раскрытие описания
  bool _isDescriptionExpanded = false;

  // Лайк/В закладках
  bool _isFavorite = false;

  // Динамические рекомендации
  List<MovieItem> _recommendations = [];
  bool _isLoadingRecommendations = true;

  // Жанр и описание, подгружаемые со страницы деталей
  late String _genre;
  late String _description;
  String? _country;
  List<Map<String, String>> _actors = [];

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    // Инициализируем из данных карточки (могут быть заглушками)
    _genre = widget.movie.genre;
    _description = widget.movie.description;
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Defer loading until page transition is complete to ensure 60/120 FPS iOS transitions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.animation != null && !route.animation!.isCompleted) {
        void listener(AnimationStatus status) {
          if (status == AnimationStatus.completed) {
            route.animation!.removeStatusListener(listener);
            if (mounted) {
              _resolvePlayerUrlAndDetails();
              _loadRecommendations();
            }
          }
        }
        route.animation!.addStatusListener(listener);
      } else {
        _resolvePlayerUrlAndDetails();
        _loadRecommendations();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // Получение плеера, жанра и описания за один запрос
  Future<void> _resolvePlayerUrlAndDetails() async {
    try {
      final result = await KinogoService.getMovieDetailsAndPlayerUrl(widget.movie.id);
      if (mounted) {
        setState(() {
          // Обновляем жанр и описание, если получены
          if (result.genre.isNotEmpty) {
            _genre = result.genre;
          }
          if (result.description.isNotEmpty) {
            _description = result.description;
          }
          if (result.country.isNotEmpty) {
            _country = result.country;
          }
          _actors = result.actors;

          if (result.playerUrl != null && result.playerUrl!.isNotEmpty) {
            _playerUrl = result.playerUrl;
            _isLoadingPlayer = false;
          } else {
            _playerError = "Источник видео не найден.";
            _isLoadingPlayer = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _playerError = "Не удалось загрузить плеер.";
          _isLoadingPlayer = false;
        });
      }
    }
  }

  // Загрузка рекомендаций (другие последние фильмы)
  Future<void> _loadRecommendations() async {
    try {
      final list = await KinogoService.fetchLatestMovies();
      if (mounted) {
        setState(() {
          // Исключаем текущий фильм из списка рекомендаций
          _recommendations = list.where((m) => m.id != widget.movie.id).toList();
          _isLoadingRecommendations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRecommendations = false;
        });
      }
    }
  }



  bool _isMobilePlatform() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android || 
           defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> _launchInBrowser() async {
    final targetUrl = _playerUrl ?? widget.movie.id;
    final uri = Uri.parse(targetUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        AppTheme.showSnackBar(context, "Не удалось открыть ссылку.");
      }
    }
  }

  int _parseSeasons(MovieItem movie) {
    final title = movie.title.toLowerCase();
    final rangeRegex = RegExp(r'1-(\d+)\s+сезон');
    final rangeMatch = rangeRegex.firstMatch(title);
    if (rangeMatch != null) {
      return int.tryParse(rangeMatch.group(1) ?? '') ?? 1;
    }
    
    final singleRegex = RegExp(r'(\d+)\s+сезон');
    final singleMatch = singleRegex.firstMatch(title);
    if (singleMatch != null) {
      return int.tryParse(singleMatch.group(1) ?? '') ?? 1;
    }

    final isSeries = movie.type.toLowerCase().contains('сериал') || 
                     movie.genre.toLowerCase().contains('сериал') ||
                     movie.genre.toLowerCase().contains('дорам') ||
                     movie.genre.toLowerCase().contains('аниме');

    if (isSeries) {
      return 1;
    }
    return 0;
  }

  int _parseEpisodes(MovieItem movie) {
    final title = movie.title.toLowerCase();
    final epRegex = RegExp(r'(\d+)\s+серия');
    final epMatch = epRegex.firstMatch(title);
    if (epMatch != null) {
      return int.tryParse(epMatch.group(1) ?? '') ?? 12;
    }

    final isSeries = movie.type.toLowerCase().contains('сериал') || 
                     movie.genre.toLowerCase().contains('сериал') ||
                     movie.genre.toLowerCase().contains('дорам') ||
                     movie.genre.toLowerCase().contains('аниме');
    if (isSeries) {
      return 12;
    }
    return 0;
  }

  Future<void> _launchUrlInBrowser(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        AppTheme.showSnackBar(context, "Не удалось открыть ссылку.");
      }
    }
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Шапка с кнопками назад и поделиться
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildGlassRoundButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => Navigator.pop(context),
                        ),
                        _buildGlassRoundButton(
                          icon: _isFavorite ? Iconsax.heart_copy : Iconsax.heart,
                          iconColor: _isFavorite ? AppColors.accentRed : Colors.white,
                          onTap: () {
                            setState(() => _isFavorite = !_isFavorite);
                            AppTheme.showSnackBar(
                              context, 
                              _isFavorite ? "Добавлено в избранное" : "Удалено из избранного"
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. ЦЕНТРАЛЬНЫЙ ПОСТЕР И ЗАГОЛОВОК (В стиле пробника)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      children: [
                        // Центральный постер
                        Center(
                          child: Container(
                            width: 170,
                            height: 250,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.6),
                                  blurRadius: 25,
                                  offset: const Offset(0, 12),
                                )
                              ],
                              image: DecorationImage(
                                image: CachedNetworkImageProvider(
                                  widget.movie.coverUrl,
                                  headers: KinogoService.imageHeaders,
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Кнопка информации и Название
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.white.withOpacity(0.4), size: 20),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                widget.movie.title,
                                style: AppText.sectionTitle.copyWith(
                                  fontSize: 22, 
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Подзаголовок / Жанры и возрастной ценз (заглушка 16+)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.movie.type,
                              style: AppText.caption.copyWith(color: Colors.white54),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 3,
                              height: 3,
                              decoration: const BoxDecoration(color: Colors.white30, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
                              ),
                              child: Text(
                                "16+",
                                style: AppText.caption.copyWith(
                                  color: Colors.white70, 
                                  fontSize: 10, 
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        ScaleButton(
                          onTap: () {
                            if (_playerUrl != null) {
                              final int seasonsCount = _parseSeasons(widget.movie);
                              final int episodesCount = _parseEpisodes(widget.movie);
                              Navigator.of(context, rootNavigator: true).push(
                                AppPageRoute.create(
                                  context,
                                  TranslationSelectionScreen(
                                    movie: widget.movie,
                                    playerUrl: _playerUrl!,
                                    seasonsCount: seasonsCount,
                                    episodesCount: episodesCount,
                                  ),
                                ),
                              );
                            } else {
                              AppTheme.showSnackBar(context, "Загрузка видео-источника...");
                            }
                          },
                          child: Container(
                            height: 56,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.12),
                                  blurRadius: 15,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 28),
                                const SizedBox(width: 8),
                                Text(
                                  "Воспроизвести",
                                  style: AppText.trackTitle.copyWith(
                                    color: Colors.black, 
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Источник: Lordfilm | Качество: HD",
                          style: AppText.caption.copyWith(color: Colors.white30, fontSize: 11),
                        ),
                        Consumer<UserProvider>(
                          builder: (context, userProvider, child) {
                            return const SizedBox.shrink(); // Скачивание фильмов временно отключено
                          },
                        ),
                      ],
                    ),
                  ),
                ),



                // 7. МЕТАДАННЫЕ (Япония, Серии, Статус и тд в виде плиток)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Column(
                      children: [
                        _buildMetaItem(Iconsax.global, "Страна", _country ?? widget.movie.country),
                        _buildMetaItem(Iconsax.calendar, "Год выпуска", "${widget.movie.year} г."),
                        _buildMetaItem(Iconsax.video_play, "Тип релиза", widget.movie.type),
                        _buildMetaItem(Iconsax.star, "Жанр", _genre),
                      ],
                    ),
                  ),
                ),

                // 8. АКТЕРЫ (Фотографии и имена)
                if (_actors.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Актёры",
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    AppPageRoute.create(
                                      context,
                                      ActorsListScreen(
                                        movieTitle: widget.movie.title,
                                        actors: _actors,
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                  "Все",
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 125,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: _actors.length,
                              itemBuilder: (context, index) {
                                 final actor = _actors[index];
                                 final name = actor['name'] ?? '';
                                 final imageUrl = actor['imageUrl'] ?? '';
                                
                                return Container(
                                  width: 80,
                                  margin: const EdgeInsets.only(right: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // Фото актера (квадратное закругленное)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          width: 64,
                                          height: 64,
                                          color: Colors.white.withOpacity(0.05),
                                          child: imageUrl.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: imageUrl,
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) => const Center(
                                                    child: SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 1.5,
                                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white30),
                                                      ),
                                                    ),
                                                  ),
                                                  errorWidget: (context, url, error) => _buildActorPlaceholder(name),
                                                )
                                              : _buildActorPlaceholder(name),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      // Имя актера
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white70,
                                        ),
                                        maxLines: 2,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 9. ОПИСАНИЕ С РАСКРЫТИЕМ (Подробнее...)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _description,
                          maxLines: _isDescriptionExpanded ? null : 3,
                          overflow: _isDescriptionExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                          style: AppText.trackArtist.copyWith(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.75),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ScaleButton(
                          scaleFactor: 0.97,
                          onTap: () {
                            setState(() {
                              _isDescriptionExpanded = !_isDescriptionExpanded;
                            });
                          },
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                _isDescriptionExpanded ? "Свернуть" : "Подробнее...",
                                style: AppText.trackTitle.copyWith(
                                  color: AppColors.accentGreen, 
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 10. РЕЙТИНГ (Большой балл + Гистограмма в стиле скриншота)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Рейтинг",
                          style: AppText.sectionTitle.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Большой балл
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.movie.rating,
                                  style: AppText.screenTitle.copyWith(fontSize: 48, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "оценка Lordfilm",
                                  style: AppText.caption.copyWith(color: Colors.white30, fontSize: 11),
                                ),
                              ],
                            ),
                            const SizedBox(width: 32),
                            // Гистограмма распределения звезд
                            Expanded(
                              child: Column(
                                children: [
                                  _buildRatingBar(5, 0.85),
                                  _buildRatingBar(4, 0.12),
                                  _buildRatingBar(3, 0.05),
                                  _buildRatingBar(2, 0.02),
                                  _buildRatingBar(1, 0.08),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 11. РЕКОМЕНДУЕМ ТАКЖЕ (В стиле скриншота)
                if (!_isLoadingRecommendations && _recommendations.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Похожие ${widget.movie.type == 'Фильм' ? 'фильмы' : widget.movie.type == 'Сериал' ? 'сериалы' : 'релизы'}",
                                style: AppText.sectionTitle.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Возможно, вы захотите посмотреть эти картины",
                                style: AppText.caption.copyWith(color: Colors.white30, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _recommendations.length,
                            itemBuilder: (context, index) {
                              final item = _recommendations[index];
                              return ScaleButton(
                                scaleFactor: 0.96,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    AppPageRoute.create(context, MovieDetailScreen(movie: item)),
                                  );
                                },
                                child: Container(
                                  width: 110,
                                  margin: const EdgeInsets.only(right: 14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(16),
                                            image: DecorationImage(
                                              image: NetworkImage(item.coverUrl),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        item.title,
                                        style: AppText.trackTitle.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
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

                // Отступ снизу
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          ),
        );
      }

  // Элемент метаданных
  Widget _buildMetaItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white30, size: 20),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppText.caption.copyWith(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppText.trackTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Полоса гистограммы рейтинга
  Widget _buildRatingBar(int index, double ratio) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text("$index", style: AppText.caption.copyWith(color: Colors.white30, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen,
                      borderRadius: BorderRadius.circular(3),
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

  // Кнопка из стекла
  Widget _buildGlassRoundButton({
    required IconData icon, 
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return ScaleButton(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        ),
        child: Icon(icon, color: iconColor ?? Colors.white, size: 18),
      ),
    );
  }



  Widget _buildActorPlaceholder(String name) {
    final cleanName = name.trim();
    String initials = "";
    if (cleanName.isNotEmpty) {
      final parts = cleanName.split(' ');
      if (parts.length >= 2) {
        initials = parts[0].substring(0, 1).toUpperCase() + parts[1].substring(0, 1).toUpperCase();
      } else if (parts.isNotEmpty) {
        initials = parts[0].substring(0, 1).toUpperCase();
      }
    }
    return Center(
      child: Text(
        initials.isNotEmpty ? initials : "?",
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white38,
          fontFamily: 'Inter',
        ),
      ),
    );
  }

}

class ActorsListScreen extends StatelessWidget {
  final String movieTitle;
  final List<Map<String, String>> actors;

  const ActorsListScreen({
    Key? key,
    required this.movieTitle,
    required this.actors,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Шапка экрана
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                children: [
                  ScaleButton(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Актёрский состав",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          movieTitle,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Сетка актеров
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 20,
                  childAspectRatio: 0.72,
                ),
                itemCount: actors.length,
                itemBuilder: (context, index) {
                  final actor = actors[index];
                  final name = actor['name'] ?? '';
                  final character = actor['character'] ?? '';
                  final imageUrl = actor['imageUrl'] ?? '';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Фото актера (квадратное закругленное)
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              color: Colors.white.withOpacity(0.05),
                              child: imageUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => const Center(
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white30),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => _buildActorPlaceholder(name),
                                    )
                                  : _buildActorPlaceholder(name),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Имя актера
                      Text(
                        name,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // Роль актера
                      Text(
                        character.isNotEmpty ? character : 'Актёр',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.45),
                        ),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActorPlaceholder(String name) {
    final cleanName = name.trim();
    String initials = "";
    if (cleanName.isNotEmpty) {
      final parts = cleanName.split(' ');
      if (parts.length >= 2) {
        initials = parts[0].substring(0, 1).toUpperCase() + parts[1].substring(0, 1).toUpperCase();
      } else if (parts.isNotEmpty) {
        initials = parts[0].substring(0, 1).toUpperCase();
      }
    }
    return Center(
      child: Text(
        initials.isNotEmpty ? initials : "?",
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white38,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/core/widgets/scale_button.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/cinema/screens/custom_video_player_screen.dart';
import 'package:ses/features/cinema/models/movie_item.dart';
import 'package:ses/features/player/providers/player_provider.dart';

class DownloadedCinemaScreen extends StatefulWidget {
  const DownloadedCinemaScreen({super.key});

  @override
  State<DownloadedCinemaScreen> createState() => _DownloadedCinemaScreenState();
}

class _DownloadedCinemaScreenState extends State<DownloadedCinemaScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── HEADER ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 16),
                  Text(
                    "Скачанные медиа",
                    style: AppText.sectionTitle.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // ── SEARCH BAR ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim().toLowerCase();
                  });
                },
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Поиск среди скачанных...",
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
                  prefixIcon: Icon(Iconsax.search_status, color: Colors.white.withOpacity(0.4), size: 18),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.accentGreen.withOpacity(0.5)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── DOWNLOADED ITEMS LIST ──
            Expanded(
              child: Consumer<UserProvider>(
                builder: (context, userProvider, child) {
                  final downloadingList = userProvider.downloadingMovieMetadata.values.where((m) {
                    if (_searchQuery.isEmpty) return true;
                    return m.title.toLowerCase().contains(_searchQuery);
                  }).toList();

                  final downloadedList = userProvider.downloadedMovies.where((m) {
                    if (_searchQuery.isEmpty) return true;
                    return m.title.toLowerCase().contains(_searchQuery);
                  }).toList();

                  if (downloadingList.isEmpty && downloadedList.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Iconsax.document_download,
                              size: 64,
                              color: Colors.white.withOpacity(0.15),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _searchQuery.isEmpty
                                  ? "Нет скачанных фильмов"
                                  : "Ничего не найдено",
                              style: AppText.trackTitle.copyWith(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isEmpty
                                  ? "Вы можете скачивать фильмы и сериалы прямо в видеоплеере во время воспроизведения."
                                  : "Попробуйте изменить поисковый запрос.",
                              style: AppText.trackArtist.copyWith(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 12,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final totalCount = downloadingList.length + downloadedList.length;

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: totalCount,
                    itemBuilder: (context, index) {
                      final isDownloading = index < downloadingList.length;
                      if (isDownloading) {
                        final item = downloadingList[index];
                        final progress = userProvider.getMovieDownloadProgress(item.id);
                        final progressPct = (progress * 100).toInt();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.02)),
                            ),
                            child: Row(
                              children: [
                                // Постер фильма с лоадером
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: CachedNetworkImage(
                                        imageUrl: item.coverUrl,
                                        width: 50,
                                        height: 70,
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) => Container(
                                          color: Colors.white10,
                                          child: const Icon(Icons.movie, color: Colors.white24, size: 24),
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              value: progress > 0 ? progress : null,
                                              color: AppColors.accentGreen,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 14),

                                // Заголовок, тип и прогресс бар
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: AppText.trackTitle.copyWith(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        progress > 0 
                                            ? "Загрузка... $progressPct%" 
                                            : "Подключение...",
                                        style: AppText.trackArtist.copyWith(
                                          fontSize: 11,
                                          color: AppColors.accentGreen,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: LinearProgressIndicator(
                                          value: progress > 0 ? progress : null,
                                          backgroundColor: Colors.white.withOpacity(0.05),
                                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                                          minHeight: 3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Кнопка отмены загрузки
                                ScaleButton(
                                  onTap: () {
                                    userProvider.cancelMovieDownload(item.id);
                                    AppTheme.showSnackBar(context, "Загрузка отменена");
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Colors.white.withOpacity(0.4),
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final item = downloadedList[index - downloadingList.length];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ScaleButton(
                          scaleFactor: 0.98,
                          onTap: () {
                            try {
                              Provider.of<PlayerProvider>(context, listen: false).pause();
                            } catch (e) {}

                            final movieItem = MovieItem(
                              id: item.id,
                              title: item.title,
                              type: item.type,
                              coverUrl: item.coverUrl,
                              bannerUrl: item.coverUrl,
                              genre: item.genre,
                              year: item.year,
                              rating: "10.0",
                              description: "Скачано для оффлайн просмотра.",
                              country: "Локальный файл",
                            );

                            Navigator.push(
                              context,
                              AppPageRoute.create(
                                context,
                                CustomVideoPlayerScreen(
                                  playerUrl: item.localFilePath,
                                  title: item.title,
                                  subtitle: "Оффлайн просмотр",
                                  isSeries: false,
                                  movie: movieItem,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.03)),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedNetworkImage(
                                    imageUrl: item.coverUrl,
                                    width: 50,
                                    height: 70,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) => Container(
                                      color: Colors.white10,
                                      child: const Icon(Icons.movie, color: Colors.white24, size: 24),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: AppText.trackTitle.copyWith(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "${item.type} • ${item.year} г.",
                                        style: AppText.trackArtist.copyWith(
                                          fontSize: 11,
                                          color: Colors.white54,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.genre,
                                        style: AppText.trackArtist.copyWith(
                                          fontSize: 10,
                                          color: Colors.white30,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),

                                ScaleButton(
                                  onTap: () {
                                    _confirmDelete(context, userProvider, item.id, item.title);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Icon(
                                      Iconsax.trash,
                                      color: AppColors.accentRed.withOpacity(0.7),
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, UserProvider provider, String id, String title) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: const BoxDecoration(
            color: Color(0xFF161616),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Удалить загрузку?",
                  style: AppText.sectionTitle.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Вы хотите удалить фильм \"$title\" из памяти устройства?",
                  style: AppText.trackArtist.copyWith(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ScaleButton(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Text(
                            "Отмена",
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ScaleButton(
                        onTap: () async {
                          Navigator.pop(context);
                          await provider.removeMovieDownload(id);
                          if (context.mounted) {
                            AppTheme.showSnackBar(context, "Фильм успешно удален");
                          }
                        },
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accentRed,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Text(
                            "Удалить",
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

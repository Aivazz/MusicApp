import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/core/widgets/scale_button.dart';
import 'package:ses/features/cinema/models/movie_item.dart';
import 'package:ses/features/cinema/screens/custom_video_player_screen.dart';
import 'package:ses/features/cinema/screens/season_selection_screen.dart';
import 'package:ses/features/cinema/screens/episode_selection_screen.dart';
import 'package:ses/features/player/providers/player_provider.dart';

class TranslationSelectionScreen extends StatelessWidget {
  final MovieItem movie;
  final String playerUrl;
  final int seasonsCount;
  final int episodesCount;

  const TranslationSelectionScreen({
    super.key,
    required this.movie,
    required this.playerUrl,
    required this.seasonsCount,
    required this.episodesCount,
  });

  bool _isMobilePlatform() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android || 
           defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> _launchUrlInBrowser(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        AppTheme.showSnackBar(context, "Не удалось открыть ссылку.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSeries = seasonsCount > 0;
    final translations = [
      "Дубляж (Официальный)",
      "HDRezka Studio",
      "LostFilm / RHS",
      "RuDub",
      "Оригинал + Субтитры",
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Minimalist Header with Back Button and simple text title only
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 16),
                  Text(
                    "Выбор озвучки",
                    style: AppText.sectionTitle.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Divider(color: Colors.white10, height: 1, thickness: 1, indent: 20, endIndent: 20),
          const SizedBox(height: 14),

          // Simple list of options
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: translations.length,
              itemBuilder: (context, index) {
                final name = translations[index];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ScaleButton(
                    scaleFactor: 0.98,
                    onTap: () {
                      if (isSeries) {
                        if (seasonsCount > 1) {
                          Navigator.push(
                            context,
                            AppPageRoute.create(
                              context,
                              SeasonSelectionScreen(
                                movie: movie,
                                playerUrl: playerUrl,
                                translation: name,
                                seasonsCount: seasonsCount,
                                episodesCount: episodesCount,
                              ),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            AppPageRoute.create(
                              context,
                              EpisodeSelectionScreen(
                                movie: movie,
                                playerUrl: playerUrl,
                                translation: name,
                                season: 1,
                                seasonsCount: seasonsCount,
                                episodesCount: episodesCount,
                              ),
                            ),
                          );
                        }
                      } else {
                        if (_isMobilePlatform()) {
                          try {
                            Provider.of<PlayerProvider>(context, listen: false).pause();
                          } catch (e) {
                            debugPrint("Error pausing music: $e");
                          }
                          Navigator.push(
                            context,
                            AppPageRoute.create(
                              context,
                              CustomVideoPlayerScreen(
                                playerUrl: playerUrl,
                                title: movie.title,
                                subtitle: name,
                                isSeries: false,
                                initialSeason: 1,
                                initialEpisode: 1,
                                seasonsCount: 1,
                                episodesCount: 1,
                                movie: movie,
                              ),
                            ),
                          );
                        } else {
                          _launchUrlInBrowser(context, playerUrl);
                        }
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.03),
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        name,
                        style: AppText.trackTitle.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

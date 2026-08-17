import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/core/widgets/scale_button.dart';
import 'package:ses/features/cinema/models/movie_item.dart';
import 'package:ses/features/cinema/screens/custom_video_player_screen.dart';
import 'package:ses/features/player/providers/player_provider.dart';

class EpisodeSelectionScreen extends StatelessWidget {
  final MovieItem movie;
  final String playerUrl;
  final String translation;
  final int season;
  final int seasonsCount;
  final int episodesCount;

  const EpisodeSelectionScreen({
    super.key,
    required this.movie,
    required this.playerUrl,
    required this.translation,
    required this.season,
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

  void _playEpisode(BuildContext context, int season, int episode) {
    String finalPlayerUrl = playerUrl;
    try {
      final uri = Uri.parse(finalPlayerUrl);
      final newParams = Map<String, String>.from(uri.queryParameters);
      newParams['season'] = season.toString();
      newParams['episode'] = episode.toString();
      finalPlayerUrl = uri.replace(queryParameters: newParams).toString();
    } catch (e) {
      debugPrint("Error updating player URL query parameters: $e");
    }

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
            playerUrl: finalPlayerUrl,
            title: movie.title,
            subtitle: "$season сезон • $episode серия • $translation",
            isSeries: true,
            initialSeason: season,
            initialEpisode: episode,
            seasonsCount: seasonsCount,
            episodesCount: episodesCount,
            movie: movie,
          ),
        ),
      );
    } else {
      _launchUrlInBrowser(context, finalPlayerUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    "Выбор серии",
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

          // Episodes List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: episodesCount,
              itemBuilder: (context, index) {
                final episodeNum = index + 1;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ScaleButton(
                    scaleFactor: 0.98,
                    onTap: () => _playEpisode(context, season, episodeNum),
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
                        "$episodeNum серия",
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

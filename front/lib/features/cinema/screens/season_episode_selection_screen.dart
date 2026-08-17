import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/core/widgets/scale_button.dart';
import 'package:ses/features/cinema/models/movie_item.dart';
import 'package:ses/features/cinema/screens/custom_video_player_screen.dart';
import 'package:ses/features/player/providers/player_provider.dart';

class SeasonEpisodeSelectionScreen extends StatefulWidget {
  final MovieItem movie;
  final String playerUrl;
  final String translation;
  final int seasonsCount;
  final int episodesCount;

  const SeasonEpisodeSelectionScreen({
    super.key,
    required this.movie,
    required this.playerUrl,
    required this.translation,
    required this.seasonsCount,
    required this.episodesCount,
  });

  @override
  State<SeasonEpisodeSelectionScreen> createState() => _SeasonEpisodeSelectionScreenState();
}

class _SeasonEpisodeSelectionScreenState extends State<SeasonEpisodeSelectionScreen> {
  int _selectedSeason = 1;
  int _selectedEpisode = 1;

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

  void _playEpisode(int season, int episode) {
    String finalPlayerUrl = widget.playerUrl;
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
            title: widget.movie.title,
            subtitle: "${season} сезон • ${episode} серия • ${widget.translation}",
            isSeries: true,
            initialSeason: season,
            initialEpisode: episode,
            seasonsCount: widget.seasonsCount,
            episodesCount: widget.episodesCount,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Minimalist Header matching app style
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "ВЫБОР СЕРИИ • ${widget.translation.toUpperCase()}",
                          style: AppText.trackArtist.copyWith(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          widget.movie.title,
                          style: AppText.trackTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Seasons Row (if seasonsCount > 1)
          if (widget.seasonsCount > 1) ...[
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: widget.seasonsCount,
                itemBuilder: (context, index) {
                  final seasonNum = index + 1;
                  final isSelected = _selectedSeason == seasonNum;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ScaleButton(
                      scaleFactor: 0.95,
                      onTap: () {
                        setState(() {
                          _selectedSeason = seasonNum;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "$seasonNum сезон",
                          style: AppText.caption.copyWith(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Grid of episodes
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: widget.episodesCount,
              itemBuilder: (context, index) {
                final episodeNum = index + 1;
                final isSelected = _selectedEpisode == episodeNum;

                return ScaleButton(
                  scaleFactor: 0.92,
                  onTap: () {
                    setState(() {
                      _selectedEpisode = episodeNum;
                    });
                    _playEpisode(_selectedSeason, episodeNum);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withOpacity(0.12) : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.03),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "$episodeNum",
                      style: AppText.trackTitle.copyWith(
                        fontSize: 16,
                        color: isSelected ? Colors.white : Colors.white.withOpacity(0.85),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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

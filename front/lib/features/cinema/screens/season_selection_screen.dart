import 'package:flutter/material.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/core/widgets/scale_button.dart';
import 'package:ses/features/cinema/models/movie_item.dart';
import 'package:ses/features/cinema/screens/episode_selection_screen.dart';

class SeasonSelectionScreen extends StatelessWidget {
  final MovieItem movie;
  final String playerUrl;
  final String translation;
  final int seasonsCount;
  final int episodesCount;

  const SeasonSelectionScreen({
    super.key,
    required this.movie,
    required this.playerUrl,
    required this.translation,
    required this.seasonsCount,
    required this.episodesCount,
  });

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
                    "Выбор сезона",
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

          // Seasons List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: seasonsCount,
              itemBuilder: (context, index) {
                final seasonNum = index + 1;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ScaleButton(
                    scaleFactor: 0.98,
                    onTap: () {
                      Navigator.push(
                        context,
                        AppPageRoute.create(
                          context,
                          EpisodeSelectionScreen(
                            movie: movie,
                            playerUrl: playerUrl,
                            translation: translation,
                            season: seasonNum,
                            seasonsCount: seasonsCount,
                            episodesCount: episodesCount,
                          ),
                        ),
                      );
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
                        "$seasonNum сезон",
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

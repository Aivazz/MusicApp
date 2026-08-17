import 'package:ses/features/library/models/song.dart';

enum SpotifyImportType { track, album, playlist, text }

class SpotifyImportResult {
  final SpotifyImportType type;
  final String title;
  final String coverUrl;
  final String? subtitle;
  final List<Song> songs;
  final List<Song> notFoundSongs;

  SpotifyImportResult({
    required this.type,
    required this.title,
    required this.coverUrl,
    this.subtitle,
    required this.songs,
    this.notFoundSongs = const [],
  });
}

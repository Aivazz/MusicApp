import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/core/network/firebase_service.dart';

class BackendService {
  static Map<String, int>? _cachedScores;

  // ── Audio Proxy ───────────────────────────────────────────────────
  static String getProxyUrl(String targetUrl) {
    // Без сервера отдаем оригинальный URL напрямую
    return targetUrl;
  }

  // Вспомогательный метод получения файла
  static Future<File> _getLocalFile(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final uid = FirebaseService.currentUser?.uid;
    if (uid != null) {
      final safeUid = uid.replaceAll(RegExp(r'[^\w\-]'), '_');
      final dotIdx = filename.lastIndexOf('.');
      if (dotIdx != -1) {
        filename = '${filename.substring(0, dotIdx)}_$safeUid${filename.substring(dotIdx)}';
      } else {
        filename = '${filename}_$safeUid';
      }
    }
    return File('${dir.path}/$filename');
  }

  static Future<File> getLocalFile(String filename) => _getLocalFile(filename);

  // ── Liked Songs ───────────────────────────────────────────────────
  static Future<List<Song>> getLikedSongs() async {
    try {
      final file = await _getLocalFile('liked_songs.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final list = jsonDecode(jsonStr) as List;
        return list.map((j) => Song.fromJson(j)).toList();
      }
    } catch (e) {
      print("Error loading liked songs locally: $e");
    }
    return [];
  }

  static Future<bool> isLiked(String id) async {
    final list = await getLikedSongs();
    return list.any((s) => s.id == id);
  }

  static Future<void> likeSong(Song s) async {
    try {
      final songs = await getLikedSongs();
      if (!songs.any((item) => item.id == s.id)) {
        songs.add(s);
        final file = await _getLocalFile('liked_songs.json');
        await file.writeAsString(
          jsonEncode(songs.map((item) => item.toJson()).toList()),
        );
      }
    } catch (e) {
      print("Error liking song locally: $e");
    }
  }

  static Future<void> unlikeSong(String id) async {
    try {
      final songs = await getLikedSongs();
      songs.removeWhere((item) => item.id == id);
      final file = await _getLocalFile('liked_songs.json');
      await file.writeAsString(
        jsonEncode(songs.map((item) => item.toJson()).toList()),
      );
    } catch (e) {
      print("Error unliking song locally: $e");
    }
  }

  // ── Search History ────────────────────────────────────────────────
  static Future<List<SearchHistoryEntry>> getSearchHistory() async {
    try {
      final file = await _getLocalFile('search_history.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final list = jsonDecode(jsonStr) as List;
        return list.map((j) => SearchHistoryEntry.fromJson(j)).toList();
      }
    } catch (e) {
      print("Error loading history locally: $e");
    }
    return [];
  }

  static Future<void> saveSearchHistory(List<SearchHistoryEntry> history) async {
    try {
      final file = await _getLocalFile('search_history.json');
      await file.writeAsString(
        jsonEncode(history.map((item) => item.toJson()).toList()),
      );
    } catch (err) {
      print("Error saving search history locally: $err");
    }
  }

  static Future<void> clearSearchHistory() async {
    try {
      final file = await _getLocalFile('search_history.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (err) {
      print("Error clearing search history locally: $err");
    }
  }

  // ── Playlists ─────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getPlaylists() async {
    try {
      final file = await _getLocalFile('playlists.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
      }
    } catch (_) {}
    return [];
  }

  // ── Followed Artists ─────────────────────────────────────────────
  static Future<List<Song>> getFollowedArtists() async {
    try {
      final file = await _getLocalFile('followed_artists.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final list = jsonDecode(jsonStr) as List;
        return list.map((j) => Song.fromJson(j)).toList();
      }
    } catch (e) {
      print("Error loading followed artists locally: $e");
    }
    return [];
  }

  static Future<bool> isFollowing(String id) async {
    final list = await getFollowedArtists();
    return list.any((a) => a.id == id);
  }

  static Future<void> followArtist(
    String id,
    String name,
    String coverUrl,
  ) async {
    try {
      final artists = await getFollowedArtists();
      if (!artists.any((a) => a.id == id)) {
        artists.insert(
          0,
          Song(
            id: id,
            videoId: id,
            title: name,
            artist: name,
            coverUrl: coverUrl,
            type: 'artist',
          ),
        );
        final file = await _getLocalFile('followed_artists.json');
        await file.writeAsString(
          jsonEncode(artists.map((a) => a.toJson()).toList()),
        );
      }
    } catch (err) {
      print("Error following artist locally: $err");
    }
  }

  static Future<void> unfollowArtist(String id) async {
    try {
      final artists = await getFollowedArtists();
      artists.removeWhere((a) => a.id == id);
      final file = await _getLocalFile('followed_artists.json');
      await file.writeAsString(
        jsonEncode(artists.map((a) => a.toJson()).toList()),
      );
    } catch (err) {
      print("Error unfollowing artist locally: $err");
    }
  }

  // ── Recommendations ───────────────────────────────────────────────
  static Future<void> updateArtistScore(String artistName, int score) async {
    try {
      final scores = await _getArtistScores();
      scores[artistName] = (scores[artistName] ?? 0) + score;
      final file = await _getLocalFile('user_preferences.json');
      await file.writeAsString(jsonEncode(scores));
    } catch (err) {
      print("Error updating artist score locally: $err");
    }
  }

  static Future<Map<String, int>> _getArtistScores() async {
    if (_cachedScores != null) return _cachedScores!;
    try {
      final file = await _getLocalFile('user_preferences.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        _cachedScores = Map<String, int>.from(jsonDecode(jsonStr));
        return _cachedScores!;
      }
    } catch (_) {}
    _cachedScores = {};
    return _cachedScores!;
  }

  static Future<List<String>> getTopArtists() async {
    try {
      final scores = await _getArtistScores();
      final sortedKeys = scores.keys.toList()
        ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
      return sortedKeys.take(10).toList();
    } catch (_) {}
    return [];
  }
}

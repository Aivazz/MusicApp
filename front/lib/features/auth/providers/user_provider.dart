import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/library/models/import_result.dart';
import 'package:ses/features/cinema/models/movie_item.dart';
import 'package:ses/features/cinema/models/downloaded_movie.dart';
import 'package:ses/core/network/backend_service.dart';
import 'package:ses/features/import_export/services/spotify_service.dart';
import 'package:ses/features/import_export/services/pirate_service.dart';
import 'package:ses/features/import_export/services/soundcloud_service.dart';
import 'package:ses/core/utils/cover_service.dart';
import 'package:ses/features/search/services/search_service.dart';
import 'package:ses/core/network/firebase_service.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/cinema/services/kinogo_service.dart';

class _HlsTask {
  final int index;
  final String segmentUri;
  final String localFilename;
  _HlsTask(this.index, this.segmentUri, this.localFilename);
}

class _MovieDownloadTask {
  final MovieItem movie;
  final String streamUrl;
  final String cleanId;
  final String displayTitle;
  final int? season;
  final int? episode;
  _MovieDownloadTask(this.movie, this.streamUrl, this.cleanId, this.displayTitle, {this.season, this.episode});
}

class UserProvider extends ChangeNotifier {
  String _getSafeFileName(String id) {
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  }

  Map<String, String> _getDownloadHeaders(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      String referer = 'https://$host/';
      String? origin;

      if (host.contains('sefon')) {
        referer = 'https://sefon.pro/';
      } else if (host.contains('drivemusic')) {
        referer = 'https://drivemusic.club/';
      } else if (host.contains('mp3party')) {
        referer = 'https://mp3party.net/';
      } else if (host.contains('ru-music')) {
        referer = 'https://ru-music.com/';
      } else if (host.contains('agugai')) {
        referer = 'https://agugai.kz/';
      } else if (host.contains('kodik')) {
        referer = 'https://kodik.info/';
        origin = 'https://kodik.info';
      } else if (host.contains('alloha')) {
        referer = 'https://alloha.tv/';
        origin = 'https://alloha.tv';
      } else if (host.contains('collaps')) {
        referer = 'https://collaps.org/';
        origin = 'https://collaps.org';
      } else if (host.contains('videocdn')) {
        referer = 'https://videocdn.tv/';
        origin = 'https://videocdn.tv';
      } else if (host.contains('kinogo')) {
        referer = KinogoService.currentMirror;
        origin = KinogoService.currentMirror;
      }

      final Map<String, String> headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": referer,
        "Accept": "*/*",
        "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
      };

      if (origin != null) {
        headers["Origin"] = origin;
      }

      return headers;
    } catch (_) {
      return {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://google.com/",
        "Accept": "*/*",
      };
    }
  }

  // ── Liked Songs ──
  final Set<String> _likedIds = {};
  List<Song> _likedSongs = [];

  List<Song> get likedSongs => _likedSongs;
  bool isLiked(String id) => _likedIds.contains(id);

  Future<void> loadLikedSongs({bool notify = true}) async {
    try {
      final firestoreSongs = await FirebaseService.getLikedSongs();
      if (firestoreSongs.isNotEmpty) {
        _likedSongs = firestoreSongs;
        _likedIds.clear();
        _likedIds.addAll(_likedSongs.map((s) => s.id));
        if (notify) notifyListeners();
        await _saveLikedSongsLocalOnly();
        return;
      }

      final file = await BackendService.getLocalFile('liked_songs.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final list = jsonDecode(jsonStr) as List;
        _likedSongs = list.map((j) => Song.fromJson(j)).toList();
        _likedIds.clear();
        _likedIds.addAll(_likedSongs.map((s) => s.id));
        if (notify) notifyListeners();

        // Background pre-resolve the top 5 liked songs
        for (var song in _likedSongs.take(5)) {
          if (!song.videoId.startsWith('http')) {
            PirateService.getStreamUrl(song.videoId).then((resolved) {
              if (resolved != null && resolved.isNotEmpty) {
                song.videoId = resolved;
              }
            }).catchError((_) {});
          }
        }
      }
    } catch (e) {
      print("Ошибка загрузки избранных: $e");
    }
  }

  Future<void> _saveLikedSongsLocalOnly() async {
    try {
      final file = await BackendService.getLocalFile('liked_songs.json');
      await file.writeAsString(
        jsonEncode(_likedSongs.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      print("Ошибка сохранения избранных локально: $e");
    }
  }

  Future<void> _saveLikedSongs() async {
    await _saveLikedSongsLocalOnly();
    await FirebaseService.saveLikedSongs(_likedSongs);
  }

  Future<void> toggleLike(Song song) async {
    if (_likedIds.contains(song.id)) {
      _likedIds.remove(song.id);
      _likedSongs.removeWhere((s) => s.id == song.id);
    } else {
      _likedIds.add(song.id);
      _likedSongs.insert(0, song);

      if (!song.videoId.startsWith('http')) {
        PirateService.getStreamUrl(song.videoId).then((resolved) {
          if (resolved != null && resolved.isNotEmpty) {
            song.videoId = resolved;
          }
        }).catchError((_) {});
      }
    }
    notifyListeners();
    await _saveLikedSongs();
    if (_smartCacheEnabled) {
      triggerSmartCache();
    }
  }

  // ── Search History ──
  List<SearchHistoryEntry> _searchHistory = [];
  List<SearchHistoryEntry> get searchHistory => _searchHistory;

  Future<void> loadSearchHistory({bool notify = true}) async {
    final firestoreHistory = await FirebaseService.getSearchHistory();
    if (firestoreHistory.isNotEmpty) {
      _searchHistory = firestoreHistory;
      if (notify) notifyListeners();
      return;
    }
    _searchHistory = await BackendService.getSearchHistory();
    if (notify) notifyListeners();
  }

  Future<void> addToHistory(SearchHistoryEntry entry) async {
    _searchHistory.removeWhere((e) => e.id == entry.id);
    _searchHistory.insert(0, entry);
    notifyListeners();
    BackendService.saveSearchHistory(_searchHistory);
    await FirebaseService.saveSearchHistory(_searchHistory);
  }

  Future<void> removeFromHistory(String id) async {
    _searchHistory.removeWhere((e) => e.id == id);
    notifyListeners();
    BackendService.saveSearchHistory(_searchHistory);
    await FirebaseService.saveSearchHistory(_searchHistory);
  }

  Future<void> clearHistory() async {
    _searchHistory.clear();
    notifyListeners();
    BackendService.clearSearchHistory();
    await FirebaseService.saveSearchHistory(_searchHistory);
  }

  // ── Playlists ──
  List<Map<String, dynamic>> _playlists = [];
  List<Map<String, dynamic>> get playlists => _playlists;

  Future<void> loadPlaylists({bool notify = true}) async {
    try {
      // 1. Быстро загружаем локальный кэш, чтобы интерфейс отрисовался мгновенно
      final file = await BackendService.getLocalFile('playlists.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final list = jsonDecode(jsonStr) as List;
        _playlists = list.map((e) => Map<String, dynamic>.from(e)).toList();
        if (notify) notifyListeners();
      }

      // 2. В фоновом режиме запрашиваем плейлисты из Firebase
      final firestorePlaylists = await FirebaseService.getPlaylists();
      if (firestorePlaylists.isNotEmpty) {
        // Проверяем на наличие реальных изменений перед перерисовкой
        final String currentJson = jsonEncode(_playlists);
        final String newJson = jsonEncode(firestorePlaylists);
        if (currentJson != newJson) {
          _playlists = firestorePlaylists;
          if (notify) notifyListeners();
          await _savePlaylistsLocalOnly();
        }
      }
    } catch (e) {
      print("Ошибка загрузки плейлистов: $e");
    }
  }

  Future<void> _savePlaylistsLocalOnly() async {
    try {
      final file = await BackendService.getLocalFile('playlists.json');
      await file.writeAsString(jsonEncode(_playlists));
    } catch (e) {
      print("Ошибка сохранения плейлистов локально: $e");
    }
  }

  Future<void> _savePlaylists({String? changedPlaylistId}) async {
    await _savePlaylistsLocalOnly();
    if (changedPlaylistId != null) {
      final playlist = _playlists.cast<Map<String, dynamic>?>().firstWhere(
        (p) => p?['id'] == changedPlaylistId,
        orElse: () => null,
      );
      if (playlist != null) {
        await FirebaseService.savePlaylist(
          playlist['id'],
          playlist['name'],
          playlist['coverUrl'] ?? '',
          playlist['songs'] ?? [],
        );
      }
    } else {
      for (var playlist in _playlists) {
        await FirebaseService.savePlaylist(
          playlist['id'],
          playlist['name'],
          playlist['coverUrl'] ?? '',
          playlist['songs'] ?? [],
        );
      }
    }
  }

  bool _isCreating = false;
  bool _isImportingSpotify = false;
  String _importProgressText = '';

  bool get isImportingSpotify => _isImportingSpotify;
  String get importProgressText => _importProgressText;

  Future<void> createPlaylist(String name) async {
    if (_isCreating) return;
    _isCreating = true;
    
    // Защита от дублей: если плейлист с таким именем уже есть, не создаем копию
    if (_playlists.any((p) => p['name'] == name)) {
      _isCreating = false;
      return;
    }

    final newPlaylist = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'coverUrl': '',
      'songs': []
    };
    _playlists.insert(0, newPlaylist);
    await _savePlaylists(changedPlaylistId: newPlaylist['id'] as String);
    notifyListeners();
    _isCreating = false;
  }

  bool isPlaylistSaved(String idOrName) {
    return _playlists.any((p) => p['id'] == idOrName || p['name'] == idOrName);
  }

  Future<void> saveCustomPlaylist(Song metadata, List<Song> songs) async {
    final String name = metadata.title;
    final String coverUrl = metadata.coverUrl;

    final existingIndex = _playlists.indexWhere(
      (p) => p['id'] == metadata.id || p['name'] == name,
    );

    final songJsonList = songs.map((s) => s.toJson()).toList();

    if (existingIndex != -1) {
      _playlists[existingIndex]['songs'] = songJsonList;
      if (coverUrl.isNotEmpty) {
        _playlists[existingIndex]['coverUrl'] = coverUrl;
      }
      await _savePlaylists(changedPlaylistId: _playlists[existingIndex]['id'] as String);
    } else {
      final newPlaylist = {
        'id': metadata.id.isNotEmpty ? metadata.id : DateTime.now().millisecondsSinceEpoch.toString(),
        'name': name,
        'coverUrl': coverUrl,
        'songs': songJsonList,
      };
      _playlists.insert(0, newPlaylist);
      await _savePlaylists(changedPlaylistId: newPlaylist['id'] as String);
    }
    notifyListeners();
  }

  Future<bool> importSpotifyPlaylist(String input) async {
    if (_isImportingSpotify) return false;
    _isImportingSpotify = true;
    _importProgressText = 'Анализ входных данных...';
    notifyListeners();

    try {
      final trimmedInput = input.trim();

      String name = 'Импортированный плейлист';
      String coverUrl = CoverService.defaultMusicCover;
      List<Song> songs = [];

      // 1. Проверяем, является ли ввод ссылкой Spotify
      if (trimmedInput.contains('spotify.com') || trimmedInput.startsWith('spotify:')) {
        _importProgressText = 'Извлечение плейлиста из Spotify...';
        notifyListeners();

        final regExp = RegExp(r'(?:playlist[/:]?)([a-zA-Z0-9]{22})');
        final match = regExp.firstMatch(trimmedInput);
        if (match == null) {
          SpotifyService.lastError = 'Неверный формат ссылки Spotify';
          _isImportingSpotify = false;
          notifyListeners();
          return false;
        }
        final playlistId = match.group(1)!;

        _importProgressText = 'Загрузка из Spotify...';
        notifyListeners();

        final details = await SpotifyService.getPlaylistDetails(playlistId);
        if (details == null) {
          _isImportingSpotify = false;
          notifyListeners();
          return false;
        }

        name = details['name'] as String;
        coverUrl = details['coverUrl'] as String;
        songs = details['songs'] as List<Song>;
      } 
      // 2. Проверяем, является ли ввод ссылкой Яндекс Музыки
      else if (trimmedInput.contains('music.yandex.ru')) {
        _importProgressText = 'Извлечение плейлиста из Яндекс Музыки...';
        notifyListeners();

        final yandexRegExp = RegExp(r'music\.yandex\.ru/users/([^/]+)/playlists/([0-9]+)');
        final yandexMatch = yandexRegExp.firstMatch(trimmedInput);
        if (yandexMatch == null) {
          SpotifyService.lastError = 'Неверный формат ссылки Яндекс Музыки';
          _isImportingSpotify = false;
          notifyListeners();
          return false;
        }
        final owner = yandexMatch.group(1)!;
        final playlistId = yandexMatch.group(2)!;

        _importProgressText = 'Загрузка из Яндекс Музыки...';
        notifyListeners();

        final apiUri = Uri.parse('https://music.yandex.ru/handlers/playlist.jsx?owner=$owner&kinds=$playlistId&light=true');
        final response = await http.get(apiUri, headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "Referer": "https://music.yandex.ru/",
        });

        if (response.statusCode != 200) {
          SpotifyService.lastError = 'Не удалось получить доступ к плейлисту Яндекс Музыки';
          _isImportingSpotify = false;
          notifyListeners();
          return false;
        }

        final data = jsonDecode(response.body);
        final playlistObj = data['playlist'];
        if (playlistObj == null) {
          SpotifyService.lastError = 'Плейлист Яндекс Музыки не найден или приватный';
          _isImportingSpotify = false;
          notifyListeners();
          return false;
        }

        name = playlistObj['title']?.toString() ?? 'Плейлист Яндекс.Музыка';
        
        if (playlistObj['cover'] != null && playlistObj['cover']['uri'] != null) {
          var uri = playlistObj['cover']['uri'].toString();
          uri = uri.replaceAll('%%', '400x400');
          if (!uri.startsWith('http')) {
            coverUrl = 'https://$uri';
          } else {
            coverUrl = uri;
          }
        }

        final List tracksList = playlistObj['tracks'] ?? [];
        for (var t in tracksList) {
          final title = t['title']?.toString() ?? '';
          final List artistsList = t['artists'] ?? [];
          final artist = artistsList.isNotEmpty 
              ? artistsList.map((a) => a['name']?.toString() ?? '').join(', ')
              : 'Unknown';
          
          final durationMs = t['durationMs'] as int? ?? 180000;
          final duration = Duration(milliseconds: durationMs);

          songs.add(Song(
            id: 'ya_${t['id'] ?? DateTime.now().millisecondsSinceEpoch}_${songs.length}',
            videoId: 'pirate:search:$artist - $title',
            title: title,
            artist: artist,
            coverUrl: coverUrl,
            duration: duration,
            type: 'song',
          ));
        }
      } 
      // 3. Иначе парсим ввод как текстовый список треков (VK Music, Apple Music, TXT и т.д.)
      else {
        _importProgressText = 'Парсинг текстового списка...';
        notifyListeners();

        final lines = trimmedInput.split('\n');
        for (var line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          String artist = 'Unknown';
          String title = trimmed;

          if (trimmed.contains(' - ')) {
            final parts = trimmed.split(' - ');
            artist = parts[0].trim();
            title = parts.sublist(1).join(' - ').trim();
          } else if (trimmed.contains(' — ')) {
            final parts = trimmed.split(' — ');
            artist = parts[0].trim();
            title = parts.sublist(1).join(' — ').trim();
          } else if (trimmed.contains('-')) {
            final index = trimmed.indexOf('-');
            artist = trimmed.substring(0, index).trim();
            title = trimmed.substring(index + 1).trim();
          }

          final id = 'txt_${DateTime.now().millisecondsSinceEpoch}_${songs.length}';
          songs.add(Song(
            id: id,
            videoId: 'pirate:search:$artist - $title',
            title: title,
            artist: artist,
            coverUrl: CoverService.defaultMusicCover,
            duration: const Duration(minutes: 3, seconds: 30),
            type: 'song',
          ));
        }
        
        name = 'Текстовый импорт';
      }

      if (songs.isEmpty) {
        SpotifyService.lastError = 'Не удалось найти песни для импорта';
        _isImportingSpotify = false;
        notifyListeners();
        return false;
      }

      _importProgressText = 'Создание плейлиста (${songs.length} треков)...';
      notifyListeners();

      final List<Map<String, dynamic>> songJsonList = songs.map((song) {
        final safeId = song.id.startsWith('sp_') || song.id.startsWith('ya_') || song.id.startsWith('txt_')
            ? song.id
            : 'sp_${song.id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';
        return Song(
          id: safeId,
          videoId: song.videoId,
          title: song.title,
          artist: song.artist,
          coverUrl: song.coverUrl,
          duration: song.duration,
          type: 'song',
        ).toJson();
      }).toList();

      String finalName = name;
      int index = 1;
      while (_playlists.any((p) => p['name'] == finalName)) {
        finalName = "$name ($index)";
        index++;
      }

      final newPlaylist = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': finalName,
        'coverUrl': coverUrl,
        'songs': songJsonList,
      };

      _playlists.insert(0, newPlaylist);
      await _savePlaylists(changedPlaylistId: newPlaylist['id'] as String);

      if (_smartCacheEnabled) {
        triggerSmartCache();
      }

      _isImportingSpotify = false;
      _importProgressText = '';
      notifyListeners();
      return true;
    } catch (e) {
      print("Ошибка импорта плейлиста: $e");
      SpotifyService.lastError = 'Произошла ошибка при загрузке: $e';
      _isImportingSpotify = false;
      _importProgressText = '';
      notifyListeners();
      return false;
    }
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((p) => p['id'] == id);
    await _savePlaylistsLocalOnly();
    await FirebaseService.deletePlaylist(id);

    // Также удаляем из недавних подборок
    _recentPlaylists.removeWhere((e) => e.playlistMetadata.id == id);
    await _saveRecentPlaylists();

    notifyListeners();
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final idx = _playlists.indexWhere((p) => p['id'] == id);
    if (idx != -1) {
      _playlists[idx]['name'] = newName;
      await _savePlaylists(changedPlaylistId: id);

      // Также обновляем имя в недавних подборках
      final recIdx = _recentPlaylists.indexWhere((e) => e.playlistMetadata.id == id);
      if (recIdx != -1) {
        final entry = _recentPlaylists[recIdx];
        final updatedSong = Song(
          id: entry.playlistMetadata.id,
          videoId: entry.playlistMetadata.videoId,
          title: newName,
          artist: entry.playlistMetadata.artist,
          coverUrl: entry.playlistMetadata.coverUrl,
          duration: entry.playlistMetadata.duration,
          type: entry.playlistMetadata.type,
        );
        _recentPlaylists[recIdx] = RecentPlaylistEntry(
          playlistMetadata: updatedSong,
          playlistType: entry.playlistType,
          viewedAt: entry.viewedAt,
        );
        await _saveRecentPlaylists();
      }

      notifyListeners();
    }
  }

  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    final idx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (idx != -1) {
      List songs = _playlists[idx]['songs'] ?? [];
      // Не добавляем дубликаты
      if (!songs.any((s) => s['id'] == song.id)) {
        songs.add(song.toJson());
        _playlists[idx]['songs'] = songs;
        // Ставим обложку первой песни, если её нет
        if (_playlists[idx]['coverUrl'] == '') {
          _playlists[idx]['coverUrl'] = song.coverUrl;
        }
        await _savePlaylists(changedPlaylistId: playlistId);
        notifyListeners();
      }
    }
  }

  Future<void> updatePlaylistCover(String playlistId, String sourcePath) async {
    final idx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (idx != -1) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final ext = sourcePath.split('.').last;
        final fileName = 'cover_${playlistId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final localPath = '${dir.path}/$fileName';

        // Копируем файл в постоянное хранилище приложения
        final sourceFile = File(sourcePath);
        await sourceFile.copy(localPath);

        // Обновляем URL (теперь это локальный путь)
        _playlists[idx]['coverUrl'] = localPath;
        await _savePlaylists(changedPlaylistId: playlistId);

        // Также обновляем обложку в недавних подборках
        final recIdx = _recentPlaylists.indexWhere((e) => e.playlistMetadata.id == playlistId);
        if (recIdx != -1) {
          final entry = _recentPlaylists[recIdx];
          final updatedSong = Song(
            id: entry.playlistMetadata.id,
            videoId: entry.playlistMetadata.videoId,
            title: entry.playlistMetadata.title,
            artist: entry.playlistMetadata.artist,
            coverUrl: localPath,
            duration: entry.playlistMetadata.duration,
            type: entry.playlistMetadata.type,
          );
          _recentPlaylists[recIdx] = RecentPlaylistEntry(
            playlistMetadata: updatedSong,
            playlistType: entry.playlistType,
            viewedAt: entry.viewedAt,
          );
          await _saveRecentPlaylists();
        }

        notifyListeners();
      } catch (e) {
        print("Ошибка обновления обложки: $e");
      }
    }
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final idx = _playlists.indexWhere((p) => p['id'] == playlistId);
    if (idx != -1) {
      List songs = _playlists[idx]['songs'] ?? [];
      songs.removeWhere((s) => s['id'] == songId);
      _playlists[idx]['songs'] = songs;
      // Если песен нет, убираем обложку
      if (songs.isEmpty) {
        _playlists[idx]['coverUrl'] = '';
      }
      await _savePlaylists(changedPlaylistId: playlistId);
      notifyListeners();
    }
  }

  // ── Followed Artists ──
  final Set<String> _followingIds = {};
  List<Song> _followedArtists = [];

  List<Song> get followedArtists => _followedArtists;
  bool isFollowing(String id) => _followingIds.contains(id);

  Future<void> loadFollowedArtists({bool notify = true}) async {
    final firestoreArtists = await FirebaseService.getFollowedArtists();
    if (firestoreArtists.isNotEmpty) {
      _followedArtists = firestoreArtists;
      _followingIds.clear();
      _followingIds.addAll(_followedArtists.map((a) => a.id));
      if (notify) notifyListeners();
      return;
    }
    _followedArtists = await BackendService.getFollowedArtists();
    _followingIds.clear();
    _followingIds.addAll(_followedArtists.map((a) => a.id));
    if (notify) notifyListeners();
  }

  // checkFollowing was removed: it contained inverted no-op logic
  // and was never called anywhere in the codebase.

  Future<void> toggleFollow(String id, String name, String coverUrl) async {
    if (_followingIds.contains(id)) {
      _followingIds.remove(id);
      _followedArtists.removeWhere((a) => a.id == id);
      BackendService.unfollowArtist(id);
    } else {
      _followingIds.add(id);
      final artist = Song(
        id: id,
        videoId: id,
        title: name,
        artist: name,
        coverUrl: coverUrl,
        type: 'artist',
      );
      _followedArtists.insert(0, artist);
      BackendService.followArtist(id, name, coverUrl);
    }
    notifyListeners();
    await FirebaseService.saveFollowedArtists(_followedArtists);
  }

  // ── DOWNLOADS (ОФФЛАЙН ПРОСЛУШИВАНИЕ) 🌟 ──
  List<Song> _downloadedSongs = [];
  List<Song> get downloadedSongs => _downloadedSongs;
  bool isDownloaded(String id) => _downloadedSongs.any((s) => s.id == id);

  final List<String> _downloadingIds = [];
  final Map<String, double> _downloadProgress = {};
  double getDownloadProgress(String id) => _downloadProgress[id] ?? 0.0;

  Future<void> loadDownloads({bool notify = true}) async {
    try {
      final file = await BackendService.getLocalFile('downloads.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final list = jsonDecode(jsonStr) as List;
        _downloadedSongs = list.map((j) => Song.fromJson(j)).toList();
        if (notify) notifyListeners();
      }
    } catch (e) {
      print("Ошибка загрузки скачанных: $e");
    }
  }

  Future<void> _saveDownloads() async {
    final file = await BackendService.getLocalFile('downloads.json');
    await file.writeAsString(
      jsonEncode(_downloadedSongs.map((s) => s.toJson()).toList()),
    );
  }

  // ── CINEMA DOWNLOADS (ОФФЛАЙН КИНО) 🎬 ──
  List<DownloadedMovie> _downloadedMovies = [];
  List<DownloadedMovie> get downloadedMovies => _downloadedMovies;
  bool isMovieDownloaded(String id) => _downloadedMovies.any((m) => m.id == id);

  final List<String> _downloadingMovieIds = [];
  final Map<String, double> _movieDownloadProgress = {};
  final Map<String, http.Client> _activeMovieClients = {};
  final Map<String, DownloadedMovie> _downloadingMovieMetadata = {};
  final List<_MovieDownloadTask> _movieDownloadQueue = [];
  bool _isProcessingMovieQueue = false;

  bool isMovieDownloading(String id) => _downloadingMovieIds.contains(id);
  double getMovieDownloadProgress(String id) => _movieDownloadProgress[id] ?? 0.0;
  Map<String, DownloadedMovie> get downloadingMovieMetadata => _downloadingMovieMetadata;

  Future<void> loadMovieDownloads({bool notify = true}) async {
    try {
      final file = await BackendService.getLocalFile('downloaded_movies.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final list = jsonDecode(jsonStr) as List;
        _downloadedMovies = list.map((j) => DownloadedMovie.fromJson(j)).toList();
        if (notify) notifyListeners();
      }
    } catch (e) {
      print("Ошибка загрузки скачанных фильмов: $e");
    }
  }

  Future<void> _saveMovieDownloads() async {
    final file = await BackendService.getLocalFile('downloaded_movies.json');
    await file.writeAsString(
      jsonEncode(_downloadedMovies.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> _downloadHls(
    MovieItem movie,
    String cleanId,
    String displayTitle,
    String streamUrl,
    String localPath,
  ) async {
    print("[CinemaDownload] Starting HLS download for '$displayTitle'. URL: $streamUrl");
    final client = http.Client();
    _activeMovieClients[cleanId] = client;

    try {
      final dir = await getApplicationDocumentsDirectory();
      
      // 1. Ensure movie directory exists
      final movieDir = Directory('${dir.path}/movies/${_getSafeFileName(cleanId)}');
      if (!await movieDir.exists()) {
        await movieDir.create(recursive: true);
      }

      // 2. Download hls.min.js if not present
      final hlsJsFile = File('${dir.path}/hls.min.js');
      if (!await hlsJsFile.exists()) {
        try {
          print("[CinemaDownload] Downloading hls.min.js...");
          final hlsResponse = await http.get(Uri.parse('https://cdn.jsdelivr.net/npm/hls.js@1.4.12/dist/hls.min.js'));
          if (hlsResponse.statusCode == 200) {
            await hlsJsFile.writeAsBytes(hlsResponse.bodyBytes);
            print("[CinemaDownload] hls.min.js saved successfully");
          } else {
            print("[CinemaDownload] Failed to download hls.min.js, status: ${hlsResponse.statusCode}");
          }
        } catch (e) {
          print("[CinemaDownload] Failed to download hls.js: $e");
        }
      }

      // 3. Fetch manifest
      var playlistUrl = Uri.parse(streamUrl);
      final downloadHeaders = _getDownloadHeaders(streamUrl);
      print("[CinemaDownload] Fetching HLS playlist manifest from $playlistUrl");
      final response = await client.get(playlistUrl, headers: downloadHeaders);
      print("[CinemaDownload] Playlist fetch status code: ${response.statusCode}");
      if (response.statusCode != 200) {
        throw Exception("Не удалось загрузить манифест HLS. HTTP Код: ${response.statusCode}");
      }
      String manifestContent = response.body;

      // 4. Resolve master playlist if present
      if (manifestContent.contains('#EXT-X-STREAM-INF')) {
        print("[CinemaDownload] Master playlist detected. Resolving best quality variant...");
        final lines = manifestContent.split('\n');
        String? selectedVariantUri;
        int highestResolution = 0;

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('#EXT-X-STREAM-INF:')) {
            int resolution = 360;
            final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
            if (resMatch != null) {
              resolution = int.tryParse(resMatch.group(2) ?? '360') ?? 360;
            }

            if (i + 1 < lines.length) {
              final nextLine = lines[i + 1].trim();
              if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
                if (selectedVariantUri == null || resolution > highestResolution) {
                  highestResolution = resolution;
                  selectedVariantUri = nextLine;
                }
              }
            } 
          }
        }

        if (selectedVariantUri != null) {
          final variantUrl = playlistUrl.resolve(selectedVariantUri);
          print("[CinemaDownload] Selected variant playlist URL: $variantUrl (Resolution: $highestResolution)");
          final variantResponse = await client.get(variantUrl, headers: downloadHeaders);
          if (variantResponse.statusCode == 200) {
            manifestContent = variantResponse.body;
            playlistUrl = variantUrl;
          } else {
            print("[CinemaDownload] Failed to fetch variant playlist, HTTP: ${variantResponse.statusCode}");
          }
        }
      }

      // 5. Parse segments
      final lines = manifestContent.split('\n');
      final List<String> segmentUrls = [];
      final List<int> lineIndices = [];

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isNotEmpty && !line.startsWith('#')) {
          segmentUrls.add(line);
          lineIndices.add(i);
        }
      }

      if (segmentUrls.isEmpty) {
        throw Exception("Не найдены видео-сегменты (.ts) в HLS плейлисте");
      }

      final totalSegments = segmentUrls.length;
      print("[CinemaDownload] Found $totalSegments HLS segments to download");
      int downloadedSegments = 0;
      double lastNotifiedProgress = 0.0;
      int lastNotifiedMs = DateTime.now().millisecondsSinceEpoch;
      final List<String> localSegmentFilenames = List.filled(totalSegments, '');

      final List<_HlsTask> queue = [];
      for (int i = 0; i < totalSegments; i++) {
        final segmentUri = playlistUrl.resolve(segmentUrls[i]).toString();
        final localFilename = 'segment_$i.ts';
        localSegmentFilenames[i] = localFilename;
        queue.add(_HlsTask(i, segmentUri, localFilename));
      }

      // Concurrency worker
      Future<void> runWorker() async {
        while (queue.isNotEmpty) {
          if (!_activeMovieClients.containsKey(cleanId)) return;
          final task = queue.removeLast();
          final segmentFile = File('${movieDir.path}/${task.localFilename}');

          int retries = 3;
          bool success = false;
          while (retries > 0 && !success) {
            if (!_activeMovieClients.containsKey(cleanId)) return;
            try {
              final segmentResponse = await client.get(
                Uri.parse(task.segmentUri),
                headers: _getDownloadHeaders(task.segmentUri),
              );
              if (segmentResponse.statusCode == 200) {
                await segmentFile.writeAsBytes(segmentResponse.bodyBytes);
                success = true;
              } else {
                print("[CinemaDownload] Segment ${task.index} fetch failed with HTTP ${segmentResponse.statusCode}, retrying...");
                retries--;
                if (retries > 0) await Future.delayed(const Duration(milliseconds: 500));
              }
            } catch (err) {
              print("[CinemaDownload] Segment ${task.index} error: $err, retrying...");
              retries--;
              if (retries > 0) await Future.delayed(const Duration(milliseconds: 500));
            }
          }

          if (!success) {
            throw Exception("Не удалось скачать сегмент ${task.index} после нескольких попыток");
          }

          downloadedSegments++;
          final progress = downloadedSegments / totalSegments;
          _movieDownloadProgress[cleanId] = progress;
          
          final now = DateTime.now().millisecondsSinceEpoch;
          if (progress == 1.0 || (progress - lastNotifiedProgress >= 0.02 && now - lastNotifiedMs >= 300)) {
            lastNotifiedProgress = progress;
            lastNotifiedMs = now;
            notifyListeners();
          }
        }
      }

      // Spin up 3 workers
      final workers = List.generate(3, (_) => runWorker());
      await Future.wait(workers);

      if (!_activeMovieClients.containsKey(cleanId)) {
        throw Exception("Скачивание фильма отменено");
      }

      // 6. Rewrite playlist
      for (int i = 0; i < totalSegments; i++) {
        final lineIndex = lineIndices[i];
        lines[lineIndex] = localSegmentFilenames[i];
      }

      final newManifestContent = lines.join('\n');
      final localM3u8File = File(localPath);
      await localM3u8File.writeAsString(newManifestContent);

      final downloaded = DownloadedMovie(
        id: cleanId,
        title: displayTitle,
        type: movie.type,
        coverUrl: movie.coverUrl,
        genre: movie.genre,
        year: movie.year,
        localFilePath: localPath,
      );

      _downloadedMovies.insert(0, downloaded);
      await _saveMovieDownloads();
      print("[CinemaDownload] HLS download successfully completed for $displayTitle");
    } catch (e) {
      print("[CinemaDownload] Error downloading HLS movie ${movie.title}: $e");
      try {
        final dir = await getApplicationDocumentsDirectory();
        final movieDir = Directory('${dir.path}/movies/${_getSafeFileName(cleanId)}');
        if (await movieDir.exists()) {
          await movieDir.delete(recursive: true);
        }
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
      _activeMovieClients.remove(cleanId);
    }
  }

  Future<void> downloadMovie(MovieItem movie, String streamUrl, {int? season, int? episode}) async {
    int? s = season;
    int? e = episode;
    if (movie.type == 'Сериал' && s == null && e == null) {
      s = 1;
      e = 1;
    }

    final cleanId = (s != null && e != null)
        ? "${movie.id}_s${s}_e${e}"
        : movie.id;
        
    final displayTitle = (s != null && e != null)
        ? "${movie.title} ($s сезон, $e серия)"
        : movie.title;

    print("[CinemaDownload] Initiating download of '$displayTitle'. ID: $cleanId");

    if (isMovieDownloaded(cleanId)) {
      print("[CinemaDownload] Movie is already downloaded!");
      return;
    }
    if (_downloadingMovieIds.contains(cleanId) || _movieDownloadQueue.any((t) => t.cleanId == cleanId)) {
      print("[CinemaDownload] Movie is already downloading or in queue!");
      return;
    }

    final tempMetadata = DownloadedMovie(
      id: cleanId,
      title: displayTitle,
      type: movie.type,
      coverUrl: movie.coverUrl,
      genre: movie.genre,
      year: movie.year,
      localFilePath: '',
    );
    _downloadingMovieMetadata[cleanId] = tempMetadata;
    _movieDownloadQueue.add(_MovieDownloadTask(movie, streamUrl, cleanId, displayTitle, season: s, episode: e));
    notifyListeners();
    _processMovieQueue();
  }

  Future<void> _processMovieQueue() async {
    if (_isProcessingMovieQueue) return;
    _isProcessingMovieQueue = true;

    while (_movieDownloadQueue.isNotEmpty) {
      final activeCount = _downloadingMovieIds.length;
      if (activeCount >= 1) {
        // Ограничиваем скачивание: максимум 1 фильм одновременно
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }

      _MovieDownloadTask? task;
      for (final t in _movieDownloadQueue) {
        if (!_downloadingMovieIds.contains(t.cleanId)) {
          task = t;
          break;
        }
      }

      if (task == null) {
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }

      _runMovieDownload(task);
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _isProcessingMovieQueue = false;
  }

  Future<void> _runMovieDownload(_MovieDownloadTask task) async {
    if (_downloadingMovieIds.contains(task.cleanId)) return;
    _downloadingMovieIds.add(task.cleanId);
    _movieDownloadProgress[task.cleanId] = 0.0;
    notifyListeners();

    try {
      final isHls = task.streamUrl.contains('.m3u8') || task.streamUrl.contains('m3u8');
      final dir = await getApplicationDocumentsDirectory();
      final localPath = isHls 
          ? '${dir.path}/movies/${_getSafeFileName(task.cleanId)}/index.m3u8'
          : '${dir.path}/${_getSafeFileName(task.cleanId)}.mp4';

      if (isHls) {
        await _downloadHls(task.movie, task.cleanId, task.displayTitle, task.streamUrl, localPath);
      } else {
        await _downloadMp4(task.movie, task.cleanId, task.displayTitle, task.streamUrl, localPath);
      }
    } catch (err) {
      print("[CinemaDownload] Task error for ${task.displayTitle}: $err");
    } finally {
      _downloadingMovieIds.remove(task.cleanId);
      _movieDownloadProgress.remove(task.cleanId);
      _downloadingMovieMetadata.remove(task.cleanId);
      _movieDownloadQueue.removeWhere((t) => t.cleanId == task.cleanId);
      notifyListeners();
      _processMovieQueue();
    }
  }

  Future<void> _downloadMp4(
    MovieItem movie,
    String cleanId,
    String displayTitle,
    String streamUrl,
    String localPath,
  ) async {
    try {
      print("[CinemaDownload] Starting MP4 download for '$displayTitle'. URL: $streamUrl");
      final client = http.Client();
      _activeMovieClients[cleanId] = client;

      final request = http.Request('GET', Uri.parse(streamUrl));
      request.headers.addAll(_getDownloadHeaders(streamUrl));
      print("[CinemaDownload] Request headers: ${request.headers}");
      
      final response = await client.send(request);
      print("[CinemaDownload] Response status: ${response.statusCode}");
      if (response.statusCode != 200) {
        throw Exception("Не удалось скачать видео. HTTP Код: ${response.statusCode}");
      }
      final total = response.contentLength ?? 0;
      print("[CinemaDownload] Content length (size): $total bytes");
      int received = 0;

      final file = File(localPath);
      final sink = file.openWrite();

      double lastNotifiedProgress = 0.0;
      int lastNotifiedMs = DateTime.now().millisecondsSinceEpoch;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final progress = received / total;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (progress == 1.0 || (progress - lastNotifiedProgress >= 0.02 && now - lastNotifiedMs >= 300)) {
            _movieDownloadProgress[cleanId] = progress;
            lastNotifiedProgress = progress;
            lastNotifiedMs = now;
            notifyListeners();
          }
        }
      }

      await sink.close();
      client.close();

      if (!_activeMovieClients.containsKey(cleanId)) {
        throw Exception("Скачивание фильма отменено");
      }

      // Валидация: проверяем что скачанный файл — действительно видео, а не HTML-страница
      final downloadedFile = File(localPath);
      final fileSize = await downloadedFile.length();
      print("[CinemaDownload] Downloaded file size: $fileSize bytes");
      if (fileSize < 10000) {
        final firstBytes = await downloadedFile.readAsString().catchError((_) => '');
        print("[CinemaDownload] First chars of small downloaded file: $firstBytes");
        if (firstBytes.contains('<html') || firstBytes.contains('<!DOCTYPE') || firstBytes.contains('<head')) {
          await downloadedFile.delete();
          throw Exception("Скачан HTML вместо видео. Попробуйте скачать из плеера.");
        }
      }

      final downloaded = DownloadedMovie(
        id: cleanId,
        title: displayTitle,
        type: movie.type,
        coverUrl: movie.coverUrl,
        genre: movie.genre,
        year: movie.year,
        localFilePath: localPath,
      );

      _downloadedMovies.insert(0, downloaded);
      await _saveMovieDownloads();
      print("[CinemaDownload] MP4 download saved successfully: $localPath");
    } catch (err) {
      print("[CinemaDownload] Error downloading MP4 movie ${movie.title}: $err");
      try {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      rethrow;
    } finally {
      _activeMovieClients.remove(cleanId);
    }
  }

  Future<void> removeMovieDownload(String id) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_getSafeFileName(id)}.mp4');
      if (await file.exists()) {
        await file.delete();
      }
      final movieDir = Directory('${dir.path}/movies/${_getSafeFileName(id)}');
      if (await movieDir.exists()) {
        await movieDir.delete(recursive: true);
      }
      _downloadedMovies.removeWhere((m) => m.id == id);
      await _saveMovieDownloads();
      notifyListeners();
    } catch (e) {
      print("Ошибка удаления скачанного фильма: $e");
    }
  }

  void cancelMovieDownload(String id) {
    final client = _activeMovieClients[id];
    if (client != null) {
      client.close();
    }
    _activeMovieClients.remove(id);
    _downloadingMovieIds.remove(id);
    _movieDownloadProgress.remove(id);
    _downloadingMovieMetadata.remove(id);
    _movieDownloadQueue.removeWhere((t) => t.cleanId == id);
    notifyListeners();
  }

  // Очередь скачивания и активные HTTP-клиенты для отмены
  final List<Song> _downloadQueue = [];
  List<Song> get downloadQueue => _downloadQueue;
  final Map<String, http.Client> _activeClients = {};
  bool _isProcessingQueue = false;

  bool isDownloading(String id) => _downloadQueue.any((s) => s.id == id);
  bool isActivelyDownloading(String id) => _downloadingIds.contains(id);

  void cancelDownload(String id) {
    if (!isActivelyDownloading(id)) {
      _downloadQueue.removeWhere((s) => s.id == id);
      notifyListeners();
      return;
    }

    final client = _activeClients[id];
    if (client != null) {
      client.close();
      _activeClients.remove(id);
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_downloadingIds.length < 2 && _downloadQueue.isNotEmpty) {
        Song? nextSong;
        try {
          nextSong = _downloadQueue.firstWhere((s) => !isActivelyDownloading(s.id));
        } catch (_) {}

        if (nextSong == null) break;

        // Запускаем асинхронно
        _runDownload(nextSong);
        await Future.delayed(const Duration(milliseconds: 100)); // Маленькая пауза для стабильности
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _runDownload(Song song) async {
    if (isDownloaded(song.id) || isActivelyDownloading(song.id)) return;

    _downloadingIds.add(song.id);
    _downloadProgress[song.id] = 0.0;
    notifyListeners();

    try {
      final streamUrl = await PirateService.getStreamUrl(song.videoId);
      if (streamUrl == null || streamUrl.isEmpty) throw Exception("Нет ссылки");

      final client = http.Client();
      _activeClients[song.id] = client;

      final request = http.Request('GET', Uri.parse(streamUrl));
      request.headers.addAll(_getDownloadHeaders(streamUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception("Не удалось скачать трек. HTTP Код: ${response.statusCode}");
      }
      final total = response.contentLength ?? 0;
      int received = 0;

      final dir = await getApplicationDocumentsDirectory();
      final localPath = '${dir.path}/${_getSafeFileName(song.id)}.m4a';
      final file = File(localPath);
      final sink = file.openWrite();

      double lastNotifiedProgress = 0.0;
      int lastNotifiedMs = DateTime.now().millisecondsSinceEpoch;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final progress = received / total;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (progress == 1.0 || (progress - lastNotifiedProgress >= 0.02 && now - lastNotifiedMs >= 300)) {
            _downloadProgress[song.id] = progress;
            lastNotifiedProgress = progress;
            lastNotifiedMs = now;
            notifyListeners();
          }
        }
      }

      await sink.close();
      client.close();

      if (!_activeClients.containsKey(song.id)) {
        throw Exception("Скачивание отменено");
      }

      final offlineSong = Song(
        id: song.id,
        videoId: localPath,
        title: song.title,
        artist: song.artist,
        coverUrl: song.coverUrl,
        duration: song.duration,
        type: song.type,
      );

      _downloadedSongs.insert(0, offlineSong);
      await _saveDownloads();
      await calculateCacheSize();
      await enforceCacheLimit();
    } catch (e) {
      print("Ошибка скачивания ${song.title}: $e");
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/${_getSafeFileName(song.id)}.m4a');
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    } finally {
      _activeClients.remove(song.id);
      _downloadingIds.remove(song.id);
      _downloadProgress.remove(song.id);
      _downloadQueue.removeWhere((s) => s.id == song.id);
      notifyListeners();
      _processQueue(); // Event-driven trigger to start next download
    }
  }

  Future<void> downloadSong(Song song) async {
    if (isDownloaded(song.id)) return;
    if (_downloadQueue.any((s) => s.id == song.id)) return;

    _downloadQueue.add(song);
    notifyListeners();
    _processQueue();
  }

  Future<void> downloadPlaylist(List<Song> songs) async {
    for (final song in songs) {
      if (!isDownloaded(song.id) && !_downloadQueue.any((s) => s.id == song.id)) {
        _downloadQueue.add(song);
      }
    }
    notifyListeners();
    _processQueue();
  }

  Future<void> removeDownload(String id) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_getSafeFileName(id)}.m4a');
      if (await file.exists()) {
        await file.delete(); // Физически удаляем файл
      }
      _downloadedSongs.removeWhere((s) => s.id == id);
      await _saveDownloads();
      await calculateCacheSize();
      notifyListeners();
    } catch (e) {}
  }

  // ── SMART CACHE (АВТОМАТИЧЕСКИЙ ОФФЛАЙН-КЭШ) 🌟 ──
  bool _smartCacheEnabled = false;
  bool _wifiOnly = true;
  String _audioQuality = 'Medium';
  String _preferredSource = 'Auto';

  // Customization Settings
  String _accentColor = 'Green';
  String _miniPlayerStyle = 'Docked';
  bool _enableBlurBackground = true;
  bool _showLyricPreview = true;

  // Premium UI/UX Settings
  bool _hapticFeedback = true;
  bool _ambientGlow = true;
  String _pageTransition = 'iOS'; // 'iOS', 'Slide', 'Fade', 'Zoom'
  bool _isOfflineMode = false;
  String _appMode = 'music'; // 'music' or 'cinema'

  // Cache & Storage Settings
  String _cacheSizeLimit = 'Unlimited'; // '500MB', '1GB', '2GB', '5GB', 'Unlimited'
  bool _cacheOnPlay = true;
  bool _autoCleanCache = false;
  double _totalCacheSizeMb = 0.0;

  bool get smartCacheEnabled => _smartCacheEnabled;
  bool get wifiOnly => _wifiOnly;
  String get audioQuality => _audioQuality;
  String get preferredSource => _preferredSource;

  String get accentColor => _accentColor;
  String get miniPlayerStyle => _miniPlayerStyle;
  bool get enableBlurBackground => _enableBlurBackground;
  bool get showLyricPreview => _showLyricPreview;

  bool get hapticFeedback => _hapticFeedback;
  bool get ambientGlow => _ambientGlow;
  String get pageTransition => _pageTransition;
  bool get isOfflineMode => _isOfflineMode;
  String get appMode => _appMode;

  Future<void> setAppMode(String value) async {
    _appMode = value;
    notifyListeners();
    await _saveSettings();
  }

  String get cacheSizeLimit => _cacheSizeLimit;
  bool get cacheOnPlay => _cacheOnPlay;
  bool get autoCleanCache => _autoCleanCache;
  double get totalCacheSizeMb => _totalCacheSizeMb;

  Future<void> setIsOfflineMode(bool value) async {
    _isOfflineMode = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> toggleSmartCache(bool value) async {
    _smartCacheEnabled = value;
    notifyListeners();
    await _saveSettings();
    if (value) {
      triggerSmartCache();
    }
  }

  Future<void> toggleWifiOnly(bool value) async {
    _wifiOnly = value;
    notifyListeners();
    await _saveSettings();
    if (_smartCacheEnabled) {
      triggerSmartCache();
    }
  }

  Future<void> setAudioQuality(String value) async {
    _audioQuality = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setPreferredSource(String value) async {
    _preferredSource = value;
    PirateService.preferredSource = value;
    notifyListeners();
    await _saveSettings();
  }

  void _updateAccentColorInTheme() {
    switch (_accentColor) {
      case 'Green':
        AppColors.customAccentColor = const Color(0xFF1DB954);
        break;
      case 'Blue':
        AppColors.customAccentColor = const Color(0xFF007AFF);
        break;
      case 'Purple':
        AppColors.customAccentColor = const Color(0xFF9F3DF7);
        break;
      case 'Orange':
        AppColors.customAccentColor = const Color(0xFFFF5500);
        break;
      default:
        AppColors.customAccentColor = const Color(0xFF1DB954);
    }
  }

  Future<void> setAccentColor(String value) async {
    _accentColor = value;
    _updateAccentColorInTheme();
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setMiniPlayerStyle(String value) async {
    _miniPlayerStyle = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setEnableBlurBackground(bool value) async {
    _enableBlurBackground = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setShowLyricPreview(bool value) async {
    _showLyricPreview = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setHapticFeedback(bool value) async {
    _hapticFeedback = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setAmbientGlow(bool value) async {
    _ambientGlow = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setPageTransition(String value) async {
    _pageTransition = value;
    notifyListeners();
    await _saveSettings();
  }

  // Cache & Storage Management Helper Methods
  Future<void> calculateCacheSize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      double totalBytes = 0;
      if (await dir.exists()) {
        final List<FileSystemEntity> entities = await dir.list().toList();
        for (var entity in entities) {
          if (entity is File && entity.path.endsWith('.m4a')) {
            totalBytes += await entity.length();
          }
        }
      }
      _totalCacheSizeMb = totalBytes / (1024 * 1024);
      notifyListeners();
    } catch (e) {
      print("Ошибка расчета размера кэша: $e");
    }
  }

  Future<void> clearAllDownloads() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = await BackendService.getLocalFile('downloads.json');
      if (await file.exists()) {
        await file.delete();
      }
      _downloadedSongs.clear();
      notifyListeners();

      // Физически удаляем все .m4a файлы
      if (await dir.exists()) {
        final List<FileSystemEntity> entities = await dir.list().toList();
        for (var entity in entities) {
          if (entity is File && entity.path.endsWith('.m4a')) {
            await entity.delete();
          }
        }
      }
      await calculateCacheSize();
    } catch (e) {
      print("Ошибка очистки кэша треков: $e");
    }
  }

  Future<void> clearMetadataCache() async {
    try {
      // Очищаем историю поиска
      await clearHistory();
      // Очищаем файл истории прослушивания
      final file = await BackendService.getLocalFile('play_history.json');
      if (await file.exists()) {
        await file.delete();
      }
      await calculateCacheSize();
    } catch (e) {
      print("Ошибка очистки метаданных: $e");
    }
  }

  Future<void> enforceCacheLimit() async {
    if (_cacheSizeLimit == 'Unlimited') return;

    double limitMb = 0.0;
    if (_cacheSizeLimit == '500MB') limitMb = 500.0;
    else if (_cacheSizeLimit == '1GB') limitMb = 1000.0;
    else if (_cacheSizeLimit == '2GB') limitMb = 2000.0;
    else if (_cacheSizeLimit == '5GB') limitMb = 5000.0;

    await calculateCacheSize();

    while (_totalCacheSizeMb > limitMb && _downloadedSongs.isNotEmpty) {
      // Удаляем самый старый скачанный трек (он в конце списка)
      final oldest = _downloadedSongs.last;
      await removeDownload(oldest.id);
    }
  }

  Future<void> setCacheSizeLimit(String value) async {
    _cacheSizeLimit = value;
    notifyListeners();
    await _saveSettings();
    await enforceCacheLimit();
  }

  Future<void> setCacheOnPlay(bool value) async {
    _cacheOnPlay = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setAutoCleanCache(bool value) async {
    _autoCleanCache = value;
    notifyListeners();
    await _saveSettings();
    if (value) {
      await enforceCacheLimit();
    }
  }

  Future<void> _saveSettings() async {
    try {
      final file = await BackendService.getLocalFile('settings.json');
      await file.writeAsString(jsonEncode({
        'smartCacheEnabled': _smartCacheEnabled,
        'wifiOnly': _wifiOnly,
        'audioQuality': _audioQuality,
        'preferredSource': _preferredSource,
        'accentColor': _accentColor,
        'miniPlayerStyle': _miniPlayerStyle,
        'enableBlurBackground': _enableBlurBackground,
        'showLyricPreview': _showLyricPreview,
        'hapticFeedback': _hapticFeedback,
        'ambientGlow': _ambientGlow,
        'pageTransition': _pageTransition,
        'cacheSizeLimit': _cacheSizeLimit,
        'cacheOnPlay': _cacheOnPlay,
        'autoCleanCache': _autoCleanCache,
        'isOfflineMode': _isOfflineMode,
        'appMode': _appMode,
      }));
    } catch (e) {
      print("Ошибка сохранения настроек: $e");
    }
  }

  Future<void> _loadSettings() async {
    try {
      final file = await BackendService.getLocalFile('settings.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        _smartCacheEnabled = data['smartCacheEnabled'] ?? false;
        _wifiOnly = data['wifiOnly'] ?? true;
        _audioQuality = data['audioQuality'] ?? 'Medium';
        _preferredSource = data['preferredSource'] ?? 'Auto';
        _accentColor = data['accentColor'] ?? 'Green';
        _miniPlayerStyle = data['miniPlayerStyle'] ?? 'Docked';
        _enableBlurBackground = data['enableBlurBackground'] ?? true;
        _showLyricPreview = data['showLyricPreview'] ?? true;
        _hapticFeedback = data['hapticFeedback'] ?? true;
        _ambientGlow = data['ambientGlow'] ?? true;
        _pageTransition = data['pageTransition'] ?? 'iOS';
        _cacheSizeLimit = data['cacheSizeLimit'] ?? 'Unlimited';
        _cacheOnPlay = data['cacheOnPlay'] ?? true;
        _autoCleanCache = data['autoCleanCache'] ?? false;
        _isOfflineMode = data['isOfflineMode'] ?? false;
        _appMode = data['appMode'] ?? 'music';
        PirateService.preferredSource = _preferredSource;
        _updateAccentColorInTheme();
        await calculateCacheSize();
        if (_autoCleanCache) {
          await enforceCacheLimit();
        }
      } else {
        await calculateCacheSize();
      }
    } catch (e) {
      print("Ошибка загрузки настроек: $e");
    }
  }

  bool _isSmartCaching = false;
  List<Song> _lastRecentSongs = [];

  Future<void> triggerSmartCache([List<Song>? recentSongs]) async {
    if (recentSongs != null) {
      _lastRecentSongs = recentSongs;
    }
    if (!_smartCacheEnabled || _isSmartCaching) return;
    _isSmartCaching = true;

    try {
      final Set<String> candidatesIds = {};
      final List<Song> candidates = [];

      for (final song in _likedSongs) {
        if (!candidatesIds.contains(song.id)) {
          candidatesIds.add(song.id);
          candidates.add(song);
        }
      }

      final recentTop20 = _lastRecentSongs.take(20).toList();
      for (final song in recentTop20) {
        if (!candidatesIds.contains(song.id)) {
          candidatesIds.add(song.id);
          candidates.add(song);
        }
      }

      final List<Song> toDownload = candidates.where((song) {
        return !isDownloaded(song.id) && !isDownloading(song.id);
      }).toList();

      if (toDownload.isEmpty) return;

      if (_wifiOnly) {
        final wifi = await _isConnectedToWifi();
        if (!wifi) {
          print("Smart Cache: Wi-Fi не подключен, авто-скачивание отложено");
          return;
        }
      }

      print("Smart Cache: Начинаем фоновое авто-скачивание ${toDownload.length} треков...");

      for (final song in toDownload) {
        if (!_smartCacheEnabled) break;
        if (_wifiOnly) {
          final wifi = await _isConnectedToWifi();
          if (!wifi) break;
        }
        await downloadSong(song);
      }
    } catch (e) {
      print("Ошибка авто-кэширования: $e");
    } finally {
      _isSmartCaching = false;
    }
  }

  Future<bool> _isConnectedToWifi() async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        return true;
      }
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('wlan') || name.contains('wifi') || name.contains('wi-fi')) {
          return true;
        }
      }
    } catch (e) {}
    return false;
  }

  // ── Init ──
  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final silenceFile = File('${dir.path}/silence.mp3');
      if (!silenceFile.existsSync()) {
        final bytes = base64Decode("SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU2LjM2LjEwMAAAAAAAAAAAAAAA//OEAAAAAAAAAAAAAAAAAAAAAAAASW5mbwAAAA8AAAAEAAABIADAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDV1dXV1dXV1dXV1dXV1dXV1dXV1dXV1dXV6urq6urq6urq6urq6urq6urq6urq6urq6v////////////////////////////////8AAAAATGF2YzU2LjQxAAAAAAAAAAAAAAAAJAAAAAAAAAAAASDs90hvAAAAAAAAAAAAAAAAAAAA//MUZAAAAAGkAAAAAAAAA0gAAAAATEFN//MUZAMAAAGkAAAAAAAAA0gAAAAARTMu//MUZAYAAAGkAAAAAAAAA0gAAAAAOTku//MUZAkAAAGkAAAAAAAAA0gAAAAANVVV");
        await silenceFile.writeAsBytes(bytes);
      }
    } catch (e) {
      debugPrint("Error creating silence placeholder: $e");
    }

    FirebaseService.authStateChanges.listen((User? user) async {
      if (user != null) {
        await clearLocalMemoryState();
        await Future.wait([
          loadLikedSongs(notify: false),
          loadSearchHistory(notify: false),
          loadPlaylists(notify: false),
          loadFollowedArtists(notify: false),
          loadDownloads(notify: false),
          loadMovieDownloads(notify: false),
          loadRecentPlaylists(notify: false),
          _loadSettings(),
        ]);
        notifyListeners();
      } else {
        await clearLocalMemoryState();
        notifyListeners();
      }
    });
  }

  Future<void> clearLocalMemoryState() async {
    // 1. Физически удаляем скачанные .m4a файлы с диска
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final song in _downloadedSongs) {
        final file = File('${dir.path}/${_getSafeFileName(song.id)}.m4a');
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      print("Ошибка при удалении локальных аудио-файлов при выходе: $e");
    }

    // 1.1. Физически удаляем скачанные .mp4 файлы с диска
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final movie in _downloadedMovies) {
        final file = File('${dir.path}/${_getSafeFileName(movie.id)}.mp4');
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      print("Ошибка при удалении локальных видео-файлов при выходе: $e");
    }

    // 2. Очищаем все локальные массивы в памяти
    _likedIds.clear();
    _likedSongs.clear();
    _searchHistory.clear();
    _playlists.clear();
    _downloadedSongs.clear();
    _downloadedMovies.clear();
    _recentPlaylists.clear();
  }

  // ── SpotMate Parsing and Importing ──

  Future<SpotifyImportResult?> parseImportInput(String input) async {
    final trimmedInput = input.trim();
    if (trimmedInput.isEmpty) return null;

    SpotifyImportType? type;
    String? title;
    String? coverUrl;
    String? subtitle;
    List<Song> rawSongs = [];

    try {
      // 1. Spotify
      if (trimmedInput.contains('spotify.com') || trimmedInput.startsWith('spotify:')) {
        // Track
        final trackRegExp = RegExp(r'(?:track[/:]?)([a-zA-Z0-9]{22})');
        final trackMatch = trackRegExp.firstMatch(trimmedInput);
        if (trackMatch != null) {
          final trackId = trackMatch.group(1)!;
          final song = await SpotifyService.getTrackDetails(trackId);
          if (song != null) {
            type = SpotifyImportType.track;
            title = song.title;
            coverUrl = song.coverUrl;
            subtitle = song.artist;
            rawSongs = [song];
          }
        }

        // Album
        if (rawSongs.isEmpty) {
          final albumRegExp = RegExp(r'(?:album[/:]?)([a-zA-Z0-9]{22})');
          final albumMatch = albumRegExp.firstMatch(trimmedInput);
          if (albumMatch != null) {
            final albumId = albumMatch.group(1)!;
            final details = await SpotifyService.getAlbumDetails(albumId);
            if (details != null) {
              type = SpotifyImportType.album;
              title = details['name'] as String;
              coverUrl = details['coverUrl'] as String;
              subtitle = details['artist'] as String?;
              rawSongs = details['songs'] as List<Song>;
            }
          }
        }

        // Playlist
        if (rawSongs.isEmpty) {
          final playlistRegExp = RegExp(r'(?:playlist[/:]?)([a-zA-Z0-9]{22})');
          final playlistMatch = playlistRegExp.firstMatch(trimmedInput);
          if (playlistMatch != null) {
            final playlistId = playlistMatch.group(1)!;
            final details = await SpotifyService.getPlaylistDetails(playlistId);
            if (details != null) {
              type = SpotifyImportType.playlist;
              title = details['name'] as String;
              coverUrl = details['coverUrl'] as String;
              subtitle = 'Spotify Playlist';
              rawSongs = details['songs'] as List<Song>;
            }
          }
        }
      }
      
      // 2. Yandex Music
      else if (trimmedInput.contains('music.yandex.ru')) {
        final yandexRegExp = RegExp(r'music\.yandex\.ru/users/([^/]+)/playlists/([0-9]+)');
        final yandexMatch = yandexRegExp.firstMatch(trimmedInput);
        if (yandexMatch != null) {
          final owner = yandexMatch.group(1)!;
          final playlistId = yandexMatch.group(2)!;
          
          final apiUri = Uri.parse('https://music.yandex.ru/handlers/playlist.jsx?owner=$owner&kinds=$playlistId&light=true');
          final response = await http.get(apiUri, headers: {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": "https://music.yandex.ru/",
          });

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final playlistObj = data['playlist'];
            if (playlistObj != null) {
              final name = playlistObj['title']?.toString() ?? 'Плейлист Яндекс.Музыка';
              var cover = CoverService.defaultMusicCover;
              if (playlistObj['cover'] != null && playlistObj['cover']['uri'] != null) {
                var uri = playlistObj['cover']['uri'].toString();
                uri = uri.replaceAll('%%', '400x400');
                cover = uri.startsWith('http') ? uri : 'https://$uri';
              }

              final List tracksList = playlistObj['tracks'] ?? [];
              final List<Song> songs = [];
              for (var t in tracksList) {
                final trackTitle = t['title']?.toString() ?? '';
                final List artistsList = t['artists'] ?? [];
                final artist = artistsList.isNotEmpty 
                    ? artistsList.map((a) => a['name']?.toString() ?? '').join(', ')
                    : 'Unknown';
                
                final durationMs = t['durationMs'] as int? ?? 180000;
                songs.add(Song(
                  id: 'ya_${t['id'] ?? DateTime.now().millisecondsSinceEpoch}_${songs.length}',
                  videoId: 'pirate:search:$artist - $trackTitle',
                  title: trackTitle,
                  artist: artist,
                  coverUrl: cover,
                  duration: Duration(milliseconds: durationMs),
                  type: 'song',
                ));
              }

              type = SpotifyImportType.playlist;
              title = name;
              coverUrl = cover;
              subtitle = 'Яндекс Музыка Плейлист';
              rawSongs = songs;
            }
          }
        }
      }

      // 3. SoundCloud
      else if (trimmedInput.contains('soundcloud.com') || trimmedInput.contains('on.soundcloud.com')) {
        final resolved = await SoundcloudService.resolveUrl(trimmedInput);
        if (resolved != null) {
          if (resolved['type'] == 'track' && resolved['song'] != null) {
            final song = resolved['song'] as Song;
            type = SpotifyImportType.track;
            title = song.title;
            coverUrl = song.coverUrl;
            subtitle = song.artist;
            rawSongs = [song];
          } else if (resolved['type'] == 'playlist' && resolved['songs'] != null) {
            type = SpotifyImportType.playlist;
            title = resolved['title'] as String? ?? 'SoundCloud Плейлист';
            final songs = List<Song>.from(resolved['songs']);
            coverUrl = songs.isNotEmpty ? songs.first.coverUrl : CoverService.defaultMusicCover;
            subtitle = 'SoundCloud (${songs.length} треков)';
            rawSongs = songs;
          }
        }

        // Fallback: если resolve не сработал — используем oEmbed API для получения метаданных
        if (rawSongs.isEmpty) {
          print('⚠️ SoundCloud resolve failed, trying oEmbed fallback...');
          try {
            // oEmbed API не требует client_id и принимает короткие ссылки
            final oEmbedUri = Uri.parse(
              'https://soundcloud.com/oembed?format=json&url=${Uri.encodeComponent(trimmedInput.trim())}',
            );
            final oEmbedRes = await http.get(oEmbedUri, headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            });

            if (oEmbedRes.statusCode == 200) {
              final oData = jsonDecode(oEmbedRes.body);
              final oTitle = oData['title']?.toString() ?? '';
              final oAuthor = oData['author_name']?.toString() ?? '';
              final oThumbnail = oData['thumbnail_url']?.toString() ?? '';

              if (oTitle.isNotEmpty) {
                // Ищем по названию + автору через SoundCloud search
                final searchQuery = oAuthor.isNotEmpty ? '$oAuthor $oTitle' : oTitle;
                print('🔍 SoundCloud oEmbed fallback search: "$searchQuery"');
                final searchResults = await SoundcloudService.search(searchQuery, limit: 20);

                if (searchResults.isNotEmpty) {
                  type = SpotifyImportType.playlist;
                  title = oTitle;
                  coverUrl = oThumbnail.isNotEmpty ? oThumbnail : searchResults.first.coverUrl;
                  subtitle = oAuthor.isNotEmpty ? oAuthor : 'SoundCloud (${searchResults.length} треков)';
                  rawSongs = searchResults;
                } else {
                  // Если SoundCloud search не сработал — ищем через PirateService
                  final pirateQuery = oAuthor.isNotEmpty ? '$oAuthor - $oTitle' : oTitle;
                  final pirateResults = await PirateService.search(pirateQuery);
                  final pirateSongs = pirateResults.where((s) => s.type == 'song').toList();
                  if (pirateSongs.isNotEmpty) {
                    type = SpotifyImportType.playlist;
                    title = oTitle;
                    coverUrl = oThumbnail.isNotEmpty ? oThumbnail : CoverService.defaultMusicCover;
                    subtitle = oAuthor.isNotEmpty ? oAuthor : 'Импорт';
                    rawSongs = pirateSongs;
                  }
                }
              }
            }
          } catch (e) {
            print('SoundCloud oEmbed fallback failed: $e');
          }
        }
      }

      // 4. Fallback: Parse text list
      if (rawSongs.isEmpty) {
        final lines = trimmedInput.split('\n');
        final List<Song> songs = [];
        for (var line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) continue;

          String artist = 'Unknown';
          String trackTitle = trimmed;

          if (trimmed.contains(' - ')) {
            final parts = trimmed.split(' - ');
            artist = parts[0].trim();
            trackTitle = parts.sublist(1).join(' - ').trim();
          } else if (trimmed.contains(' — ')) {
            final parts = trimmed.split(' — ');
            artist = parts[0].trim();
            trackTitle = parts.sublist(1).join(' — ').trim();
          } else if (trimmed.contains('-')) {
            final index = trimmed.indexOf('-');
            artist = trimmed.substring(0, index).trim();
            trackTitle = trimmed.substring(index + 1).trim();
          }

          final id = 'txt_${DateTime.now().millisecondsSinceEpoch}_${songs.length}';
          songs.add(Song(
            id: id,
            videoId: 'pirate:search:$artist - $trackTitle',
            title: trackTitle,
            artist: artist,
            coverUrl: CoverService.defaultMusicCover,
            duration: const Duration(minutes: 3, seconds: 30),
            type: 'song',
          ));
        }

        if (songs.isNotEmpty) {
          type = SpotifyImportType.text;
          title = 'Текстовый импорт';
          coverUrl = CoverService.defaultMusicCover;
          subtitle = '${songs.length} треков';
          rawSongs = songs;
        }
      }

      if (rawSongs.isEmpty) return null;

      // 4. Поиск песен: SoundCloud → через SoundCloud API, остальные → через пиратские сайты
      final List<Song> foundSongs = [];
      final List<Song> notFoundSongs = [];

      // Определяем источник импорта
      final bool isSoundcloudImport = trimmedInput.contains('soundcloud.com') || trimmedInput.contains('on.soundcloud.com');

      final searchFutures = rawSongs.map((song) async {
        // Уже готовые SoundCloud треки — пропускаем
        if (song.id.startsWith('sc_') || song.videoId.startsWith('sc_stream:') || song.videoId.startsWith('http')) {
          return MapEntry(song, song);
        }
        try {
          final query = "${song.artist} - ${song.title}";

          List<Song> results;
          if (isSoundcloudImport) {
            // SoundCloud импорт → ищем через SoundCloud API
            results = await SoundcloudService.search(query, limit: 10);
          } else {
            // Spotify / Yandex / текст → ищем через пиратские сайты напрямую
            final pirateResults = await PirateService.search(query);
            results = pirateResults.where((s) => s.type == 'song').toList();
          }

          if (results.isNotEmpty) {
            // Сначала строгая проверка совпадения
            Song? matched;
            for (final candidate in results) {
              if (PirateService.isMatch(query, candidate.artist, candidate.title)) {
                matched = candidate;
                break;
              }
            }
            // Если строгая не сработала — пробуем relaxed
            if (matched == null) {
              for (final candidate in results) {
                if (PirateService.isMatchRelaxed(query, candidate.artist, candidate.title)) {
                  matched = candidate;
                  print("💡 Import relaxed match: $query -> ${candidate.artist} - ${candidate.title}");
                  break;
                }
              }
            }
            // Если совпадений нет — берём первый результат как лучший вариант
            matched ??= results.first;

            final resolvedSong = Song(
              id: matched.id,
              title: song.title,
              artist: song.artist,
              coverUrl: song.coverUrl.isNotEmpty ? song.coverUrl : matched.coverUrl,
              duration: matched.duration != Duration.zero ? matched.duration : song.duration,
              videoId: matched.videoId,
              type: 'song',
            );
            return MapEntry(song, resolvedSong);
          }
        } catch (e) {
          print("Ошибка поиска песни во время импорта: $e");
        }
        return MapEntry(song, null as Song?);
      }).toList();

      final searchResultsList = await Future.wait(searchFutures);
      for (final entry in searchResultsList) {
        if (entry.value != null) {
          foundSongs.add(entry.value!);
        } else {
          notFoundSongs.add(entry.key);
        }
      }

      return SpotifyImportResult(
        type: type ?? SpotifyImportType.text,
        title: title ?? 'Импортированный плейлист',
        coverUrl: coverUrl ?? CoverService.defaultMusicCover,
        subtitle: subtitle,
        songs: foundSongs,
        notFoundSongs: notFoundSongs,
      );
    } catch (e) {
      print("Error parsing import input: $e");
    }
    return null;
  }

  Future<void> saveImportedPlaylist(String name, String coverUrl, List<Song> songs) async {
    final List<Map<String, dynamic>> songJsonList = songs.map((song) {
      final safeId = song.id.startsWith('sp_') || song.id.startsWith('ya_') || song.id.startsWith('txt_')
          ? song.id
          : 'sp_${song.id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';
      return Song(
        id: safeId,
        videoId: song.videoId,
        title: song.title,
        artist: song.artist,
        coverUrl: song.coverUrl,
        duration: song.duration,
        type: 'song',
      ).toJson();
    }).toList();

    String finalName = name;
    int index = 1;
    while (_playlists.any((p) => p['name'] == finalName)) {
      finalName = "$name ($index)";
      index++;
    }

    final newPlaylist = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': finalName,
      'coverUrl': coverUrl,
      'songs': songJsonList,
    };

    _playlists.insert(0, newPlaylist);
    await _savePlaylists(changedPlaylistId: newPlaylist['id'] as String);
    notifyListeners();
  }

  // ── Recent Playlists ──
  List<RecentPlaylistEntry> _recentPlaylists = [];
  List<RecentPlaylistEntry> get recentPlaylists => _recentPlaylists;

  Future<void> loadRecentPlaylists({bool notify = true}) async {
    try {
      final firestoreRecent = await FirebaseService.getRecentPlaylists();
      if (firestoreRecent.isNotEmpty) {
        _recentPlaylists = firestoreRecent;
        if (notify) notifyListeners();
        await _saveRecentPlaylistsLocalOnly();
        return;
      }

      final file = await BackendService.getLocalFile('recent_playlists.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final list = jsonDecode(jsonStr) as List;
        _recentPlaylists = list.map((e) => RecentPlaylistEntry.fromJson(e)).toList();
        if (notify) notifyListeners();
      }
    } catch (e) {
      print("Ошибка загрузки недавних плейлистов: $e");
    }
  }

  Future<void> _saveRecentPlaylistsLocalOnly() async {
    try {
      final file = await BackendService.getLocalFile('recent_playlists.json');
      await file.writeAsString(jsonEncode(_recentPlaylists.map((e) => e.toJson()).toList()));
    } catch (e) {
      print("Ошибка сохранения недавних плейлистов локально: $e");
    }
  }

  Future<void> _saveRecentPlaylists() async {
    await _saveRecentPlaylistsLocalOnly();
    await FirebaseService.saveRecentPlaylists(_recentPlaylists);
  }

  Future<void> addToRecentPlaylists(Song playlistMetadata, String playlistType) async {
    if (playlistType != "Playlist" && playlistType != "Album" && playlistType != "CustomPlaylist") return;

    // Удаляем дубликат по ID
    _recentPlaylists.removeWhere((e) => e.playlistMetadata.id == playlistMetadata.id);

    // Добавляем в начало
    _recentPlaylists.insert(
      0,
      RecentPlaylistEntry(
        playlistMetadata: playlistMetadata,
        playlistType: playlistType,
        viewedAt: DateTime.now(),
      ),
    );

    // Ограничиваем список (например, 10 штук)
    if (_recentPlaylists.length > 10) {
      _recentPlaylists = _recentPlaylists.sublist(0, 10);
    }

    notifyListeners();
    await _saveRecentPlaylists();
  }

  Future<void> clearRecentPlaylists() async {
    _recentPlaylists.clear();
    notifyListeners();
    try {
      final file = await BackendService.getLocalFile('recent_playlists.json');
      if (await file.exists()) {
        await file.delete();
      }
      await FirebaseService.saveRecentPlaylists([]);
    } catch (e) {
      print("Ошибка при очистке недавних плейлистов: $e");
    }
  }
}

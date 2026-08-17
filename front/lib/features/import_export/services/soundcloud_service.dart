import 'dart:convert';
import 'dart:io';
import 'package:ses/core/network/network_service.dart';
import 'package:ses/core/utils/cover_service.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/import_export/services/pirate_service.dart';

class SoundcloudService {
  static String _clientId = 'pj6Fj6roW2KRzWACwxGjbkkQ8VRBjJyB';
  static bool _clientIdResolved = false;

  /// Известные clientId (обновляются периодически)
  static const List<String> _knownClientIds = [
    'pj6Fj6roW2KRzWACwxGjbkkQ8VRBjJyB',
    'iZIs9mchVcX5lhVRyQGGAYlNPVldzAoX',
    'a3e059563d7fd3372b49b37f00a00bcf',
    'OurFvFiucUX84MbVzo4fj0mqKnCIWQKi',
  ];

  static String get clientId => _clientId;

  /// Получает рабочий clientId: проверяет известные, затем скрейпит с сайта
  static Future<String> _getClientId() async {
    if (_clientIdResolved) return _clientId;

    // 1. Проверяем известные clientId
    for (final id in _knownClientIds) {
      if (await _testClientId(id)) {
        _clientId = id;
        _clientIdResolved = true;
        print('✅ SoundCloud clientId valid: $id');
        return _clientId;
      }
    }

    // 2. Скрейпим с сайта SoundCloud
    try {
      final scraped = await _scrapeClientId();
      if (scraped != null && await _testClientId(scraped)) {
        _clientId = scraped;
        _clientIdResolved = true;
        print('✅ SoundCloud clientId scraped: $scraped');
        return _clientId;
      }
    } catch (e) {
      print('Error scraping SoundCloud clientId: $e');
    }

    // 3. Если ничего не сработало — используем последний известный
    print('⚠️ Could not find working SoundCloud clientId, using default');
    return _clientId;
  }

  /// Проверяет работоспособность clientId
  static Future<bool> _testClientId(String id) async {
    try {
      final uri = Uri.parse(
        'https://api-v2.soundcloud.com/search/tracks?q=test&client_id=$id&limit=1',
      );
      final response = await NetworkService.get(
        uri,
        headers: _headers,
        timeout: const Duration(seconds: 5),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Скрейпит clientId из JS-бандлов SoundCloud
  static Future<String?> _scrapeClientId() async {
    try {
      // Загружаем главную страницу SoundCloud
      final mainPage = await NetworkService.get(
        Uri.parse('https://soundcloud.com'),
        headers: {
          'User-Agent': _headers['User-Agent']!,
          'Accept': 'text/html',
        },
        timeout: const Duration(seconds: 10),
      );

      if (mainPage.statusCode != 200) return null;

      // Ищем ссылки на JS-бандлы
      final scriptMatches = RegExp(
        r'src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"',
      ).allMatches(mainPage.body);

      final scriptUrls = scriptMatches.map((m) => m.group(1)!).toList();
      print('🔍 Found ${scriptUrls.length} SoundCloud JS bundles');

      // Проверяем последние скрипты (clientId обычно в последних бандлах)
      for (final url in scriptUrls.reversed.take(5)) {
        try {
          final jsResponse = await NetworkService.get(
            Uri.parse(url),
            headers: _headers,
            timeout: const Duration(seconds: 8),
          );

          if (jsResponse.statusCode == 200) {
            // Ищем паттерн client_id в JS коде
            final idMatch = RegExp(r'client_id:"([a-zA-Z0-9]{32})"')
                .firstMatch(jsResponse.body);
            if (idMatch != null) {
              final foundId = idMatch.group(1)!;
              print('🔑 Found clientId in JS bundle: $foundId');
              return foundId;
            }
            // Альтернативный паттерн
            final altMatch = RegExp(r'client_id=([a-zA-Z0-9]{32})')
                .firstMatch(jsResponse.body);
            if (altMatch != null) {
              final foundId = altMatch.group(1)!;
              print('🔑 Found clientId (alt pattern) in JS bundle: $foundId');
              return foundId;
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      print('Error scraping SoundCloud JS bundles: $e');
    }
    return null;
  }

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  /// Поиск треков через SoundCloud API v2
  static Future<List<Song>> search(
    String query, {
    int offset = 0,
    int limit = 20,
  }) async {
    if (query.trim().isEmpty) return [];
    await _getClientId();

    try {
      final searchUrl = Uri.parse(
        'https://api-v2.soundcloud.com/search/tracks?q=${Uri.encodeComponent(query)}&client_id=$clientId&limit=$limit&offset=$offset',
      );

      final response = await NetworkService.get(
        searchUrl,
        headers: _headers,
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) {
        print('SoundCloud search failed with status: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      final collection = data['collection'] as List? ?? [];

      final List<Song> songs = [];
      for (final item in collection) {
        final trackId = item['id']?.toString() ?? '';
        if (trackId.isEmpty) continue;

        final title = item['title']?.toString() ?? 'Unknown Track';
        final user = item['user'] as Map<String, dynamic>?;
        final artist = user?['username']?.toString() ?? 'SoundCloud';

        String? artwork = item['artwork_url']?.toString();
        if (artwork != null && artwork.isNotEmpty) {
          artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
        } else {
          artwork = user?['avatar_url']?.toString();
          if (artwork != null && artwork.isNotEmpty) {
            artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
          }
        }

        final coverUrl = (artwork != null && artwork.isNotEmpty)
            ? artwork
            : CoverService.defaultMusicCover;

        final durationMs = item['duration'] as int? ?? 0;
        final fullDurationMs = item['full_duration'] as int? ?? 0;
        final playbackCount = item['playback_count'] as int?;
        final createdAt = item['created_at']?.toString();

        // Detect snippet/Go+ tracks at search time
        final policy = item['policy']?.toString() ?? '';
        final isSnippet = item['snipped'] == true ||
            policy == 'SNIP' ||
            policy == 'BLOCK' ||
            item['access'] == 'preview' ||
            (fullDurationMs > 0 && durationMs > 0 && fullDurationMs > durationMs + 5000);

        // Snippet tracks get pirate:search: videoId so they resolve via full-length MP3 scrapers
        final videoId = isSnippet
            ? 'pirate:search:$artist - $title'
            : 'sc_stream:$trackId';
        final actualDuration = isSnippet && fullDurationMs > 0 ? fullDurationMs : durationMs;

        songs.add(
          Song(
            id: 'sc_$trackId',
            videoId: videoId,
            title: title,
            artist: artist,
            coverUrl: coverUrl,
            duration: Duration(milliseconds: actualDuration),
            type: 'song',
            playCount: playbackCount,
            yearText: createdAt,
          ),
        );
      }

      return songs;
    } catch (e) {
      print('Error in SoundCloud search: $e');
    }
    return [];
  }

  /// Поиск альбомов SoundCloud
  static Future<List<Song>> searchAlbums(
    String query, {
    int offset = 0,
    int limit = 20,
  }) async {
    if (query.trim().isEmpty) return [];
    await _getClientId();

    try {
      final searchUrl = Uri.parse(
        'https://api-v2.soundcloud.com/search/albums?q=${Uri.encodeComponent(query)}&client_id=$clientId&limit=$limit&offset=$offset',
      );

      final response = await NetworkService.get(
        searchUrl,
        headers: _headers,
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) {
        print('SoundCloud searchAlbums failed: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      final collection = data['collection'] as List? ?? [];

      final List<Song> albums = [];
      for (final item in collection) {
        final albumId = item['id']?.toString() ?? '';
        if (albumId.isEmpty) continue;

        final title = item['title']?.toString() ?? 'SoundCloud Album';
        final user = item['user'] as Map<String, dynamic>?;
        final artist = user?['username']?.toString() ?? 'SoundCloud';

        String? artwork = item['artwork_url']?.toString();
        if (artwork != null && artwork.isNotEmpty) {
          artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
        } else {
          artwork = user?['avatar_url']?.toString();
          if (artwork != null && artwork.isNotEmpty) {
            artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
          }
        }

        final coverUrl = (artwork != null && artwork.isNotEmpty)
            ? artwork
            : CoverService.defaultMusicCover;
        final createdAt = item['release_date']?.toString() ?? item['created_at']?.toString();
        final trackCount = item['track_count'] as int? ?? 0;

        albums.add(
          Song(
            id: 'sc_album_$albumId',
            videoId: 'sc_playlist:$albumId',
            title: title,
            artist: artist,
            coverUrl: coverUrl,
            duration: Duration.zero,
            type: 'Album',
            playCount: trackCount,
            yearText: createdAt,
          ),
        );
      }

      return albums;
    } catch (e) {
      print('Error in SoundCloud searchAlbums: $e');
    }
    return [];
  }

  /// Поиск плейлистов SoundCloud
  static Future<List<Song>> searchPlaylists(
    String query, {
    int offset = 0,
    int limit = 20,
  }) async {
    if (query.trim().isEmpty) return [];
    await _getClientId();

    try {
      final searchUrl = Uri.parse(
        'https://api-v2.soundcloud.com/search/playlists_without_albums?q=${Uri.encodeComponent(query)}&client_id=$clientId&limit=$limit&offset=$offset',
      );

      final response = await NetworkService.get(
        searchUrl,
        headers: _headers,
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) {
        print('SoundCloud searchPlaylists failed: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      final collection = data['collection'] as List? ?? [];

      final List<Song> playlists = [];
      for (final item in collection) {
        final playlistId = item['id']?.toString() ?? '';
        if (playlistId.isEmpty) continue;

        final title = item['title']?.toString() ?? 'SoundCloud Playlist';
        final user = item['user'] as Map<String, dynamic>?;
        final artist = user?['username']?.toString() ?? 'SoundCloud';

        String? artwork = item['artwork_url']?.toString();
        if (artwork != null && artwork.isNotEmpty) {
          artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
        } else {
          artwork = user?['avatar_url']?.toString();
          if (artwork != null && artwork.isNotEmpty) {
            artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
          }
        }

        final coverUrl = (artwork != null && artwork.isNotEmpty)
            ? artwork
            : CoverService.defaultMusicCover;
        final likesCount = item['likes_count'] as int? ?? item['reposts_count'] as int? ?? 0;
        final createdAt = item['created_at']?.toString();

        playlists.add(
          Song(
            id: 'sc_playlist_$playlistId',
            videoId: 'sc_playlist:$playlistId',
            title: title,
            artist: artist,
            coverUrl: coverUrl,
            duration: Duration.zero,
            type: 'Playlist',
            playCount: likesCount,
            yearText: createdAt,
          ),
        );
      }

      return playlists;
    } catch (e) {
      print('Error in SoundCloud searchPlaylists: $e');
    }
    return [];
  }

  /// Получение всех треков плейлиста или альбома SoundCloud по ID
  static Future<List<Song>> getPlaylistSongs(String rawId) async {
    var cleanId = rawId;
    if (cleanId.startsWith('sc_playlist_')) {
      cleanId = cleanId.replaceFirst('sc_playlist_', '');
    } else if (cleanId.startsWith('sc_album_')) {
      cleanId = cleanId.replaceFirst('sc_album_', '');
    } else if (cleanId.startsWith('sc_playlist:')) {
      cleanId = cleanId.replaceFirst('sc_playlist:', '');
    } else if (cleanId.startsWith('sc_')) {
      cleanId = cleanId.replaceFirst('sc_', '');
    }

    if (cleanId.isEmpty) return [];
    await _getClientId();

    try {
      final uri = Uri.parse(
        'https://api-v2.soundcloud.com/playlists/$cleanId?client_id=$clientId',
      );

      final response = await NetworkService.get(
        uri,
        headers: _headers,
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) {
        print('SoundCloud getPlaylistSongs failed with status: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      final rawTracks = data['tracks'] as List? ?? [];

      final List<Map<String, dynamic>> fullTrackItems = [];
      final List<String> missingTrackIds = [];

      for (final t in rawTracks) {
        if (t is Map<String, dynamic>) {
          if (t.containsKey('title') && t['title'] != null) {
            fullTrackItems.add(t);
          } else if (t.containsKey('id')) {
            missingTrackIds.add(t['id'].toString());
          }
        }
      }

      if (missingTrackIds.isNotEmpty) {
        final idsChunk = missingTrackIds.take(50).join(',');
        final tracksUri = Uri.parse(
          'https://api-v2.soundcloud.com/tracks?ids=$idsChunk&client_id=$clientId',
        );
        final tracksResponse = await NetworkService.get(
          tracksUri,
          headers: _headers,
          timeout: const Duration(seconds: 8),
        );
        if (tracksResponse.statusCode == 200) {
          final fetchedList = jsonDecode(tracksResponse.body) as List? ?? [];
          for (final ft in fetchedList) {
            if (ft is Map<String, dynamic>) {
              fullTrackItems.add(ft);
            }
          }
        }
      }

      final List<Song> songs = [];
      for (final item in fullTrackItems) {
        final trackId = item['id']?.toString() ?? '';
        if (trackId.isEmpty) continue;

        final title = item['title']?.toString() ?? 'Unknown Track';
        final user = item['user'] as Map<String, dynamic>?;
        final artist = user?['username']?.toString() ?? 'SoundCloud';

        String? artwork = item['artwork_url']?.toString();
        if (artwork != null && artwork.isNotEmpty) {
          artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
        } else {
          artwork = user?['avatar_url']?.toString();
          if (artwork != null && artwork.isNotEmpty) {
            artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
          }
        }

        final coverUrl = (artwork != null && artwork.isNotEmpty)
            ? artwork
            : CoverService.defaultMusicCover;

        final durationMs = item['duration'] as int? ?? 0;
        final fullDurationMs = item['full_duration'] as int? ?? 0;
        final playbackCount = item['playback_count'] as int?;
        final createdAt = item['created_at']?.toString();

        final policy = item['policy']?.toString() ?? '';
        final isSnippet = item['snipped'] == true ||
            policy == 'SNIP' ||
            policy == 'BLOCK' ||
            item['access'] == 'preview' ||
            (fullDurationMs > 0 && durationMs > 0 && fullDurationMs > durationMs + 5000);

        final videoId = isSnippet
            ? 'pirate:search:$artist - $title'
            : 'sc_stream:$trackId';
        final actualDuration = isSnippet && fullDurationMs > 0 ? fullDurationMs : durationMs;

        songs.add(
          Song(
            id: 'sc_$trackId',
            videoId: videoId,
            title: title,
            artist: artist,
            coverUrl: coverUrl,
            duration: Duration(milliseconds: actualDuration),
            type: 'song',
            playCount: playbackCount,
            yearText: createdAt,
          ),
        );
      }

      return songs;
    } catch (e) {
      print('Error in SoundCloud getPlaylistSongs: $e');
    }
    return [];
  }

  /// Поиск артистов (пользователей) через SoundCloud API v2
  static Future<List<Song>> searchArtists(
    String query, {
    int limit = 20,
  }) async {
    if (query.trim().isEmpty) return [];
    await _getClientId();

    try {
      final searchUrl = Uri.parse(
        'https://api-v2.soundcloud.com/search/users?q=${Uri.encodeComponent(query)}&client_id=$clientId&limit=$limit',
      );

      final response = await NetworkService.get(
        searchUrl,
        headers: _headers,
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final collection = data['collection'] as List? ?? [];

        final List<Song> artists = [];
        for (final item in collection) {
          final userId = item['id']?.toString() ?? '';
          if (userId.isEmpty) continue;

          final username = item['username']?.toString() ?? 'Artist';
          String? avatar = item['avatar_url']?.toString();
          if (avatar != null && avatar.isNotEmpty) {
            avatar = avatar.replaceAll('-large.jpg', '-t500x500.jpg');
          }

          final coverUrl = (avatar != null && avatar.isNotEmpty)
              ? avatar
              : CoverService.defaultMusicCover;
          final followers = item['followers_count'] as int? ?? 0;

          artists.add(
            Song(
              id: 'sc_user_$userId',
              videoId: '',
              title: username,
              artist: 'Артист',
              coverUrl: coverUrl,
              type: 'artist',
              followersCount: followers,
            ),
          );
        }
        return artists;
      }
    } catch (e) {
      print('Error in SoundCloud searchArtists: $e');
    }
    return [];
  }

  /// Получить популярные песни артиста SoundCloud
  static Future<List<Song>> getArtistSongs(String artistId, String artistName) async {
    await _getClientId();
    var userId = artistId.startsWith('sc_user_') ? artistId.replaceFirst('sc_user_', '') : '';

    if (userId.isNotEmpty) {
      try {
        final uri = Uri.parse(
          'https://api-v2.soundcloud.com/users/$userId/tracks?client_id=$clientId&limit=30',
        );
        final response = await NetworkService.get(
          uri,
          headers: _headers,
          timeout: const Duration(seconds: 8),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final collection = data['collection'] as List? ?? [];
          final List<Song> songs = [];
          for (final item in collection) {
            final trackId = item['id']?.toString() ?? '';
            if (trackId.isEmpty) continue;

            final title = item['title']?.toString() ?? 'Track';
            final user = item['user'] as Map<String, dynamic>?;
            final artist = user?['username']?.toString() ?? artistName;

            String? artwork = item['artwork_url']?.toString();
            if (artwork != null && artwork.isNotEmpty) {
              artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
            } else {
              artwork = user?['avatar_url']?.toString();
              if (artwork != null && artwork.isNotEmpty) {
                artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
              }
            }

            final coverUrl = (artwork != null && artwork.isNotEmpty)
                ? artwork
                : CoverService.defaultMusicCover;

            songs.add(Song(
              id: 'sc_$trackId',
              videoId: 'sc_stream:$trackId',
              title: title,
              artist: artist,
              coverUrl: coverUrl,
              duration: Duration(milliseconds: item['duration'] as int? ?? 0),
              type: 'song',
            ));
          }
          if (songs.isNotEmpty) return songs;
        }
      } catch (e) {
        print('Error getting SoundCloud artist tracks by userId: $e');
      }
    }

    return search(artistName, limit: 30);
  }

  /// Получить альбомы/плейлисты артиста SoundCloud
  static Future<List<Song>> getArtistAlbums(String artistId, String artistName) async {
    await _getClientId();
    var userId = artistId.startsWith('sc_user_') ? artistId.replaceFirst('sc_user_', '') : '';

    if (userId.isNotEmpty) {
      try {
        final uri = Uri.parse(
          'https://api-v2.soundcloud.com/users/$userId/playlists?client_id=$clientId&limit=20',
        );
        final response = await NetworkService.get(
          uri,
          headers: _headers,
          timeout: const Duration(seconds: 8),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final collection = data['collection'] as List? ?? [];
          final List<Song> albums = [];
          for (final item in collection) {
            final albumId = item['id']?.toString() ?? '';
            if (albumId.isEmpty) continue;

            final title = item['title']?.toString() ?? 'Album';
            final user = item['user'] as Map<String, dynamic>?;
            final artist = user?['username']?.toString() ?? artistName;

            String? artwork = item['artwork_url']?.toString();
            if (artwork != null && artwork.isNotEmpty) {
              artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
            }

            final coverUrl = (artwork != null && artwork.isNotEmpty)
                ? artwork
                : CoverService.defaultMusicCover;

            albums.add(Song(
              id: 'sc_album_$albumId',
              videoId: 'sc_playlist:$albumId',
              title: title,
              artist: artist,
              coverUrl: coverUrl,
              type: 'Album',
            ));
          }
          if (albums.isNotEmpty) return albums;
        }
      } catch (e) {
        print('Error getting SoundCloud artist playlists by userId: $e');
      }
    }

    return searchAlbums(artistName, limit: 20);
  }

  /// Получить подробные данные артиста SoundCloud (аватарка, шапка/баннер, количество подписчиков)
  static Future<Map<String, dynamic>?> getArtistDetails(String artistId, String artistName) async {
    await _getClientId();
    var userId = artistId.startsWith('sc_user_') ? artistId.replaceFirst('sc_user_', '') : '';

    if (userId.isEmpty) {
      final artists = await searchArtists(artistName, limit: 1);
      if (artists.isNotEmpty && artists.first.id.startsWith('sc_user_')) {
        userId = artists.first.id.replaceFirst('sc_user_', '');
      }
    }

    if (userId.isNotEmpty) {
      try {
        final uri = Uri.parse(
          'https://api-v2.soundcloud.com/users/$userId?client_id=$clientId',
        );
        final response = await NetworkService.get(
          uri,
          headers: _headers,
          timeout: const Duration(seconds: 8),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          String avatar = data['avatar_url']?.toString() ?? '';
          if (avatar.isNotEmpty) {
            avatar = avatar.replaceAll('-large.jpg', '-t500x500.jpg').replaceAll('-large.png', '-t500x500.png');
          }

          String banner = '';
          final visuals = data['visuals']?['visuals'] as List? ?? [];
          if (visuals.isNotEmpty) {
            banner = visuals.first['visual_url']?.toString() ?? '';
          }
          if (banner.isEmpty && data['visual_url'] != null) {
            banner = data['visual_url'].toString();
          }

          if (banner.isNotEmpty) {
            banner = banner
                .replaceAll('-t200x50.', '-t2480x520.')
                .replaceAll('-t500x500.', '-t2480x520.')
                .replaceAll('-large.', '-t2480x520.');
          }

          final followersCount = data['followers_count'] as int? ?? 0;
          final followingsCount = data['followings_count'] as int? ?? 0;
          final username = data['username']?.toString() ?? artistName;

          return {
            'id': userId,
            'username': username,
            'avatarUrl': avatar,
            'bannerUrl': banner,
            'followersCount': followersCount,
            'followingsCount': followingsCount,
          };
        }
      } catch (e) {
        print('Error fetching SoundCloud user details: $e');
      }
    }

    return null;
  }

  /// Пакетная загрузка полных данных о треках по их ID (для работы с заглушками в плейлистах SoundCloud)
  static Future<List<Song>> fetchFullTracksByIds(List<String> trackIds) async {
    if (trackIds.isEmpty) return [];
    await _getClientId();

    final List<Song> songs = [];

    for (var i = 0; i < trackIds.length; i += 50) {
      final chunk = trackIds.sublist(i, i + 50 > trackIds.length ? trackIds.length : i + 50);
      final idsParam = chunk.join(',');

      try {
        final uri = Uri.parse(
          'https://api-v2.soundcloud.com/tracks?ids=$idsParam&client_id=$clientId',
        );

        final response = await NetworkService.get(
          uri,
          headers: _headers,
          timeout: const Duration(seconds: 10),
        );

        if (response.statusCode == 200) {
          final List items = jsonDecode(response.body) as List? ?? [];
          for (final item in items) {
            final trackId = item['id']?.toString() ?? '';
            if (trackId.isEmpty) continue;

            final title = item['title']?.toString() ?? 'Track';
            final user = item['user'] as Map<String, dynamic>?;
            final artist = user?['username']?.toString() ?? 'SoundCloud';

            String? artwork = item['artwork_url']?.toString();
            if (artwork != null && artwork.isNotEmpty) {
              artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
            } else {
              artwork = user?['avatar_url']?.toString();
              if (artwork != null && artwork.isNotEmpty) {
                artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
              }
            }

            final coverUrl = (artwork != null && artwork.isNotEmpty)
                ? artwork
                : CoverService.defaultMusicCover;

            final durationMs = item['duration'] as int? ?? 0;

            songs.add(Song(
              id: 'sc_$trackId',
              videoId: 'sc_stream:$trackId',
              title: title,
              artist: artist,
              coverUrl: coverUrl,
              duration: Duration(milliseconds: durationMs),
              type: 'song',
            ));
          }
        }
      } catch (e) {
        print('Error batch fetching SoundCloud tracks by IDs: $e');
      }
    }

    return songs;
  }

  /// Получение списка треков альбома SoundCloud по его ID
  static Future<List<Song>> getAlbumSongs(String rawAlbumId) async {
    var albumId = rawAlbumId;
    if (albumId.startsWith('sc_playlist:')) {
      albumId = albumId.replaceFirst('sc_playlist:', '');
    } else if (albumId.startsWith('sc_album_')) {
      albumId = albumId.replaceFirst('sc_album_', '');
    } else if (albumId.startsWith('sc_')) {
      albumId = albumId.replaceFirst('sc_', '');
    }

    if (albumId.isEmpty) return [];
    await _getClientId();

    try {
      final playlistUrl = Uri.parse(
        'https://api-v2.soundcloud.com/playlists/$albumId?client_id=$clientId',
      );

      final response = await NetworkService.get(
        playlistUrl,
        headers: _headers,
        timeout: const Duration(seconds: 10),
      );

      if (response.statusCode != 200) {
        print('SoundCloud playlist details failed: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      final rawTracks = data['tracks'] as List? ?? [];
      final trackIds = rawTracks
          .map((t) => t['id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();

      final songs = await fetchFullTracksByIds(trackIds);
      if (songs.isNotEmpty) return songs;
    } catch (e) {
      print('Error getting SoundCloud album songs: $e');
    }
    return [];
  }

  /// Разрешение прямого аудио-потока (HLS/MP3) по ID трека
  static Future<String?> getStreamUrl(String rawTrackId) async {
    var trackId = rawTrackId;
    if (trackId.startsWith('sc_stream:')) {
      trackId = trackId.replaceFirst('sc_stream:', '');
    } else if (trackId.startsWith('sc_')) {
      trackId = trackId.replaceFirst('sc_', '');
    } else if (trackId.startsWith('soundcloud:')) {
      trackId = trackId.replaceFirst('soundcloud:', '');
    }

    if (trackId.isEmpty) return null;
    await _getClientId();

    try {
      final trackUrl = Uri.parse(
        'https://api-v2.soundcloud.com/tracks/$trackId?client_id=$clientId',
      );

      final response = await NetworkService.get(
        trackUrl,
        headers: _headers,
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) {
        print('SoundCloud track details failed: ${response.statusCode}');
        return null;
      }

      final trackData = jsonDecode(response.body);

      // Check if SoundCloud track is restricted to a 30-second snippet (Go+ / Snippet track)
      final fullDur = trackData['full_duration'] as int? ?? 0;
      final dur = trackData['duration'] as int? ?? 0;
      final policy = trackData['policy']?.toString() ?? '';
      final access = trackData['access']?.toString() ?? '';
      final isSnipped = trackData['snipped'] == true ||
          policy == 'SNIP' ||
          policy == 'BLOCK' ||
          access == 'preview' ||
          (fullDur > 0 && dur > 0 && fullDur > dur + 5000);

      if (isSnipped) {
        final title = trackData['title']?.toString() ?? '';
        final user = trackData['user'] as Map<String, dynamic>?;
        final artist = user?['username']?.toString() ?? '';
        print('⚠️ SoundCloud track ($trackId) is a 30s snippet. Redirecting to full MP3 search for: $artist - $title');
        if (artist.isNotEmpty || title.isNotEmpty) {
          final fullUrl = await PirateService.getStreamUrl("pirate:search:$artist - $title");
          if (fullUrl != null && fullUrl.isNotEmpty) {
            return fullUrl;
          }
        }
      }

      final transcodings =
          trackData['media']?['transcodings'] as List? ?? [];

      if (transcodings.isEmpty) return null;

      Map<String, dynamic>? selectedTranscoding;

      for (final t in transcodings) {
        final format = t['format'] as Map<String, dynamic>?;
        final protocol = format?['protocol']?.toString();
        if (protocol == 'progressive') {
          selectedTranscoding = t as Map<String, dynamic>;
          break;
        }
      }

      selectedTranscoding ??= transcodings.firstWhere(
        (t) => (t['format']?['protocol']?.toString() == 'hls'),
        orElse: () => transcodings.first,
      ) as Map<String, dynamic>?;

      final streamApiUrl = selectedTranscoding?['url']?.toString();
      if (streamApiUrl == null || streamApiUrl.isEmpty) return null;

      final finalStreamUrl = Uri.parse('$streamApiUrl?client_id=$clientId');
      final streamResponse = await NetworkService.get(
        finalStreamUrl,
        headers: _headers,
        timeout: const Duration(seconds: 8),
      );

      if (streamResponse.statusCode == 200) {
        final streamData = jsonDecode(streamResponse.body);
        final directUrl = streamData['url']?.toString();
        if (directUrl != null && directUrl.isNotEmpty) {
          print('⚡ SoundCloud stream URL successfully resolved: $directUrl');
          return directUrl;
        }
      }
    } catch (e) {
      print('Error resolving SoundCloud stream URL: $e');
    }
    return null;
  }

  /// Lightweight metadata fetch — returns {artist, title} for a SoundCloud track ID.
  /// Used by PirateService when SoundCloud stream resolution fails and we need a
  /// meaningful search query for fallback MP3 scrapers.
  static Future<Map<String, String>?> getTrackMeta(String rawTrackId) async {
    var trackId = rawTrackId;
    if (trackId.startsWith('sc_stream:')) {
      trackId = trackId.replaceFirst('sc_stream:', '');
    } else if (trackId.startsWith('sc_')) {
      trackId = trackId.replaceFirst('sc_', '');
    } else if (trackId.startsWith('soundcloud:')) {
      trackId = trackId.replaceFirst('soundcloud:', '');
    }
    if (trackId.isEmpty) return null;
    await _getClientId();

    try {
      final trackUrl = Uri.parse(
        'https://api-v2.soundcloud.com/tracks/$trackId?client_id=$clientId',
      );
      final response = await NetworkService.get(
        trackUrl,
        headers: _headers,
        timeout: const Duration(seconds: 6),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final title = data['title']?.toString() ?? '';
        final user = data['user'] as Map<String, dynamic>?;
        final artist = user?['username']?.toString() ?? '';
        if (title.isNotEmpty || artist.isNotEmpty) {
          return {'title': title, 'artist': artist};
        }
      }
    } catch (e) {
      print('Error fetching SoundCloud track meta: $e');
    }
    return null;
  }

  /// Надежное раскрытие коротких ссылок on.soundcloud.com в канонические ссылки soundcloud.com
  static Future<String> expandShortUrl(String shortUrl) async {
    var targetUrl = shortUrl.trim();
    if (!targetUrl.contains('on.soundcloud.com')) return targetUrl;

    // Способ 1: dart:io HttpClient — следуем цепочке редиректов вручную (до 10 хопов)
    try {
      final ioClient = HttpClient();
      ioClient.connectionTimeout = const Duration(seconds: 8);
      var currentUrl = targetUrl;

      for (var i = 0; i < 10; i++) {
        final request = await ioClient.getUrl(Uri.parse(currentUrl));
        request.followRedirects = false;
        request.headers.set('User-Agent', _headers['User-Agent']!);
        final response = await request.close();

        if (response.statusCode == 301 ||
            response.statusCode == 302 ||
            response.statusCode == 303 ||
            response.statusCode == 307 ||
            response.statusCode == 308) {
          final location = response.headers.value('location');
          await response.drain<void>();
          if (location != null && location.isNotEmpty) {
            // Относительный редирект
            if (location.startsWith('/')) {
              final uri = Uri.parse(currentUrl);
              currentUrl = '${uri.scheme}://${uri.host}$location';
            } else {
              currentUrl = location;
            }
            print('🔗 Redirect hop ${i + 1}: $currentUrl');
            // Если мы уже получили soundcloud.com URL — выходим
            if (currentUrl.contains('soundcloud.com/') && !currentUrl.contains('on.soundcloud.com')) {
              targetUrl = currentUrl;
              break;
            }
          } else {
            await response.drain<void>();
            break;
          }
        } else {
          // Если 200 — проверяем, может в body есть canonical
          if (response.statusCode == 200) {
            final body = await response.transform(const SystemEncoding().decoder).join();
            final canonicalMatch = RegExp(r'<link[^>]+rel="canonical"[^>]+href="([^"]+)"').firstMatch(body);
            if (canonicalMatch != null) {
              currentUrl = canonicalMatch.group(1)!;
              print('🔗 Resolved via canonical tag (dart:io): $currentUrl');
              if (!currentUrl.contains('on.soundcloud.com')) {
                targetUrl = currentUrl;
              }
            } else {
              final ogMatch = RegExp(r'<meta[^>]+property="og:url"[^>]+content="([^"]+)"').firstMatch(body);
              if (ogMatch != null) {
                currentUrl = ogMatch.group(1)!;
                print('🔗 Resolved via og:url (dart:io): $currentUrl');
                if (!currentUrl.contains('on.soundcloud.com')) {
                  targetUrl = currentUrl;
                }
              }
            }
          } else {
            await response.drain<void>();
          }
          break;
        }
      }
      ioClient.close(force: true);
    } catch (e) {
      print('Error expanding short SoundCloud URL (dart:io): $e');
    }

    // Способ 2: Если dart:io не сработал, пробуем GET с автоматическими редиректами + парсим HTML
    if (targetUrl.contains('on.soundcloud.com')) {
      try {
        final res = await NetworkService.get(
          Uri.parse(targetUrl),
          headers: _headers,
          timeout: const Duration(seconds: 10),
        );
        final bodyText = res.body;
        // Парсим HTML на предмет canonical или og:url
        final canonicalMatch = RegExp(r'<link[^>]+rel="canonical"[^>]+href="([^"]+)"').firstMatch(bodyText);
        if (canonicalMatch != null) {
          targetUrl = canonicalMatch.group(1)!;
          print('🔗 Resolved via canonical tag (http): $targetUrl');
        } else {
          final ogMatch = RegExp(r'<meta[^>]+property="og:url"[^>]+content="([^"]+)"').firstMatch(bodyText);
          if (ogMatch != null) {
            targetUrl = ogMatch.group(1)!;
            print('🔗 Resolved via og:url tag (http): $targetUrl');
          }
        }
        // Пробуем найти URL в window.__sc_hydration или JS-редиректе
        if (targetUrl.contains('on.soundcloud.com')) {
          final urlMatch = RegExp(r'https://soundcloud\.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+(?:/[a-zA-Z0-9_-]+)?').firstMatch(bodyText);
          if (urlMatch != null) {
            targetUrl = urlMatch.group(0)!;
            print('🔗 Resolved via body URL match: $targetUrl');
          }
        }
      } catch (e) {
        print('Error expanding short SoundCloud URL (http fallback): $e');
      }
    }

    // Способ 3: SoundCloud oEmbed API — принимает короткие ссылки напрямую
    if (targetUrl.contains('on.soundcloud.com')) {
      try {
        final oEmbedUri = Uri.parse(
          'https://soundcloud.com/oembed?format=json&url=${Uri.encodeComponent(shortUrl.trim())}',
        );
        final res = await NetworkService.get(
          oEmbedUri,
          headers: _headers,
          timeout: const Duration(seconds: 10),
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          // oEmbed ответ содержит поле "author_url" (профиль) и HTML с iframe src
          final html = data['html']?.toString() ?? '';
          final srcMatch = RegExp(r'src="https://w\.soundcloud\.com/player/\?url=(https%3A[^&"]+)').firstMatch(html);
          if (srcMatch != null) {
            targetUrl = Uri.decodeComponent(srcMatch.group(1)!);
            print('🔗 Resolved via oEmbed API: $targetUrl');
          }
        }
      } catch (e) {
        print('Error expanding via oEmbed: $e');
      }
    }

    // Нормализация URL
    targetUrl = targetUrl.replaceAll('m.soundcloud.com', 'soundcloud.com');
    if (targetUrl.contains('?')) {
      targetUrl = targetUrl.split('?')[0];
    }

    print('🔗 Final expanded URL: $targetUrl');
    return targetUrl;
  }

  /// Импорт / Разрешение ссылки SoundCloud (короткие ссылки on.soundcloud.com, треки, плейлисты, артисты)
  static Future<Map<String, dynamic>?> resolveUrl(String url) async {
    var targetUrl = url.trim();
    if (!targetUrl.contains('soundcloud.com')) return null;
    await _getClientId();

    try {
      if (targetUrl.contains('on.soundcloud.com')) {
        targetUrl = await expandShortUrl(targetUrl);
      }

      // Нормализация URL
      targetUrl = targetUrl.replaceAll('m.soundcloud.com', 'soundcloud.com');
      // Убираем query параметры (?si=, ?utm_, и т.д.)
      if (targetUrl.contains('?')) {
        targetUrl = targetUrl.split('?')[0];
      }
      // Убираем trailing slash
      if (targetUrl.endsWith('/')) {
        targetUrl = targetUrl.substring(0, targetUrl.length - 1);
      }
      // Убираем якори
      if (targetUrl.contains('#')) {
        targetUrl = targetUrl.split('#')[0];
      }

      print('🔍 SoundCloud resolving URL: $targetUrl');

      final resolveUri = Uri.parse(
        'https://api-v2.soundcloud.com/resolve?url=${Uri.encodeComponent(targetUrl)}&client_id=$clientId',
      );

      final response = await NetworkService.get(
        resolveUri,
        headers: _headers,
        timeout: const Duration(seconds: 10),
      );

      if (response.statusCode != 200) {
        print('SoundCloud URL resolve failed for $targetUrl: ${response.statusCode} | body: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
        return null;
      }

      final data = jsonDecode(response.body);
      final kind = data['kind']?.toString();

      if (kind == 'track') {
        final trackId = data['id']?.toString() ?? '';
        final title = data['title']?.toString() ?? 'Track';
        final user = data['user'] as Map<String, dynamic>?;
        final artist = user?['username']?.toString() ?? 'SoundCloud';
        String? artwork = data['artwork_url']?.toString();
        if (artwork != null && artwork.isNotEmpty) {
          artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
        } else {
          artwork = user?['avatar_url']?.toString();
          if (artwork != null && artwork.isNotEmpty) {
            artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
          }
        }
        final coverUrl = (artwork != null && artwork.isNotEmpty)
            ? artwork
            : CoverService.defaultMusicCover;

        final song = Song(
          id: 'sc_$trackId',
          videoId: 'sc_stream:$trackId',
          title: title,
          artist: artist,
          coverUrl: coverUrl,
          duration: Duration(milliseconds: data['duration'] as int? ?? 0),
        );

        return {
          'type': 'track',
          'song': song,
        };
      } else if (kind == 'playlist') {
        final playlistTitle = data['title']?.toString() ?? 'SoundCloud Playlist';
        final rawTracks = data['tracks'] as List? ?? [];
        final trackIds = rawTracks
            .map((t) => t['id']?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .cast<String>()
            .toList();

        List<Song> songs = await fetchFullTracksByIds(trackIds);

        // Fallback если пакетная загрузка не вернула результат
        if (songs.isEmpty) {
          for (final item in rawTracks) {
            final trackId = item['id']?.toString() ?? '';
            if (trackId.isEmpty) continue;
            final title = item['title']?.toString() ?? 'Unknown Track';
            final user = item['user'] as Map<String, dynamic>?;
            final artist = user?['username']?.toString() ?? 'SoundCloud';
            String? artwork = item['artwork_url']?.toString();
            if (artwork != null && artwork.isNotEmpty) {
              artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
            }
            final coverUrl = (artwork != null && artwork.isNotEmpty)
                ? artwork
                : CoverService.defaultMusicCover;

            songs.add(Song(
              id: 'sc_$trackId',
              videoId: 'sc_stream:$trackId',
              title: title,
              artist: artist,
              coverUrl: coverUrl,
              duration: Duration(milliseconds: item['duration'] as int? ?? 0),
            ));
          }
        }

        return {
          'type': 'playlist',
          'title': playlistTitle,
          'songs': songs,
        };
      } else if (kind == 'user') {
        final userId = data['id']?.toString() ?? '';
        final username = data['username']?.toString() ?? 'Артист SoundCloud';
        if (userId.isNotEmpty) {
          final userTracksUri = Uri.parse(
            'https://api-v2.soundcloud.com/users/$userId/tracks?client_id=$clientId&limit=35',
          );
          final tracksResponse = await NetworkService.get(
            userTracksUri,
            headers: _headers,
            timeout: const Duration(seconds: 10),
          );

          if (tracksResponse.statusCode == 200) {
            final tracksData = jsonDecode(tracksResponse.body);
            final collection = tracksData['collection'] as List? ?? [];

            final List<Song> songs = [];
            for (final item in collection) {
              final trackId = item['id']?.toString() ?? '';
              if (trackId.isEmpty) continue;

              final title = item['title']?.toString() ?? 'Unknown Track';
              final user = item['user'] as Map<String, dynamic>?;
              final artist = user?['username']?.toString() ?? username;

              String? artwork = item['artwork_url']?.toString();
              if (artwork != null && artwork.isNotEmpty) {
                artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
              } else {
                artwork = user?['avatar_url']?.toString();
                if (artwork != null && artwork.isNotEmpty) {
                  artwork = artwork.replaceAll('-large.jpg', '-t500x500.jpg');
                }
              }

              final coverUrl = (artwork != null && artwork.isNotEmpty)
                  ? artwork
                  : CoverService.defaultMusicCover;

              songs.add(Song(
                id: 'sc_$trackId',
                videoId: 'sc_stream:$trackId',
                title: title,
                artist: artist,
                coverUrl: coverUrl,
                duration: Duration(milliseconds: item['duration'] as int? ?? 0),
              ));
            }

            return {
              'type': 'playlist',
              'title': 'Треки $username',
              'songs': songs,
            };
          }
        }
      }
    } catch (e) {
      print('Error resolving SoundCloud URL: $e');
    }
    return null;
  }
}

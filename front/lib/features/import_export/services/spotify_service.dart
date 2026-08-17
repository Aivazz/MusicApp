import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ses/core/network/network_service.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/core/utils/cover_service.dart';

class SpotifyService {
  // CONFIGURATION: Вставьте ваши ключи от Spotify Developer Dashboard сюда
  // Вы можете бесплатно зарегистрировать их на https://developer.spotify.com/
  static const String clientId = ''; // Deprecated, using anonymous player token
  static const String clientSecret = ''; // Deprecated, using anonymous player token

  static String lastError = '';
  static String? _accessToken;
  static DateTime? _tokenExpiry;

  static bool get isConfigured => true;

  static Future<http.Response> _getWithProxy(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final proxyUrl = Uri.parse('https://corsproxy.io/?${Uri.encodeComponent(url)}');
      final res = await NetworkService.get(proxyUrl, headers: headers, timeout: timeout);
      if (res.statusCode == 200) {
        return res;
      }
      print("Proxy fetch returned status ${res.statusCode}, trying direct connection.");
    } catch (e) {
      print("Proxy fetch failed: $e, trying direct connection.");
    }

    return await NetworkService.get(Uri.parse(url), headers: headers, timeout: timeout);
  }

  static Future<String?> _getAccessToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken;
    }

    try {
      lastError = 'Fetching cookies from open.spotify.com...';
      // 1. Visit homepage to get cookies
      final homeResponse = await _getWithProxy(
        'https://open.spotify.com/',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
        },
        timeout: const Duration(seconds: 10),
      );

      String? cookieHeader;
      if (homeResponse.headers.containsKey('set-cookie')) {
        final rawCookies = homeResponse.headers['set-cookie']!;
        final cookies = rawCookies.split(RegExp(r',(?=[^;]*=)'))
            .map((c) => c.split(';').first.trim())
            .join('; ');
        cookieHeader = cookies;
      } else {
        final key = homeResponse.headers.keys.firstWhere(
          (k) => k.toLowerCase() == 'set-cookie',
          orElse: () => '',
        );
        if (key.isNotEmpty) {
          final rawCookies = homeResponse.headers[key]!;
          final cookies = rawCookies.split(RegExp(r',(?=[^;]*=)'))
              .map((c) => c.split(';').first.trim())
              .join('; ');
          cookieHeader = cookies;
        }
      }

      lastError = 'Requesting anonymous token...';
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
        'Accept': 'application/json',
        'Referer': 'https://open.spotify.com/',
      };
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        headers['Cookie'] = cookieHeader;
      }

      final response = await _getWithProxy(
        'https://open.spotify.com/get_access_token?reason=transport&productType=web_player',
        headers: headers,
        timeout: const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['accessToken'];
        final expMs = data['accessTokenExpirationTimestampMs'] as int?;
        if (expMs != null) {
          _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(expMs - 60000);
        } else {
          _tokenExpiry = DateTime.now().add(const Duration(minutes: 50));
        }
        lastError = '';
        return _accessToken;
      } else {
        lastError = 'Auth HTTP ${response.statusCode}: ${response.body}';
        print("Spotify anonymous auth failed: ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      lastError = 'Auth Exception: $e';
      print("Error fetching Spotify anonymous token: $e");
    }
    return null;
  }

  static Future<List<Song>> search(String query, {int offset = 0, int limit = 35}) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    try {
      final response = await NetworkService
          .get(
            Uri.parse(
              'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=track&limit=$limit&offset=$offset',
            ),
            headers: {'Authorization': 'Bearer $token'},
            timeout: const Duration(seconds: 6),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['tracks']?['items'] as List? ?? [];
        return items.map((item) {
          final title = item['name'] ?? 'Unknown';
          final artist =
              (item['artists'] as List?)?.map((a) => a['name']).join(', ') ??
              'Unknown';
          final images = item['album']?['images'] as List? ?? [];
          final coverUrl = images.isNotEmpty
              ? images[0]['url']?.toString() ?? ''
              : '';
          final durationMs = item['duration_ms'] as int? ?? 0;

          // Используем специальную схему search: для фонового разрешения стрима
          final queryId = "pirate:search:${artist} - ${title}";

          return Song(
            id: item['id'] ?? '',
            title: title,
            artist: artist,
            coverUrl: coverUrl,
            duration: Duration(milliseconds: durationMs),
            videoId: queryId,
          );
        }).toList();
      }
    } catch (e) {
      print("Error searching Spotify tracks: $e");
    }
    return [];
  }

  static Future<List<Song>> searchArtists(String query) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    try {
      final response = await NetworkService
          .get(
            Uri.parse(
              'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=artist&limit=5',
            ),
            headers: {'Authorization': 'Bearer $token'},
            timeout: const Duration(seconds: 6),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['artists']?['items'] as List? ?? [];
        return items.map((item) {
          final id = item['id'] ?? '';
          final name = item['name'] ?? 'Unknown';
          final images = item['images'] as List? ?? [];
          final coverUrl = images.isNotEmpty
              ? images[0]['url']?.toString() ?? ''
              : '';

          return Song(
            id: id,
            title: name,
            artist: 'Artist',
            coverUrl: coverUrl,
            duration: Duration.zero,
            videoId: '',
            type: 'artist',
          );
        }).toList();
      }
    } catch (e) {
      print("Error searching Spotify artists: $e");
    }
    return [];
  }

  static Future<List<Song>> searchAlbums(String query) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    try {
      final response = await NetworkService
          .get(
            Uri.parse(
              'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=album&limit=10',
            ),
            headers: {'Authorization': 'Bearer $token'},
            timeout: const Duration(seconds: 6),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['albums']?['items'] as List? ?? [];
        return items.map((item) {
          final id = item['id'] ?? '';
          final name = item['name'] ?? 'Unknown';
          final artist =
              (item['artists'] as List?)?.map((a) => a['name']).join(', ') ??
              'Unknown';
          final images = item['images'] as List? ?? [];
          final coverUrl = images.isNotEmpty
              ? images[0]['url']?.toString() ?? ''
              : '';

          return Song(
            id: id,
            title: name,
            artist: artist,
            coverUrl: coverUrl,
            duration: Duration.zero,
            videoId: '',
            type: 'Album',
          );
        }).toList();
      }
    } catch (e) {
      print("Error searching Spotify albums: $e");
    }
    return [];
  }

  static Future<List<Song>> searchMixed(String query, {int offset = 0, int limit = 35}) async {
    if (offset == 0) {
      final results = await Future.wait([
        searchArtists(query),
        search(query, offset: offset, limit: limit),
      ]);
      return [...results[0], ...results[1]];
    } else {
      return await search(query, offset: offset, limit: limit);
    }
  }

  static Future<List<Song>> getArtistSongs(String artistId) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    try {
      final response = await NetworkService
          .get(
            Uri.parse(
              'https://api.spotify.com/v1/artists/$artistId/top-tracks?market=US',
            ),
            headers: {'Authorization': 'Bearer $token'},
            timeout: const Duration(seconds: 6),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['tracks'] as List? ?? [];
        return items.map((item) {
          final title = item['name'] ?? 'Unknown';
          final artist =
              (item['artists'] as List?)?.map((a) => a['name']).join(', ') ??
              'Unknown';
          final images = item['album']?['images'] as List? ?? [];
          final coverUrl = images.isNotEmpty
              ? images[0]['url']?.toString() ?? ''
              : '';
          final durationMs = item['duration_ms'] as int? ?? 0;

          return Song(
            id: item['id'] ?? '',
            title: title,
            artist: artist,
            coverUrl: coverUrl,
            duration: Duration(milliseconds: durationMs),
            videoId: "pirate:search:${artist} - ${title}",
          );
        }).toList();
      }
    } catch (e) {
      print("Error getting Spotify artist top tracks: $e");
    }
    return [];
  }

  static Future<List<Song>> getArtistAlbums(String artistId) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    try {
      final response = await NetworkService
          .get(
            Uri.parse(
              'https://api.spotify.com/v1/artists/$artistId/albums?limit=20&include_groups=album,single',
            ),
            headers: {'Authorization': 'Bearer $token'},
            timeout: const Duration(seconds: 6),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List? ?? [];
        return items.map((item) {
          final id = item['id'] ?? '';
          final name = item['name'] ?? 'Unknown';
          final artist =
              (item['artists'] as List?)?.map((a) => a['name']).join(', ') ??
              'Unknown';
          final images = item['images'] as List? ?? [];
          final coverUrl = images.isNotEmpty
              ? images[0]['url']?.toString() ?? ''
              : '';

          return Song(
            id: id,
            title: name,
            artist: artist,
            coverUrl: coverUrl,
            duration: Duration.zero,
            videoId: '',
            type: 'Album',
          );
        }).toList();
      }
    } catch (e) {
      print("Error getting Spotify artist albums: $e");
    }
    return [];
  }

  static Future<Map<String, dynamic>?> getArtistDetails(String artistId) async {
    final token = await _getAccessToken();
    if (token == null) return null;

    try {
      final response = await NetworkService.get(
        Uri.parse('https://api.spotify.com/v1/artists/$artistId'),
        headers: {'Authorization': 'Bearer $token'},
        timeout: const Duration(seconds: 6),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Error getting Spotify artist details: $e");
    }
    return null;
  }

  static Future<List<Song>> getAlbumSongs(
    String albumId, {
    String? coverUrl,
  }) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    try {
      final response = await NetworkService
          .get(
            Uri.parse('https://api.spotify.com/v1/albums/$albumId'),
            headers: {'Authorization': 'Bearer $token'},
            timeout: const Duration(seconds: 6),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tracksItems = data['tracks']?['items'] as List? ?? [];
        final albumCover =
            coverUrl ??
            (data['images'] as List?)?.first['url']?.toString() ??
            '';

        return tracksItems.map((item) {
          final title = item['name'] ?? 'Unknown';
          final artist =
              (item['artists'] as List?)?.map((a) => a['name']).join(', ') ??
              'Unknown';
          final durationMs = item['duration_ms'] as int? ?? 0;

          return Song(
            id: item['id'] ?? '',
            title: title,
            artist: artist,
            coverUrl: albumCover,
            duration: Duration(milliseconds: durationMs),
            videoId: "pirate:search:${artist} - ${title}",
          );
        }).toList();
      }
    } catch (e) {
      print("Error getting Spotify album songs: $e");
    }
    return [];
  }

  /// Получает данные плейлиста через scraping embed-страницы Spotify.
  /// Не требует API-токена — работает даже при блокировке api.spotify.com.
  static Future<Map<String, dynamic>?> getPlaylistDetails(String playlistId) async {
    try {
      lastError = 'Загрузка embed-страницы Spotify...';

      final embedUrl = 'https://open.spotify.com/embed/playlist/$playlistId';
      final response = await NetworkService.get(
        Uri.parse(embedUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode != 200) {
        lastError = 'Embed HTTP ${response.statusCode}';
        return null;
      }

      // Извлекаем JSON из <script id="__NEXT_DATA__">
      final scriptMatch = RegExp(
        r'<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>',
        dotAll: true,
      ).firstMatch(response.body);

      if (scriptMatch == null) {
        lastError = 'Не найден __NEXT_DATA__ в HTML';
        return null;
      }

      final nextData = jsonDecode(scriptMatch.group(1)!);
      final entity = nextData['props']?['pageProps']?['state']?['data']?['entity'];

      if (entity == null) {
        lastError = 'Не найден entity в данных';
        return null;
      }

      final name = entity['name']?.toString() ?? 'Spotify Playlist';

      // Обложка плейлиста
      final coverSources = entity['coverArt']?['sources'] as List? ?? [];
      final coverUrl = coverSources.isNotEmpty
          ? coverSources[0]['url']?.toString() ?? ''
          : '';

      // Треки
      final trackList = entity['trackList'] as List? ?? [];
      final List<Song> songs = [];

      for (final track in trackList) {
        final title = track['title']?.toString() ?? 'Unknown';
        final artist = track['subtitle']?.toString() ?? 'Unknown';
        final durationMs = track['duration'] as int? ?? 0;
        final uri = track['uri']?.toString() ?? '';
        // Извлекаем Spotify track ID из URI (spotify:track:XXXX)
        final trackId = uri.contains(':') ? uri.split(':').last : '';

        songs.add(Song(
          id: trackId.isNotEmpty ? trackId : 'sp_${songs.length}',
          title: title,
          artist: artist,
          coverUrl: CoverService.defaultMusicCover, // Устанавливаем дефолтную обложку для динамического фонового резолвинга
          duration: Duration(milliseconds: durationMs),
          videoId: "pirate:search:$artist - $title",
        ));
      }

      lastError = '';
      return {
        'name': name,
        'coverUrl': coverUrl,
        'songs': songs,
      };
    } catch (e) {
      lastError = 'Ошибка парсинга: $e';
      print("Error scraping Spotify embed page: $e");
    }
    return null;
  }

  static Future<Song?> getTrackDetails(String trackId) async {
    final token = await _getAccessToken();
    if (token == null) return null;

    try {
      final response = await NetworkService.get(
        Uri.parse('https://api.spotify.com/v1/tracks/$trackId'),
        headers: {'Authorization': 'Bearer $token'},
        timeout: const Duration(seconds: 6),
      );

      if (response.statusCode == 200) {
        final item = jsonDecode(response.body);
        final title = item['name'] ?? 'Unknown';
        final artist = (item['artists'] as List?)?.map((a) => a['name']).join(', ') ?? 'Unknown';
        final images = item['album']?['images'] as List? ?? [];
        final coverUrl = images.isNotEmpty ? images[0]['url']?.toString() ?? '' : '';
        final durationMs = item['duration_ms'] as int? ?? 0;

        return Song(
          id: item['id'] ?? '',
          title: title,
          artist: artist,
          coverUrl: coverUrl,
          duration: Duration(milliseconds: durationMs),
          videoId: "pirate:search:$artist - $title",
        );
      } else {
        lastError = 'Track API HTTP ${response.statusCode}';
      }
    } catch (e) {
      lastError = 'Track API Exception: $e';
      print("Error getting Spotify track details: $e");
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getAlbumDetails(String albumId) async {
    final token = await _getAccessToken();
    if (token == null) return null;

    try {
      final response = await NetworkService.get(
        Uri.parse('https://api.spotify.com/v1/albums/$albumId'),
        headers: {'Authorization': 'Bearer $token'},
        timeout: const Duration(seconds: 6),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final name = data['name'] ?? 'Unknown Album';
        final artist = (data['artists'] as List?)?.map((a) => a['name']).join(', ') ?? 'Unknown';
        final images = data['images'] as List? ?? [];
        final coverUrl = images.isNotEmpty ? images[0]['url']?.toString() ?? '' : '';

        final tracksItems = data['tracks']?['items'] as List? ?? [];
        final List<Song> songs = tracksItems.map((item) {
          final title = item['name'] ?? 'Unknown';
          final trackArtist = (item['artists'] as List?)?.map((a) => a['name']).join(', ') ?? artist;
          final durationMs = item['duration_ms'] as int? ?? 0;

          return Song(
            id: item['id'] ?? '',
            title: title,
            artist: trackArtist,
            coverUrl: coverUrl,
            duration: Duration(milliseconds: durationMs),
            videoId: "pirate:search:$trackArtist - $title",
          );
        }).toList();

        lastError = '';
        return {
          'name': name,
          'artist': artist,
          'coverUrl': coverUrl,
          'songs': songs,
        };
      } else {
        lastError = 'Album API HTTP ${response.statusCode}';
      }
    } catch (e) {
      lastError = 'Album API Exception: $e';
      print("Error getting Spotify album details: $e");
    }
    return null;
  }
}

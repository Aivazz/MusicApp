import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/import_export/services/pirate_service.dart';
import 'package:ses/features/import_export/services/spotify_service.dart';
import 'package:ses/features/import_export/services/soundcloud_service.dart';

class SearchService {
  static final Map<String, List<Song>> _cache = {};
  static const int _maxCacheSize = 100;

  static final _cyrillicToLatinMap = <String, String>{
    'а': 'a', 'ә': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'ғ': 'g',
    'д': 'd', 'е': 'e', 'ё': 'yo', 'ж': 'zh', 'з': 'z', 'и': 'i',
    'й': 'y', 'к': 'k', 'қ': 'q', 'л': 'l', 'м': 'm', 'н': 'n',
    'ң': 'n', 'о': 'o', 'ө': 'o', 'п': 'p', 'р': 'r', 'с': 's',
    'т': 't', 'у': 'u', 'ұ': 'u', 'ү': 'u', 'ф': 'f', 'х': 'kh',
    'һ': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
    'ъ': '', 'ы': 'y', 'і': 'i', 'ь': '', 'э': 'e', 'ю': 'yu',
    'я': 'ya',
  };

  static String _normalizeQuery(String query) {
    return query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _transliterate(String text) {
    final lower = text.toLowerCase();
    final buf = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      buf.write(_cyrillicToLatinMap[ch] ?? ch);
    }
    return buf.toString();
  }

  static bool _hasCyrillic(String text) => RegExp(r'[\u0400-\u04FF]').hasMatch(text);

  static List<Song> _sortByRelevance(List<Song> songs, String rawQuery) {
    final q = _normalizeQuery(rawQuery);
    if (q.isEmpty) return songs;

    final exactOrPrefixArtist = <Song>[];
    final exactOrPrefixTitle = <Song>[];
    final containsQuery = <Song>[];
    final others = <Song>[];

    for (var song in songs) {
      final artistLower = song.artist.toLowerCase();
      final titleLower = song.title.toLowerCase();

      if (artistLower == q || artistLower.startsWith(q)) {
        exactOrPrefixArtist.add(song);
      } else if (titleLower == q || titleLower.startsWith(q)) {
        exactOrPrefixTitle.add(song);
      } else if (artistLower.contains(q) || titleLower.contains(q)) {
        containsQuery.add(song);
      } else {
        others.add(song);
      }
    }

    return [...exactOrPrefixArtist, ...exactOrPrefixTitle, ...containsQuery, ...others];
  }

  static String _cacheKey(String query, int offset, int limit) =>
      '${_normalizeQuery(query)}_${offset}_$limit';

  static List<Song>? getCachedMixed(String query, {int offset = 0, int limit = 35}) {
    final key = _cacheKey(query, offset, limit);
    return _cache[key];
  }

  static void _addToCache(String key, List<Song> results) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = results;
  }

  static void _preResolveResults(List<Song> songs) {
    final list = songs.where((s) => s.type == 'song').take(3).toList();
    for (var song in list) {
      if (!song.videoId.startsWith('http')) {
        PirateService.getStreamUrl(song.videoId).then((resolved) {
          if (resolved != null && resolved.isNotEmpty) {
            song.videoId = resolved;
          }
        }).catchError((_) {});
      }
    }
  }

  static Future<List<Song>> search(String query, {int offset = 0, int limit = 35}) async {
    final clean = _normalizeQuery(query);
    if (clean.isEmpty) return [];

    try {
      final spotifyResults = await SpotifyService.search(clean, offset: offset, limit: limit);
      if (spotifyResults.isNotEmpty) {
        final sorted = _sortByRelevance(spotifyResults, clean);
        _preResolveResults(sorted);
        return sorted;
      }
    } catch (e) {
      print("Spotify search failed, falling back to PirateService: $e");
    }

    if (offset == 0) {
      final results = await PirateService.search(clean);
      final songs = results.where((s) => s.type == 'song').toList();
      final sorted = _sortByRelevance(songs, clean);
      _preResolveResults(sorted);
      return sorted;
    }
    return [];
  }

  static Future<List<Song>> searchArtists(String query) async {
    final clean = _normalizeQuery(query);
    if (clean.isEmpty) return [];
    try {
      final sc = await SoundcloudService.searchArtists(clean);
      if (sc.isNotEmpty) return sc;
      return await SpotifyService.searchArtists(clean);
    } catch (_) {}
    return [];
  }

  static Future<List<Song>> searchAlbums(String query, {int offset = 0, int limit = 20}) async {
    final clean = _normalizeQuery(query);
    if (clean.isEmpty) return [];
    try {
      final sc = await SoundcloudService.searchAlbums(clean, offset: offset, limit: limit);
      if (sc.isNotEmpty) return sc;
      return await SpotifyService.searchAlbums(clean);
    } catch (_) {}
    return [];
  }

  static Future<List<Song>> searchPlaylists(String query, {int offset = 0, int limit = 20}) async {
    final clean = _normalizeQuery(query);
    if (clean.isEmpty) return [];
    try {
      return await SoundcloudService.searchPlaylists(clean, offset: offset, limit: limit);
    } catch (_) {}
    return [];
  }

  static Future<List<Song>> getAlbumSongs(String albumId, {String? coverUrl}) async {
    if (albumId.startsWith('sc_') || albumId.startsWith('soundcloud:')) {
      final scSongs = await SoundcloudService.getPlaylistSongs(albumId);
      if (scSongs.isNotEmpty) {
        _preResolveResults(scSongs);
        return scSongs;
      }
    }

    try {
      final spotifyResults = await SpotifyService.getAlbumSongs(albumId, coverUrl: coverUrl);
      if (spotifyResults.isNotEmpty) {
        _preResolveResults(spotifyResults);
        return spotifyResults;
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Song>> searchMixed(String query, {int offset = 0, int limit = 35}) async {
    final cleanQuery = _normalizeQuery(query);
    if (cleanQuery.isEmpty) return [];

    // 🌟 Обработка прямых ссылок SoundCloud
    if (cleanQuery.contains('soundcloud.com')) {
      try {
        final resolved = await SoundcloudService.resolveUrl(cleanQuery);
        if (resolved != null) {
          if (resolved['type'] == 'track' && resolved['song'] != null) {
            return [resolved['song'] as Song];
          } else if (resolved['type'] == 'playlist' && resolved['songs'] != null) {
            return List<Song>.from(resolved['songs']);
          }
        }
      } catch (e) {
        print("Error resolving SoundCloud URL link: $e");
      }
    }

    final key = _cacheKey(cleanQuery, offset, limit);
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    List<Song> results = [];
    try {
      final futures = await Future.wait([
        SoundcloudService.search(cleanQuery, offset: offset, limit: limit).catchError((_) => <Song>[]),
        offset == 0
            ? SoundcloudService.searchArtists(cleanQuery, limit: 3).catchError((_) => <Song>[])
            : Future.value(<Song>[]),
        offset == 0
            ? SoundcloudService.searchPlaylists(cleanQuery, limit: 3).catchError((_) => <Song>[])
            : Future.value(<Song>[]),
        offset == 0
            ? SoundcloudService.searchAlbums(cleanQuery, limit: 3).catchError((_) => <Song>[])
            : Future.value(<Song>[]),
        offset == 0
            ? PirateService.search(cleanQuery).catchError((_) => <Song>[])
            : Future.value(<Song>[]),
        offset == 0
            ? SpotifyService.searchMixed(cleanQuery, offset: offset, limit: limit).catchError((_) => <Song>[])
            : Future.value(<Song>[]),
      ]);

      final scTracks = futures[0];
      final scArtists = futures[1];
      final scPlaylists = futures[2];
      final scAlbums = futures[3];
      final pirateTracks = futures[4].where((s) => s.type == 'song').toList();
      final spotifyItems = futures[5];

      final Set<String> seenKeys = {};
      void addUnique(List<Song> items) {
        for (final song in items) {
          final songKey = '${song.title.toLowerCase().trim()}_${song.artist.toLowerCase().trim()}';
          if (!seenKeys.contains(songKey)) {
            seenKeys.add(songKey);
            results.add(song);
          }
        }
      }

      addUnique(scArtists);
      addUnique(scTracks);
      addUnique(scPlaylists);
      addUnique(scAlbums);
      addUnique(pirateTracks);
      addUnique(spotifyItems);
    } catch (e) {
      print("Mixed search failed: $e");
    }

    // Fallback 1: if Cyrillic query returned 0 results, retry with transliterated query
    if (results.isEmpty && _hasCyrillic(cleanQuery)) {
      final transliterated = _transliterate(cleanQuery);
      if (transliterated != cleanQuery && transliterated.isNotEmpty) {
        try {
          final futuresTrans = await Future.wait([
            SoundcloudService.search(transliterated, offset: offset, limit: limit).catchError((_) => <Song>[]),
            offset == 0
                ? PirateService.search(transliterated).catchError((_) => <Song>[])
                : Future.value(<Song>[]),
          ]);
          final scTrans = futuresTrans[0];
          final pirateTrans = futuresTrans[1].where((s) => s.type == 'song').toList();

          final Set<String> seenKeys = {};
          for (final song in [...scTrans, ...pirateTrans]) {
            final songKey = '${song.title.toLowerCase().trim()}_${song.artist.toLowerCase().trim()}';
            if (!seenKeys.contains(songKey)) {
              seenKeys.add(songKey);
              results.add(song);
            }
          }
        } catch (_) {}
      }
    }

    results = _sortByRelevance(results, cleanQuery);

    if (results.isNotEmpty) {
      _preResolveResults(results);
      _addToCache(key, results);
    }
    return results;
  }

  static Future<List<Song>> getArtistSongs(String artistId, String artistName) async {
    try {
      final scResults = await SoundcloudService.getArtistSongs(artistId, artistName);
      if (scResults.isNotEmpty) {
        _preResolveResults(scResults);
        return scResults;
      }
      final spotifyResults = await SpotifyService.getArtistSongs(artistId);
      if (spotifyResults.isNotEmpty) {
        _preResolveResults(spotifyResults);
        return spotifyResults;
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Song>> getArtistAlbums(String artistId, String artistName) async {
    try {
      final scResults = await SoundcloudService.getArtistAlbums(artistId, artistName);
      if (scResults.isNotEmpty) return scResults;
      final spotifyResults = await SpotifyService.getArtistAlbums(artistId);
      if (spotifyResults.isNotEmpty) return spotifyResults;
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>?> getArtistDetails(String artistId, String artistName) async {
    try {
      final details = await SoundcloudService.getArtistDetails(artistId, artistName);
      if (details != null) return details;
    } catch (_) {}
    return null;
  }


  static Future<List<Song>> getTrendingArtists() async {
    final topArtists = [
      {
        'name': 'The Weeknd',
        'image':
            'https://i.scdn.co/image/ab6761610000e5eb214f3cf1cbe7139c1e26ffbb',
      },
      {
        'name': 'Taylor Swift',
        'image':
            'https://i.scdn.co/image/ab6761610000e5eb5a00969a4898c152a514d026',
      },
      {
        'name': 'Drake',
        'image':
            'https://i.scdn.co/image/ab6761610000e5eb4293385d324db8558179afd9',
      },
      {
        'name': 'Eminem',
        'image':
            'https://i.scdn.co/image/ab6761610000e5eba00b11c129b27a88fc72f36b',
      },
      {
        'name': 'Ariana Grande',
        'image':
            'https://i.scdn.co/image/ab6761610000e5ebcdce7620dc940db079bf4952',
      },
      {
        'name': 'Justin Bieber',
        'image':
            'https://i.scdn.co/image/ab6761610000e5eb8ae7f2aaa9817a704a87ea36',
      },
      {
        'name': 'Post Malone',
        'image':
            'https://i.scdn.co/image/ab6761610000e5eb6be070445b03e0b63147c2c1',
      },
      {
        'name': 'Billie Eilish',
        'image':
            'https://i.scdn.co/image/ab6761610000e5ebd8b9980db67272cb4d2c3daf',
      },
      {
        'name': 'Bruno Mars',
        'image':
            'https://i.scdn.co/image/ab6761610000e5ebb99cacf8acd537820682226f',
      },
      {
        'name': 'Ed Sheeran',
        'image':
            'https://i.scdn.co/image/ab6761610000e5eb12a2ef08d00dd7451a6dbed6',
      },
    ];

    return topArtists
        .map(
          (a) => Song(
            id: a['name']!,
            videoId: '',
            title: a['name']!,
            artist: 'Artist',
            coverUrl: a['image']!,
            type: 'artist',
          ),
        )
        .toList();
  }

  static Future<List<Song>> searchSoundcloud(String query, {int offset = 0, int limit = 25}) async {
    final cleanQuery = _normalizeQuery(query);
    if (cleanQuery.isEmpty) return [];
    return SoundcloudService.search(cleanQuery, offset: offset, limit: limit);
  }
}

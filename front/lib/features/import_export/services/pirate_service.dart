import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:html/parser.dart' as hp;
import 'package:path_provider/path_provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/core/network/network_service.dart';
import 'package:ses/features/import_export/services/soundcloud_service.dart';

class PirateService {
  static String preferredSource = 'Auto';

  static String fixHomoglyphs(String text) {
    final cyrillicToLatin = {
      'а': 'a', 'с': 'c', 'е': 'e', 'о': 'o', 'р': 'p', 'х': 'x', 'у': 'y',
      'А': 'A', 'С': 'C', 'Е': 'E', 'О': 'O', 'Р': 'P', 'Х': 'X', 'У': 'Y',
      'і': 'i', 'І': 'I', 'ѕ': 's', 'Ѕ': 'S', 'м': 'm', 'М': 'M', 'Т': 'T', 'Н': 'H', 'В': 'B', 'К': 'K',
    };

    final words = text.split(' ');
    final fixedWords = words.map((word) {
      int latinCount = 0;
      int cyrillicCount = 0;
      for (int i = 0; i < word.length; i++) {
        final charCode = word.codeUnitAt(i);
        if ((charCode >= 65 && charCode <= 90) || (charCode >= 97 && charCode <= 122)) {
          latinCount++;
        } else if (charCode >= 1040 && charCode <= 1103) {
          cyrillicCount++;
        }
      }

      if (latinCount > 0 && cyrillicCount > 0) {
        if (latinCount >= cyrillicCount) {
          final sb = StringBuffer();
          for (int i = 0; i < word.length; i++) {
            final char = word[i];
            sb.write(cyrillicToLatin[char] ?? char);
          }
          return sb.toString();
        }
      }
      return word;
    }).toList();

    return fixedWords.join(' ');
  }

  static Future<List<Song>> search(String query) async {
    final fixedQuery = fixHomoglyphs(query.trim());
    print("🚀 Running native Dart scrapers on phone for: $fixedQuery (original: $query)");
    try {
      var localResults = await _searchLocal(fixedQuery);
      
      // Fallback 1: if search returns 0 results, retry with super cleaned query
      if (localResults.isEmpty) {
        final fallbackQuery = superCleanQuery(fixedQuery);
        if (fallbackQuery != fixedQuery && fallbackQuery.isNotEmpty) {
          print("⚠️ Strict query returned 0 results. Retrying search with super clean query: $fallbackQuery");
          localResults = await _searchLocal(fallbackQuery);
        }
      }

      // Fallback 2: if still empty and has hyphen, try searching only the title
      if (localResults.isEmpty && fixedQuery.contains(' - ')) {
        final parts = fixedQuery.split(' - ');
        final titleOnly = parts[1].trim();
        if (titleOnly.isNotEmpty) {
          print("⚠️ Still 0 results. Retrying search with Title only: $titleOnly");
          localResults = await _searchLocal(titleOnly);
        }
      }

      // Fallback 3: if still empty and has hyphen, try searching only the artist
      if (localResults.isEmpty && fixedQuery.contains(' - ')) {
        final parts = fixedQuery.split(' - ');
        final artistOnly = parts[0].trim();
        if (artistOnly.isNotEmpty) {
          print("⚠️ Still 0 results. Retrying search with Artist only: $artistOnly");
          localResults = await _searchLocal(artistOnly);
        }
      }

      return localResults.map((item) {
        return Song(
          id: 'pirate:${item.artist.replaceAll(':', '')}_${item.title.replaceAll(':', '')}',
          videoId: 'pirate:search:${item.artist} - ${item.title}',
          title: item.title,
          artist: item.artist,
          coverUrl: item.coverUrl,
          duration: item.duration,
          type: 'song',
        );
      }).toList();
    } catch (e) {
      print("Error in phone-side scraper search: $e");
    }
    return [];
  }

  static final Map<String, _CachedUrl> _streamUrlCache = {};

  static Future<void> saveCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/stream_url_cache.json');
      final Map<String, Map<String, String>> data = {};
      _streamUrlCache.forEach((key, value) {
        data[key] = {
          'url': value.url,
          'timestamp': value.timestamp.toIso8601String(),
        };
      });
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      print("Error saving stream URL cache: $e");
    }
  }

  static Future<void> loadCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/stream_url_cache.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        map.forEach((key, val) {
          final url = val['url'] as String;
          final timestamp = DateTime.parse(val['timestamp'] as String);
          if (DateTime.now().difference(timestamp).inMinutes < 360) {
            _streamUrlCache[key] = _CachedUrl(url, timestamp);
          }
        });
        print("⚡ Stream URL cache loaded: ${_streamUrlCache.length} items");
      }
    } catch (e) {
      print("Error loading stream URL cache: $e");
    }
  }

  static String cleanQuery(String query) {
    if (query.contains(' - ')) {
      final parts = query.split(' - ');
      var artist = parts[0].trim();
      var title = parts[1].trim();

      // Оставляем только первого артиста (до запятой, " feat. ", " & ", " x ", " and ")
      artist = artist.split(RegExp(r',| feat\.? | & | x | and ', caseSensitive: false)).first.trim();

      // Убираем из названия (feat...), (with...), (prod...), (remix...), [video...] и т.д.
      title = title.replaceAll(RegExp(r'\((?:feat|with|prod|remix|acoustic|live|official)[^\)]*\)', caseSensitive: false), '');
      title = title.replaceAll(RegExp(r'\[(?:feat|with|prod|remix|acoustic|live|official)[^\]]*\]', caseSensitive: false), '');
      title = title.trim();

      return "$artist $title";
    }
    return query;
  }

  static bool isMatch(String query, String resultArtist, String resultTitle) {
    final cleanQ = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();
    final cleanArtist = resultArtist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();
    final cleanTitle = resultTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();

    String qArtist = '';
    String qTitle = '';
    
    if (query.contains(' - ')) {
      final parts = query.split(' - ');
      qArtist = parts[0].trim();
      qTitle = parts.sublist(1).join(' - ').trim();
    } else if (query.contains(' — ')) {
      final parts = query.split(' — ');
      qArtist = parts[0].trim();
      qTitle = parts.sublist(1).join(' — ').trim();
    } else if (query.contains('-')) {
      final index = query.indexOf('-');
      qArtist = query.substring(0, index).trim();
      qTitle = query.substring(index + 1).trim();
    }

    if (qArtist.isNotEmpty && qTitle.isNotEmpty) {
      final cleanQArtist = qArtist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();
      final cleanQTitle = qTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();

      final bool artistOk = cleanArtist.contains(cleanQArtist) || cleanQArtist.contains(cleanArtist);
      final bool titleOk = cleanTitle.contains(cleanQTitle) || cleanQTitle.contains(cleanTitle);

      if (artistOk && titleOk) {
        return true;
      }

      final firstQArtistWord = cleanQArtist.split(' ').first;
      if (firstQArtistWord.length > 2 && cleanArtist.contains(firstQArtistWord)) {
        if (titleOk) {
          return true;
        }
      }
      return false;
    }

    return cleanQ.contains(cleanArtist) || cleanQ.contains(cleanTitle);
  }

  static String superCleanQuery(String query) {
    if (query.contains(' - ')) {
      final parts = query.split(' - ');
      var artist = parts[0].trim();
      var title = parts[1].trim();

      // Оставляем только первого артиста
      artist = artist.split(RegExp(r',| feat\.? | & | x | and ', caseSensitive: false)).first.trim();

      // Полностью удаляем все круглые и квадратные скобки и их содержимое
      title = title.replaceAll(RegExp(r'\([^\)]*\)'), '');
      title = title.replaceAll(RegExp(r'\[[^\]]*\]'), '');

      // Убираем лишние спецсимволы
      title = title.replaceAll(RegExp(r'[^a-zA-Z0-9а-яА-ЯёЁ\s]'), '');
      artist = artist.replaceAll(RegExp(r'[^a-zA-Z0-9а-яА-ЯёЁ\s]'), '');

      return "${artist.trim()} ${title.trim()}".replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    var q = query.replaceAll(RegExp(r'\([^\)]*\)'), '');
    q = q.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    return q.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool isMatchRelaxed(String query, String resultArtist, String resultTitle) {
    final cleanQ = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();
    final cleanArtist = resultArtist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();
    final cleanTitle = resultTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();

    String qArtist = '';
    String qTitle = '';

    if (query.contains(' - ')) {
      final parts = query.split(' - ');
      qArtist = parts[0].trim();
      qTitle = parts.sublist(1).join(' - ').trim();
    } else if (query.contains(' — ')) {
      final parts = query.split(' — ');
      qArtist = parts[0].trim();
      qTitle = parts.sublist(1).join(' — ').trim();
    } else if (query.contains('-')) {
      final index = query.indexOf('-');
      qArtist = query.substring(0, index).trim();
      qTitle = query.substring(index + 1).trim();
    }

    if (qArtist.isNotEmpty && qTitle.isNotEmpty) {
      final cleanQArtist = qArtist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();
      final cleanQTitle = qTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();

      // Check if artist matches (first word of the artist matches or contains)
      final firstQArtistWord = cleanQArtist.split(' ').first;
      final bool artistOk = cleanArtist.contains(firstQArtistWord) || firstQArtistWord.contains(cleanArtist) || cleanArtist.contains(cleanQArtist) || cleanQArtist.contains(cleanArtist);

      // Check if title matches (first word of the title matches or contains)
      final firstQTitleWord = cleanQTitle.split(' ').first;
      final bool titleOk = cleanTitle.contains(firstQTitleWord) || firstQTitleWord.contains(cleanTitle) || cleanTitle.contains(cleanQTitle) || cleanQTitle.contains(cleanTitle);

      if (artistOk && titleOk) {
        return true;
      }
    }
    return cleanQ.contains(cleanArtist) || cleanQ.contains(cleanTitle);
  }

  // Resolve a stream URL dynamically on the fly
  static Future<String?> getStreamUrl(String query) async {
    if (query.startsWith('sc_stream:') || query.startsWith('sc_') || query.startsWith('soundcloud:')) {
      final scUrl = await SoundcloudService.getStreamUrl(query);
      if (scUrl != null && scUrl.isNotEmpty) return scUrl;

      // SoundCloud failed (snippet/blocked/error). Extract track metadata for pirate fallback.
      final trackMeta = await SoundcloudService.getTrackMeta(query);
      if (trackMeta != null) {
        final fallbackQuery = "pirate:search:${trackMeta['artist']} - ${trackMeta['title']}";
        print("⚠️ SoundCloud stream failed for $query. Falling back to pirate search: $fallbackQuery");
        return getStreamUrl(fallbackQuery);
      }
    }

    var cleanQueryString = query;
    if (cleanQueryString.startsWith('pirate:search:')) {
      cleanQueryString = cleanQueryString.replaceFirst('pirate:search:', '');
    } else if (cleanQueryString.startsWith('sc_stream:')) {
      cleanQueryString = cleanQueryString.replaceFirst('sc_stream:', '');
    } else if (cleanQueryString.startsWith('sc_')) {
      cleanQueryString = cleanQueryString.replaceFirst('sc_', '');
    } else if (cleanQueryString.startsWith('soundcloud:')) {
      cleanQueryString = cleanQueryString.replaceFirst('soundcloud:', '');
    }

    if (cleanQueryString.startsWith('http') || cleanQueryString.startsWith('file://') || cleanQueryString.startsWith('/')) {
      return cleanQueryString;
    }

    final cached = _streamUrlCache[cleanQueryString];
    if (cached != null) {
      final age = DateTime.now().difference(cached.timestamp);
      if (age.inMinutes < 360) {
        print("⚡ Cache hit for stream URL: $cleanQueryString");
        return cached.url;
      } else {
        _streamUrlCache.remove(cleanQueryString);
      }
    }

    // Resolve directly on phone using scrapers
    final cleanedQuery = cleanQuery(cleanQueryString);
    print("🚀 Resolving stream URL natively on phone for: $cleanedQuery (originally: $cleanQueryString)");
    try {
      var results = await _searchLocal(cleanedQuery);

      // Fallback 1: If search returned 0 results, retry search with super cleaned query
      if (results.isEmpty) {
        final fallbackQuery = superCleanQuery(cleanQueryString);
        if (fallbackQuery != cleanedQuery && fallbackQuery.isNotEmpty) {
          print("⚠️ Stream search returned 0 results. Retrying with super clean query: $fallbackQuery");
          results = await _searchLocal(fallbackQuery);
        }
      }

      String? matchedId;

      bool isFullLength(Song item) => item.duration == Duration.zero || item.duration.inSeconds >= 45;

      // Pass 1: strict match (prioritize full-length tracks)
      for (final item in results) {
        if (isFullLength(item) && isMatch(cleanQueryString, item.artist, item.title)) {
          matchedId = item.id;
          break;
        }
      }
      if (matchedId == null) {
        for (final item in results) {
          if (isMatch(cleanQueryString, item.artist, item.title)) {
            matchedId = item.id;
            break;
          }
        }
      }

      // Pass 2: relaxed match (prioritize full-length tracks)
      if (matchedId == null) {
        for (final item in results) {
          if (isFullLength(item) && isMatchRelaxed(cleanQueryString, item.artist, item.title)) {
            matchedId = item.id;
            print("💡 Relaxed full-length match applied: $cleanQueryString -> ${item.artist} - ${item.title}");
            break;
          }
        }
      }
      if (matchedId == null) {
        for (final item in results) {
          if (isMatchRelaxed(cleanQueryString, item.artist, item.title)) {
            matchedId = item.id;
            print("💡 Relaxed match applied: $cleanQueryString -> ${item.artist} - ${item.title}");
            break;
          }
        }
      }

      // Pass 3: extreme relaxed match (prioritize full-length tracks)
      if (matchedId == null) {
        for (final item in results) {
          if (isFullLength(item) && _isExtremeRelaxedMatch(cleanQueryString, item.artist, item.title)) {
            matchedId = item.id;
            print("💡 Extreme relaxed full-length match applied: $cleanQueryString -> ${item.artist} - ${item.title}");
            break;
          }
        }
      }

      // Pass 4: Fallback to first full-length search result
      if (matchedId == null && results.isNotEmpty) {
        final fullItem = results.firstWhere((item) => isFullLength(item), orElse: () => results.first);
        matchedId = fullItem.id;
        print("⚠️ No perfect match found for: $cleanQueryString. Falling back to search result: ${fullItem.artist} - ${fullItem.title}");
      }

      if (matchedId != null && matchedId.isNotEmpty) {
        _streamUrlCache[cleanQueryString] = _CachedUrl(matchedId, DateTime.now());
        saveCache();
        return matchedId;
      }
    } catch (e) {
      print("Error in phone-side scraper resolution: $e");
    }
    return null;
  }

  static bool _isExtremeRelaxedMatch(String query, String resultArtist, String resultTitle) {
    final cleanQ = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();
    final cleanArtist = resultArtist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();
    final cleanTitle = resultTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();

    String qArtist = '';
    String qTitle = '';

    if (query.contains(' - ')) {
      final parts = query.split(' - ');
      qArtist = parts[0].trim();
      qTitle = parts.sublist(1).join(' - ').trim();
    } else if (query.contains(' — ')) {
      final parts = query.split(' — ');
      qArtist = parts[0].trim();
      qTitle = parts.sublist(1).join(' — ').trim();
    } else if (query.contains('-')) {
      final index = query.indexOf('-');
      qArtist = query.substring(0, index).trim();
      qTitle = query.substring(index + 1).trim();
    }

    if (qArtist.isNotEmpty && qTitle.isNotEmpty) {
      final cleanQArtist = qArtist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();
      final cleanQTitle = qTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();

      // Check if the title words overlap
      final titleWords = cleanQTitle.split(' ').where((w) => w.length > 2);
      bool titleOverlap = false;
      for (final word in titleWords) {
        if (cleanTitle.contains(word)) {
          titleOverlap = true;
          break;
        }
      }

      // Check if the artist words overlap
      final artistWords = cleanQArtist.split(' ').where((w) => w.length > 2);
      bool artistOverlap = false;
      for (final word in artistWords) {
        if (cleanArtist.contains(word)) {
          artistOverlap = true;
          break;
        }
      }

      if (titleOverlap && artistOverlap) {
        return true;
      }
    }

    return cleanQ.contains(cleanArtist) || cleanQ.contains(cleanTitle);
  }



  static bool isQueryResultRelevant(String query, String artist, String title) {
    final q = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), '').trim();
    if (q.isEmpty) return true;
    final words = q.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    if (words.isEmpty) return true;
    
    final a = artist.toLowerCase();
    final t = title.toLowerCase();
    
    // Check if at least one query word is in the artist or title
    for (final word in words) {
      if (a.contains(word) || t.contains(word)) {
        return true;
      }
    }
    return false;
  }

  // ─── Native Phone-Side Scraper implementation ───

  static const String _defaultCover = "https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400&auto=format&fit=crop";

  static int _parseDurationSeconds(String durStr) {
    durStr = durStr.trim();
    if (durStr.isEmpty) return 210;
    final parts = durStr.split(':');
    try {
      if (parts.length == 2) {
        final min = int.parse(parts[0]);
        final sec = int.parse(parts[1]);
        return min * 60 + sec;
      } else if (parts.length == 3) {
        final hr = int.parse(parts[0]);
        final min = int.parse(parts[1]);
        final sec = int.parse(parts[2]);
        return hr * 3600 + min * 60 + sec;
      }
    } catch (_) {}
    return 210;
  }

  static String? _decryptSefonUrl(String dataUrl, String key) {
    try {
      if (dataUrl.startsWith('#')) {
        dataUrl = dataUrl.substring(1);
      }
      
      // Reverse key string
      String reversedKey = key.split('').reversed.join('');
      
      for (int i = 0; i < reversedKey.length; i++) {
        String char = reversedKey[i];
        List<String> parts = dataUrl.split(char);
        parts = parts.reversed.toList();
        dataUrl = parts.join(char);
      }
      
      // Base64 decode
      final decodedBytes = base64.decode(dataUrl);
      return utf8.decode(decodedBytes);
    } catch (e) {
      print("Error decrypting Sefon URL on mobile: $e");
      return null;
    }
  }

  static bool _isKazakhQuery(String query) {
    final kzChars = RegExp(r'[әіңғүұқөһӘІҢҒҮҰҚӨҺ]');
    return kzChars.hasMatch(query);
  }

  static Future<List<Song>> _searchMuzofondLocal(String query) async {
    try {
      final formattedQuery = query.replaceAll(' ', '+');
      final searchUrl = Uri.parse("https://muzofond.fm/search/$formattedQuery");
      final response = await NetworkService.get(
        searchUrl,
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
          "Referer": "https://muzofond.fm/",
        },
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) return [];

      final htmlBody = response.body;

      return await Isolate.run(() {
        final List<Song> songs = [];
        final document = hp.parse(htmlBody);
        final trackElements = document.querySelectorAll("li.item");

        for (var s in trackElements) {
          final playBtn = s.querySelector(".play");
          if (playBtn == null) continue;
          
          var streamUrl = playBtn.attributes['data-url'];
          if (streamUrl == null || streamUrl.isEmpty) continue;

          if (streamUrl.startsWith('/')) {
            streamUrl = "https://muzofond.fm$streamUrl";
          }

          final artistEl = s.querySelector(".artist");
          final titleEl = s.querySelector(".title");
          final durationEl = s.querySelector(".duration");

          final artist = artistEl?.text.trim() ?? "Muzofond Artist";
          final title = titleEl?.text.trim() ?? "Muzofond Title";
          final durationStr = durationEl?.text.trim() ?? "";

          songs.add(Song(
            id: streamUrl,
            videoId: streamUrl,
            title: title,
            artist: artist,
            coverUrl: _defaultCover,
            duration: Duration(seconds: _parseDurationSeconds(durationStr)),
            type: 'song',
          ));
        }
        return songs;
      });
    } catch (e) {
      print("Error in Dart Muzofond scraper: $e");
    }
    return [];
  }

  static Future<List<Song>> _searchLocal(String query) async {
    final source = preferredSource.toLowerCase();

    // Helper to run a specific source search
    Future<List<Song>> runSource(String src) {
      switch (src) {
        case 'agugai':
          return _searchAgugaiLocal(query).catchError((_) => <Song>[]);
        case 'sefon':
          return _searchSefonLocal(query).catchError((_) => <Song>[]);
        case 'drivemusic':
          return _searchDriveMusicLocal(query).catchError((_) => <Song>[]);
        case 'mp3party':
          return _searchMp3PartyLocal(query).catchError((_) => <Song>[]);
        case 'rumusic':
          return _searchRuMusicLocal(query).catchError((_) => <Song>[]);
        case 'muzofond':
          return _searchMuzofondLocal(query).catchError((_) => <Song>[]);
        default:
          return Future.value(<Song>[]);
      }
    }

    // 1. If a specific source is preferred, try it first
    if (source != 'auto') {
      try {
        final preferredResults = await runSource(source).timeout(const Duration(milliseconds: 4000));
        if (preferredResults.isNotEmpty) {
          final filtered = preferredResults.where((s) => isQueryResultRelevant(query, s.artist, s.title)).toList();
          if (filtered.isNotEmpty) {
            print("⚡ Preferred source ($preferredSource) resolved ${filtered.length} tracks");
            return filtered;
          }
        }
      } catch (e) {
        print("Preferred source $preferredSource failed or timed out: $e");
      }
    }

    // 2. Fast path: if the query contains Kazakh characters, prioritize Agugai
    final isKz = _isKazakhQuery(query);
    if (isKz && source != 'agugai') {
      try {
        print("🇰🇿 Kazakh query detected! Prioritizing Agugai fast-path...");
        final kzResults = await _searchAgugaiLocal(query).timeout(const Duration(milliseconds: 4000));
        if (kzResults.isNotEmpty) {
          final filtered = kzResults.where((s) => isQueryResultRelevant(query, s.artist, s.title)).toList();
          if (filtered.isNotEmpty) {
            print("⚡ Kazakh fast-path Agugai resolved ${filtered.length} tracks");
            return filtered;
          }
        }
      } catch (e) {
        print("Agugai fast-path timeout or error: $e");
      }
    }

    // 3. Try Sefon first (unless it was already run as preferred)
    if (source != 'sefon') {
      try {
        final sefonResults = await _searchSefonLocal(query).timeout(const Duration(milliseconds: 4000));
        if (sefonResults.isNotEmpty) {
          final filtered = sefonResults.where((s) => isQueryResultRelevant(query, s.artist, s.title)).toList();
          if (filtered.isNotEmpty) {
            print("⚡ Fast-path Sefon resolved ${filtered.length} tracks");
            return filtered;
          }
        }
      } catch (e) {
        print("Sefon fast-path timeout or error: $e");
      }
    }

    // 4. Query all other sources in parallel
    print("⏳ Fast-paths empty/slow, querying remaining sources in parallel...");
    final List<String> remainingSources = ['agugai', 'sefon', 'drivemusic', 'mp3party', 'rumusic', 'muzofond'];
    if (source != 'auto') {
      remainingSources.remove(source);
    }
    if (isKz) {
      remainingSources.remove('agugai');
    }
    remainingSources.remove('sefon');

    final List<Future<List<Song>>> tasks = remainingSources.map((src) => runSource(src)).toList();

    try {
      final results = await Future.wait(tasks).timeout(const Duration(milliseconds: 6000));
      final List<Song> merged = [];
      
      int maxLen = 0;
      for (final list in results) {
        if (list.length > maxLen) maxLen = list.length;
      }
      
      for (int i = 0; i < maxLen; i++) {
        for (final list in results) {
          if (i < list.length) {
            merged.add(list[i]);
          }
        }
      }
      
      final filtered = merged.where((s) => isQueryResultRelevant(query, s.artist, s.title)).toList();
      if (filtered.isNotEmpty) {
        return filtered;
      }

      // Fallback: If filtered list is empty but merged is not, return merged!
      if (merged.isNotEmpty) {
        print("⚠️ Relevancy filtering removed all results. Returning unfiltered merged list to avoid 0 results.");
        return merged;
      }
    } catch (e) {
      print("Parallel sources failed or timed out: $e");
    }

    return [];
  }

  static Future<List<Song>> _searchSefonLocal(String query) async {
    try {
      final searchUrl = Uri.parse("https://sefon.pro/search/?q=${Uri.encodeComponent(query)}");
      final response = await NetworkService.get(
        searchUrl,
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "Referer": "https://sefon.pro/",
        },
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) return [];

      final htmlBody = response.body;

      return await Isolate.run(() {
        final List<Song> songs = [];
        final document = hp.parse(htmlBody);
        
        // Map artist photos
        final Map<String, String> artistPhotos = {};
        final artistElements = document.querySelectorAll(".b_list_artists .li");
        for (var s in artistElements) {
          final nameEl = s.querySelector(".name");
          final imgEl = s.querySelector("img");
          if (nameEl != null && imgEl != null) {
            final artistName = nameEl.text.trim().toLowerCase();
            String? photoSrc = imgEl.attributes['src'];
            if (photoSrc != null && photoSrc.isNotEmpty && artistName.isNotEmpty) {
              if (!photoSrc.startsWith('http')) {
                photoSrc = "https://sefon.pro$photoSrc";
              }
              artistPhotos[artistName] = photoSrc;
            }
          }
        }

        final mp3Elements = document.querySelectorAll(".b_list_mp3s .mp3");
        for (var s in mp3Elements) {
          final idAttr = s.attributes['data-mp3_id'];
          if (idAttr == null || idAttr.isEmpty) continue;

          final artistEl = s.querySelector(".title .artist_name");
          final titleEl = s.querySelector(".title .song_name");
          final durationEl = s.querySelector(".duration .value");
          final protectedEl = s.querySelector(".url_protected");

          if (artistEl == null || titleEl == null || protectedEl == null) continue;

          final artist = artistEl.text.trim();
          final title = titleEl.text.trim();
          final durationStr = durationEl?.text.trim() ?? "";

          final encUrl = protectedEl.attributes['data-url'];
          final key = protectedEl.attributes['data-key'];

          if (encUrl == null || key == null || encUrl.isEmpty || key.isEmpty) continue;

          var streamUrl = _decryptSefonUrl(encUrl, key);
          if (streamUrl == null || streamUrl.isEmpty) continue;
          if (streamUrl.startsWith('/')) {
            streamUrl = "https://sefon.pro$streamUrl";
          }

          String cover = _defaultCover;
          if (artistPhotos.containsKey(artist.toLowerCase())) {
            cover = artistPhotos[artist.toLowerCase()]!;
          }

          songs.add(Song(
            id: streamUrl,
            videoId: streamUrl,
            title: title,
            artist: artist,
            coverUrl: cover,
            duration: Duration(seconds: _parseDurationSeconds(durationStr)),
            type: 'song',
          ));
        }
        return songs;
      });
    } catch (e) {
      print("Error in Dart Sefon scraper: $e");
    }
    return [];
  }

  static Future<List<Song>> _searchDriveMusicLocal(String query) async {
    try {
      final searchUrl = Uri.parse("https://drivemusic.club/?do=search&subaction=search&story=${Uri.encodeComponent(query)}");
      final response = await NetworkService.get(
        searchUrl,
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "Referer": "https://drivemusic.club/",
        },
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) return [];

      final htmlBody = response.body;

      return await Isolate.run(() {
        final List<Song> songs = [];
        final document = hp.parse(htmlBody);
        final wrappers = document.querySelectorAll(".genre-music .music-popular-wrapper");

        for (var s in wrappers) {
          final btn = s.querySelector(".btn_player button");
          if (btn == null) continue;

          var streamUrl = btn.attributes['data-url'];
          if (streamUrl == null || streamUrl.isEmpty) continue;
          if (streamUrl.startsWith('/')) {
            streamUrl = "https://drivemusic.club$streamUrl";
          }

          final authorEl = s.querySelector(".popular-play-name .popular-play-author");
          final compEl = s.querySelector(".popular-play-name .popular-play-composition");
          final downloadEl = s.querySelector(".popular-download .popular-download-number");

          if (authorEl == null || compEl == null) continue;

          final artist = compEl.text.trim();
          var title = authorEl.text.trim();
          final durationStr = downloadEl?.text.trim() ?? "";

          title = title.replaceAll('\n', ' ');
          title = title.split(RegExp(r'\s+')).join(' ');

          songs.add(Song(
            id: streamUrl,
            videoId: streamUrl,
            title: title,
            artist: artist,
            coverUrl: _defaultCover,
            duration: Duration(seconds: _parseDurationSeconds(durationStr)),
            type: 'song',
          ));
        }
        return songs;
      });
    } catch (e) {
      print("Error in Dart DriveMusic scraper: $e");
    }
    return [];
  }

  static Future<List<Song>> _searchMp3PartyLocal(String query) async {
    try {
      final searchUrl = Uri.parse("https://mp3party.net/search?q=${Uri.encodeComponent(query)}");
      final response = await NetworkService.get(
        searchUrl,
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
          "Referer": "https://mp3party.net/",
        },
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) return [];

      final htmlBody = response.body;

      return await Isolate.run(() {
        final List<Song> songs = [];
        final document = hp.parse(htmlBody);
        final trackElements = document.querySelectorAll(".track");

        for (var s in trackElements) {
          final panel = s.querySelector(".track__user-panel");
          if (panel == null) continue;

          final artist = panel.attributes['data-js-artist-name'];
          final title = panel.attributes['data-js-song-title'];
          var streamUrl = panel.attributes['data-js-url'];

          if (artist == null || title == null || streamUrl == null || streamUrl.isEmpty) continue;

          if (streamUrl.startsWith('/')) {
            streamUrl = "https://mp3party.net$streamUrl";
          }

          final durationEl = s.querySelector(".track__info-item");
          final durationStr = durationEl?.text.trim() ?? "";

          songs.add(Song(
            id: streamUrl,
            videoId: streamUrl,
            title: title,
            artist: artist,
            coverUrl: _defaultCover,
            duration: Duration(seconds: _parseDurationSeconds(durationStr)),
            type: 'song',
          ));
        }
        return songs;
      });
    } catch (e) {
      print("Error in Dart Mp3party scraper: $e");
    }
    return [];
  }

  static Future<List<Song>> _searchRuMusicLocal(String query) async {
    try {
      final formattedQuery = query.replaceAll(' ', '+');
      final searchUrl = Uri.parse("https://ru-music.com/search/$formattedQuery/");
      final response = await NetworkService.get(
        searchUrl,
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
          "Referer": "https://ru-music.com/",
        },
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) return [];

      final htmlBody = response.body;

      return await Isolate.run(() {
        final List<Song> songs = [];
        final document = hp.parse(htmlBody);
        final trackElements = document.querySelectorAll("li.track");

        for (var s in trackElements) {
          var streamUrl = s.attributes['data-mp3'];
          if (streamUrl == null || streamUrl.isEmpty) continue;

          if (streamUrl.startsWith('/')) {
            streamUrl = "https://ru-music.com$streamUrl";
          }

          final artistEl = s.querySelector(".playlist-name b a");
          final titleEl = s.querySelector(".playlist-name em a");

          if (artistEl == null || titleEl == null) continue;

          final artist = artistEl.text.trim();
          final title = titleEl.text.trim();
          final coverUrl = s.attributes['data-img'] ?? _defaultCover;
          
          final durationMsStr = s.attributes['data-duration'] ?? "210000";
          final durationMs = int.tryParse(durationMsStr) ?? 210000;

          songs.add(Song(
            id: streamUrl,
            videoId: streamUrl,
            title: title,
            artist: artist,
            coverUrl: coverUrl,
            duration: Duration(milliseconds: durationMs),
            type: 'song',
          ));
        }
        return songs;
      });
    } catch (e) {
      print("Error in Dart Ru-music scraper: $e");
    }
    return [];
  }

  static Future<List<Song>> _searchAgugaiLocal(String query) async {
    try {
      final searchUrl = Uri.parse("https://agugai.kz/catalog/music?q=${Uri.encodeComponent(query)}");
      final response = await NetworkService.get(
        searchUrl,
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "Referer": "https://agugai.kz/",
        },
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) return [];

      final htmlBody = response.body;

      return await Isolate.run(() {
        final List<Song> songs = [];
        final document = hp.parse(htmlBody);
        final playElements = document.querySelectorAll("span.play[data-url]");

        for (var el in playElements) {
          final title = el.attributes['data-name']?.trim() ?? "";
          final artist = el.attributes['data-artist']?.trim() ?? "";
          var streamUrl = el.attributes['data-url']?.trim() ?? "";

          if (title.isEmpty || streamUrl.isEmpty) continue;

          if (streamUrl.startsWith('/')) {
            streamUrl = "https://agugai.kz$streamUrl";
          }

          // Agugai links can have Kazakh titles and artists
          songs.add(Song(
            id: streamUrl,
            videoId: streamUrl,
            title: title,
            artist: artist.isEmpty ? "Agugai Artist" : artist,
            coverUrl: _defaultCover,
            duration: const Duration(seconds: 210), // Agugai does not put duration in span.play
            type: 'song',
          ));
        }
        return songs;
      });
    } catch (e) {
      print("Error in Dart Agugai scraper: $e");
    }
    return [];
  }

  static Future<List<Song>> _getSefonPopularLocal() async {
    try {
      final url = Uri.parse("https://sefon.pro/");
      final response = await NetworkService.get(
        url,
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "Referer": "https://sefon.pro/",
        },
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) return [];

      final htmlBody = response.body;

      return await Isolate.run(() {
        final List<Song> songs = [];
        final document = hp.parse(htmlBody);
        
        final Map<String, String> artistPhotos = {};
        final artistElements = document.querySelectorAll(".b_list_artists .li");
        for (var s in artistElements) {
          final nameEl = s.querySelector(".name");
          final imgEl = s.querySelector("img");
          if (nameEl != null && imgEl != null) {
            final artistName = nameEl.text.trim().toLowerCase();
            String? photoSrc = imgEl.attributes['src'];
            if (photoSrc != null && photoSrc.isNotEmpty && artistName.isNotEmpty) {
              if (!photoSrc.startsWith('http')) {
                photoSrc = "https://sefon.pro$photoSrc";
              }
              artistPhotos[artistName] = photoSrc;
            }
          }
        }

        final mp3Elements = document.querySelectorAll(".b_list_mp3s .mp3");
        for (var s in mp3Elements) {
          final idAttr = s.attributes['data-mp3_id'];
          if (idAttr == null || idAttr.isEmpty) continue;

          final artistEl = s.querySelector(".title .artist_name");
          final titleEl = s.querySelector(".title .song_name");
          final durationEl = s.querySelector(".duration .value");
          final protectedEl = s.querySelector(".url_protected");

          if (artistEl == null || titleEl == null || protectedEl == null) continue;

          final artist = artistEl.text.trim();
          final title = titleEl.text.trim();
          final durationStr = durationEl?.text.trim() ?? "";

          final encUrl = protectedEl.attributes['data-url'];
          final key = protectedEl.attributes['data-key'];

          if (encUrl == null || key == null || encUrl.isEmpty || key.isEmpty) continue;

          var streamUrl = _decryptSefonUrl(encUrl, key);
          if (streamUrl == null || streamUrl.isEmpty) continue;
          if (streamUrl.startsWith('/')) {
            streamUrl = "https://sefon.pro$streamUrl";
          }

          String cover = _defaultCover;
          if (artistPhotos.containsKey(artist.toLowerCase())) {
            cover = artistPhotos[artist.toLowerCase()]!;
          }

          songs.add(Song(
            id: streamUrl,
            videoId: streamUrl,
            title: title,
            artist: artist,
            coverUrl: cover,
            duration: Duration(seconds: _parseDurationSeconds(durationStr)),
            type: 'song',
          ));
        }
        return songs;
      });
    } catch (e) {
      print("Error in Dart Sefon popular scraper: $e");
    }
    return [];
  }

  static Future<List<Song>> _getDriveMusicPopularLocal() async {
    try {
      final url = Uri.parse("https://drivemusic.club/");
      final response = await NetworkService.get(
        url,
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "Referer": "https://drivemusic.club/",
        },
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode != 200) return [];

      final htmlBody = response.body;

      return await Isolate.run(() {
        final List<Song> songs = [];
        final document = hp.parse(htmlBody);
        final wrappers = document.querySelectorAll(".genre-music .music-popular-wrapper");

        for (var s in wrappers) {
          final btn = s.querySelector(".btn_player button");
          if (btn == null) continue;

          var streamUrl = btn.attributes['data-url'];
          if (streamUrl == null || streamUrl.isEmpty) continue;
          if (streamUrl.startsWith('/')) {
            streamUrl = "https://drivemusic.club$streamUrl";
          }

          final authorEl = s.querySelector(".popular-play-name .popular-play-author");
          final compEl = s.querySelector(".popular-play-name .popular-play-composition");
          final downloadEl = s.querySelector(".popular-download .popular-download-number");

          if (authorEl == null || compEl == null) continue;

          final artist = compEl.text.trim();
          var title = authorEl.text.trim();
          final durationStr = downloadEl?.text.trim() ?? "";

          title = title.replaceAll('\n', ' ');
          title = title.split(RegExp(r'\s+')).join(' ');

          songs.add(Song(
            id: streamUrl,
            videoId: streamUrl,
            title: title,
            artist: artist,
            coverUrl: _defaultCover,
            duration: Duration(seconds: _parseDurationSeconds(durationStr)),
            type: 'song',
          ));
        }
        return songs;
      });
    } catch (e) {
      print("Error in Dart DriveMusic popular scraper: $e");
    }
    return [];
  }

  static final List<String> _popularCisArtists = [
    'Miyagi & Andy Panda', 'Macan', 'Anna Asti', 'Jony', 'Скриптонит', 
    'Jah Khalib', 'Баста', 'HammAli & Navai', 'Zivert', 'The Limba',
    "Ramil'", "L'One", 'T-Fest', 'Грибы', 'Кайрат Нуртас', 'Димаш Кудайберген',
    'Ерке Есмахан', 'Мирас Жугунусов', 'Люся Чеботина', 'GAYAZOV\$ BROTHER\$'
  ];

  static const List<String> _popularForeignArtists = [
    'The Weeknd', 'Billie Eilish', 'Eminem', 'Drake', 'Dua Lipa', 
    'Travis Scott', 'Ed Sheeran', 'Bruno Mars', 'Justin Bieber', 
    'Rihanna', 'Ariana Grande', 'Taylor Swift', 'Imagine Dragons',
    'Post Malone', 'Coldplay', 'Maroon 5', 'Adele', 'Beyonce',
    'David Guetta', 'Katy Perry', 'Harry Styles'
  ];

  static Future<List<Song>> getPopularSongs({int page = 1}) async {
    print("🚀 Fetching popular songs for radio (page $page)...");
    
    // Page 1: Try to scrape the popular charts directly from Sefon and DriveMusic
    if (page == 1) {
      try {
        final results = await Future.wait([
          _getSefonPopularLocal().catchError((_) => <Song>[]),
          _getDriveMusicPopularLocal().catchError((_) => <Song>[]),
        ]).timeout(const Duration(seconds: 10));

        final sefonSongs = results[0];
        final dmSongs = results[1];

        final List<Song> merged = [];
        int maxLen = sefonSongs.length > dmSongs.length ? sefonSongs.length : dmSongs.length;

        for (int i = 0; i < maxLen; i++) {
          if (i < sefonSongs.length) merged.add(sefonSongs[i]);
          if (i < dmSongs.length) merged.add(dmSongs[i]);
        }

        if (merged.length >= 25) {
          merged.shuffle();
          return merged;
        }
      } catch (e) {
        print("Error fetching popular homepages: $e");
      }
    }

    // Dynamic fallback for page 1 (if sparse) or generation for page > 1:
    // We pick 3 random CIS and 3 random foreign artists and search for their tracks.
    print("🎲 Generating page $page using dynamic search queries...");
    try {
      final List<String> cisList = List.from(_popularCisArtists)..shuffle();
      final List<String> foreignList = List.from(_popularForeignArtists)..shuffle();
      
      final selectedArtists = [
        ...cisList.take(3),
        ...foreignList.take(3),
      ];
      
      print("🔎 Querying popular songs for: ${selectedArtists.join(', ')}");
      
      final List<Future<List<Song>>> searchTasks = selectedArtists.map((artist) async {
        try {
          final results = await _searchLocal(artist).timeout(const Duration(seconds: 6));
          final artistLower = artist.toLowerCase();
          return results.where((s) {
            final trackArtist = s.artist.toLowerCase();
            return trackArtist.contains(artistLower) || artistLower.contains(trackArtist);
          }).toList();
        } catch (e) {
          print("Error searching for artist '$artist' in radio feed: $e");
          return <Song>[];
        }
      }).toList();

      final searchResults = await Future.wait(searchTasks);
      
      final List<Song> merged = [];
      int maxLen = 0;
      for (final list in searchResults) {
        if (list.length > maxLen) maxLen = list.length;
      }
      
      // Interleave results to keep it mixed
      for (int i = 0; i < maxLen; i++) {
        for (final list in searchResults) {
          if (i < list.length) {
            final rawSong = list[i];
            merged.add(Song(
              id: 'pirate:${rawSong.artist.replaceAll(':', '')}_${rawSong.title.replaceAll(':', '')}',
              videoId: 'pirate:search:${rawSong.artist} - ${rawSong.title}',
              title: rawSong.title,
              artist: rawSong.artist,
              coverUrl: rawSong.coverUrl,
              duration: rawSong.duration,
              type: 'song',
            ));
          }
        }
      }

      if (merged.isNotEmpty) {
        merged.shuffle();
        return merged;
      }
    } catch (e) {
      print("Error generating dynamic radio feed: $e");
    }

    // Static fallback list if all scrapers and searches fail
    print("⚠️ Using static fallback list for radio (page $page)");
    final List<Song> staticFallback = [
      Song(
        id: 'pirate:search:Miyagi & Andy Panda - Minor',
        videoId: 'pirate:search:Miyagi & Andy Panda - Minor',
        title: 'Minor',
        artist: 'Miyagi & Andy Panda',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 3, seconds: 30),
      ),
      Song(
        id: 'pirate:search:Macan - Asphalt 8',
        videoId: 'pirate:search:Macan - Asphalt 8',
        title: 'Asphalt 8',
        artist: 'Macan',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 3, seconds: 0),
      ),
      Song(
        id: 'pirate:search:Anna Asti - Царица',
        videoId: 'pirate:search:Anna Asti - Царица',
        title: 'Царица',
        artist: 'Anna Asti',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 3, seconds: 40),
      ),
      Song(
        id: 'pirate:search:Jony - Комета',
        videoId: 'pirate:search:Jony - Комета',
        title: 'Комета',
        artist: 'Jony',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 3, seconds: 15),
      ),
      Song(
        id: 'pirate:search:Скриптонит - Положение',
        videoId: 'pirate:search:Скриптонит - Положение',
        title: 'Положение',
        artist: 'Скриптонит',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 4, seconds: 0),
      ),
      Song(
        id: 'pirate:search:HammAli & Navai - Птичка',
        videoId: 'pirate:search:HammAli & Navai - Птичка',
        title: 'Птичка',
        artist: 'HammAli & Navai',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 3, seconds: 10),
      ),
      Song(
        id: 'pirate:search:Zivert - Life',
        videoId: 'pirate:search:Zivert - Life',
        title: 'Life',
        artist: 'Zivert',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 3, seconds: 25),
      ),
      Song(
        id: 'pirate:search:Кайрат Нуртас - Махаббат бер маған',
        videoId: 'pirate:search:Кайрат Нуртас - Махаббат бер маған',
        title: 'Махаббат бер маған',
        artist: 'Кайрат Нуртас',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 3, seconds: 35),
      ),
      Song(
        id: 'pirate:search:The Weeknd - Blinding Lights',
        videoId: 'pirate:search:The Weeknd - Blinding Lights',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 3, seconds: 20),
      ),
      Song(
        id: 'pirate:search:Billie Eilish - Bad Guy',
        videoId: 'pirate:search:Billie Eilish - Bad Guy',
        title: 'Bad Guy',
        artist: 'Billie Eilish',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 3, seconds: 14),
      ),
      Song(
        id: 'pirate:search:Eminem - Without Me',
        videoId: 'pirate:search:Eminem - Without Me',
        title: 'Without Me',
        artist: 'Eminem',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 4, seconds: 50),
      ),
      Song(
        id: 'pirate:search:Drake - Hotline Bling',
        videoId: 'pirate:search:Drake - Hotline Bling',
        title: 'Hotline Bling',
        artist: 'Drake',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 4, seconds: 27),
      ),
      Song(
        id: 'pirate:search:Dua Lipa - Levitating',
        videoId: 'pirate:search:Dua Lipa - Levitating',
        title: 'Levitating',
        artist: 'Dua Lipa',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 3, seconds: 23),
      ),
      Song(
        id: 'pirate:search:Travis Scott - Goosebumps',
        videoId: 'pirate:search:Travis Scott - Goosebumps',
        title: 'Goosebumps',
        artist: 'Travis Scott',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 4, seconds: 2),
      ),
      Song(
        id: 'pirate:search:Ed Sheeran - Shape of You',
        videoId: 'pirate:search:Ed Sheeran - Shape of You',
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 3, seconds: 53),
      ),
      Song(
        id: 'pirate:search:Bruno Mars - Uptown Funk',
        videoId: 'pirate:search:Bruno Mars - Uptown Funk',
        title: 'Uptown Funk',
        artist: 'Bruno Mars',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 4, seconds: 30),
      ),
      Song(
        id: 'pirate:search:Justin Bieber - Stay',
        videoId: 'pirate:search:Justin Bieber - Stay',
        title: 'Stay',
        artist: 'Justin Bieber',
        coverUrl: 'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400',
        duration: const Duration(minutes: 2, seconds: 21),
      ),
    ];
    staticFallback.shuffle();
    return staticFallback;
  }
}

class _CachedUrl {
  final String url;
  final DateTime timestamp;
  _CachedUrl(this.url, this.timestamp);
}

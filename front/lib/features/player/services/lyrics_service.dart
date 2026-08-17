import 'dart:convert';
import 'package:ses/core/network/network_service.dart';
import 'package:ses/core/network/backend_service.dart';

class LyricLine {
  final Duration time;
  final String text;

  LyricLine({required this.time, required this.text});
}

class LyricsData {
  final String? plainLyrics;
  final List<LyricLine>? syncedLines;
  final bool isInstrumental;

  LyricsData({
    this.plainLyrics,
    this.syncedLines,
    required this.isInstrumental,
  });

  bool get hasSynced => syncedLines != null && syncedLines!.isNotEmpty;
  bool get hasLyrics => (plainLyrics != null && plainLyrics!.isNotEmpty) || hasSynced;

  Map<String, dynamic> toJson() {
    return {
      'plainLyrics': plainLyrics,
      'isInstrumental': isInstrumental,
      'syncedLines': syncedLines?.map((l) => {
        'timeMs': l.time.inMilliseconds,
        'text': l.text,
      }).toList(),
    };
  }

  factory LyricsData.fromJson(Map<String, dynamic> json) {
    final synced = json['syncedLines'] as List?;
    return LyricsData(
      plainLyrics: json['plainLyrics'] as String?,
      isInstrumental: json['isInstrumental'] == true,
      syncedLines: synced?.map((item) => LyricLine(
        time: Duration(milliseconds: item['timeMs'] as int),
        text: item['text'] as String,
      )).toList(),
    );
  }
}

/// Sentinel value cached when we know a song has no lyrics on the server
// (reserved for future use)

class LyricsService {
  // ─── In-memory LRU cache (max 50 entries) ───
  static final Map<String, LyricsData?> _cache = {};
  static const int _maxCacheSize = 50;

  static String _cacheKey(String artist, String title) =>
      '${artist.toLowerCase().trim()}||${title.toLowerCase().trim()}';

  static void _putCache(String key, LyricsData? data) {
    // Evict oldest if full
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = data;
    saveCache();
  }

  static Future<void> loadCache() async {
    try {
      final file = await BackendService.getLocalFile('lyrics_cache.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        map.forEach((key, value) {
          if (value == null) {
            _cache[key] = null;
          } else {
            _cache[key] = LyricsData.fromJson(value as Map<String, dynamic>);
          }
        });
        print("[LyricsService] Loaded ${_cache.length} cached lyrics from disk");
      }
    } catch (e) {
      print("[LyricsService] Error loading lyrics cache: $e");
    }
  }

  static Future<void> saveCache() async {
    try {
      final file = await BackendService.getLocalFile('lyrics_cache.json');
      final map = _cache.map((key, value) => MapEntry(key, value?.toJson()));
      await file.writeAsString(jsonEncode(map));
    } catch (e) {
      print("[LyricsService] Error saving lyrics cache: $e");
    }
  }

  // ─── Query cleaning ───
  static String _cleanQuery(String s) {
    // 1. Remove bracketed text, like (feat. ...), [Official Video], [Remix]
    s = s.replaceAll(RegExp(r'[\(\[][^\]\)]*[\)\]]'), '');
    // 2. Remove common noisy video/audio terms
    s = s.replaceAll(RegExp(r'\b(official|video|lyric|remix|edit|prod|by|audio|clip|hq|hd|remastered)\b', caseSensitive: false), '');
    // 3. Remove extra whitespaces
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String _cleanArtist(String artist) {
    // Split by feat, ft, &, comma and take primary artist
    final splitters = RegExp(r'\b(feat\.?|ft\.?|&|,|and)\b', caseSensitive: false);
    String firstArtist = artist.split(splitters).first.trim();
    return _cleanQuery(firstArtist);
  }

  static String _cleanTitle(String title) {
    return _cleanQuery(title);
  }

  // ─── Cyrillic → Latin transliteration (for Genius search) ───
  static final _cyrillicToLatinMap = <String, String>{
    'а': 'a', 'ә': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'ғ': 'g',
    'д': 'd', 'е': 'e', 'ё': 'yo', 'ж': 'zh', 'з': 'z', 'и': 'i',
    'й': 'y', 'к': 'k', 'қ': 'q', 'л': 'l', 'м': 'm', 'н': 'n',
    'ң': 'n', 'о': 'o', 'ө': 'o', 'п': 'p', 'р': 'r', 'с': 's',
    'т': 't', 'у': 'u', 'ұ': 'u', 'ү': 'u', 'ф': 'f', 'х': 'kh',
    'һ': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
    'ъ': '', 'ы': 'y', 'і': 'i', 'ь': '', 'э': 'e', 'ю': 'yu',
    'я': 'ya',
    'А': 'A', 'Ә': 'A', 'Б': 'B', 'В': 'V', 'Г': 'G', 'Ғ': 'G',
    'Д': 'D', 'Е': 'E', 'Ё': 'Yo', 'Ж': 'Zh', 'З': 'Z', 'И': 'I',
    'Й': 'Y', 'К': 'K', 'Қ': 'Q', 'Л': 'L', 'М': 'M', 'Н': 'N',
    'Ң': 'N', 'О': 'O', 'Ө': 'O', 'П': 'P', 'Р': 'R', 'С': 'S',
    'Т': 'T', 'У': 'U', 'Ұ': 'U', 'Ү': 'U', 'Ф': 'F', 'Х': 'Kh',
    'Һ': 'H', 'Ц': 'Ts', 'Ч': 'Ch', 'Ш': 'Sh', 'Щ': 'Shch',
    'Ъ': '', 'Ы': 'Y', 'І': 'I', 'Ь': '', 'Э': 'E', 'Ю': 'Yu',
    'Я': 'Ya',
  };

  static bool _hasCyrillic(String text) =>
      RegExp(r'[\u0400-\u04FF]').hasMatch(text);

  static String _transliterate(String text) {
    final buf = StringBuffer();
    for (var ch in text.split('')) {
      buf.write(_cyrillicToLatinMap[ch] ?? ch);
    }
    return buf.toString();
  }

  static LyricsData _parseLrcLibData(Map<String, dynamic> data) {
    final isInstrumental = data['instrumental'] == true;
    final plain = data['plainLyrics'] as String?;
    final synced = data['syncedLyrics'] as String?;

    List<LyricLine>? lines;
    if (synced != null && synced.isNotEmpty) {
      lines = _parseLrc(synced);
    }

    return LyricsData(
      plainLyrics: plain,
      syncedLines: lines,
      isInstrumental: isInstrumental,
    );
  }

  static final _lrcHeaders = {
    'User-Agent': 'SesMusic/1.0.0 (https://github.com/aivaz/sesmusic)',
  };

  /// Helper that performs a GET and returns null on any error
  static Future<dynamic> _safeGet(String url, {Map<String, String>? headers, Duration? timeout}) async {
    try {
      return await NetworkService.get(
        Uri.parse(url),
        headers: headers ?? _lrcHeaders,
        timeout: timeout ?? const Duration(seconds: 15),
      );
    } catch (_) {
      return null;
    }
  }

  /// Fetch lyrics with in-memory cache & multi-source fallback
  static Future<LyricsData?> fetchLyrics(String artist, String title) async {
    final cleanArtist = _cleanArtist(artist);
    final cleanTitle = _cleanTitle(title);
    final key = _cacheKey(cleanArtist, cleanTitle);

    // Return cached result instantly
    if (_cache.containsKey(key)) {
      final cached = _cache[key];
      // Move to end (LRU refresh)
      _cache.remove(key);
      _cache[key] = cached;
      return cached;
    }

    // ─── Source 1: LRCLIB (synced + plain) ───
    final lrcFuture = _fetchFromLrcLib(cleanArtist, cleanTitle);

    // ─── Source 2: Genius (plain lyrics fallback) — start in parallel ───
    final geniusFuture = _fetchFromGenius(cleanArtist, cleanTitle);

    // Wait for LRCLIB first (it has synced lyrics)
    final lrcResult = await lrcFuture;
    if (lrcResult != null && lrcResult.hasLyrics) {
      _putCache(key, lrcResult);
      return lrcResult;
    }

    // Fallback to Genius
    final geniusResult = await geniusFuture;
    if (geniusResult != null && geniusResult.hasLyrics) {
      _putCache(key, geniusResult);
      return geniusResult;
    }

    // Cache the miss too so we don't re-fetch
    _putCache(key, null);
    return null;
  }

  // ─────────────────────────────────────────────
  // Source 1: LRCLIB
  // ─────────────────────────────────────────────
  static Future<LyricsData?> _fetchFromLrcLib(String artist, String title) async {
    final artistEscaped = Uri.encodeComponent(artist);
    final titleEscaped = Uri.encodeComponent(title);
    final exactUrl = 'https://lrclib.net/api/get?artist_name=$artistEscaped&track_name=$titleEscaped';
    final searchQuery = '$artist $title';
    final searchUrl = 'https://lrclib.net/api/search?q=${Uri.encodeComponent(searchQuery)}';

    final exactFuture = _safeGet(exactUrl);
    final searchFuture = _safeGet(searchUrl);

    // 1. Wait for exact match first
    final exactResponse = await exactFuture;
    if (exactResponse != null && exactResponse.statusCode == 200) {
      try {
        final data = jsonDecode(utf8.decode(exactResponse.bodyBytes)) as Map<String, dynamic>;
        return _parseLrcLibData(data);
      } catch (_) {}
    }

    // 2. Fallback: search results
    final searchResponse = await searchFuture;
    if (searchResponse != null && searchResponse.statusCode == 200) {
      try {
        final List data = jsonDecode(utf8.decode(searchResponse.bodyBytes));
        if (data.isNotEmpty) {
          final bestMatch = data.first as Map<String, dynamic>;
          return _parseLrcLibData(bestMatch);
        }
      } catch (_) {}
    }

    return null;
  }

  // ─────────────────────────────────────────────
  // Source 2: Genius (search → scrape page)
  // ─────────────────────────────────────────────
  static final _geniusHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
  };

  static Future<LyricsData?> _fetchFromGenius(String artist, String title) async {
    try {
      // Build search queries: original + transliterated (for Kazakh/Russian songs)
      final queries = <String>[];
      final original = '$artist $title';
      queries.add(original);

      // If query contains Cyrillic, also try transliterated version
      if (_hasCyrillic(original)) {
        queries.add(_transliterate(original));
      }

      String? songUrl;

      // Try each query variant until we find a result
      for (final query in queries) {
        final searchUrl = 'https://genius.com/api/search/song?q=${Uri.encodeComponent(query)}&per_page=5';
        final searchResponse = await _safeGet(searchUrl, headers: _geniusHeaders, timeout: const Duration(seconds: 10));
        if (searchResponse == null || searchResponse.statusCode != 200) continue;

        final searchData = jsonDecode(utf8.decode(searchResponse.bodyBytes));
        final hits = searchData['response']?['sections']?[0]?['hits'] as List?;
        if (hits == null || hits.isEmpty) continue;

        // Find best match
        final lowerArtist = artist.toLowerCase();
        final lowerTitle = title.toLowerCase();
        final lowerTransTitle = _hasCyrillic(title) ? _transliterate(title).toLowerCase() : lowerTitle;
        final lowerTransArtist = _hasCyrillic(artist) ? _transliterate(artist).toLowerCase() : lowerArtist;

        for (final hit in hits) {
          final result = hit['result'] as Map<String, dynamic>?;
          if (result == null) continue;

          final hitTitle = (result['title'] as String? ?? '').toLowerCase();
          final hitArtist = (result['primary_artist']?['name'] as String? ?? '').toLowerCase();

          // Match against both original and transliterated
          if (hitTitle.contains(lowerTitle) || lowerTitle.contains(hitTitle) ||
              hitTitle.contains(lowerTransTitle) || lowerTransTitle.contains(hitTitle) ||
              hitArtist.contains(lowerArtist) || lowerArtist.contains(hitArtist) ||
              hitArtist.contains(lowerTransArtist) || lowerTransArtist.contains(hitArtist)) {
            songUrl = result['url'] as String?;
            break;
          }
        }

        // If no fuzzy match but we have results, take first
        songUrl ??= hits[0]['result']?['url'] as String?;
        if (songUrl != null) break;
      }

      if (songUrl == null) return null;

      // Fetch the song page and extract lyrics
      final pageResponse = await _safeGet(songUrl, headers: _geniusHeaders, timeout: const Duration(seconds: 10));
      if (pageResponse == null || pageResponse.statusCode != 200) return null;

      final html = utf8.decode(pageResponse.bodyBytes);
      final lyrics = _extractGeniusLyrics(html);

      if (lyrics != null && lyrics.trim().isNotEmpty) {
        return LyricsData(
          plainLyrics: lyrics,
          syncedLines: null,
          isInstrumental: false,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Extract lyrics text from Genius HTML page
  static String? _extractGeniusLyrics(String html) {
    // Genius stores lyrics in <div data-lyrics-container="true"> elements
    final containerPattern = RegExp(
      r'data-lyrics-container="true"[^>]*>(.*?)</div>',
      dotAll: true,
    );

    final matches = containerPattern.allMatches(html);
    if (matches.isEmpty) return null;

    final buffer = StringBuffer();
    for (final match in matches) {
      var block = match.group(1) ?? '';
      // Replace <br> and <br/> with newlines
      block = block.replaceAll(RegExp(r'<br\s*/?>'), '\n');
      // Remove all remaining HTML tags
      block = block.replaceAll(RegExp(r'<[^>]+>'), '');
      // Decode HTML entities
      block = _decodeHtmlEntities(block);
      buffer.writeln(block.trim());
    }

    var result = buffer.toString().trim();
    if (result.isEmpty) return null;

    // Clean up Genius header artifacts like "5 ContributorsSongName Lyrics"
    result = result.replaceAll(RegExp(r'^\d+\s*Contributors?.*?Lyrics\n?', caseSensitive: false), '');
    // Remove trailing "Embed" or "You might also like" artifacts
    result = result.replaceAll(RegExp(r'\n?You might also like.*$', dotAll: true), '');
    result = result.replaceAll(RegExp(r'\n?\d*Embed$'), '');

    return result.trim().isEmpty ? null : result.trim();
  }

  /// Decode common HTML entities
  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  static List<LyricLine> _parseLrc(String lrc) {
    final List<LyricLine> lines = [];
    final RegExp regExp = RegExp(r'\[(\d+):(\d+)(?:\.(\d+))?\](.*)');
    
    for (var rawLine in lrc.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      
      final match = regExp.firstMatch(line);
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final msStr = match.group(3) ?? '0';
        final ms = int.parse(msStr.padRight(3, '0').substring(0, 3));
        
        final text = match.group(4)!.trim();
        final time = Duration(minutes: min, seconds: sec, milliseconds: ms);
        
        lines.add(LyricLine(time: time, text: text));
      }
    }
    
    // Сортируем на всякий случай по времени
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }
}

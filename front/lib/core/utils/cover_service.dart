import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:ses/core/network/network_service.dart';

class CoverService {
  static final Map<String, String> _memoryCache = {};
  static const int _maxCacheSize = 250;
  static bool _isLoaded = false;
  static Future<void>? _loadFuture;
  static bool _isSaving = false;
  static bool _savePending = false;
  static const String defaultMusicCover = "https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400&auto=format&fit=crop";

  static void _checkCacheLimit() {
    if (_memoryCache.length > _maxCacheSize) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  // Preload cover cache on startup
  static Future<void> preload() => _loadCache();

  // Initialize and load cache from file
  static Future<void> _loadCache() {
    _loadFuture ??= _loadCacheImpl();
    return _loadFuture!;
  }

  static Future<void> _loadCacheImpl() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/cover_cache.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        data.forEach((key, value) {
          _memoryCache[key] = value.toString();
        });
      }
    } catch (e) {
      print("Error loading cover cache: $e");
    }
    _isLoaded = true;
  }

  // Save cache to file
  static Future<void> _saveCache() async {
    if (_isSaving) {
      _savePending = true;
      return;
    }
    _isSaving = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/cover_cache.json');
      await file.writeAsString(jsonEncode(_memoryCache));
    } catch (e) {
      print("Error saving cover cache: $e");
    } finally {
      _isSaving = false;
      if (_savePending) {
        _savePending = false;
        await _saveCache();
      }
    }
  }

  // Check memory cache synchronously
  static String? getCachedCover(String artist, String title) {
    final cacheKey = "${artist.trim().toLowerCase()} - ${title.trim().toLowerCase()}";
    return _memoryCache[cacheKey];
  }

  static final Map<String, Future<String>> _pendingQueries = {};

  // Get cover art URL from cache or iTunes API search
  static Future<String> getCoverUrl(String artist, String title) async {
    if (artist.isEmpty || title.isEmpty) return defaultMusicCover;

    final cacheKey = "${artist.trim().toLowerCase()} - ${title.trim().toLowerCase()}";
    
    await _loadCache();
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey]!;
    }

    // Coalesce concurrent requests for the same track
    if (_pendingQueries.containsKey(cacheKey)) {
      return _pendingQueries[cacheKey]!;
    }

    final future = _fetchCoverFromITunes(artist, title, cacheKey);
    _pendingQueries[cacheKey] = future;

    try {
      return await future;
    } finally {
      _pendingQueries.remove(cacheKey);
    }
  }

  static Future<String> _fetchCoverFromITunes(String artist, String title, String cacheKey) async {
    try {
      // Clean query search term (avoid things like (feat. ...) or brackets for better iTunes matching)
      String cleanTitle = title.split(RegExp(r'[\(\[\-]')).first.trim();
      String cleanArtist = artist.split(RegExp(r'[\(\[\-]')).first.trim();
      final query = "$cleanArtist $cleanTitle";
      
      final url = Uri.parse("https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=song&limit=1");
      final response = await NetworkService.get(url, timeout: const Duration(seconds: 4));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List results = data['results'] ?? [];
        if (results.isNotEmpty) {
          final String? artworkUrl = results.first['artworkUrl100']?.toString();
          if (artworkUrl != null && artworkUrl.isNotEmpty) {
            // Upgrade resolution to 500x500
            final highResUrl = artworkUrl.replaceAll("100x100bb.jpg", "500x500bb.jpg");
            _checkCacheLimit();
            _memoryCache[cacheKey] = highResUrl;
            await _saveCache();
            print("🎨 iTunes Cover Art cached for: $artist - $title -> $highResUrl");
            return highResUrl;
          }
        }
      }
    } catch (e) {
      print("Error fetching cover art from iTunes for $artist - $title: $e");
    }

    return defaultMusicCover;
  }
}

import 'package:html/parser.dart' as hp;
import 'package:http/http.dart' as http;
import 'package:ses/features/cinema/models/movie_item.dart';
import 'package:ses/core/network/network_service.dart';

class KinogoService {
  // Список зеркал Lordfilm (работают без Cloudflare-блокировки)
  static final List<String> mirrors = [
    'https://www.lordfilm.ae',
    'https://lordfilm.ae',
    'https://lordfilm.uno',
    'https://lordfilm.vet',
    'https://lordfilm.tax',
  ];

  static String currentMirror = mirrors[0];

  static Map<String, String> get imageHeaders => {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Referer": currentMirror,
  };

  // Общие HTTP-заголовки для обхода ботозащиты
  static Map<String, String> get _defaultHeaders => {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
    "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
    "Referer": "https://google.com/",
  };

  /// Выполнение запроса с перебором зеркал при ошибке
  static Future<http.Response?> _requestWithFallback(String path, {String method = 'GET', Map<String, String>? body}) async {
    // Сначала пробуем текущее выбранное зеркало
    try {
      final url = Uri.parse("$currentMirror$path");
      final response = method == 'POST'
          ? await NetworkService.post(url, headers: _defaultHeaders, body: body)
          : await NetworkService.get(url, headers: _defaultHeaders);
      
      if (response.statusCode == 200) {
        // Проверяем, не сбросило ли нас редиректом на главную страницу при поиске
        final finalUrlStr = response.request?.url.toString() ?? '';
        if (path.contains('do=search') && !finalUrlStr.contains('story=')) {
          print("⚠️ Search query stripped on $currentMirror (redirected to $finalUrlStr). Swapping mirror...");
        } else {
          return response;
        }
      }
    } catch (_) {}

    // Если текущее зеркало не ответило или сбросило поиск, перебираем остальные
    for (final mirror in mirrors) {
      if (mirror == currentMirror) continue;
      try {
        final url = Uri.parse("$mirror$path");
        final response = method == 'POST'
            ? await NetworkService.post(url, headers: _defaultHeaders, body: body)
            : await NetworkService.get(url, headers: _defaultHeaders);

        if (response.statusCode == 200) {
          final finalUrlStr = response.request?.url.toString() ?? '';
          if (path.contains('do=search') && !finalUrlStr.contains('story=')) {
            continue; // Этот зеркальный сервер сбрасывает параметры поиска
          }
          currentMirror = mirror;
          print("⚡ Switched to working mirror: $currentMirror");
          return response;
        }
      } catch (_) {}
    }
    return null;
  }

  // ══════════════════════════════════════════════════════
  //  ПУБЛИЧНЫЕ МЕТОДЫ
  // ══════════════════════════════════════════════════════

  /// Парсинг фильмов с главной страницы
  static Future<List<MovieItem>> fetchLatestMovies() async {
    final response = await _requestWithFallback('/');
    if (response == null) return [];
    return _parseMoviesFromHtml(response.body);
  }

  /// Парсинг фильмов по конкретной категории
  /// Пути: '/film/', '/series/', '/anime/', '/multfilm/'
  static Future<List<MovieItem>> fetchMoviesByCategory(String categoryPath) async {
    final response = await _requestWithFallback(categoryPath);
    if (response == null) return [];
    return _parseMoviesFromHtml(response.body);
  }

  /// Загрузка фильмов с пагинацией
  static Future<List<MovieItem>> fetchMoviesWithFilter({
    required String path,
    required int page,
  }) async {
    String fullPath = path;
    if (page > 1) {
      if (fullPath == '/') {
        fullPath = '/page/$page/';
      } else {
        if (fullPath.endsWith('/')) {
          fullPath = '${fullPath}page/$page/';
        } else {
          fullPath = '$fullPath/page/$page/';
        }
      }
    }
    final response = await _requestWithFallback(fullPath);
    if (response == null) return [];
    return _parseMoviesFromHtml(response.body);
  }

  /// Умный многоуровневый поиск фильмов, сериалов, аниме и мультфильмов
  static Future<List<MovieItem>> searchMovies(String query, {String? tabType}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // 1. Пробуем основной GET DLE-поиск
    try {
      final encodedQuery = Uri.encodeComponent(cleanQuery);
      final response = await _requestWithFallback('/index.php?do=search&subaction=search&story=$encodedQuery');
      if (response != null && response.body.isNotEmpty) {
        final results = _parseMoviesFromHtml(response.body);
        if (results.isNotEmpty) return results;
      }
    } catch (_) {}

    // 2. Резервный POST DLE-поиск
    try {
      final response = await _requestWithFallback(
        '/index.php?do=search',
        method: 'POST',
        body: {
          'do': 'search',
          'subaction': 'search',
          'search_start': '0',
          'full_search': '0',
          'result_from': '1',
          'story': cleanQuery,
        },
      );
      if (response != null && response.body.isNotEmpty) {
        return _parseMoviesFromHtml(response.body);
      }
    } catch (_) {}

    return [];
  }

  /// Извлечение ссылки на плеер (iframe) из страницы фильма
  static Future<String?> getMoviePlayerUrl(String movieUrl) async {
    try {
      final headers = {
        ..._defaultHeaders,
        "Referer": currentMirror,
      };
      
      final response = await NetworkService.get(Uri.parse(movieUrl), headers: headers);
      if (response.statusCode != 200) return null;

      return _extractPlayerUrlFromHtml(response.body);
    } catch (e) {
      print("Ошибка при получении плеера: $e");
    }
    return null;
  }

  /// Извлечение жанра и описания со страницы деталей фильма.
  /// Lordfilm не показывает жанр/описание в карточках списка,
  /// эти данные доступны только на индивидуальной странице фильма.
  static Future<Map<String, String>> fetchMovieDetails(String movieUrl) async {
    try {
      final headers = {
        ..._defaultHeaders,
        "Referer": currentMirror,
      };

      final response = await NetworkService.get(Uri.parse(movieUrl), headers: headers);
      if (response.statusCode != 200) return {};

      return _extractDetailsFromHtml(response.body);
    } catch (e) {
      print("Ошибка при загрузке деталей фильма: $e");
    }
    return {};
  }

  /// Комбинированный метод: извлекает плеер, жанр, описание, страну и актеров за один запрос
  static Future<({String? playerUrl, String genre, String description, String country, List<Map<String, String>> actors})> getMovieDetailsAndPlayerUrl(String movieUrl) async {
    try {
      final headers = {
        ..._defaultHeaders,
        "Referer": currentMirror,
      };

      final response = await NetworkService.get(Uri.parse(movieUrl), headers: headers);
      if (response.statusCode != 200) {
        return (playerUrl: null, genre: '', description: '', country: '', actors: <Map<String, String>>[]);
      }

      final playerUrl = _extractPlayerUrlFromHtml(response.body);
      final details = _extractDetailsFromHtml(response.body);
      final String country = details['country'] ?? '';
      
      // Ищем ссылку на TMDB в HTML
      String? tmdbUrl;
      final tmdbRegex = RegExp(r'https?://(?:www\.)?themoviedb\.org/(?:movie|tv)/\d+');
      final match = tmdbRegex.firstMatch(response.body);
      if (match != null) {
        tmdbUrl = match.group(0);
      }

      final List<Map<String, String>> actorsList = [];
      if (tmdbUrl != null) {
        try {
          final tmdbResponse = await NetworkService.get(Uri.parse(tmdbUrl), headers: _defaultHeaders);
          if (tmdbResponse.statusCode == 200) {
            final tmdbDoc = hp.parse(tmdbResponse.body);
            final cards = tmdbDoc.querySelectorAll("li.card");
            for (final card in cards) {
              final nameEl = card.querySelector("p a");
              final characterEl = card.querySelector("p.character");
              final imgEl = card.querySelector("img");
              
              final name = nameEl?.text.trim() ?? "";
              final character = characterEl?.text.trim() ?? "";
              final imgSrc = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? "";
              
              if (name.isNotEmpty) {
                actorsList.add({
                  'name': name,
                  'character': character,
                  'imageUrl': imgSrc,
                });
              }
              if (actorsList.length >= 15) break;
            }
          }
        } catch (e) {
          print("Ошибка загрузки актеров с TMDB: $e");
        }
      }

      // Если актеры с TMDB не загрузились, парсим текстовый список с Лордфильма
      if (actorsList.isEmpty && details['actors'] != null) {
        final names = details['actors']!.split(',');
        for (final rawName in names) {
          final name = rawName.trim();
          if (name.isNotEmpty) {
            actorsList.add({
              'name': name,
              'character': 'Актер',
              'imageUrl': '',
            });
          }
          if (actorsList.length >= 15) break;
        }
      }

      return (
        playerUrl: playerUrl,
        genre: details['genre'] ?? '',
        description: details['description'] ?? '',
        country: country,
        actors: actorsList,
      );
    } catch (e) {
      print("Ошибка при загрузке деталей и плеера: $e");
    }
    return (playerUrl: null, genre: '', description: '', country: '', actors: <Map<String, String>>[]);
  }

  /// Извлечение URL плеера из HTML страницы фильма
  static String? _extractPlayerUrlFromHtml(String html) {
    final document = hp.parse(html);

    // Ищем iframe плеера
    final iframes = document.querySelectorAll("iframe");
    for (final iframe in iframes) {
      String? src = iframe.attributes['data-src'] ?? iframe.attributes['src'];
      if (src != null && src.isNotEmpty) {
        src = _decodeHtmlUrl(src);
        // Пропускаем YouTube-трейлеры и рекламу, берем только видео-балансеры
        if (src.contains('youtube') || src.contains('google')) continue;
        if (src.contains('kodik') || src.contains('alloha') || src.contains('collaps') || 
            src.contains('videocdn') || src.contains('frame') || src.contains('embed') ||
            src.contains('ortified') || src.contains('rezka') || src.contains('hdvb') ||
            src.contains('bazon') || src.contains('voidboost')) {
          if (src.startsWith('//')) {
            return "https:$src";
          }
          return src;
        }
      }
    }

    // Альтернативный поиск через регулярные выражения в скриптах страницы
    final scriptRegExp = RegExp(r'''iframe\s+(?:data-)?src=["']([^"']+)["']''', caseSensitive: false);
    final match = scriptRegExp.firstMatch(html);
    if (match != null) {
      String? src = match.group(1);
      if (src != null) {
        src = _decodeHtmlUrl(src);
        if (!src.contains('youtube') && !src.contains('google')) {
          if (src.startsWith('//')) return "https:$src";
          return src;
        }
      }
    }

    return null;
  }

  /// Извлечение жанра и описания из HTML страницы деталей фильма
  static Map<String, String> _extractDetailsFromHtml(String html) {
    final result = <String, String>{};
    try {
      final document = hp.parse(html);

      // Жанр: <span class="genres"><a>Боевик</a>, <a>Драма</a></span>
      final genreEl = document.querySelector('.genres');
      if (genreEl != null) {
        final genreLinks = genreEl.querySelectorAll('a');
        if (genreLinks.isNotEmpty) {
          result['genre'] = genreLinks.map((g) => g.text.trim()).join(', ');
        } else {
          final genreText = genreEl.text.trim();
          if (genreText.isNotEmpty) {
            result['genre'] = genreText;
          }
        }
      }

      // Страна: <span class="countries"><a>США</a></span>
      final countryEl = document.querySelector('.countries');
      if (countryEl != null) {
        final countryLinks = countryEl.querySelectorAll('a');
        if (countryLinks.isNotEmpty) {
          result['country'] = countryLinks.map((c) => c.text.trim()).join(', ');
        } else {
          final countryText = countryEl.text.trim();
          if (countryText.isNotEmpty) {
            result['country'] = countryText;
          }
        }
      }

      // В ролях (актеры) из detail-row
      final detailRows = document.querySelectorAll('.detail-row');
      for (final row in detailRows) {
        final spanLabel = row.querySelector('span:first-child');
        if (spanLabel != null && spanLabel.text.toLowerCase().contains('ролях')) {
          final spanValue = row.querySelector('span:last-child');
          if (spanValue != null) {
            result['actors'] = spanValue.text.trim();
          }
        }
      }

      // Описание: <div class="page__text"><div class="full-text"><p>...</p></div></div>
      final descEl = document.querySelector('.page__text .full-text');
      if (descEl != null) {
        final descText = descEl.text.trim();
        if (descText.isNotEmpty) {
          result['description'] = descText;
        }
      } else {
        // Fallback: ищем .full-text напрямую
        final fallbackDesc = document.querySelector('.full-text');
        if (fallbackDesc != null) {
          final descText = fallbackDesc.text.trim();
          if (descText.isNotEmpty) {
            result['description'] = descText;
          }
        }
      }
    } catch (e) {
      print("Ошибка парсинга деталей: $e");
    }
    return result;
  }

  /// Попытка извлечь прямую ссылку на видео (.mp4/.m3u8)
  static Future<String?> resolveDirectVideoUrl(String iframeUrl) async {
    try {
      final headers = {
        ..._defaultHeaders,
        "Referer": currentMirror,
      };

      final response = await NetworkService.get(Uri.parse(iframeUrl), headers: headers);
      if (response.statusCode != 200) return null;

      final body = response.body;

      // 1. Прямые ссылки на .mp4 или .m3u8
      final mp4Regex = RegExp(r'''(https?://[^\s"'\\]+\.(?:mp4|m3u8)[^\s"'\\]*)''', caseSensitive: false);
      final mp4Matches = mp4Regex.allMatches(body);
      for (final match in mp4Matches) {
        String url = match.group(1) ?? '';
        url = url.replaceAll(r'\/', '/');
        if (url.contains('google') || url.contains('analytics') || url.contains('facebook') || url.contains('mc.yandex') || url.contains('counter')) continue;
        if (url.length < 30) continue;
        return url;
      }

      // 2. JSON file/src/source
      final fileRegex = RegExp(r'''["'](?:file|src|source|url|video)["']\s*:\s*["'](https?://[^"']+)["']''', caseSensitive: false);
      final fileMatch = fileRegex.firstMatch(body);
      if (fileMatch != null) {
        String url = fileMatch.group(1) ?? '';
        url = url.replaceAll(r'\/', '/');
        if (url.contains('.mp4') || url.contains('.m3u8')) {
          return url;
        }
      }

      // 3. Внутренний iframe
      final innerIframeRegex = RegExp(r'''<iframe[^>]+(?:data-)?src=["']([^"']+)["']''', caseSensitive: false);
      final innerIframeMatch = innerIframeRegex.firstMatch(body);
      if (innerIframeMatch != null) {
        String innerUrl = innerIframeMatch.group(1) ?? '';
        innerUrl = _decodeHtmlUrl(innerUrl);
        if (innerUrl.startsWith('//')) innerUrl = 'https:$innerUrl';
        if (innerUrl.startsWith('http') && innerUrl != iframeUrl) {
          final resolved = await resolveDirectVideoUrl(innerUrl);
          if (resolved != null) return resolved;
        }
      }
    } catch (e) {
      print("Ошибка при резолве прямого URL видео: $e");
    }
    return null;
  }

  // ══════════════════════════════════════════════════════
  //  ПРИВАТНЫЕ МЕТОДЫ
  // ══════════════════════════════════════════════════════

  /// Декодирование HTML-сущностей в URL
  static String _decodeHtmlUrl(String url) {
    return url
        .replaceAll('&#58;', ':')
        .replaceAll('&amp;', '&')
        .replaceAll('&#37;', '%')
        .replaceAll('&#47;', '/');
  }

  /// Общий парсер карточек фильмов из HTML
  /// Поддерживает верстку Lordfilm (.item) и Kinogo (.shortstory, .movie)
  static List<MovieItem> _parseMoviesFromHtml(String html) {
    final List<MovieItem> movies = [];
    final Set<String> seenIds = {};
    try {
      final document = hp.parse(html);
      
      // Поддерживаем все вариации карточек Lordfilm, Kinogo и DLE-поиска
      final cards = document.querySelectorAll(".item, .grid-items__item, .shortstory, .movie, .search-result, .story");
      
      for (var card in cards) {
        // Пропускаем верхний слайдер/карусель популярных новинок
        var p = card.parent;
        bool isCarousel = false;
        while (p != null) {
          if (p.className.contains('carou') || p.id.contains('carou')) {
            isCarousel = true;
            break;
          }
          p = p.parent;
        }
        if (isCarousel) continue;

        // ── Заголовок и ссылка ──
        final titleEl = card.querySelector(".item__title, .shortstory__title a, .zagolovki a, .shortstorytitle a, a.expand-link__trg, a[href*='/film/'], a[href*='/series/'], a[href*='/anime/'], a[href*='/multfilm/']");
        if (titleEl == null) continue;

        final detailsUrl = titleEl.attributes['href'] ?? '';
        if (detailsUrl.isEmpty) continue;

        final fullDetailsUrl = detailsUrl.startsWith('http') ? detailsUrl : "$currentMirror$detailsUrl";
        final title = titleEl.text.trim();
        if (title.isEmpty) continue;

        if (seenIds.contains(fullDetailsUrl)) continue;
        seenIds.add(fullDetailsUrl);

        // ── Постер ──
        final imgEl = card.querySelector(".item__img img, .shortstory__poster img, .movie__info-img img, img");
        String coverUrl = imgEl?.attributes['data-src'] ?? imgEl?.attributes['src'] ?? imgEl?.attributes['data-original'] ?? '';
        
        // Пропускаем base64-заглушки (Kinogo / Lordfilm lazy-load)
        if (coverUrl.startsWith('data:') || coverUrl.contains('lazy-poster') || coverUrl.isEmpty) {
          final altImg = card.querySelector("img");
          if (altImg != null) {
            coverUrl = altImg.attributes['data-src'] ?? altImg.attributes['src'] ?? altImg.attributes['data-original'] ?? '';
          }
        }

        if (coverUrl.isNotEmpty) {
          if (coverUrl.contains('/images/w300/') || coverUrl.contains('/images/w500/') || coverUrl.contains('/images/w185/')) {
            coverUrl = coverUrl.replaceAll(RegExp(r'^.*?/images/'), 'https://image.tmdb.org/t/p/');
          } else if (coverUrl.startsWith('//')) {
            coverUrl = "https:$coverUrl";
          } else if (!coverUrl.startsWith('http')) {
            coverUrl = "$currentMirror${coverUrl.startsWith('/') ? '' : '/'}$coverUrl";
          }
        }
        coverUrl = coverUrl.replaceAll('/thumbs/', '/');

        // ── Рейтинг ──
        String rating = '';
        final imdbEl = card.querySelector(".item__rates-item.imdb");
        final kpEl = card.querySelector(".kp");
        
        if (imdbEl != null) {
          rating = imdbEl.text.replaceAll('⭐', '').replaceAll('IMDB', '').trim();
        } else if (kpEl != null) {
          rating = kpEl.text.replaceAll('KP', '').trim();
        } else {
          // Kinogo DLE-рейтинг
          final votesEl = card.querySelector(".rating__votes");
          if (votesEl != null) {
            final match = RegExp(r'([0-9.]+)/5').firstMatch(votesEl.text);
            if (match != null) {
              final val = double.tryParse(match.group(1) ?? '');
              if (val != null) {
                rating = (val * 2).toStringAsFixed(1);
              }
            }
          }
        }
        if (rating.isEmpty) rating = '7.5';

        // ── Год ──
        String year = '2024';
        final yearEl = card.querySelector(".item__rates-item.kp a, .item__rates-item.kp");
        if (yearEl != null) {
          final yearText = yearEl.text.trim();
          if (RegExp(r'^\d{4}$').hasMatch(yearText)) {
            year = yearText;
          }
        }
        // Kinogo fallback
        if (year == '2024') {
          final infoItems = card.querySelectorAll(".movie__info-item, .shortstory__info span, .shortstory__info-wrapper span");
          for (var item in infoItems) {
            if (item.text.toLowerCase().contains('год')) {
              final yearLink = item.querySelector("a");
              if (yearLink != null) {
                year = yearLink.text.trim();
              } else {
                final yearMatch = RegExp(r'\b(20\d{2}|19\d{2})\b').firstMatch(item.text);
                if (yearMatch != null) year = yearMatch.group(1)!;
              }
              break;
            }
          }
        }

        // ── Жанр ──
        String genre = 'Фильм';
        final genreEl = card.querySelector(".genres");
        if (genreEl != null) {
          genre = genreEl.text.trim();
        } else {
          final infoItems = card.querySelectorAll(".movie__info-item, .shortstory__info span, .shortstory__info-wrapper span");
          for (var item in infoItems) {
            if (item.text.toLowerCase().contains('жанр')) {
              final genreLinks = item.querySelectorAll("a");
              if (genreLinks.isNotEmpty) {
                genre = genreLinks.map((g) => g.text.trim()).join(', ');
              }
              break;
            }
          }
        }

        // ── Страна ──
        String country = 'Зарубежный';
        final infoItems = card.querySelectorAll(".movie__info-item, .shortstory__info span, .shortstory__info-wrapper span");
        for (var item in infoItems) {
          if (item.text.toLowerCase().contains('страна')) {
            final countryLinks = item.querySelectorAll("a");
            if (countryLinks.isNotEmpty) {
              country = countryLinks.map((c) => c.text.trim()).join(', ');
            } else {
              final cleanText = item.text.replaceAll(RegExp(r'страна:?', caseSensitive: false), '').trim();
              if (cleanText.isNotEmpty) country = cleanText;
            }
            break;
          }
        }

        // ── Описание ──
        final descEl = card.querySelector(".excerpt, .movie__info-desc");
        final description = descEl?.text.trim() ?? 'Смотрите онлайн.';

        // ── Тип контента ──
        String finalType = 'Фильм';
        final labelEl = card.querySelector(".item__label");
        if (labelEl != null) {
          final label = labelEl.text.trim().toLowerCase();
          if (label.contains('сериал') || label == 'сериал') {
            finalType = 'Сериал';
          } else if (label.contains('аниме') || label == 'аниме') {
            finalType = 'Аниме';
          } else if (label.contains('мульт')) {
            finalType = 'Мультфильм';
          }
        } else {
          final detailsUrlLower = fullDetailsUrl.toLowerCase();
          final genreLower = genre.toLowerCase();
          final titleLower = title.toLowerCase();

          if (detailsUrlLower.contains('/anime') || genreLower.contains('аниме')) {
            finalType = 'Аниме';
          } else if (detailsUrlLower.contains('/series') || detailsUrlLower.contains('/serialy/') || 
                     titleLower.contains('сезон') || titleLower.contains('сериал') || genreLower.contains('сериал')) {
            finalType = 'Сериал';
          } else if (genreLower.contains('дорам')) {
            finalType = 'Дорама';
          } else if (detailsUrlLower.contains('/multfilm') || detailsUrlLower.contains('/multseries')) {
            finalType = 'Мультфильм';
          }
        }

        movies.add(MovieItem(
          id: fullDetailsUrl,
          title: title,
          type: finalType,
          coverUrl: coverUrl.isEmpty ? 'https://images.unsplash.com/photo-1485846234645-a62644f84728?q=80&w=400' : coverUrl,
          bannerUrl: coverUrl,
          rating: rating,
          year: year,
          genre: genre,
          description: description,
          country: country,
        ));
      }
    } catch (e) {
      print("Ошибка парсинга HTML: $e");
    }
    return movies;
  }
}

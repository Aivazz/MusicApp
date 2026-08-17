import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/cinema/models/movie_item.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/core/widgets/scale_button.dart';

class CustomVideoPlayerScreen extends StatefulWidget {
  final String playerUrl;
  final String title;
  final String subtitle;
  final bool isSeries;
  final int initialSeason;
  final int initialEpisode;
  final int seasonsCount;
  final int episodesCount;
  final MovieItem? movie;

  const CustomVideoPlayerScreen({
    super.key,
    required this.playerUrl,
    required this.title,
    required this.subtitle,
    this.isSeries = false,
    this.initialSeason = 1,
    this.initialEpisode = 1,
    this.seasonsCount = 1,
    this.episodesCount = 1,
    this.movie,
  });

  @override
  State<CustomVideoPlayerScreen> createState() => _CustomVideoPlayerScreenState();
}

class _CustomVideoPlayerScreenState extends State<CustomVideoPlayerScreen> with TickerProviderStateMixin {
  late WebViewController _webViewController;
  bool _isLoading = true;
  bool _isPlayerReady = false;

  // Контроль воспроизведения
  bool _isPlaying = false;
  double _currentTime = 0.0;
  double _duration = 1.0;
  double _playbackSpeed = 1.0;
  String _quality = "360p";

  // Состояние воспроизведения сериала
  late int _currentSeason;
  late int _currentEpisode;
  late String _currentSubtitle;
  late String _currentPlayerUrl;

  // Жесты и оверлеи
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isLocked = false;

  // Имитация яркости (через затемняющий слой)
  double _brightness = 1.0; // 1.0 = ярко, 0.0 = темно
  bool _showBrightnessIndicator = false;
  Timer? _brightnessTimer;

  // Индикаторы быстрой перемотки (double tap)
  bool _showLeftSeekIndicator = false;
  bool _showRightSeekIndicator = false;
  Timer? _seekIndicatorTimer;

  // Громкость (через JS-управление видео-тегом)
  double _volume = 1.0; // 0.0 до 1.0
  bool _showVolumeIndicator = false;
  Timer? _volumeTimer;

  // Анимация пульсации и кнопок
  late AnimationController _playPauseController;
  late AnimationController _fadeController;

  // Периодическое чтение состояния плеера
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();

    _currentSeason = widget.initialSeason;
    _currentEpisode = widget.initialEpisode;
    _currentSubtitle = widget.subtitle;
    _currentPlayerUrl = widget.playerUrl;

    // Блокируем ориентацию в альбомный режим
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );

    _initWebViewController();
    _startHideTimer();
    _startUpdateTimer();
  }

  @override
  void dispose() {
    // Возвращаем портретную ориентацию и системные бары
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _hideTimer?.cancel();
    _updateTimer?.cancel();
    _brightnessTimer?.cancel();
    _volumeTimer?.cancel();
    _seekIndicatorTimer?.cancel();
    _playPauseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _initWebViewController() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _webViewController = WebViewController.fromPlatformCreationParams(params);

    // Разрешаем автовоспроизведение медиа без жестов на Android
    if (_webViewController.platform is AndroidWebViewController) {
      (_webViewController.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _webViewController
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            _injectVideoListeners();
          },
          onNavigationRequest: (NavigationRequest request) {
            // Блокируем рекламные редиректы и всплывающие окна
            if (request.url.contains("collaps") || 
                request.url.contains("kinogo") || 
                request.url.contains("cdn") || 
                request.url == _currentPlayerUrl) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );
    _loadPlayerUrl();
  }

  Future<void> _loadPlayerUrl() async {
    if (!_currentPlayerUrl.startsWith('http')) {
      final fileUri = _currentPlayerUrl.startsWith('file://') 
          ? _currentPlayerUrl 
          : Uri.file(_currentPlayerUrl).toString();
      
      final isHls = _currentPlayerUrl.contains('.m3u8');
      
      String scriptTag = "";
      String hlsJsSetup = "";
      
      if (isHls) {
        final dir = await getApplicationDocumentsDirectory();
        final hlsJsFile = File('${dir.path}/hls.min.js');
        if (await hlsJsFile.exists()) {
          final hlsJsFileUri = Uri.file(hlsJsFile.path).toString();
          scriptTag = '<script src="$hlsJsFileUri"></script>';
        } else {
          scriptTag = '<script src="https://cdn.jsdelivr.net/npm/hls.js@1.4.12/dist/hls.min.js"></script>';
        }
        hlsJsSetup = """
          if (typeof Hls !== 'undefined' && Hls.isSupported()) {
            var config = {
              maxBufferLength: 30,
              maxMaxBufferLength: 90,
              maxBufferSize: 80 * 1024 * 1024,
              enableWorker: true,
              lowBufferWatchdogPeriod: 0.5,
              nudgeOffset: 0.1,
              nudgeMaxRetry: 5
            };
            var hls = new Hls(config);
            hls.loadSource('$fileUri');
            hls.attachMedia(video);
          } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
            video.src = '$fileUri';
          } else {
            video.src = '$fileUri';
          }
        """;
      } else {
        hlsJsSetup = "video.src = '$fileUri';";
      }

      final localHtml = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <style>
            body, html {
              margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background-color: #000;
            }
            video {
              width: 100%; height: 100%; object-fit: contain; position: fixed; top: 0; left: 0; z-index: 999999;
            }
            video::-webkit-media-controls { display: none !important; }
            video::-webkit-media-controls-enclosure { display: none !important; }
          </style>
          $scriptTag
        </head>
        <body>
          <video id="offline-video" autoplay playsinline></video>
          <script>
            var video = document.getElementById('offline-video');
            $hlsJsSetup
          </script>
        </body>
        </html>
      """;
      _webViewController.loadHtmlString(localHtml, baseUrl: 'file://');
    } else {
      _webViewController.loadRequest(Uri.parse(_currentPlayerUrl));
    }
  }

  // Инъекция JS для автоматического поиска видео-тега и подписки на события
  void _injectVideoListeners() {
    const jsSetup = """
      (function() {
        var video = document.querySelector('video');
        if (video) {
          // Запускаем воспроизведение
          video.play().catch(function(e) {});
          
          // Отключаем нативные элементы управления HTML5 видео
          video.controls = false;
          
          // Принудительно позиционируем видео на весь экран поверх всего
          video.style.setProperty('position', 'fixed', 'important');
          video.style.setProperty('top', '0', 'important');
          video.style.setProperty('left', '0', 'important');
          video.style.setProperty('width', '100%', 'important');
          video.style.setProperty('height', '100%', 'important');
          video.style.setProperty('z-index', '999999', 'important');
          video.style.setProperty('background', '#000000', 'important');
          video.style.setProperty('object-fit', 'contain', 'important');

          // Добавляем глобальный стиль для скрытия кастомных элементов управления третьей стороны (Collaps, CDN и др.)
          var style = document.createElement('style');
          style.textContent = `
            video::-webkit-media-controls { display: none !important; }
            video::-webkit-media-controls-enclosure { display: none !important; }
            .vjs-control-bar, .player-controls, .controls, .control-bar, .clps-controls, .kinogo-controls, .yohoho-controls, .iframe-player-controls, .plyr__controls, .players-controls, .translations, .quality, .settings, .branding, .logo, .watermark, .click-to-play, .play-button-overlay {
              display: none !important;
            }
          `;
          document.head.appendChild(style);
          return true;
        }
        return false;
      })();
    """;
    _webViewController.runJavaScript(jsSetup);
  }

  // Обновление состояния плеера из WebView
  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_isLoading || _isLocked) return;

      try {
        final stateJson = await _webViewController.runJavaScriptReturningResult("""
          (function() {
            var video = document.querySelector('video');
            if (video) {
              // Каждую итерацию принудительно скрываем нативные кнопки и выносим видео поверх
              video.controls = false;
              if (video.style.position !== 'fixed') {
                video.style.setProperty('position', 'fixed', 'important');
                video.style.setProperty('top', '0', 'important');
                video.style.setProperty('left', '0', 'important');
                video.style.setProperty('width', '100%', 'important');
                video.style.setProperty('height', '100%', 'important');
                video.style.setProperty('z-index', '999999', 'important');
                video.style.setProperty('background', '#000000', 'important');
                video.style.setProperty('object-fit', 'contain', 'important');
              }
              
              // Каждую итерацию скрываем рекламу, заголовки, выбор перевода и панели управления
              var selectors = [
                '.vjs-control-bar', '.player-controls', '.controls', '.control-bar', 
                '.clps-controls', '.kinogo-controls', '.yohoho-controls', 
                '.plyr__controls', '.players-controls', '.translations', '.quality', 
                '.settings', '.branding', '.logo', '.watermark', '.click-to-play',
                '.play-button-overlay', '.vast-blocker', '.ad-banner',
                '[class*="controls"]', '[class*="control-bar"]',
                '[class*="player-panel"]', '[class*="header"]', '[class*="title"]',
                '[class*="panel"]'
              ];
              selectors.forEach(function(sel) {
                var elements = document.querySelectorAll(sel);
                elements.forEach(function(el) {
                  if (el && el !== video && !el.contains(video)) {
                    el.style.setProperty('display', 'none', 'important');
                  }
                });
              });

              return JSON.stringify({
                currentTime: video.currentTime,
                duration: video.duration,
                paused: video.paused,
                playbackRate: video.playbackRate,
                volume: video.volume,
                ended: video.ended
              });
            }
            return null;
          })();
        """);

        if (stateJson != null && stateJson.toString() != "null" && stateJson.toString().isNotEmpty) {
          // Декодируем JSON-строку, которая иногда возвращается обернутой в кавычки в некоторых версиях WebView
          String cleanJson = stateJson.toString();
          if (cleanJson.startsWith('"') && cleanJson.endsWith('"')) {
            cleanJson = cleanJson.substring(1, cleanJson.length - 1)
                .replaceAll(r'\"', '"')
                .replaceAll(r'\\', r'\');
          }

          // Ручной парсинг простых полей, чтобы избежать внешних зависимостей
          final curTimeMatch = RegExp(r'"currentTime":\s*([0-9.]+)').firstMatch(cleanJson);
          final durMatch = RegExp(r'"duration":\s*([0-9.]+)').firstMatch(cleanJson);
          final pausedMatch = RegExp(r'"paused":\s*(true|false)').firstMatch(cleanJson);
          final speedMatch = RegExp(r'"playbackRate":\s*([0-9.]+)').firstMatch(cleanJson);
          final volMatch = RegExp(r'"volume":\s*([0-9.]+)').firstMatch(cleanJson);
          final endedMatch = RegExp(r'"ended":\s*(true|false)').firstMatch(cleanJson);

          if (mounted) {
            setState(() {
              _isPlayerReady = true;
              if (curTimeMatch != null) _currentTime = double.tryParse(curTimeMatch.group(1) ?? "0") ?? _currentTime;
              if (durMatch != null) {
                double parsedDur = double.tryParse(durMatch.group(1) ?? "1") ?? _duration;
                if (parsedDur > 0) _duration = parsedDur;
              }
              if (pausedMatch != null) {
                _isPlaying = pausedMatch.group(1) == "false";
                if (_isPlaying) {
                  _playPauseController.forward();
                } else {
                  _playPauseController.reverse();
                }
              }
              if (speedMatch != null) _playbackSpeed = double.tryParse(speedMatch.group(1) ?? "1.0") ?? _playbackSpeed;
              if (volMatch != null) _volume = double.tryParse(volMatch.group(1) ?? "1.0") ?? _volume;
            });

            // Автоматическое переключение на следующую серию при завершении
            final ended = endedMatch?.group(1) == "true";
            if (ended && widget.isSeries && !_isLoading) {
              _playNextEpisode();
            }
          }
        }
      } catch (e) {
        // Ошибка JS-вызова игнорируется, пока страница загружается
      }
    });
  }

  void _playNextEpisode() {
    if (!widget.isSeries) return;
    
    int nextEpisode = _currentEpisode + 1;
    int nextSeason = _currentSeason;
    
    if (nextEpisode > widget.episodesCount) {
      if (_currentSeason < widget.seasonsCount) {
        nextSeason = _currentSeason + 1;
        nextEpisode = 1;
      } else {
        AppTheme.showSnackBar(context, "Это последняя серия последнего сезона");
        return;
      }
    }
    
    _loadEpisode(nextSeason, nextEpisode);
  }

  void _playPreviousEpisode() {
    if (!widget.isSeries) return;
    
    int prevEpisode = _currentEpisode - 1;
    int prevSeason = _currentSeason;
    
    if (prevEpisode < 1) {
      if (_currentSeason > 1) {
        prevSeason = _currentSeason - 1;
        prevEpisode = widget.episodesCount;
      } else {
        AppTheme.showSnackBar(context, "Это первая серия первого сезона");
        return;
      }
    }
    
    _loadEpisode(prevSeason, prevEpisode);
  }

  void _loadEpisode(int season, int episode) {
    setState(() {
      _isLoading = true;
      _currentSeason = season;
      _currentEpisode = episode;
      
      final uri = Uri.parse(_currentPlayerUrl);
      final newParams = Map<String, String>.from(uri.queryParameters);
      newParams['season'] = season.toString();
      newParams['episode'] = episode.toString();
      _currentPlayerUrl = uri.replace(queryParameters: newParams).toString();
      
      final parts = _currentSubtitle.split('•');
      if (parts.length >= 3) {
        final translation = parts.last.trim();
        _currentSubtitle = "$season сезон • $episode серия • $translation";
      } else {
        _currentSubtitle = "$season сезон • $episode серия";
      }
    });
    
    _loadPlayerUrl();
  }

  void _showEpisodesMenu() {
    _resetHideTimer();
    showDialog(
      context: context,
      builder: (context) {
        int tempSeason = _currentSeason;
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AlertDialog(
                backgroundColor: const Color(0xFF141414).withOpacity(0.92),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
                title: const Text(
                  "Выбор серии",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                content: Container(
                  width: MediaQuery.of(context).size.width * 0.6,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Сезон", style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 34,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: widget.seasonsCount,
                          itemBuilder: (context, index) {
                            final sNum = index + 1;
                            final isSel = tempSeason == sNum;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ScaleButton(
                                scaleFactor: 0.95,
                                onTap: () {
                                  setDialogState(() {
                                    tempSeason = sNum;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: isSel ? AppColors.accentGreen : Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    "$sNum сезон",
                                    style: TextStyle(
                                      color: isSel ? Colors.white : Colors.white70,
                                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text("Серия", style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 6),
                      Container(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.35,
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 6,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                              childAspectRatio: 1.3,
                            ),
                            itemCount: widget.episodesCount,
                            itemBuilder: (context, index) {
                              final epNum = index + 1;
                              final isSel = _currentEpisode == epNum && tempSeason == _currentSeason;
                              return ScaleButton(
                                scaleFactor: 0.92,
                                onTap: () {
                                  Navigator.pop(context);
                                  _loadEpisode(tempSeason, epNum);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSel ? AppColors.accentGreen : Colors.white.withOpacity(0.04),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSel ? Colors.transparent : Colors.white.withOpacity(0.06),
                                      width: 1,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    "$epNum",
                                    style: TextStyle(
                                      color: isSel ? Colors.white : Colors.white70,
                                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Управление воспроизведением
  void _togglePlay() {
    _resetHideTimer();
    if (_isPlaying) {
      _webViewController.runJavaScript("document.querySelector('video').pause();");
      _playPauseController.reverse();
      setState(() => _isPlaying = false);
    } else {
      _webViewController.runJavaScript("document.querySelector('video').play();");
      _playPauseController.forward();
      setState(() => _isPlaying = true);
    }
  }

  void _seekTo(double seconds) {
    _resetHideTimer();
    setState(() {
      _currentTime = seconds;
    });
    _webViewController.runJavaScript("document.querySelector('video').currentTime = $seconds;");
  }

  void _setPlaybackSpeed(double speed) {
    _resetHideTimer();
    setState(() {
      _playbackSpeed = speed;
    });
    _webViewController.runJavaScript("document.querySelector('video').playbackRate = $speed;");
  }

  // Автоматическое скрытие элементов управления
  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
        _fadeController.reverse();
      }
    });
  }

  void _resetHideTimer() {
    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
      _fadeController.forward();
    }
    _startHideTimer();
  }

  void _toggleControls() {
    if (_isLocked) {
      setState(() {
        _showControls = !_showControls;
      });
      if (_showControls) {
        _fadeController.forward();
        _startHideTimer();
      } else {
        _fadeController.reverse();
        _hideTimer?.cancel();
      }
      return;
    }
    
    _hideTimer?.cancel();
    if (_showControls) {
      setState(() {
        _showControls = false;
      });
      _fadeController.reverse();
    } else {
      setState(() {
        _showControls = true;
      });
      _fadeController.forward();
      _startHideTimer();
    }
  }

  // Форматирование времени
  String _formatDuration(double seconds) {
    if (seconds.isNaN || seconds.isInfinite) return "00:00";
    final duration = Duration(seconds: seconds.toInt());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return "$hours:$minutes:$secs";
    }
    return "$minutes:$secs";
  }

  // Управление яркостью (жест слева)
  void _adjustBrightness(double delta) {
    setState(() {
      _showBrightnessIndicator = true;
      _brightness = (_brightness + delta).clamp(0.1, 1.0);
    });

    _brightnessTimer?.cancel();
    _brightnessTimer = Timer(const Duration(seconds: 1), () {
      setState(() => _showBrightnessIndicator = false);
    });
  }

  // Управление громкостью через JS (жест справа)
  void _adjustVolume(double delta) {
    setState(() {
      _showVolumeIndicator = true;
      _volume = (_volume + delta).clamp(0.0, 1.0);
    });
    _webViewController.runJavaScript("document.querySelector('video').volume = $_volume;");

    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(seconds: 1), () {
      setState(() => _showVolumeIndicator = false);
    });
  }

  // Меню выбора скорости
  void _showSpeedMenu() {
    _resetHideTimer();
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161616),
      barrierColor: Colors.black54,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return Container(
          color: const Color(0xFF161616),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    "Скорость воспроизведения",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: speeds.map((speed) {
                          final isSelected = _playbackSpeed == speed;
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              dense: true,
                              title: Text(
                                speed == 1.0 ? "Обычная" : "${speed}x",
                                style: TextStyle(
                                  color: isSelected ? AppColors.accentGreen : Colors.white70,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                              trailing: isSelected ? Icon(Icons.check, color: AppColors.accentGreen, size: 18) : null,
                              onTap: () {
                                _setPlaybackSpeed(speed);
                                Navigator.pop(context);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Изменение качества видео через JS-инъекцию
  void _setQuality(String q) {
    _resetHideTimer();
    setState(() {
      _quality = q;
    });

    final cleanQ = q.replaceAll('p', '');

    final jsCode = """
      (function() {
        var targetQ = "$q";
        var cleanQ = "$cleanQ";
        
        var clicked = false;
        var els = document.querySelectorAll('button, li, span, div, a, .vjs-menu-item, .plyr__menu__container button, .clps-quality-item, [class*="quality"]');
        for (var i = 0; i < els.length; i++) {
          var el = els[i];
          var text = (el.textContent || el.innerText || "").trim().toLowerCase();
          if (text === targetQ.toLowerCase() || text === cleanQ || text === (cleanQ + " p") || text === (cleanQ + "p")) {
            el.click();
            var ev = new MouseEvent('click', { bubbles: true, cancelable: true, view: window });
            el.dispatchEvent(ev);
            clicked = true;
          }
        }
        if (clicked) return true;

        if (window.player && typeof window.player.currentSources === 'function') {
          var sources = window.player.currentSources();
          if (sources && sources.length > 0) {
            for (var i = 0; i < sources.length; i++) {
              if (sources[i].label && sources[i].label.indexOf(cleanQ) !== -1) {
                window.player.src(sources[i]);
                window.player.play().catch(function(e){});
                return true;
              }
            }
          }
        }

        return false;
      })();
    """;

    _webViewController.runJavaScript(jsCode);
  }

  void _showQualityMenu() {
    _resetHideTimer();
    final qualities = ["360p", "480p", "720p", "1080p"];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161616),
      barrierColor: Colors.black54,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return Container(
          color: const Color(0xFF161616),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    "Качество видео",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: qualities.map((q) {
                          final isSelected = _quality == q;
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              dense: true,
                              title: Text(
                                q,
                                style: TextStyle(
                                  color: isSelected ? AppColors.accentGreen : Colors.white70,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                              trailing: isSelected ? Icon(Icons.check, color: AppColors.accentGreen, size: 18) : null,
                              onTap: () {
                                _setQuality(q);
                                Navigator.pop(context);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. WEBVIEW С ПЛЕЕРОМ
          IgnorePointer(
            ignoring: _showControls, // Когда оверлей открыт, кликаем по оверлею. Когда скрыт — кликаем в WebView.
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: WebViewWidget(controller: _webViewController),
              ),
            ),
          ),

          // 2. ИМИТАЦИЯ ЯРКОСТИ (Черный оверлей поверх всего)
          if (_brightness < 1.0)
            IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity(1.0 - _brightness),
              ),
            ),

          // 3. ЗОНЫ ЖЕСТОВ И КЛИКОВ (Показываются, когда оверлей активен)
          GestureDetector(
            onTap: _toggleControls,
            onDoubleTapDown: (details) {
              if (_isLocked) return;
              _resetHideTimer();
              final screenWidth = MediaQuery.of(context).size.width;
              final tapX = details.globalPosition.dx;
              
              if (tapX < screenWidth / 2) {
                // Двойной тап слева -> Перемотка назад
                setState(() {
                  _showLeftSeekIndicator = true;
                  _showRightSeekIndicator = false;
                });
                double newPos = _currentTime - 10;
                _seekTo(newPos.clamp(0.0, _duration));

                _seekIndicatorTimer?.cancel();
                _seekIndicatorTimer = Timer(const Duration(milliseconds: 600), () {
                  setState(() => _showLeftSeekIndicator = false);
                });
              } else {
                // Двойной тап справа -> Перемотка вперед
                setState(() {
                  _showRightSeekIndicator = true;
                  _showLeftSeekIndicator = false;
                });
                double newPos = _currentTime + 10;
                _seekTo(newPos.clamp(0.0, _duration));

                _seekIndicatorTimer?.cancel();
                _seekIndicatorTimer = Timer(const Duration(milliseconds: 600), () {
                  setState(() => _showRightSeekIndicator = false);
                });
              }
            },
            onVerticalDragUpdate: (details) {
              if (_isLocked) return;
              final screenWidth = MediaQuery.of(context).size.width;
              final delta = -details.primaryDelta! / 200; // Направление свайпа вверх = плюс
              if (details.globalPosition.dx < screenWidth / 2) {
                _adjustBrightness(delta);
              } else {
                _adjustVolume(delta);
              }
            },
            child: Container(
              color: Colors.transparent,
            ),
          ),

          // 4. ОВЕРЛЕИ С КНОПКАМИ УПРАВЛЕНИЯ
          FadeTransition(
            opacity: _fadeController,
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Stack(
                children: [
                  // Верхнее и нижнее затемнение для лучшей читаемости кнопок
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 80,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 90,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),

                  // ЭКРАН ЗАБЛОКИРОВАН (Кнопка быстрой разблокировки)
                  if (_isLocked)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: SafeArea(
                        child: ScaleButton(
                          onTap: () {
                            setState(() {
                              _isLocked = false;
                              _showControls = true;
                            });
                            _fadeController.forward();
                            _startHideTimer();
                          },
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.15)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: Icon(Icons.lock_outline_rounded, color: AppColors.accentGreen, size: 24),
                          ),
                        ),
                      ),
                    ),

                  // ЭЛЕМЕНТЫ УПРАВЛЕНИЯ (Когда экран не заблокирован)
                  if (!_isLocked) ...[
                    // А. ВЕРХНЯЯ ПАНЕЛЬ
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: SafeArea(
                        child: Row(
                          children: [
                            // Кнопка Назад
                            ScaleButton(
                              onTap: () => Navigator.pop(context),
                              child: const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Название и серия
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _currentSubtitle,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Скорость
                            ScaleButton(
                              onTap: _showSpeedMenu,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.play_circle_outline, color: Colors.white, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      _playbackSpeed == 1.0 ? "Обычн." : "${_playbackSpeed}x",
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 14),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Качество
                            ScaleButton(
                              onTap: _showQualityMenu,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.hd_outlined, color: Colors.white, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      _quality,
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 14),
                                  ],
                                ),
                              ),
                            ),
                            if (widget.isSeries) ...[
                              const SizedBox(width: 12),
                              // Серии
                              ScaleButton(
                                onTap: _showEpisodesMenu,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.format_list_bulleted_rounded, color: Colors.white, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        "Серия $_currentEpisode",
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 14),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (widget.movie != null && widget.playerUrl.startsWith('http') && false) ...[
                              const SizedBox(width: 12),
                              Consumer<UserProvider>(
                                builder: (context, userProvider, child) {
                                  final movieId = widget.isSeries 
                                      ? "${widget.movie!.id}_s${_currentSeason}_e${_currentEpisode}"
                                      : widget.movie!.id;
                                  final isDownloaded = userProvider.isMovieDownloaded(movieId);
                                  final isDownloading = userProvider.isMovieDownloading(movieId);
                                  final progress = userProvider.getMovieDownloadProgress(movieId);

                                  if (isDownloaded) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentGreen.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: AppColors.accentGreen.withOpacity(0.3)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 16),
                                          const SizedBox(width: 4),
                                          const Text(
                                            "Скачано",
                                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  if (isDownloading) {
                                    return ScaleButton(
                                      onTap: () => userProvider.cancelMovieDownload(movieId),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                value: progress,
                                                strokeWidth: 2,
                                                color: AppColors.accentGreen,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              "${(progress * 100).toInt()}%",
                                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  return ScaleButton(
                                    onTap: () async {
                                      try {
                                        final result = await _webViewController.runJavaScriptReturningResult("""
                                          (function() {
                                            function clean(url) {
                                              if (!url) return '';
                                              return url.replace(/\\\\/g, '').replace(/\\"/g, '').replace(/\\'/g, '');
                                            }

                                            var video = document.querySelector('video');

                                            // 0. Check Hls.js instances
                                            if (window.Hls && window.Hls.instances) {
                                              for (var i = 0; i < window.Hls.instances.length; i++) {
                                                var inst = window.Hls.instances[i];
                                                if (inst && inst.url && inst.url.startsWith('http')) {
                                                  return clean(inst.url);
                                                }
                                              }
                                            }
                                            if (window.hls && window.hls.url && window.hls.url.startsWith('http')) {
                                              return clean(window.hls.url);
                                            }

                                            // 1. Try to get from VideoJS player object if present
                                            if (window.player) {
                                              if (typeof window.player.currentSrc === 'function') {
                                                var src = window.player.currentSrc();
                                                if (src && !src.startsWith('blob:') && src.startsWith('http')) {
                                                  return clean(src);
                                                }
                                              }
                                              if (typeof window.player.src === 'function') {
                                                var src = window.player.src();
                                                if (src && typeof src === 'string' && !src.startsWith('blob:') && src.startsWith('http')) {
                                                  return clean(src);
                                                }
                                              }
                                              if (typeof window.player.currentSources === 'function') {
                                                var sources = window.player.currentSources();
                                                if (sources && sources.length > 0) {
                                                  for (var i = sources.length - 1; i >= 0; i--) {
                                                    var src = sources[i].src;
                                                    if (src && !src.startsWith('blob:') && src.startsWith('http')) {
                                                      return clean(src);
                                                    }
                                                  }
                                                }
                                              }
                                            }

                                            // 2. Try to get from video.currentSrc or video.src first if it's not a blob
                                            if (video) {
                                              var src = video.currentSrc || video.src;
                                              if (src && !src.startsWith('blob:') && src.startsWith('http')) {
                                                return clean(src);
                                              }
                                            }

                                            // 3. Search window object for common balancer video config variables
                                            if (window.playerParams && window.playerParams.file) {
                                              return clean(window.playerParams.file);
                                            }
                                            
                                            // Look for any string ending in .mp4 or .m3u8 in global variables
                                            for (var key in window) {
                                              if (key === 'webkitStorageInfo' || key === 'webkitIndexedDB') continue;
                                              try {
                                                var val = window[key];
                                                if (typeof val === 'string') {
                                                  if ((val.indexOf('.mp4') !== -1 || val.indexOf('.m3u8') !== -1) && val.startsWith('http')) {
                                                    return clean(val);
                                                  }
                                                }
                                              } catch(e) {}
                                            }

                                            // 4. Try finding inside all script tags
                                            var scripts = document.getElementsByTagName('script');
                                            for (var i = 0; i < scripts.length; i++) {
                                              var content = scripts[i].textContent || scripts[i].innerText;
                                              if (content) {
                                                var match = content.match(/https?:\\/\\/[^"\\s]+\\.(?:mp4|m3u8)[^"\\s]*/);
                                                if (match) return clean(match[0]);
                                                var match2 = content.match(/https?:\\/\\/[^'\\s]+\\.(?:mp4|m3u8)[^'\\s]*/);
                                                if (match2) return clean(match2[0]);
                                              }
                                            }

                                            return '';
                                          })();
                                        """);
                                        String videoUrl = result.toString();
                                        if (videoUrl.startsWith('"') && videoUrl.endsWith('"')) {
                                          videoUrl = videoUrl.substring(1, videoUrl.length - 1);
                                        }
                                        videoUrl = videoUrl.replaceAll(r'\/', '/').replaceAll(r'\\/', '/').replaceAll(r'\\', '').trim();

                                        if (videoUrl.isEmpty || videoUrl == 'null' || videoUrl.startsWith('blob:')) {
                                          AppTheme.showSnackBar(context, "Идет буферизация видео, попробуйте скачать через несколько секунд...");
                                        } else {
                                          AppTheme.showSnackBar(context, "Скачивание запущено");
                                           userProvider.downloadMovie(
                                             widget.movie!, 
                                             videoUrl,
                                             season: widget.isSeries ? _currentSeason : null,
                                             episode: widget.isSeries ? _currentEpisode : null,
                                           ).then((_) {
                                             if (context.mounted) {
                                               AppTheme.showSnackBar(context, "Скачивание успешно завершено!");
                                             }
                                           }).catchError((err) {
                                             if (context.mounted) {
                                               AppTheme.showSnackBar(context, "Ошибка при скачивании: $err");
                                             }
                                           });
                                        }
                                      } catch (e) {
                                        AppTheme.showSnackBar(context, "Не удалось начать скачивание: $e");
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.download_for_offline_outlined, color: Colors.white, size: 16),
                                          const SizedBox(width: 4),
                                          const Text(
                                            "Скачать",
                                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                            const SizedBox(width: 12),
                            // Заблокировать экран
                            ScaleButton(
                              onTap: () {
                                setState(() {
                                  _isLocked = true;
                                  _showControls = true;
                                });
                                _startHideTimer();
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Icon(Icons.lock_open_outlined, color: Colors.white, size: 24),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Б. ЦЕНТРАЛЬНАЯ КНОПКА PLAY/PAUSE И SKIP
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Предыдущая серия / перемотка назад
                          ScaleButton(
                            onTap: () {
                              _resetHideTimer();
                              if (widget.isSeries) {
                                _playPreviousEpisode();
                              } else {
                                double newPos = _currentTime - 10;
                                _seekTo(newPos.clamp(0.0, _duration));
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.skip_previous_rounded, color: Colors.white, size: 40),
                            ),
                          ),
                          const SizedBox(width: 32),
                          // Главная кнопка воспроизведения
                          ScaleButton(
                            scaleFactor: 0.92,
                            onTap: _togglePlay,
                            child: Container(
                              width: 72,
                              height: 72,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 15,
                                    offset: Offset(0, 4),
                                  )
                                ],
                              ),
                              child: AnimatedIcon(
                                icon: AnimatedIcons.play_pause,
                                progress: _playPauseController,
                                color: Colors.black,
                                size: 36,
                              ),
                            ),
                          ),
                          const SizedBox(width: 32),
                          // Следующая серия / перемотка вперед
                          ScaleButton(
                            onTap: () {
                              _resetHideTimer();
                              if (widget.isSeries) {
                                _playNextEpisode();
                              } else {
                                double newPos = _currentTime + 10;
                                _seekTo(newPos.clamp(0.0, _duration));
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.skip_next_rounded, color: Colors.white, size: 40),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // В. НИЖНЯЯ ПАНЕЛЬ С СЛАЙДЕРОМ
                    Positioned(
                      bottom: 12,
                      left: 16,
                      right: 16,
                      child: SafeArea(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                // Текущее время
                                Text(
                                  _formatDuration(_currentTime),
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                // Слайдер (Timeline)
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      activeTrackColor: Colors.white,
                                      inactiveTrackColor: Colors.white24,
                                      thumbColor: Colors.white,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                    ),
                                    child: Slider(
                                      value: _currentTime.clamp(0.0, _duration),
                                      min: 0.0,
                                      max: _duration,
                                      onChanged: (val) {
                                        setState(() {
                                          _currentTime = val;
                                        });
                                      },
                                      onChangeEnd: (val) {
                                        _seekTo(val);
                                      },
                                    ),
                                  ),
                                ),
                                // Общее время
                                Text(
                                  _formatDuration(_duration),
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 16),
                                // Ускоренная перемотка >>
                                const Icon(Icons.double_arrow_rounded, color: Colors.white, size: 20),
                                const SizedBox(width: 16),
                                // PiP / Картинка в картинке
                                const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 20),
                                const SizedBox(width: 16),
                                // Полноэкранный режим
                                IconButton(
                                  icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 24),
                                  onPressed: () {
                                    _resetHideTimer();
                                    // Симулируем выход по клику на полноэкранную иконку (или другое действие)
                                    AppTheme.showSnackBar(context, "Плеер уже запущен во весь экран.");
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 5. ИНДИКАТОР ГРОМКОСТИ (Правая сторона)
          if (_showVolumeIndicator)
            Positioned(
              right: 40,
              top: MediaQuery.of(context).size.height / 2 - 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.volume_up_rounded, color: Colors.white, size: 20),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: LinearProgressIndicator(
                          value: _volume,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 6. ИНДИКАТОР ЯРКОСТИ (Левая сторона)
          if (_showBrightnessIndicator)
            Positioned(
              left: 40,
              top: MediaQuery.of(context).size.height / 2 - 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.brightness_5_rounded, color: Colors.white, size: 20),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: LinearProgressIndicator(
                          value: _brightness,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 8. ВИЗУАЛЬНЫЕ ОВЕРЛЕИ ДВОЙНОГО ТАПА
          if (_showLeftSeekIndicator)
            Positioned(
              left: MediaQuery.of(context).size.width / 4 - 36,
              top: MediaQuery.of(context).size.height / 2 - 36,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    width: 72,
                    height: 72,
                    color: Colors.black45,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fast_rewind_rounded, color: Colors.white, size: 28),
                        SizedBox(height: 4),
                        Text("-10 сек", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (_showRightSeekIndicator)
            Positioned(
              right: MediaQuery.of(context).size.width / 4 - 36,
              top: MediaQuery.of(context).size.height / 2 - 36,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    width: 72,
                    height: 72,
                    color: Colors.black45,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fast_forward_rounded, color: Colors.white, size: 28),
                        SizedBox(height: 4),
                        Text("+10 сек", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 7. СПИННЕР ЗАГРУЗКИ ПЛЕЕРА
          if (_isLoading)
            Container(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

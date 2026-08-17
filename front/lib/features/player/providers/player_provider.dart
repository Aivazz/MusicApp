import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:ses/features/player/services/audio_handler.dart';
import 'package:path_provider/path_provider.dart'; // 🌟 Для динамического поиска скачанных файлов
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/import_export/services/pirate_service.dart';
import 'package:ses/core/network/backend_service.dart';
import 'package:ses/core/network/firebase_service.dart';
import 'package:ses/features/auth/providers/user_provider.dart';

enum PlayerState { idle, loading, playing, paused, error }

class PlayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  String _getSafeFileName(String id) {
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  }

  UserProvider? _userProvider;
  String? _currentUid;

  void setDependency(UserProvider userProvider) {
    _userProvider = userProvider;
    final newUid = FirebaseService.currentUser?.uid;
    if (_currentUid != newUid) {
      _currentUid = newUid;
      if (newUid == null) {
        stopAndReset();
      } else {
        playHistory.clear();
        _loadPlayHistory();
      }
    }
    if (playHistory.isNotEmpty) {
      _userProvider?.triggerSmartCache(playHistory.map((e) => e.song).toList());
    }
  }
  final AudioPlayer _audioPlayer = audioHandler.player;

  Song? _currentSong;
  PlayerState _state = PlayerState.idle;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String? _errorMessage;

  bool _isShuffle = false;
  int _repeatMode = 0; // 0: Выкл, 1: Повтор всех, 2: Повтор одной

  List<Song> queue = [];
  List<PlayHistoryEntry> playHistory = [];

  int _activeSessionId = 0;
  ConcatenatingAudioSource? _playlistSource;
  final Set<String> _resolvingIds = {};
  Timer? _saveHistoryDebounce;

  Timer? _sleepTimer;
  Timer? _sleepTimerTicker;
  Duration? _sleepDurationRemaining;
  bool _showMiniPlayer = true;

  Duration? get sleepDurationRemaining => _sleepDurationRemaining;
  bool get showMiniPlayer => _showMiniPlayer;

  void setShowMiniPlayer(bool value) {
    if (_showMiniPlayer != value) {
      _showMiniPlayer = value;
      notifyListeners();
    }
  }

  Song? get currentSong => _currentSong;
  bool get isPlaying => _state == PlayerState.playing;
  bool get isLoading => _state == PlayerState.loading;
  PlayerState get state => _state;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  String? get errorMessage => _errorMessage;
  late final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  late final Stream<Duration> positionStream = _positionController.stream;
  StreamSubscription<Duration>? _nativePositionSub;
  Timer? _positionTimer;
  bool _useHighPrecision = false;
  bool _isAppInBackground = false;

  void setHighPrecision(bool enable) {
    if (_useHighPrecision != enable) {
      _useHighPrecision = enable;
      _updatePositionTimer();
    }
  }

  void _updatePositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;

    if (_useHighPrecision && !_isAppInBackground && _audioPlayer.playing) {
      _positionTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
        if (!_positionController.isClosed) {
          _currentPosition = _audioPlayer.position;
          _positionController.add(_currentPosition);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _isAppInBackground = true;
      _updatePositionTimer();
    } else if (state == AppLifecycleState.resumed) {
      _isAppInBackground = false;
      _updatePositionTimer();
    }
  }

  void _initPositionStream() {
    _nativePositionSub = _audioPlayer.positionStream.listen((pos) {
      _currentPosition = pos;
      if (!_positionController.isClosed) {
        _positionController.add(pos);
      }

      // Aggressive prefetch: if 15 seconds remaining, ensure index+1 and index+2 are resolved
      if (_totalDuration > Duration.zero && _totalDuration - pos < const Duration(seconds: 15)) {
        final currentIndex = _audioPlayer.currentIndex;
        if (currentIndex != null) {
          final nextIndex = currentIndex + 1;
          if (nextIndex < queue.length) {
            final nextSong = queue[nextIndex];
            if (!nextSong.videoId.startsWith('http') && !_resolvingIds.contains(nextSong.id)) {
              _resolveSongsAroundIndex(currentIndex, _activeSessionId);
            }
          }
        }
      }
    }, onError: (e) {
      _handlePlayerError(e);
    });
  }

  void updateDragPosition(Duration pos) {
    _currentPosition = pos;
    if (!_positionController.isClosed) {
      _positionController.add(pos);
    }
  }

  bool get isShuffle => _isShuffle;
  int get repeatMode => _repeatMode;

  PlayerProvider() {
    _initPositionStream();
    _listenToPlayer();
    _loadPlayHistory();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _loadPlayHistory() async {
    try {
      final firestoreHistory = await FirebaseService.getPlayHistory();
      if (firestoreHistory.isNotEmpty) {
        playHistory = firestoreHistory;
        notifyListeners();
        await _savePlayHistoryLocalOnly();
        if (playHistory.isNotEmpty) {
          _userProvider?.triggerSmartCache(playHistory.map((e) => e.song).toList());
        }
        return;
      }

      final file = await BackendService.getLocalFile('play_history.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final list = jsonDecode(jsonStr) as List;
        try {
          playHistory = list.map((j) => PlayHistoryEntry.fromJson(j)).toList();
        } catch (_) {
          final oldSongs = list.map((j) => Song.fromJson(j)).toList();
          playHistory = oldSongs.map((s) => PlayHistoryEntry(song: s, playedAt: DateTime.now())).toList();
        }
        notifyListeners();
        if (playHistory.isNotEmpty) {
          _userProvider?.triggerSmartCache(playHistory.map((e) => e.song).toList());
        }
      }
    } catch (e) {
      print("Ошибка загрузки истории прослушиваний: $e");
    }
  }

  Future<void> _savePlayHistoryLocalOnly() async {
    try {
      final file = await BackendService.getLocalFile('play_history.json');
      await file.writeAsString(
        jsonEncode(playHistory.map((entry) => entry.toJson()).toList()),
      );
    } catch (e) {
      print("Ошибка сохранения истории прослушиваний локально: $e");
    }
  }

  Future<void> _savePlayHistory() async {
    await _savePlayHistoryLocalOnly();
    await FirebaseService.savePlayHistory(playHistory);
  }

  Future<void> clearPlayHistory() async {
    try {
      playHistory.clear();
      notifyListeners();
      final file = await BackendService.getLocalFile('play_history.json');
      if (await file.exists()) {
        await file.delete();
      }
      await FirebaseService.savePlayHistory([]);
      _userProvider?.triggerSmartCache([]);
    } catch (e) {
      print("Ошибка очистки истории прослушиваний: $e");
    }
  }

  void _listenToPlayer() {
    _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        _totalDuration = duration;
        notifyListeners();
      }
    }, onError: (e) {
      _handlePlayerError(e);
    });

    _audioPlayer.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.loading ||
          playerState.processingState == ProcessingState.buffering) {
        _state = PlayerState.loading;
      } else if (playerState.playing) {
        _state = PlayerState.playing;
        _showMiniPlayer = true;
        _errorMessage = null;
      } else if (playerState.processingState == ProcessingState.completed) {
        _state = PlayerState.idle;
      } else {
        _state = PlayerState.paused;
      }
      _updatePositionTimer();
      notifyListeners();
    }, onError: (e) {
      _handlePlayerError(e);
    });

    _audioPlayer.currentIndexStream.listen((index) {
      if (index != null && queue.isNotEmpty && index < queue.length) {
        _currentSong = queue[index];
        _showMiniPlayer = true;

        // Обновляем "Недавно прослушанные"
        playHistory.removeWhere((entry) => entry.song.id == _currentSong!.id);
        playHistory.insert(0, PlayHistoryEntry(song: _currentSong!, playedAt: DateTime.now()));
        if (playHistory.length > 50) playHistory = playHistory.sublist(0, 50);
        _saveHistoryDebounce?.cancel();
        _saveHistoryDebounce = Timer(const Duration(seconds: 2), () => _savePlayHistory());

        // Обновляем предпочтения артиста на бэкенде для системы рекомендаций
        BackendService.updateArtistScore(_currentSong!.artist, 1);

        notifyListeners();
        _userProvider?.triggerSmartCache(playHistory.map((e) => e.song).toList());

        // Авто-кэширование при воспроизведении (если включено в настройках)
        if (_userProvider != null && _userProvider!.cacheOnPlay) {
          final s = _currentSong!;
          if (!_userProvider!.isDownloaded(s.id) && !_userProvider!.isDownloading(s.id)) {
            _userProvider!.downloadSong(s);
          }
        }



        // Лениво разрешаем текущую, следующую и предыдущую песни
        _resolveSongsAroundIndex(index, _activeSessionId);
      }
    }, onError: (e) {
      _handlePlayerError(e);
    });
  }

  Future<void> _handlePlayerError(dynamic e) async {
    final index = _audioPlayer.currentIndex;
    if (index != null && queue.isNotEmpty && index < queue.length) {
      final song = queue[index];
      if (song.videoId.startsWith('http://') || song.videoId.startsWith('https://')) {
        print("⚠️ Ошибка воспроизведения трека: ${song.title} (${song.videoId}). Ошибка: $e. Пытаемся восстановить...");
        song.videoId = 'pirate:search:${song.artist} - ${song.title}';
        
        _state = PlayerState.loading;
        _errorMessage = null;
        notifyListeners();
        
        try {
          final resolved = await PirateService.getStreamUrl(song.videoId);
          if (resolved != null && resolved.isNotEmpty) {
            song.videoId = resolved;
            final newSource = LockCachingAudioSource(
              Uri.parse(resolved),
              headers: _getHeadersForUrl(resolved),
              tag: MediaItem(
                id: song.id,
                title: song.title,
                artist: song.artist,
                artUri: Uri.tryParse(song.coverUrl),
                duration: song.duration,
              ),
            );
            if (_playlistSource != null && index < _playlistSource!.length) {
              await _playlistSource!.removeAt(index);
              await _playlistSource!.insert(index, newSource);
              await _audioPlayer.play();
              return;
            }
          }
        } catch (err) {
          print("❌ Авто-восстановление завершилось ошибкой: $err");
        }
      }
    }
    
    _state = PlayerState.error;
    _errorMessage = "Ошибка плеера: $e";
    notifyListeners();

    // Auto-skip unplayable song after 1.5s delay so user isn't stuck on a broken track
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_state == PlayerState.error && queue.isNotEmpty) {
        next();
      }
    });
  }

  Future<void> setQueueAndPlay(List<Song> songs, {int startIndex = 0, bool isRetry = false}) async {
    try {
      if (songs.isEmpty) return;

      _activeSessionId++;
      final sessionId = _activeSessionId;

      _state = PlayerState.loading;
      _errorMessage = null;
      _showMiniPlayer = true;

      final dir = await getApplicationDocumentsDirectory();
      final children = <AudioSource>[];
      final validSongs = <Song>[];

      // 1. Сначала мгновенно разрешаем стрим для стартового трека (синхронно до setAudioSource)
      final songAtStart = startIndex < songs.length ? songs[startIndex] : songs.first;
      _currentSong = songAtStart;
      notifyListeners();

      bool startIsOffline = false;
      try {
        final startLocalPath = '${dir.path}/${_getSafeFileName(songAtStart.id)}.m4a';
        startIsOffline = File(startLocalPath).existsSync();
      } catch (_) {}

      if (!startIsOffline && !songAtStart.videoId.startsWith('http')) {
        try {
          final resolved = await PirateService.getStreamUrl(songAtStart.videoId)
              .timeout(const Duration(seconds: 4));
          if (resolved != null && resolved.isNotEmpty) {
            songAtStart.videoId = resolved;
          }
        } catch (e) {
          print("Ошибка предзагрузки стартового трека: $e");
        }
      }

      if (!startIsOffline && !songAtStart.videoId.startsWith('http')) {
        _state = PlayerState.error;
        _errorMessage = "Не удалось разрешить аудио-ссылку для трека";
        notifyListeners();
        return;
      }

      // 2. Строим аудиоисточники для всей очереди
      for (var s in songs) {
        bool isOffline = false;
        String localPath = '${dir.path}/${_getSafeFileName(s.id)}.m4a';
        try {
          isOffline = File(localPath).existsSync();
        } catch (_) {}

        Uri? uri;
        if (isOffline) {
          uri = Uri.file(localPath);
        } else if (s.videoId.isNotEmpty && (s.videoId.startsWith('http://') || s.videoId.startsWith('https://'))) {
          uri = Uri.tryParse(s.videoId);
        } else {
          uri = Uri.file('${dir.path}/silence.mp3');
        }

        if (uri == null || uri.toString().isEmpty) continue;

        validSongs.add(s);
        final isRemote = !isOffline && (uri.scheme == 'http' || uri.scheme == 'https');
        children.add(
          isRemote
              ? LockCachingAudioSource(
                  uri,
                  headers: _getHeadersForUrl(uri.toString()),
                  tag: MediaItem(
                    id: s.id,
                    title: s.title,
                    artist: s.artist,
                    artUri: Uri.tryParse(s.coverUrl),
                    duration: s.duration,
                  ),
                )
              : AudioSource.uri(
                  uri,
                  headers: isOffline ? null : _getHeadersForUrl(uri.toString()),
                  tag: MediaItem(
                    id: s.id,
                    title: s.title,
                    artist: s.artist,
                    artUri: Uri.tryParse(s.coverUrl),
                    duration: s.duration,
                  ),
                ),
        );
      }

      if (children.isEmpty) {
        _state = PlayerState.error;
        _errorMessage = "Нет воспроизводимых треков";
        notifyListeners();
        return;
      }

      queue = validSongs;

      int newStartIndex = 0;
      final idx = validSongs.indexWhere((s) => s.id == songAtStart.id);
      if (idx != -1) newStartIndex = idx;
      newStartIndex = newStartIndex.clamp(0, children.length - 1);

      _playlistSource = ConcatenatingAudioSource(children: children);

      await _audioPlayer.setLoopMode(
        _repeatMode == 0
            ? LoopMode.off
            : (_repeatMode == 1 ? LoopMode.all : LoopMode.one),
      );
      await _audioPlayer.setShuffleModeEnabled(_isShuffle);

      await _audioPlayer.setAudioSource(_playlistSource!, initialIndex: newStartIndex);
      await _audioPlayer.play();

      // 3. Лениво разрешаем текущую и соседние песни (остальные по мере переключения)
      _resolveSongsAroundIndex(newStartIndex, sessionId);
    } catch (e) {
      if (!isRetry) {
        print("⚠️ Ошибка при воспроизведении: $e. Попытка восстановить ссылки...");
        for (var s in songs) {
          if (s.videoId.startsWith('http://') || s.videoId.startsWith('https://')) {
            s.videoId = 'pirate:search:${s.artist} - ${s.title}';
          }
        }
        await setQueueAndPlay(songs, startIndex: startIndex, isRetry: true);
        return;
      }
      _state = PlayerState.error;
      _errorMessage = "Ошибка: $e";
      print("❌ Ошибка загрузки очереди: $e");
      notifyListeners();
    }
  }

  Future<void> _resolveSongsAroundIndex(int index, int sessionId) async {
    if (_playlistSource == null || queue.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    // Разрешаем текущую, две следующие (+1, +2) и предыдущую (-1) песни для бесшовного перехода
    final List<int> indices = [index, index + 1, index + 2, index - 1];

    for (int idx in indices) {
      if (idx < 0 || idx >= queue.length) continue;
      if (sessionId != _activeSessionId) return;

      final song = queue[idx];
      bool isOffline = false;
      try {
        final localPath = '${dir.path}/${_getSafeFileName(song.id)}.m4a';
        isOffline = File(localPath).existsSync();
      } catch (_) {}

      // Никогда не обновляем текущую воспроизводимую песню (idx == index) во время ее проигрывания через removeAt/insert, 
      // чтобы избежать краша плеера. Все активные песни должны быть разрешены до воспроизведения.
      if (!isOffline && !song.videoId.startsWith('http') && !_resolvingIds.contains(song.id) && idx != index) {
        _resolvingIds.add(song.id);
        try {
          final resolved = await PirateService.getStreamUrl(song.videoId);
          if (resolved != null && resolved.isNotEmpty && sessionId == _activeSessionId) {
            song.videoId = resolved;
            if (_playlistSource != null && idx < _playlistSource!.length) {
              try {
                final newSource = LockCachingAudioSource(
                  Uri.parse(resolved),
                  headers: _getHeadersForUrl(resolved),
                  tag: MediaItem(
                    id: song.id,
                    title: song.title,
                    artist: song.artist,
                    artUri: Uri.tryParse(song.coverUrl),
                    duration: song.duration,
                  ),
                );
                await _playlistSource!.removeAt(idx);
                await _playlistSource!.insert(idx, newSource);
              } catch (e) {
                print("Ошибка динамического обновления трека $idx: $e");
              }
            }
          }
        } finally {
          _resolvingIds.remove(song.id);
        }
      }
    }
  }

  Future<void> _ensureSongResolved(int targetIndex) async {
    if (targetIndex < 0 || targetIndex >= queue.length) return;
    final song = queue[targetIndex];
    final dir = await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/${_getSafeFileName(song.id)}.m4a';
    final isOffline = File(localPath).existsSync();
    
    if (!isOffline && !song.videoId.startsWith('http') && !_resolvingIds.contains(song.id)) {
      _resolvingIds.add(song.id);
      _state = PlayerState.loading;
      notifyListeners();
      try {
        final resolved = await PirateService.getStreamUrl(song.videoId);
        if (resolved != null && resolved.isNotEmpty) {
          song.videoId = resolved;
          final newSource = LockCachingAudioSource(
            Uri.parse(resolved),
            headers: _getHeadersForUrl(resolved),
            tag: MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
              artUri: Uri.tryParse(song.coverUrl),
              duration: song.duration,
            ),
          );
          if (_playlistSource != null && targetIndex < _playlistSource!.length) {
            try {
              await _playlistSource!.removeAt(targetIndex);
              await _playlistSource!.insert(targetIndex, newSource);
            } catch (e) {
              print("Ошибка обновления при принудительном разрешении: $e");
            }
          }
        } else {
          _state = PlayerState.error;
          _errorMessage = "Не удалось разрешить аудио-ссылку для трека";
          notifyListeners();
        }
      } finally {
        _resolvingIds.remove(song.id);
      }
    }
  }

  Future<void> playSong(Song song) async {
    try {
      _showMiniPlayer = true;
      _currentSong = song;
      notifyListeners();
      // Если песня уже в текущей очереди, просто перематываем на нее (бесшовно)
      int index = queue.indexWhere((s) => s.id == song.id);
      if (index != -1 && _audioPlayer.audioSource is ConcatenatingAudioSource) {
        await _ensureSongResolved(index);
        // Если при разрешении произошла ошибка, прекращаем запуск
        if (_state == PlayerState.error) return;
        await _audioPlayer.seek(Duration.zero, index: index);
        await _audioPlayer.play();
      } else {
        // Иначе создаем новую мини-очередь из этой одной песни
        await setQueueAndPlay([song]);
      }
    } catch (e) {
      print("Error playing song: $e");
    }
  }

  Future<void> addToQueue(Song song) async {
    try {
      if (queue.isEmpty || _playlistSource == null) {
        await setQueueAndPlay([song]);
        return;
      }

      if (queue.any((s) => s.id == song.id)) {
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final localPath = '${dir.path}/${_getSafeFileName(song.id)}.m4a';
      final isOffline = File(localPath).existsSync();

      Uri? uri;
      if (isOffline) {
        uri = Uri.file(localPath);
      } else if (song.videoId.isNotEmpty && (song.videoId.startsWith('http://') || song.videoId.startsWith('https://'))) {
        uri = Uri.tryParse(song.videoId);
      } else {
        uri = Uri.file('${dir.path}/silence.mp3');
      }

      if (uri == null || uri.toString().isEmpty) return;

      final newSource = AudioSource.uri(
        uri,
        headers: isOffline ? null : _getHeadersForUrl(uri.toString()),
        tag: MediaItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          artUri: Uri.tryParse(song.coverUrl),
          duration: song.duration,
        ),
      );

      queue.add(song);
      await _playlistSource!.add(newSource);
      notifyListeners();

      if (!isOffline && !song.videoId.startsWith('http')) {
        PirateService.getStreamUrl(song.videoId).then((resolved) async {
          if (resolved != null && resolved.isNotEmpty && _playlistSource != null) {
            song.videoId = resolved;
            final currentIndex = queue.indexWhere((s) => s.id == song.id);
            if (currentIndex != -1 && currentIndex < _playlistSource!.length) {
              final resolvedSource = AudioSource.uri(
                Uri.parse(resolved),
                headers: _getHeadersForUrl(resolved),
                tag: MediaItem(
                  id: song.id,
                  title: song.title,
                  artist: song.artist,
                  artUri: Uri.tryParse(song.coverUrl),
                  duration: song.duration,
                ),
              );
              await _playlistSource!.removeAt(currentIndex);
              await _playlistSource!.insert(currentIndex, resolvedSource);
            }
          }
        }).catchError((e) {
          print("Ошибка фонового разрешения добавленного трека: $e");
        });
      }
    } catch (e) {
      print("Ошибка добавления в очередь: $e");
    }
  }

  Future<void> togglePlayPause() async {
    if (_currentSong == null && queue.isNotEmpty) {
      await playSong(queue.first);
      return;
    }
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
        _state = PlayerState.paused;
      } else {
        await _audioPlayer.play();
        _state = PlayerState.playing;
      }
      notifyListeners();
    } catch (e) {
      print("Error toggling play/pause: $e");
    }
  }

  Future<void> pause() async {
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
        _state = PlayerState.paused;
        notifyListeners();
      }
    } catch (e) {
      print("Error pausing: $e");
    }
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimerTicker?.cancel();
    if (duration == null || duration == Duration.zero) {
      _sleepDurationRemaining = null;
      notifyListeners();
      return;
    }

    _sleepDurationRemaining = duration;
    notifyListeners();

    _sleepTimerTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sleepDurationRemaining != null) {
        if (_sleepDurationRemaining!.inSeconds <= 1) {
          _sleepDurationRemaining = null;
          _sleepTimerTicker?.cancel();
          _sleepTimer?.cancel();
          pause();
          notifyListeners();
        } else {
          _sleepDurationRemaining = _sleepDurationRemaining! - const Duration(seconds: 1);
          notifyListeners();
        }
      }
    });

    _sleepTimer = Timer(duration, () {
      pause();
      _sleepDurationRemaining = null;
      _sleepTimerTicker?.cancel();
      notifyListeners();
    });
  }

  void toggleShuffle() async {
    try {
      _isShuffle = !_isShuffle;
      await _audioPlayer.setShuffleModeEnabled(_isShuffle);
      notifyListeners();
    } catch (e) {
      print("Error toggling shuffle: $e");
    }
  }

  void toggleRepeat() async {
    try {
      _repeatMode = (_repeatMode + 1) % 3;
      if (_repeatMode == 0) {
        await _audioPlayer.setLoopMode(LoopMode.off);
      } else if (_repeatMode == 1) {
        await _audioPlayer.setLoopMode(LoopMode.all);
      } else {
        await _audioPlayer.setLoopMode(LoopMode.one);
      }
      notifyListeners();
    } catch (e) {
      print("Error toggling repeat: $e");
    }
  }

  Future<void> next({bool isAutoPlay = false}) async {
    try {
      final nextIndex = _audioPlayer.currentIndex != null ? _audioPlayer.currentIndex! + 1 : 0;
      if (nextIndex < queue.length) {
        await _ensureSongResolved(nextIndex);
        if (_state == PlayerState.error) return;
        await _audioPlayer.seek(Duration.zero, index: nextIndex);
        await _audioPlayer.play();
      } else if (queue.isNotEmpty) {
        // Перескакиваем в начало, если очередь закончилась
        await _ensureSongResolved(0);
        if (_state == PlayerState.error) return;
        await _audioPlayer.seek(Duration.zero, index: 0);
        await _audioPlayer.play();
      }
    } catch (e) {
      print("Error seeking next: $e");
    }
  }

  Future<void> previous() async {
    try {
      if (_currentPosition.inSeconds > 3) {
        // По стандарту всех плееров: если слушаешь дольше 3 сек — кнопка "назад" возвращает в начало трека
        await _audioPlayer.seek(Duration.zero);
      } else {
        final prevIndex = _audioPlayer.currentIndex != null ? _audioPlayer.currentIndex! - 1 : -1;
        if (prevIndex >= 0) {
          await _ensureSongResolved(prevIndex);
          if (_state == PlayerState.error) return;
          await _audioPlayer.seek(Duration.zero, index: prevIndex);
          await _audioPlayer.play();
        } else if (queue.isNotEmpty) {
          // Если это самый первый трек, перескакиваем в самый конец плейлиста
          final target = queue.length - 1;
          await _ensureSongResolved(target);
          if (_state == PlayerState.error) return;
          await _audioPlayer.seek(Duration.zero, index: target);
          await _audioPlayer.play();
        }
      }
    } catch (e) {
      print("Error seeking previous: $e");
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
      notifyListeners();
    } catch (e) {
      print("Error seeking: $e");
    }
  }

  double get volume => _audioPlayer.volume;
  Stream<double> get volumeStream => _audioPlayer.volumeStream;
  Future<void> setVolume(double value) async {
    try {
      await _audioPlayer.setVolume(value);
      notifyListeners();
    } catch (e) {
      print("Error setting volume: $e");
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final Song item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);
    _playlistSource?.move(oldIndex, newIndex);
    notifyListeners();
  }

  Map<String, String>? _getHeadersForUrl(String url) {
    if (url.contains('sefon.pro') || url.contains('sefon')) {
      return {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://sefon.pro/',
      };
    } else if (url.contains('drivemusic')) {
      return {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://drivemusic.club/',
      };
    } else if (url.contains('youtube') || url.contains('googlevideo')) {
      return {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://www.youtube.com/',
      };
    }
    return {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
  }



  Future<void> stopAndReset() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      print("Ошибка остановки плеера: $e");
    }
    _sleepTimer?.cancel();
    _sleepTimerTicker?.cancel();
    _sleepDurationRemaining = null;
    _currentSong = null;
    _state = PlayerState.idle;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    queue.clear();
    playHistory.clear();
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sleepTimer?.cancel();
    _sleepTimerTicker?.cancel();
    _saveHistoryDebounce?.cancel();
    _nativePositionSub?.cancel();
    _positionTimer?.cancel();
    _positionController.close();
    _audioPlayer.dispose();
    super.dispose();
  }
}

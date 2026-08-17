import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/search/services/search_service.dart';
import 'package:ses/core/utils/cover_service.dart';

class ScreenshotImportSheet extends StatefulWidget {
  final String rawText;
  const ScreenshotImportSheet({super.key, required this.rawText});

  @override
  State<ScreenshotImportSheet> createState() => _ScreenshotImportSheetState();
}

class _ScreenshotImportSheetState extends State<ScreenshotImportSheet> {
  bool _isLoading = true;
  final List<Song> _foundSongs = [];
  final List<String> _notFoundQueries = [];
  final Map<String, bool> _selectedSongs = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSearch();
    });
  }

  int get _selectedCount => _foundSongs.where((s) => _selectedSongs[s.id] ?? true).length;

  bool _isValidMatch(String query, String resultArtist, String resultTitle) {
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

    bool isSimilar(String a, String b) {
      final cleanA = a.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]'), '');
      final cleanB = b.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]'), '');
      if (cleanA.isEmpty || cleanB.isEmpty) return false;
      if (cleanA.contains(cleanB) || cleanB.contains(cleanA)) return true;
      
      final wordsA = a.toLowerCase().split(RegExp(r'[^a-z0-9а-яё]')).where((w) => w.length > 2).toSet();
      final wordsB = b.toLowerCase().split(RegExp(r'[^a-z0-9а-яё]')).where((w) => w.length > 2).toSet();
      if (wordsA.isNotEmpty && wordsB.isNotEmpty) {
        if (wordsA.intersection(wordsB).isNotEmpty) return true;
      }
      return false;
    }

    if (qArtist.isNotEmpty && qTitle.isNotEmpty) {
      return isSimilar(qArtist, resultArtist) && isSimilar(qTitle, resultTitle);
    }

    return isSimilar(query, resultTitle) || isSimilar(query, resultArtist);
  }

  Future<void> _startSearch() async {
    final cleanedText = _cleanOcrText(widget.rawText);
    final queries = cleanedText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l.length > 2)
        .toList();

    if (queries.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppTheme.showSnackBar(context, "Не удалось распознать названия песен на скриншоте.");
      }
      return;
    }

    final searchFutures = queries.map((query) async {
      try {
        final results = await SearchService.search(query);
        if (results.isNotEmpty) {
          Song? bestMatch;
          for (final matched in results) {
            if (_isValidMatch(query, matched.artist, matched.title)) {
              bestMatch = Song(
                id: matched.id,
                title: matched.title,
                artist: matched.artist,
                coverUrl: matched.coverUrl.isNotEmpty ? matched.coverUrl : CoverService.defaultMusicCover,
                duration: matched.duration,
                videoId: matched.videoId,
                type: 'song',
              );
              break;
            }
          }
          return MapEntry(query, bestMatch);
        }
      } catch (e) {
        debugPrint("Ошибка поиска по скриншоту для запроса '$query': $e");
      }
      return MapEntry<String, Song?>(query, null);
    }).toList();

    final searchResults = await Future.wait(searchFutures);

    if (!mounted) return;

    final Set<String> seenIds = {};
    final List<MapEntry<String, Song>> tempFound = [];

    for (final entry in searchResults) {
      if (entry.value != null) {
        final song = entry.value!;
        if (!seenIds.contains(song.id)) {
          seenIds.add(song.id);
          tempFound.add(MapEntry(entry.key, song));
        }
      }
    }

    final Set<String> foundArtists = tempFound
        .map((e) => e.value.artist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]'), ''))
        .toSet();

    for (final entry in tempFound) {
      _foundSongs.add(entry.value);
      _selectedSongs[entry.value.id] = true;
    }

    for (final entry in searchResults) {
      if (entry.value == null) {
        final cleanKey = entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]'), '');
        // Ignore if query matches the artist of any successfully found song
        bool isArtistLine = foundArtists.any((artist) => artist.contains(cleanKey) || cleanKey.contains(artist));
        if (!isArtistLine) {
          _notFoundQueries.add(entry.key);
        }
      }
    }

    setState(() {
      _isLoading = false;
    });

    if (_foundSongs.isNotEmpty) {
      if (_notFoundQueries.isNotEmpty) {
        AppTheme.showSnackBar(
          context,
          "Найдено ${_foundSongs.length} треков. Не найдено: ${_notFoundQueries.length}",
        );
      } else {
        AppTheme.showSnackBar(
          context,
          "Поиск завершен. Найдено ${_foundSongs.length} треков!",
        );
      }
    } else {
      AppTheme.showSnackBar(
        context,
        "К сожалению, ни один трек не был найден в каталоге.",
      );
    }
  }

  void _handleImport() {
    final selectedList = _foundSongs.where((s) => _selectedSongs[s.id] ?? true).toList();
    if (selectedList.isEmpty) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    userProvider.saveImportedPlaylist(
      "Импорт по скриншоту",
      CoverService.defaultMusicCover,
      selectedList,
    );

    AppTheme.showSnackBar(
      context,
      "Успешно создано плейлист с ${selectedList.length} треками!",
    );
    Navigator.pop(context);
  }

  bool _isUiNoise(String line) {
    final lower = line.toLowerCase().trim();
    if (lower.isEmpty) return true;
    
    if (RegExp(r'^\d+$').hasMatch(lower)) return true;
    if (RegExp(r'^\d+:\d+$').hasMatch(lower)) return true;
    if (RegExp(r'^\d+:\d+:\d+$').hasMatch(lower)) return true;
    if (lower.length < 3) return true;

    final noiseWords = {
      // English
      'spotify', 'apple music', 'yandex', 'vk', 'play', 'shuffle', 'repeat', 
      'library', 'search', 'home', 'settings', 'premium', 'album', 'artist', 
      'playlist', 'track', 'download', 'downloads', 'history', 'like', 'liked', 
      'favorite', 'favorites', 'edit', 'share', 'add', 'remove', 'delete', 
      'cancel', 'save', 'done', 'queue', 'player', 'views', 'min', 'sec', 'hours', 
      'minutes', 'seconds', 'release', 'radio', 'chart', 'charts', 'top', 'following',
      'followers', 'playlists', 'albums', 'artists', 'songs', 'tracks', 'subscribers',
      // Russian
      'спотифай', 'яндекс', 'музыка', 'вк', 'библиотека', 'поиск', 'главная', 
      'настройки', 'премиум', 'альбом', 'артист', 'плейлист', 'трек', 'скачать', 
      'загрузки', 'история', 'лайк', 'любимые', 'избранное', 'редактировать', 
      'поделиться', 'добавить', 'удалить', 'отмена', 'сохранить', 'готово', 
      'очередь', 'плеер', 'просмотры', 'мин', 'сек', 'часов', 'минут', 'секунд', 
      'радио', 'чарт', 'чарты', 'топ', 'подписчики', 'подписки', 'песни', 'песня',
      'треки', 'прослушивания', 'прослушиваний', 'воспроизвести', 'перемешать'
    };

    if (noiseWords.contains(lower)) return true;

    final words = lower.split(RegExp(r'[\s\-_,\.]'));
    if (words.every((w) => noiseWords.contains(w) || RegExp(r'^\d*$').hasMatch(w))) {
      return true;
    }

    return false;
  }

  String _cleanOcrText(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !_isUiNoise(l))
        .toList();

    final List<String> resultLines = [];
    
    bool hasHyphens = lines.any((l) => l.contains('-') || l.contains('—') || l.contains('–'));
    if (hasHyphens) {
      for (var line in lines) {
        if (!line.contains('-') && !line.contains('—') && !line.contains('–')) {
          continue;
        }
        if (line.length > 3) {
          resultLines.add(line);
        }
      }
    } else {
      resultLines.addAll(lines);
    }
    return resultLines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final playerProvider = Provider.of<PlayerProvider>(context);
    final currentSong = playerProvider.currentSong;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width > 600 ? 550 : double.infinity,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF151515),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Iconsax.image,
                      color: AppColors.accentGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Импорт по скриншоту",
                          style: AppText.sectionTitle.copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Выберите треки для добавления в медиатеку",
                          style: AppText.caption.copyWith(color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Main Content
            if (_isLoading) ...[
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Ищем треки в поисковике...",
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 20),
                  children: [
                    // Result Header Card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 56,
                                height: 56,
                                color: AppColors.accentGreen.withValues(alpha: 0.1),
                                  child: Center(
                                    child: Icon(
                                      Iconsax.music_playlist,
                                      color: AppColors.accentGreen,
                                      size: 28,
                                    ),
                                  ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Распознанные треки",
                                    style: AppText.trackTitleActive.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Всего найдено: ${_foundSongs.length} треков",
                                    style: AppText.caption.copyWith(color: Colors.white60),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Warning for not found queries
                    if (_notFoundQueries.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Iconsax.info_circle, color: Colors.amber, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Не удалось найти (${_notFoundQueries.length} шт.):",
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ..._notFoundQueries.map((query) => Padding(
                                padding: const EdgeInsets.only(left: 26, top: 4),
                                child: Text(
                                  "• $query",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 11,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              )),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // Found Songs List Header
                    if (_foundSongs.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Найденные треки (${_foundSongs.length})",
                              style: AppText.sectionTitle.copyWith(fontSize: 15),
                            ),
                            GestureDetector(
                              onTap: () {
                                final allSelected = _selectedCount == _foundSongs.length;
                                setState(() {
                                  for (var s in _foundSongs) {
                                    _selectedSongs[s.id] = !allSelected;
                                  }
                                });
                              },
                              child: Text(
                                _selectedCount == _foundSongs.length ? "Снять все" : "Выбрать все",
                                style: TextStyle(
                                  color: AppColors.accentGreen,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // List of track rows
                      ...List.generate(_foundSongs.length, (index) {
                        final song = _foundSongs[index];
                        final isCurrent = currentSong?.title == song.title && currentSong?.artist == song.artist;
                        final isLiked = userProvider.isLiked(song.id);
                        final isSelected = _selectedSongs[song.id] ?? true;

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                          child: AppTrackRow(
                            title: song.title,
                            artist: song.artist,
                            coverUrl: song.coverUrl,
                            isCurrent: isCurrent,
                            isLiked: isLiked,
                            onTap: () {
                              playerProvider.setQueueAndPlay(_foundSongs, startIndex: index);
                            },
                            onLike: () => userProvider.toggleLike(song),
                            onAction: () {
                              setState(() {
                                _selectedSongs[song.id] = !isSelected;
                              });
                            },
                            actionIcon: isSelected 
                                ? Iconsax.tick_square
                                : Iconsax.square,
                            actionColor: isSelected 
                                ? AppColors.accentGreen 
                                : Colors.white24,
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              
              // Persistent bottom Import Button
              if (_foundSongs.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).padding.bottom + 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _selectedCount == 0 ? null : _handleImport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentGreen,
                        disabledBackgroundColor: Colors.white12,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _selectedCount == 0 
                            ? "Выберите песни для импорта" 
                            : "Импортировать выбранные ($_selectedCount)",
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

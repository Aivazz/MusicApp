import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/library/models/import_result.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/import_export/screens/qr_scan_screen.dart';

class SpotifyImportSheet extends StatefulWidget {
  final String? prefilledText;
  const SpotifyImportSheet({super.key, this.prefilledText});

  @override
  State<SpotifyImportSheet> createState() => _SpotifyImportSheetState();
}

class _SpotifyImportSheetState extends State<SpotifyImportSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;
  SpotifyImportResult? _result;

  // Batch download state
  bool _isDownloadingAll = false;
  int _downloadAllCurrent = 0;
  int _downloadAllTotal = 0;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledText != null) {
      _controller.text = widget.prefilledText!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleConvert();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        _controller.text = data.text!;
      });
    }
  }

  Future<void> _scanQRCode() async {
    final code = await Navigator.push<String>(
      context,
      AppPageRoute.create(context, const QRScanScreen()),
    );
    if (code != null && code.isNotEmpty) {
      setState(() {
        _controller.text = code;
      });
      _handleConvert();
    }
  }

  Future<void> _handleConvert() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    _focusNode.unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final parsed = await userProvider.parseImportInput(input);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (parsed != null) {
          if (parsed.songs.isNotEmpty) {
            _result = parsed;
            // Автоматическое создание и сохранение плейлиста
            userProvider.saveImportedPlaylist(
              parsed.title,
              parsed.coverUrl,
              parsed.songs,
            );
            if (parsed.notFoundSongs.isNotEmpty) {
              AppTheme.showSnackBar(
                context,
                "Плейлист сохранен (${parsed.songs.length} треков). Не найдено: ${parsed.notFoundSongs.length}",
              );
            } else {
              AppTheme.showSnackBar(
                context,
                "Создан и сохранен плейлист: ${parsed.title}",
              );
            }
          } else {
            _errorMessage = "Ни один трек не был найден в поисковике приложения.";
          }
        } else {
          _errorMessage = "Не удалось распознать ссылку или загрузить данные.";
        }
      });
    }
  }

  Future<void> _downloadAllSongs(List<Song> songs, UserProvider userProvider) async {
    if (_isDownloadingAll) return;
    setState(() {
      _isDownloadingAll = true;
      _downloadAllTotal = songs.length;
      _downloadAllCurrent = 0;
    });

    for (var song in songs) {
      if (!mounted) break;
      if (!userProvider.isDownloaded(song.id)) {
        setState(() {
          _downloadAllCurrent++;
        });
        try {
          await userProvider.downloadSong(song);
        } catch (e) {
          debugPrint("Error in batch download for song ${song.title}: $e");
        }
      } else {
        setState(() {
          _downloadAllCurrent++;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isDownloadingAll = false;
      });
      AppTheme.showSnackBar(context, "Все доступные треки успешно загружены!");
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final playerProvider = Provider.of<PlayerProvider>(context);
    final currentSong = playerProvider.currentSong;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.fastOutSlowIn,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width > 600 ? 550 : double.infinity,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
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
            // ── Drag Handle ──
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

            // ── Header ──
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
                      Iconsax.document_download,
                      color: AppColors.accentGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Импорт",
                        style: AppText.sectionTitle.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "SoundCloud, Spotify, Яндекс Музыка или текст",
                        style: AppText.caption.copyWith(color: Colors.white38),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Input & Convert ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              maxLines: 3,
                              minLines: 1,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText: "Вставьте ссылку или список треков...",
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Iconsax.scan_barcode, color: AppColors.accentGreen, size: 20),
                            tooltip: "Сканировать QR-код",
                            onPressed: _scanQRCode,
                          ),
                          IconButton(
                            icon: Icon(AppIcons.close, color: Colors.white30, size: 18),
                            onPressed: () => _controller.clear(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onPressed: _pasteFromClipboard,
                            icon: const Icon(Iconsax.clipboard_text, size: 14),
                            label: const Text("Вставить", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentGreen,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _handleConvert,
                            child: const Text(
                              "Конвертировать",
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Error Message ──
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accentRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.accentRed.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Iconsax.info_circle, color: AppColors.accentRed, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.accentRed, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // ── Loading State ──
            if (_isLoading) ...[
              const SizedBox(height: 40),
              Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Загружаем метаданные...",
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],

            // ── Result State ──
            if (_result != null) ...[
              const SizedBox(height: 16),
              Expanded(
                child: _buildClassicResultList(userProvider, playerProvider, currentSong),
              ),
            ] else ...[
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultHeaderCard(UserProvider userProvider, PlayerProvider playerProvider) {
    if (_result == null) return const SizedBox.shrink();

    final isSingleTrack = _result!.type == SpotifyImportType.track || _result!.songs.length == 1;

    if (isSingleTrack) {
      final song = _result!.songs.first;
      final isLiked = userProvider.isLiked(song.id);
      final isDownloaded = userProvider.isDownloaded(song.id);
      final isDownloading = userProvider.isDownloading(song.id);
      final downloadProgress = userProvider.getDownloadProgress(song.id);
      final isCurrent = playerProvider.currentSong?.title == song.title && playerProvider.currentSong?.artist == song.artist;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                AppCover(
                  url: song.coverUrl,
                  size: 80,
                  radius: 12,
                  artist: song.artist,
                  title: song.title,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        style: AppText.trackTitleActive.copyWith(fontSize: 16),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist,
                        style: AppText.trackArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Play Button
                _buildActionChip(
                  icon: isCurrent && playerProvider.isPlaying ? AppIcons.pause : AppIcons.play,
                  label: "Слушать",
                  onTap: () {
                    if (isCurrent) {
                      playerProvider.togglePlayPause();
                    } else {
                      playerProvider.playSong(song);
                    }
                  },
                ),

                // Download Button
                _buildActionChip(
                  icon: isDownloading
                      ? Iconsax.timer
                      : (isDownloaded ? AppIcons.downloadDone : AppIcons.download),
                  iconColor: isDownloaded ? AppColors.accentGreen : null,
                  label: isDownloading
                      ? "Загрузка ${(downloadProgress * 100).toInt()}%"
                      : (isDownloaded ? "Скачано" : "Скачать MP3"),
                  onTap: isDownloading
                      ? null
                      : () {
                          if (isDownloaded) {
                            userProvider.removeDownload(song.id);
                          } else {
                            userProvider.downloadSong(song);
                          }
                        },
                ),

                // Favorite Button
                _buildActionChip(
                  icon: isLiked ? AppIcons.heartFilled : AppIcons.heart,
                  iconColor: isLiked ? AppColors.accentRed : null,
                  label: isLiked ? "Любимый" : "Нравится",
                  onTap: () => userProvider.toggleLike(song),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // Playlist / Album
      final bool alreadyImported = userProvider.playlists.any((p) => p['name'] == _result!.title);

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCover(
                  url: _result!.coverUrl,
                  size: 70,
                  radius: 12,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTag(
                        text: _result!.type == SpotifyImportType.album ? "АЛЬБОМ" : "ПЛЕЙЛИСТ",
                        color: AppColors.accentGreen.withValues(alpha: 0.12),
                        textColor: AppColors.accentGreen,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _result!.title,
                        style: AppText.trackTitleActive.copyWith(fontSize: 16),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_result!.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _result!.subtitle!,
                          style: AppText.trackArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Download All
                Expanded(
                  child: GestureDetector(
                    onTap: _isDownloadingAll
                        ? null
                        : () => _downloadAllSongs(_result!.songs, userProvider),
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: _isDownloadingAll
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(AppIcons.download, color: Colors.black, size: 13),
                                  const SizedBox(width: 6),
                                  const Text(
                                    "Скачать все",
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Save / Import Playlist
                GestureDetector(
                  onTap: alreadyImported
                      ? null
                      : () async {
                          await userProvider.saveImportedPlaylist(
                            _result!.title,
                            _result!.coverUrl,
                            _result!.songs,
                          );
                          if (mounted) {
                            AppTheme.showSnackBar(context, "Импортировано в медиатеку!");
                          }
                        },
                  child: Container(
                    height: 36,
                    width: 90,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: alreadyImported ? AppColors.accentGreen.withValues(alpha: 0.3) : Colors.white10,
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            alreadyImported ? AppIcons.check : AppIcons.plus,
                            color: alreadyImported ? AppColors.accentGreen : Colors.white,
                            size: 13,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            alreadyImported ? "Импорт." : "Импорт",
                            style: TextStyle(
                              color: alreadyImported ? AppColors.accentGreen : Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor ?? Colors.white.withValues(alpha: 0.8),
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassicResultList(UserProvider userProvider, PlayerProvider playerProvider, Song? currentSong) {
    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      children: [
        // Result Header Card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildResultHeaderCard(userProvider, playerProvider),
        ),

        // Warning for not found songs
        if (_result!.notFoundSongs.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withOpacity(0.2)),
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
                          "Некоторые треки не найдены в поисковике (${_result!.notFoundSongs.length} шт.):",
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
                  ..._result!.notFoundSongs.map((song) => Padding(
                    padding: const EdgeInsets.only(left: 26, top: 4),
                    child: Text(
                      "• ${song.artist} - ${song.title}",
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

        // Tracks List Header
        if (_result!.songs.length > 1) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Треки в импорте (${_result!.songs.length})",
                  style: AppText.sectionTitle.copyWith(fontSize: 15),
                ),
                if (_isDownloadingAll)
                  Text(
                    "Скачивание $_downloadAllCurrent из $_downloadAllTotal...",
                    style: AppText.caption.copyWith(color: AppColors.accentGreen),
                  ),
              ],
            ),
          ),
          // List of track rows
          ...List.generate(_result!.songs.length, (index) {
            final song = _result!.songs[index];
            final isCurrent = currentSong?.title == song.title && currentSong?.artist == song.artist;
            final isLiked = userProvider.isLiked(song.id);
            final isDownloaded = userProvider.isDownloaded(song.id);
            final isDownloading = userProvider.isDownloading(song.id);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: AppTrackRow(
                title: song.title,
                artist: song.artist,
                coverUrl: song.coverUrl,
                isCurrent: isCurrent,
                isLiked: isLiked,
                isDownloaded: isDownloaded,
                song: song,
                onTap: () {
                  playerProvider.setQueueAndPlay(_result!.songs, startIndex: index);
                },
                onLike: () => userProvider.toggleLike(song),
                onAction: isDownloading
                    ? null
                    : () {
                        if (isDownloaded) {
                          userProvider.removeDownload(song.id);
                        } else {
                          userProvider.downloadSong(song);
                        }
                      },
                actionIcon: isDownloading
                    ? null
                    : (isDownloaded ? AppIcons.trash : AppIcons.download),
                actionColor: isDownloading
                    ? null
                    : (isDownloaded ? AppColors.accentRed.withValues(alpha: 0.6) : Colors.white60),
              ),
            );
          }),
        ],
      ],
    );
  }


}

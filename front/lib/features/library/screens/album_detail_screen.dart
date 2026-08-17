import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/features/player/widgets/mini_player.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/search/services/search_service.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/widgets/playlist_selection_sheet.dart';
import 'package:ses/features/import_export/services/pirate_service.dart';
import 'package:ses/features/import_export/services/spotify_service.dart';
import 'package:ses/features/import_export/services/soundcloud_service.dart';

class AlbumDetailScreen extends StatefulWidget {
  final Song albumMetadata;
  final String type; // "Playlist", "Album", or "CustomPlaylist"

  const AlbumDetailScreen({
    super.key,
    required this.albumMetadata,
    this.type = "Playlist",
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<Song> _playlistSongs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _fetchSongs();
      context.read<UserProvider>().addToRecentPlaylists(widget.albumMetadata, widget.type);
    });
  }

  Future<void> _fetchSongs() async {
    try {
      List<Song> results = [];
      final id = widget.albumMetadata.id;

      if (id.startsWith('sc_') || widget.albumMetadata.videoId.startsWith('sc_playlist:')) {
        results = await SoundcloudService.getPlaylistSongs(id.isNotEmpty ? id : widget.albumMetadata.videoId);
      }

      if (results.isEmpty && (widget.type == "Album" || widget.type == "Playlist")) {
        results = await SearchService.getAlbumSongs(widget.albumMetadata.id, coverUrl: widget.albumMetadata.coverUrl);
        if (results.isEmpty) {
          results = await SearchService.search('${widget.albumMetadata.title} ${widget.albumMetadata.artist}');
        }
      } else if (results.isEmpty && widget.type == "CustomPlaylist") {
        final user = context.read<UserProvider>();
        final p = user.playlists.firstWhere((p) => p['id'] == widget.albumMetadata.id, orElse: () => {});
        if (p.isNotEmpty && p['songs'] != null) {
          results = (p['songs'] as List).map((s) => Song.fromJson(s as Map<String, dynamic>)).toList();
        }
      } else if (results.isEmpty && widget.type == "SpotifyPlaylist") {
        final playlistData = await SpotifyService.getPlaylistDetails(widget.albumMetadata.id);
        if (playlistData != null && playlistData['songs'] != null) {
          results = List<Song>.from(playlistData['songs']);
        }
      } else if (results.isEmpty && widget.type == "DailyMix") {
        results = await SearchService.search(widget.albumMetadata.videoId);
      } else if (results.isEmpty) {
        results = await SearchService.search('${widget.albumMetadata.title} ${widget.albumMetadata.artist}');
      }

      if (mounted) {
        setState(() {
          _playlistSongs = results;
          _isLoading = false;
        });
        _preResolveSongs(results.take(5).toList());
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _preResolveSongs(List<Song> songs) {
    for (var song in songs) {
      if (!song.videoId.startsWith('http')) {
        PirateService.getStreamUrl(song.videoId).then((resolved) {
          if (resolved != null && resolved.isNotEmpty) {
            song.videoId = resolved;
          }
        }).catchError((_) {});
      }
    }
  }

  LinearGradient _getPlaylistGradient(String name) {
    final int hash = name.hashCode;
    final List<List<Color>> palettes = [
      [const Color(0xFF3A1C71), const Color(0xFFD76D77), const Color(0xFFFFAF7B)],
      [const Color(0xFF2C5364), const Color(0xFF203A43), const Color(0xFF0F2027)],
      [const Color(0xFF1A2A6C), const Color(0xFFB21F1F), const Color(0xFFFDBB2D)],
      [const Color(0xFF00C6FF), const Color(0xFF0072FF)],
      [const Color(0xFF11998E), const Color(0xFF38EF7D)],
      [const Color(0xFFAA076B), const Color(0xFF61045F)],
      [const Color(0xFF833AB4), const Color(0xFFFD1D1D), const Color(0xFFFCB045)],
      [const Color(0xFF4E54C8), const Color(0xFF8F94FB)],
      [const Color(0xFF00F260), const Color(0xFF0575E6)],
    ];
    final palette = palettes[hash.abs() % palettes.length];
    return LinearGradient(
      colors: palette,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      await context.read<UserProvider>().updatePlaylistCover(widget.albumMetadata.id, image.path);
    }
  }

  void _showRenameSheet(BuildContext context, UserProvider user) {
    final currentPlaylistData = user.playlists.firstWhere((p) => p['id'] == widget.albumMetadata.id, orElse: () => {});
    final currentName = currentPlaylistData['name'] ?? widget.albumMetadata.title;

    final controller = TextEditingController(text: currentName);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          curve: Curves.fastOutSlowIn,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.03))),
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              MediaQuery.of(ctx).padding.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                const SizedBox(height: 24),
                Text(
                  "Переименовать плейлист",
                  style: AppText.sectionTitle.copyWith(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "Введите новое название подборки",
                  style: AppText.caption.copyWith(color: Colors.white38),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: AppText.trackTitle,
                  decoration: InputDecoration(
                    hintText: "Название плейлиста",
                    hintStyle: AppText.trackArtist.copyWith(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.03),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.input,
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppRadius.input,
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          "Отмена",
                          style: AppText.caption.copyWith(color: Colors.white38, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          final name = controller.text.trim();
                          if (name.isNotEmpty) {
                            user.renamePlaylist(widget.albumMetadata.id, name);
                          }
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.accentGreen,
                            borderRadius: AppRadius.card,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accentGreen.withOpacity(0.2),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              "Сохранить",
                              style: AppText.trackTitle.copyWith(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final user = Provider.of<UserProvider>(context);
    final currentSong = context.select<PlayerProvider, Song?>((p) => p.currentSong);
    final hasMiniPlayer = currentSong != null && context.select<PlayerProvider, bool>((p) => p.showMiniPlayer);

    Map<String, dynamic> currentPlaylistData = {};
    if (widget.type == "CustomPlaylist") {
      currentPlaylistData = user.playlists.firstWhere((p) => p['id'] == widget.albumMetadata.id, orElse: () => {});
    }

    final coverUrl = widget.type == "CustomPlaylist" 
        ? (currentPlaylistData['coverUrl'] ?? widget.albumMetadata.coverUrl)
        : widget.albumMetadata.coverUrl;
    
    final playlistName = widget.type == "CustomPlaylist"
        ? (currentPlaylistData['name'] ?? widget.albumMetadata.title)
        : widget.albumMetadata.title;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 380,
            pinned: true,
            stretch: true,
            leading: const AppBackButton(),
            backgroundColor: AppColors.background,
            actions: [
              if (widget.type == "CustomPlaylist") ...[
                AppCircleButton(
                  icon: AppIcons.edit,
                  onTap: () => _showRenameSheet(context, user),
                  size: 40,
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: AppCircleButton(
                    icon: AppIcons.camera,
                    onTap: _pickImage,
                    size: 40,
                  ),
                ),
              ],
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground, StretchMode.fadeTitle],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  coverUrl.isEmpty
                      ? Container(
                          decoration: BoxDecoration(
                            gradient: _getPlaylistGradient(playlistName),
                          ),
                          child: Center(
                            child: Icon(
                              AppIcons.music,
                              color: Colors.white.withOpacity(0.85),
                              size: 80,
                            ),
                          ),
                        )
                      : AppCover(url: coverUrl, size: 500, radius: 0),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.4),
                          Colors.transparent,
                          AppColors.background.withOpacity(0.8),
                          AppColors.background,
                        ],
                        stops: const [0.0, 0.4, 0.85, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 24, left: 24, right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlistName,
                          style: AppText.screenTitle.copyWith(fontSize: 34),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: AppRadius.tag,
                              ),
                              child: Text(
                                widget.type == "CustomPlaylist"
                                    ? "ПЛЕЙЛИСТ"
                                    : (widget.type == "Album"
                                        ? "АЛЬБОМ"
                                        : (widget.type == "DailyMix" ? "МИКС ДНЯ" : "ПОДБОРКА")),
                                style: AppText.label.copyWith(color: Colors.white60, letterSpacing: 1.2),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "${widget.albumMetadata.artist} • ${_playlistSongs.length} треков",
                                style: AppText.caption.copyWith(color: Colors.white38),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  Builder(
                    builder: (context) {
                      final isSaved = user.isPlaylistSaved(widget.albumMetadata.id) || user.isPlaylistSaved(widget.albumMetadata.title);
                      return AppCircleButton(
                        icon: isSaved ? AppIcons.check : AppIcons.plus,
                        onTap: () async {
                          if (!isSaved) {
                            await user.saveCustomPlaylist(widget.albumMetadata, _playlistSongs);
                            if (context.mounted) {
                              AppTheme.showSnackBar(
                                context,
                                'Плейлист "${widget.albumMetadata.title}" добавлен в плейлисты',
                              );
                            }
                          } else {
                            user.deletePlaylist(widget.albumMetadata.id);
                            if (context.mounted) {
                              AppTheme.showSnackBar(
                                context,
                                'Плейлист "${widget.albumMetadata.title}" удален из плейлистов',
                              );
                            }
                          }
                        },
                        iconColor: isSaved ? AppColors.accentGreen : null,
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  AppCircleButton(
                    icon: _playlistSongs.isNotEmpty && _playlistSongs.every((s) => user.isDownloaded(s.id))
                        ? AppIcons.downloadDone
                        : AppIcons.download,
                    onTap: () {
                      if (_playlistSongs.isNotEmpty) {
                        final toDownload = _playlistSongs.where((s) => !user.isDownloaded(s.id) && !user.downloadQueue.any((q) => q.id == s.id)).toList();
                        user.downloadPlaylist(_playlistSongs);
                        if (toDownload.isEmpty) {
                          AppTheme.showSnackBar(context, 'Все треки уже скачаны или скачиваются');
                        } else {
                          AppTheme.showSnackBar(context, 'Загрузка ${toDownload.length} треков...');
                        }
                      }
                    },
                    iconColor: _playlistSongs.isNotEmpty && _playlistSongs.every((s) => user.isDownloaded(s.id))
                        ? AppColors.accentGreen
                        : null,
                  ),
                  if (widget.type == "CustomPlaylist") ...[
                    const SizedBox(width: 16),
                    AppCircleButton(
                      icon: AppIcons.trash,
                      onTap: () async {
                        final confirm = await _showDeleteConfirm(context);
                        if (confirm == true && context.mounted) {
                          context.read<UserProvider>().deletePlaylist(widget.albumMetadata.id);
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                  const Spacer(),
                  AppPlayButton(
                    size: 56,
                    onTap: () {
                      if (_playlistSongs.isNotEmpty) {
                        player.setQueueAndPlay(_playlistSongs, startIndex: 0);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          if (_isLoading)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => const AppTrackRowShimmer(),
                childCount: 6,
              ),
            )
          else if (_playlistSongs.isEmpty)
            SliverToBoxAdapter(
              child: Center(child: Padding(padding: const EdgeInsets.all(64.0), child: Text("Треки не найдены", style: AppText.trackArtist))),
            )
          else
            SliverFixedExtentList(
              itemExtent: 74.0,
              delegate: SliverChildBuilderDelegate((context, index) {
                final song = _playlistSongs[index];
                final isCurrent = currentSong?.id == song.id || (currentSong?.title == song.title && currentSong?.artist == song.artist);
                final isLiked = user.isLiked(song.id);

                return AppTrackRow(
                  title: song.title,
                  artist: song.artist,
                  coverUrl: song.coverUrl.isNotEmpty ? song.coverUrl : widget.albumMetadata.coverUrl,
                  isCurrent: isCurrent,
                  isLiked: isLiked,
                  isDownloaded: user.isDownloaded(song.id),
                  onTap: () => player.setQueueAndPlay(_playlistSongs, startIndex: index),
                  onLike: () {
                    user.toggleLike(song);
                    AppTheme.showSnackBar(
                      context,
                      isLiked ? 'Удалено из избранного' : 'Добавлено в избранное',
                    );
                  },
                  onAction: () {
                    if (widget.type == "CustomPlaylist") {
                      user.removeSongFromPlaylist(widget.albumMetadata.id, song.id);
                      setState(() => _playlistSongs.removeWhere((s) => s.id == song.id));
                    } else {
                      showPlaylistSelectionSheet(context, song);
                    }
                  },
                  actionIcon: widget.type == "CustomPlaylist" ? AppIcons.close : AppIcons.plus,
                  song: song,
                );
              }, childCount: _playlistSongs.length),
            ),
          
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
      bottomNavigationBar: hasMiniPlayer ? const MiniPlayer() : null,
    );
  }

  Future<bool?> _showDeleteConfirm(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.modal),
        title: Center(child: Text("Удалить плейлист", style: AppText.sectionTitle)),
        content: Text("Все треки будут удалены из этой подборки. Продолжить?", 
          textAlign: TextAlign.center, style: AppText.trackArtist),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(onPressed: () => Navigator.pop(ctx, false), 
                  child: Text("Отмена", style: AppText.trackArtist)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: AppColors.accentRed, borderRadius: AppRadius.card),
                  child: TextButton(onPressed: () => Navigator.pop(ctx, true), 
                    child: Text("Удалить", style: AppText.trackTitle.copyWith(color: Colors.white))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

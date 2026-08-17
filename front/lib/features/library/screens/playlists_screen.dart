import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ses/features/library/models/song.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/features/player/providers/player_provider.dart';
import 'package:ses/core/theme/app_theme.dart';
import 'package:ses/features/library/screens/album_detail_screen.dart';
import 'package:ses/features/library/widgets/create_playlist_sheet.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isTransitioning = true;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null && _routeAnimation == null) {
      _routeAnimation = modalRoute.animation;
      _routeAnimation?.addStatusListener(_onAnimationStatusChanged);
      _isTransitioning = _routeAnimation?.isCompleted == false;
      
      // Если переход неактивен (например, при мгновенном открытии), загружаем сразу
      if (!_isTransitioning) {
        context.read<UserProvider>().loadPlaylists();
      }
    }
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    final transitioning = status != AnimationStatus.completed;
    if (transitioning != _isTransitioning) {
      setState(() {
        _isTransitioning = transitioning;
      });
      if (!transitioning) {
        // Загружаем данные только после завершения анимации перехода
        context.read<UserProvider>().loadPlaylists();
      }
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onAnimationStatusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  LinearGradient _getPlaylistGradient(String name) {
    final int hash = name.hashCode;
    final List<List<Color>> palettes = [
      [const Color(0xFF3A1C71), const Color(0xFFD76D77), const Color(0xFFFFAF7B)], // Sunset Glow
      [const Color(0xFF2C5364), const Color(0xFF203A43), const Color(0xFF0F2027)], // Deep Teal
      [const Color(0xFF1A2A6C), const Color(0xFFB21F1F), const Color(0xFFFDBB2D)], // Royal Crimson
      [const Color(0xFF00C6FF), const Color(0xFF0072FF)], // Electric Blue
      [const Color(0xFF11998E), const Color(0xFF38EF7D)], // Emerald Isle
      [const Color(0xFFAA076B), const Color(0xFF61045F)], // Sunset Magenta
      [const Color(0xFF833AB4), const Color(0xFFFD1D1D), const Color(0xFFFCB045)], // Vivid Orange
      [const Color(0xFF4E54C8), const Color(0xFF8F94FB)], // Indigo Dream
      [const Color(0xFF00F260), const Color(0xFF0575E6)], // Aurora Borealis
    ];
    final palette = palettes[hash.abs() % palettes.length];
    return LinearGradient(
      colors: palette,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, UserProvider user) {
    showCreatePlaylistSheet(context, user);
  }

  void _showRenamePlaylistSheet(BuildContext context, Map<String, dynamic> playlist, UserProvider user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          curve: Curves.fastOutSlowIn,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: _RenamePlaylistSheetContent(playlist: playlist, user: user),
        );
      },
    );
  }

  void _showDeleteConfirmSheet(BuildContext context, Map<String, dynamic> playlist, UserProvider user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) {
        return Container(
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
                "Удалить плейлист?",
                style: AppText.sectionTitle.copyWith(fontSize: 20, color: AppColors.accentRed),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Плейлист «${playlist['name']}» будет безвозвратно удален с вашего устройства.",
                style: AppText.caption.copyWith(color: Colors.white38),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
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
                        user.deletePlaylist(playlist['id'] ?? '');
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.accentRed,
                          borderRadius: AppRadius.card,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentRed.withOpacity(0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            "Удалить",
                            style: AppText.trackTitle.copyWith(
                              color: Colors.white,
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
        );
      },
    );
  }

  void _showPlaylistOptions(BuildContext context, Map<String, dynamic> playlist, UserProvider user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.03))),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(ctx).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                playlist['name'] ?? 'Плейлист',
                style: AppText.sectionTitle.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                "Управление плейлистом",
                style: AppText.caption.copyWith(color: Colors.white38),
              ),
              const SizedBox(height: 24),
              Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    _buildOptionItem(
                      icon: AppIcons.edit,
                      label: "Переименовать",
                      color: Colors.white,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showRenamePlaylistSheet(context, playlist, user);
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildOptionItem(
                      icon: AppIcons.trash,
                      label: "Удалить плейлист",
                      color: AppColors.accentRed,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showDeleteConfirmSheet(context, playlist, user);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.01)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 16),
            Text(
              label,
              style: AppText.trackTitle.copyWith(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(AppIcons.angleRight, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context);
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final currentSong = context.select<PlayerProvider, Song?>((p) => p.currentSong);
    
    final allPlaylists = user.playlists;
    final query = _searchController.text.trim().toLowerCase();
    final displayedPlaylists = query.isEmpty 
        ? allPlaylists 
        : allPlaylists.where((p) {
            final name = (p['name'] as String?)?.toLowerCase() ?? '';
            return name.contains(query);
          }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── HEADER ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 16),
                  Text("Плейлисты", style: AppText.screenTitle.copyWith(fontSize: 26, letterSpacing: -0.5)),
                  const Spacer(),
                  AppCircleButton(
                    icon: AppIcons.plus,
                    onTap: () => _showCreatePlaylistDialog(context, user),
                    size: 40,
                  ),
                ],
              ),
            ),

            // ── SEARCH ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: AppSearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hint: "Найти плейлист",
              ),
            ),

            const SizedBox(height: 8),

            // ── COUNT ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                "${allPlaylists.length} ваших подборок",
                style: AppText.caption.copyWith(color: Colors.white38),
              ),
            ),

            const SizedBox(height: 16),

            // ── GRID ──
            Expanded(
              child: displayedPlaylists.isEmpty
                  ? Center(
                      child: Text(
                        query.isEmpty ? "Нет созданных плейлистов" : "Ничего не найдено",
                        style: AppText.trackArtist,
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final double width = constraints.maxWidth;
                        final int crossAxisCount = width > 1000 ? 5 : (width > 750 ? 4 : (width > 500 ? 3 : 2));
                        return GridView.builder(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, currentSong != null ? 120 : 20),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 20,
                            childAspectRatio: 0.76,
                          ),
                          itemCount: displayedPlaylists.length,
                          itemBuilder: (context, index) {
                            final playlist = displayedPlaylists[index];
                            final cover = playlist['coverUrl'] as String? ?? '';
                            final name = playlist['name'] ?? 'Untitled';
                            final artist = playlist['artist'] ?? 'Вы';
                            
                            final coverWidget = cover.isEmpty
                                ? Container(
                                    decoration: BoxDecoration(
                                      gradient: _getPlaylistGradient(name),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        AppIcons.music,
                                        color: Colors.white.withOpacity(0.85),
                                        size: crossAxisCount > 2 ? 36 : 48,
                                      ),
                                    ),
                                  )
                                : AppCover(url: cover, size: 200, radius: 16);

                            return GestureDetector(
                              onLongPress: () => _showPlaylistOptions(context, playlist, user),
                              onTap: () {
                                _searchFocusNode.unfocus();
                                final song = Song(
                                  id: playlist['id'] ?? '',
                                  videoId: '',
                                  title: name,
                                  artist: artist,
                                  coverUrl: cover,
                                  type: 'playlist',
                                );
                                Navigator.push(
                                  context,
                                  AppPageRoute.create(
                                    context,
                                    AlbumDetailScreen(albumMetadata: song, type: "CustomPlaylist"),
                                  ),
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.surface.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white.withOpacity(0.02)),
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AspectRatio(
                                      aspectRatio: 1,
                                      child: coverWidget,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      name,
                                      style: AppText.trackTitle.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "Плейлист • $artist",
                                      style: AppText.trackArtist.copyWith(fontSize: 11, color: Colors.white38),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RenamePlaylistSheetContent extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final UserProvider user;
  const _RenamePlaylistSheetContent({required this.playlist, required this.user});

  @override
  State<_RenamePlaylistSheetContent> createState() => _RenamePlaylistSheetContentState();
}

class _RenamePlaylistSheetContentState extends State<_RenamePlaylistSheetContent> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.playlist['name']);
    _focusNode = FocusNode();
    
    // Задержка открытия клавиатуры до завершения анимации выдвижения шторки
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.03))),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).padding.bottom + 24,
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
            controller: _controller,
            focusNode: _focusNode,
            style: AppText.trackTitle,
            decoration: InputDecoration(
              hintText: "Название плейлиста",
              hintStyle: AppText.trackArtist.copyWith(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.03),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: AppRadius.input,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.input,
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
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
                    final name = _controller.text.trim();
                    if (name.isNotEmpty) {
                      widget.user.renamePlaylist(widget.playlist['id'] ?? '', name);
                    }
                    Navigator.pop(context);
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen,
                      borderRadius: AppRadius.card,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentGreen.withValues(alpha: 0.2),
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
    );
  }
}

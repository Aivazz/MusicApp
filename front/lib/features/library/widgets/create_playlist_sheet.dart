import 'package:flutter/material.dart';
import 'package:ses/features/auth/providers/user_provider.dart';
import 'package:ses/core/theme/app_theme.dart';

void showCreatePlaylistSheet(BuildContext context, UserProvider user) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    barrierColor: Colors.black.withValues(alpha: 0.8),
    builder: (ctx) {
      return AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.fastOutSlowIn,
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _CreatePlaylistSheetContent(user: user),
      );
    },
  );
}

class _CreatePlaylistSheetContent extends StatefulWidget {
  final UserProvider user;
  const _CreatePlaylistSheetContent({required this.user});

  @override
  State<_CreatePlaylistSheetContent> createState() => _CreatePlaylistSheetContentState();
}

class _CreatePlaylistSheetContentState extends State<_CreatePlaylistSheetContent> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
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
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
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
            "Новый плейлист",
            style: AppText.sectionTitle.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            "Создайте свою уникальную подборку.",
            style: AppText.caption.copyWith(color: Colors.white38),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: AppText.trackTitle,
            textAlign: TextAlign.left,
            decoration: InputDecoration(
              hintText: "Название плейлиста",
              hintStyle: AppText.trackArtist.copyWith(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.02),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: AppRadius.input,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.input,
                borderSide: const BorderSide(color: Colors.white10, width: 1),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Отмена", style: AppText.caption.copyWith(color: Colors.white54)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    final name = _controller.text.trim();
                    if (name.isNotEmpty) {
                      widget.user.createPlaylist(name);
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
                          color: AppColors.accentGreen.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        "Создать",
                        style: AppText.trackTitle.copyWith(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ses/core/services/update_service.dart';
import 'package:ses/core/theme/app_theme.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
  });

  static Future<void> show(BuildContext context, UpdateInfo updateInfo) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => UpdateDialog(updateInfo: updateInfo),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  @override
  void initState() {
    super.initState();
    UpdateService.downloadNotifier.addListener(_onDownloadProgressChanged);
  }

  @override
  void dispose() {
    UpdateService.downloadNotifier.removeListener(_onDownloadProgressChanged);
    super.dispose();
  }

  void _onDownloadProgressChanged() {
    if (mounted) setState(() {});
  }

  void _startUpdate() async {
    final downloadUrl = widget.updateInfo.downloadUrl;
    final progressState = UpdateService.downloadNotifier.value;

    // Если файл скачан и готов к установке — напрямую запускаем нативную установку
    if (progressState?.isReadyToInstall == true) {
      final installed = await UpdateService.installDownloadedApk();
      if (!installed) {
        UpdateService.startBackgroundDownload(widget.updateInfo);
      }
      return;
    }

    if (downloadUrl == null || downloadUrl.isEmpty || !Platform.isAndroid) {
      UpdateService.openReleasePage(widget.updateInfo.htmlUrl);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    UpdateService.startBackgroundDownload(widget.updateInfo);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.updateInfo;
    final progressState = UpdateService.downloadNotifier.value;
    final isDownloading = progressState?.isDownloading ?? false;
    final isReadyToInstall = progressState?.isReadyToInstall ?? false;
    final hasError = progressState?.error != null;
    final progress = progressState?.progress ?? 0.0;
    final statusText = progressState?.statusText ?? 'Начало скачивания...';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Иконка и Заголовок
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (info.hasUpdate ? AppColors.accentBlue : const Color(0xFF34C759)).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    info.hasUpdate ? Icons.arrow_downward_rounded : Icons.check_circle_rounded,
                    color: info.hasUpdate ? AppColors.accentBlue : const Color(0xFF34C759),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.hasUpdate ? 'Обновление' : 'Обновлений не найдено',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.hasUpdate
                            ? 'v${info.currentVersion} → v${info.latestVersion}'
                            : 'У вас установлена последняя версия (v${info.currentVersion})',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: info.hasUpdate ? AppColors.accentBlue : const Color(0xFF34C759),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Информация / Changelog
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(
                  info.hasUpdate
                      ? (hasError
                          ? 'Ошибка установки: ${progressState!.error}'
                          : (isReadyToInstall
                              ? 'Файл обновления скачан. Нажмите «Обновить» для повторного запуска установки.'
                              : info.releaseNotes))
                      : 'У вас установлена самая свежая версия приложения (v${info.currentVersion}).',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: hasError ? Colors.redAccent : Colors.white70,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Кнопки управления
            if (!info.hasUpdate) ...[
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Отлично',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ] else if (isDownloading) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    statusText,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentBlue),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        AppTheme.showSnackBar(
                          context,
                          'Загрузка продолжается в фоновом режиме',
                        );
                      },
                      icon: const Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.white54),
                      label: const Text(
                        'Свернуть (в фоне)',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Позже',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _startUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.arrow_downward_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            isReadyToInstall ? 'Повторить' : 'Обновить',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

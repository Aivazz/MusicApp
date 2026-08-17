import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
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
      barrierDismissible: false,
      builder: (context) => UpdateDialog(updateInfo: updateInfo),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';
  StreamSubscription<OtaEvent>? _otaSubscription;

  @override
  void dispose() {
    _otaSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startUpdate() async {
    final downloadUrl = widget.updateInfo.downloadUrl;

    if (downloadUrl == null || downloadUrl.isEmpty || !Platform.isAndroid) {
      // Файл APK не найден или платформа не Android — открываем браузер
      await UpdateService.openReleasePage(widget.updateInfo.htmlUrl);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusText = 'Начало скачивания...';
    });

    try {
      _otaSubscription = UpdateService.downloadAndInstallApk(downloadUrl).listen(
        (OtaEvent event) {
          if (!mounted) return;
          setState(() {
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
                _progress = (double.tryParse(event.value ?? '0') ?? 0) / 100.0;
                _statusText = 'Загрузка: ${(double.tryParse(event.value ?? '0') ?? 0).toInt()}%';
                break;
              case OtaStatus.INSTALLING:
                _progress = 1.0;
                _statusText = 'Запуск установки...';
                break;
              case OtaStatus.ALREADY_RUNNING_ERROR:
                _statusText = 'Загрузка уже выполняется';
                break;
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                _statusText = 'Нет разрешения на установку сторонних APK';
                _showFallbackOption('Не дано разрешение на установку приложений.');
                break;
              case OtaStatus.INTERNAL_ERROR:
              case OtaStatus.DOWNLOAD_ERROR:
              case OtaStatus.CHECKSUM_ERROR:
                _statusText = 'Ошибка скачивания';
                _showFallbackOption('Не удалось скачать обновление.');
                break;
            }
          });
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _statusText = 'Ошибка скачивания';
          });
          _showFallbackOption('Произошла ошибка: $error');
        },
      );
    } catch (e) {
      if (mounted) {
        _showFallbackOption('Не удалось запустить установщик: $e');
      }
    }
  }

  void _showFallbackOption(String message) {
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.accentRed,
        action: SnackBarAction(
          label: 'Браузер',
          textColor: Colors.white,
          onPressed: () {
            UpdateService.openReleasePage(
              widget.updateInfo.downloadUrl ?? widget.updateInfo.htmlUrl,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.updateInfo;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Иконка и Заголовок
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.accentBlue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: AppColors.accentBlue,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Доступно обновление!',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Версия v${info.currentVersion} → v${info.latestVersion}',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Название релиза (если есть)
            if (info.releaseName != null && info.releaseName!.isNotEmpty) ...[
              Text(
                info.releaseName!,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Описание изменений (Changelog)
            const Text(
              'Что нового:',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              maxHeight: 180,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              padding: const EdgeInsets.all(14),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(
                  info.releaseNotes.isEmpty
                      ? 'Улучшения производительности и исправление ошибок.'
                      : info.releaseNotes,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Статус скачивания / Прогресс-бар
            if (_isDownloading) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _statusText,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: AppColors.accentBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentBlue),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        UpdateService.openReleasePage(info.downloadUrl ?? info.htmlUrl);
                      },
                      child: const Text(
                        'Скачать через браузер',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Кнопки управления
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Позже',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _startUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.download_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            info.downloadUrl != null ? 'Обновить' : 'Открыть GitHub',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
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

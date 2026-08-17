import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseNotes;
  final String? downloadUrl;
  final String htmlUrl;
  final String? releaseName;
  final String? publishedAt;
  final bool hasUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseNotes,
    this.downloadUrl,
    required this.htmlUrl,
    this.releaseName,
    this.publishedAt,
    required this.hasUpdate,
  });
}

class UpdateService {
  // Настройки репозитория GitHub по умолчанию.
  // Можно переопределить или передать при вызове.
  static String githubOwner = 'Aivazz';
  static String githubRepo = 'MusicApp';

  /// Возвращает текущую версию приложения (например, "1.0.0")
  static Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '1.0.0';
    }
  }

  /// Проверяет наличие обновлений и отображает диалог если доступна новая версия
  static Future<void> checkAndShowUpdateDialog(
    dynamic context, {
    bool silent = false,
    Function(String msg)? onNotify,
    Function(UpdateInfo info)? onShowDialog,
  }) async {
    final info = await checkForUpdate();
    if (info != null && info.hasUpdate) {
      if (onShowDialog != null) {
        onShowDialog(info);
      }
    } else if (!silent && onNotify != null) {
      if (info != null) {
        onNotify('У вас установлена последняя версия (v${info.currentVersion})');
      } else {
        onNotify('Не удалось получить информацию об обновлениях');
      }
    }
  }

  /// Запрашивает последний релиз с GitHub и сравнивает с текущей версией приложения
  static Future<UpdateInfo?> checkForUpdate({
    String? owner,
    String? repo,
  }) async {
    final targetOwner = owner ?? githubOwner;
    final targetRepo = repo ?? githubRepo;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final url = Uri.parse(
        'https://api.github.com/repos/$targetOwner/$targetRepo/releases/latest',
      );

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'SesMusicApp/${packageInfo.version}',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('GitHub Release Check status: ${response.statusCode}');
        }
        return null;
      }

      final Map<String, dynamic> json = jsonDecode(response.body);

      // Извлекаем тег (например: "v1.0.2" или "1.0.2")
      final tagName = (json['tag_name'] as String? ?? '').trim();
      final cleanLatestVersion = _cleanVersion(tagName);
      final cleanCurrentVersion = _cleanVersion(currentVersion);

      if (cleanLatestVersion.isEmpty) return null;

      final isNewer = _isVersionNewer(cleanLatestVersion, cleanCurrentVersion);

      // Ищем .apk файл в прикрепленных дистрибутивах (assets)
      String? apkDownloadUrl;
      final assets = json['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final downloadUrl = asset['browser_download_url'] as String?;
        if (name.endsWith('.apk') && downloadUrl != null) {
          apkDownloadUrl = downloadUrl;
          break;
        }
      }

      final htmlUrl = json['html_url'] as String? ??
          'https://github.com/$targetOwner/$targetRepo/releases';
      final releaseNotes = json['body'] as String? ?? 'Описание отсутствует.';
      final releaseName = json['name'] as String?;
      final publishedAt = json['published_at'] as String?;

      return UpdateInfo(
        latestVersion: cleanLatestVersion,
        currentVersion: cleanCurrentVersion,
        releaseNotes: releaseNotes,
        downloadUrl: apkDownloadUrl,
        htmlUrl: htmlUrl,
        releaseName: releaseName,
        publishedAt: publishedAt,
        hasUpdate: isNewer,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Ошибка при проверке обновлений на GitHub: $e');
      }
      return null;
    }
  }

  /// Скачивание и установка APK на Android с отслеживанием прогресса
  static Stream<OtaEvent> downloadAndInstallApk(String downloadUrl) {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Прямая установка поддерживается только на Android');
    }
    return OtaUpdate().execute(
      downloadUrl,
      destinationFilename: 'ses-music-update.apk',
    );
  }

  /// Резервный вариант: открыть страницу релиза или прямую ссылку в браузере
  static Future<bool> openReleasePage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Очищает строку версии от символов 'v', 'V' и билдов
  static String _cleanVersion(String version) {
    var v = version.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1);
    }
    if (v.contains('+')) {
      v = v.split('+').first;
    }
    return v;
  }

  /// Сравнивает две версии в формате SemVer (например, "1.0.2" и "1.0.0")
  static bool _isVersionNewer(String latest, String current) {
    final latestParts = _parseVersionParts(latest);
    final currentParts = _parseVersionParts(current);

    final maxLength = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    for (int i = 0; i < maxLength; i++) {
      final latestNum = i < latestParts.length ? latestParts[i] : 0;
      final currentNum = i < currentParts.length ? currentParts[i] : 0;

      if (latestNum > currentNum) return true;
      if (latestNum < currentNum) return false;
    }

    return false;
  }

  static List<int> _parseVersionParts(String version) {
    return version
        .split('.')
        .map((e) => int.tryParse(RegExp(r'\d+').stringMatch(e) ?? '') ?? 0)
        .toList();
  }
}

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../platform_resolver/platform_resolver.dart';

class AvailableMediaFormat {
  const AvailableMediaFormat({
    required this.url,
    required this.container,
    required this.mimeType,
    this.fileSize,
  });

  final Uri url;
  final String container;
  final String mimeType;
  final int? fileSize;

  String get label => '$container • الملف الأصلي';
}

class MediaSourceInspection {
  const MediaSourceInspection({
    required this.sourceName,
    required this.formats,
    required this.message,
  });

  final String sourceName;
  final List<AvailableMediaFormat> formats;
  final String message;

  bool get hasFormats => formats.isNotEmpty;
}

class MediaSourceInspector {
  MediaSourceInspector({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  static const _extensions = <String>{
    '.mp4',
    '.m4v',
    '.mov',
    '.webm',
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
  };

  Future<MediaSourceInspection> inspect(Uri uri) async {
    final platform = PlatformResolver.resolve(uri.toString());
    if (platform == MediaPlatform.unknown) {
      return const MediaSourceInspection(
        sourceName: 'مصدر غير معروف',
        formats: [],
        message: 'الرابط غير صالح أو يستخدم بروتوكولًا غير مدعوم.',
      );
    }
    if (platform != MediaPlatform.direct) {
      return MediaSourceInspection(
        sourceName: PlatformResolver.label(platform),
        formats: const [],
        message:
            'هذا رابط صفحة من ${PlatformResolver.label(platform)} وليس رابط ملف مباشر. لا يوجد في التطبيق موفّر تنزيل مخوّل لهذه الصفحة، لذلك لن تُعرض جودات افتراضية.',
      );
    }

    try {
      final response = await _client
          .head(uri)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return MediaSourceInspection(
          sourceName: 'خادم الرابط المباشر',
          formats: const [],
          message:
              'لم يسمح الخادم بفحص الصيغ (HTTP ${response.statusCode}). لم يتم اختراع خيارات جودة؛ جرّب رابط ملف مباشر آخر.',
        );
      }

      final mimeType = response.headers['content-type']
              ?.split(';')
              .first
              .trim()
              .toLowerCase() ??
          '';
      final extension = p.extension(uri.path).toLowerCase();
      final hasKnownExtension = _extensions.contains(extension);
      final isMedia = mimeType.startsWith('video/') ||
          mimeType.startsWith('audio/') ||
          hasKnownExtension;
      if (!isMedia || mimeType.contains('text/html')) {
        return const MediaSourceInspection(
          sourceName: 'خادم الرابط المباشر',
          formats: [],
          message:
              'الخادم لا يعرّف هذا العنوان كملف صوت أو فيديو مباشر. صفحات الويب تحتاج إلى موفّر متوافق.',
        );
      }

      final actualExtension = hasKnownExtension
          ? extension
          : _extensionFor(mimeType);
      final container = actualExtension == '.bin'
          ? (mimeType.startsWith('video/') ? 'VIDEO' : 'AUDIO')
          : actualExtension.replaceFirst('.', '').toUpperCase();
      final size = int.tryParse(response.headers['content-length'] ?? '');
      return MediaSourceInspection(
        sourceName: 'خادم الرابط المباشر',
        formats: [
          AvailableMediaFormat(
            url: uri,
            container: container,
            mimeType: mimeType.isEmpty ? 'نوع الملف غير معلن' : mimeType,
            fileSize: size,
          ),
        ],
        message:
            'عثر الخادم على ملف واحد مباشر. لم يعلن عن دقة الصورة، لذلك تظهر الصيغة الأصلية فقط.',
      );
    } catch (error) {
      return MediaSourceInspection(
        sourceName: 'خادم الرابط المباشر',
        formats: const [],
        message:
            'تعذر فحص المصدر: ${error.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  String _extensionFor(String mimeType) {
    if (mimeType.contains('webm')) return '.webm';
    if (mimeType.contains('quicktime')) return '.mov';
    if (mimeType.contains('mpeg')) return '.mp3';
    if (mimeType.contains('ogg')) return '.ogg';
    if (mimeType.contains('wav')) return '.wav';
    if (mimeType.contains('mp4')) return '.mp4';
    return '.bin';
  }
}

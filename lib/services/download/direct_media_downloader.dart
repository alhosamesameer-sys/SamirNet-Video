import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DirectMediaDownloader {
  DirectMediaDownloader({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  bool _closed = false;

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

  Future<File> download({
    required Uri uri,
    required String fileName,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (_closed) {
      throw const HttpException('محرك التنزيل مغلق. ابدأ تنزيلًا جديدًا.');
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const HttpException('يجب أن يكون الرابط http أو https.');
    }

    final request = http.Request('GET', uri)
      ..headers['User-Agent'] = 'SamirNetVideos/1.0';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream
          .timeout(const Duration(seconds: 30))
          .drain<void>();
      throw HttpException('فشل الخادم برمز HTTP ${response.statusCode}.');
    }

    final contentType =
        response.headers['content-type']?.split(';').first.toLowerCase() ?? '';
    final pathExtension = p.extension(uri.path).toLowerCase();
    final hasMediaExtension = _extensions.contains(pathExtension);
    final isMedia = contentType.startsWith('video/') ||
        contentType.startsWith('audio/') ||
        hasMediaExtension;
    if (!isMedia || contentType.contains('text/html')) {
      await response.stream
          .timeout(const Duration(seconds: 30))
          .drain<void>();
      throw const HttpException(
        'الرابط لا يشير إلى ملف صوت أو فيديو مباشر. روابط صفحات المنصات تحتاج إلى موفّر متوافق.',
      );
    }

    final extension = hasMediaExtension
        ? pathExtension
        : _extensionFor(contentType);
    final appDirectory = await getApplicationDocumentsDirectory();
    final mediaDirectory = Directory(p.join(appDirectory.path, 'SamirNetVideos'));
    await mediaDirectory.create(recursive: true);
    final safeName = _safeFileName(fileName, extension);
    final file = await _uniqueFile(mediaDirectory, safeName);
    final sink = file.openWrite();
    var received = 0;
    var sinkClosed = false;

    try {
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, response.contentLength);
      }
      await sink.flush();
      await sink.close();
      sinkClosed = true;

      if (received == 0) {
        throw const HttpException('الملف المستلم فارغ.');
      }
      return file;
    } catch (_) {
      if (!sinkClosed) {
        try {
          await sink.close();
        } catch (_) {
          // Continue to remove the incomplete file.
        }
      }
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Keep the original network or cancellation error.
      }
      rethrow;
    }
  }

  Future<File> _uniqueFile(Directory directory, String name) async {
    final extension = p.extension(name);
    final baseName = p.basenameWithoutExtension(name);
    var candidate = File(p.join(directory.path, name));
    var index = 1;
    while (await candidate.exists()) {
      candidate = File(
        p.join(directory.path, '$baseName ($index)$extension'),
      );
      index++;
    }
    return candidate;
  }

  String _safeFileName(String name, String extension) {
    var clean = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .trim();
    if (clean.isEmpty) {
      clean = 'media_${DateTime.now().millisecondsSinceEpoch}';
    }
    final currentExtension = p.extension(clean).toLowerCase();
    if (currentExtension.isNotEmpty) {
      clean = p.basenameWithoutExtension(clean);
    }
    clean = '$clean$extension';
    return clean;
  }

  String _extensionFor(String type) {
    if (type.contains('webm')) return '.webm';
    if (type.contains('mpeg')) return '.mp3';
    if (type.contains('ogg')) return '.ogg';
    if (type.contains('wav')) return '.wav';
    if (type.contains('quicktime')) return '.mov';
    if (type.contains('mp4')) return '.mp4';
    return '.bin';
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}

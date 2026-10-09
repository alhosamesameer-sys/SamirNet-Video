import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DirectMediaDownloader {
  DirectMediaDownloader({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _extensions = <String>{'.mp4', '.m4v', '.mov', '.webm', '.mp3', '.m4a', '.aac', '.wav', '.ogg'};

  Future<File> download({
    required Uri uri,
    required String fileName,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const HttpException('يجب أن يكون الرابط http أو https.');
    }
    final request = http.Request('GET', uri);
    request.headers['User-Agent'] = 'SamirNetVideos/1.0';
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('فشل الخادم برمز HTTP ${response.statusCode}.');
    }
    final contentType = response.headers['content-type']?.split(';').first.toLowerCase() ?? '';
    final extension = p.extension(uri.path).toLowerCase();
    final isMedia = contentType.startsWith('video/') ||
        contentType.startsWith('audio/') || _extensions.contains(extension);
    if (!isMedia || contentType.contains('text/html')) {
      await response.stream.drain<void>();
      throw const HttpException('الرابط لا يشير إلى ملف صوت أو فيديو مباشر. روابط صفحات المنصات تحتاج إلى موفّر رسمي.');
    }
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'SamirNetVideos'));
    await mediaDir.create(recursive: true);
    final safeName = _safeFileName(fileName, extension.isEmpty ? _extensionFor(contentType) : extension);
    final file = File(p.join(mediaDir.path, safeName));
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, response.contentLength);
      }
      await sink.flush();
      await sink.close();
      if (received == 0) {
        await file.delete();
        throw const HttpException('الملف المستلم فارغ.');
      }
      return file;
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  String _safeFileName(String name, String extension) {
    var clean = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    if (clean.isEmpty) clean = 'media_${DateTime.now().millisecondsSinceEpoch}';
    if (!p.extension(clean).isNotEmpty) clean = '$clean$extension';
    return clean;
  }

  String _extensionFor(String type) {
    if (type.contains('webm')) return '.webm';
    if (type.contains('mpeg')) return '.mp3';
    if (type.contains('ogg')) return '.ogg';
    if (type.contains('wav')) return '.wav';
    if (type.contains('quicktime')) return '.mov';
    return '.mp4';
  }

  void close() => _client.close();
}

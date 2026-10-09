import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ytdlp_flutter/ytdlp_flutter.dart' show Ytdlp;

class YtDlpService {
  YtDlpService._();
  static final YtDlpService instance = YtDlpService._();
  static const MethodChannel _methods = MethodChannel('ytdlp_flutter');
  static const EventChannel _events = EventChannel('ytdlp_flutter/progress');
  Future<void>? _initializing;

  Future<void> initialize() => _initializing ??= Ytdlp.init();

  Future<Map<String, dynamic>> inspect(String url) async {
    await initialize();
    final raw = await _methods
        .invokeMethod<String>('getVideoInfo', <String, Object?>{'url': url})
        .timeout(const Duration(minutes: 2));
    if (raw == null || raw.trim().isEmpty) {
      throw Exception('لم يُرجع مصدر الفيديو معلومات قابلة للقراءة.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('صيغة معلومات الفيديو غير متوقعة.');
    }
    return decoded;
  }

  List<YtDlpFormat> videoFormats(Map<String, dynamic> info) {
    final raw = info['formats'];
    if (raw is! List) return const [];
    final byHeight = <int, YtDlpFormat>{};
    final noHeight = <String, YtDlpFormat>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final format = YtDlpFormat.fromJson(Map<String, dynamic>.from(item));
      if (!format.hasVideo || format.formatId.isEmpty) continue;
      final height = format.height;
      if (height == null) {
        noHeight.putIfAbsent(format.formatId, () => format);
        continue;
      }
      final old = byHeight[height];
      if (old == null ||
          (format.hasAudio && !old.hasAudio) ||
          (format.hasAudio == old.hasAudio &&
              (format.fileSize ?? 0) > (old.fileSize ?? 0))) {
        byHeight[height] = format;
      }
    }
    final formats = byHeight.values.toList()
      ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    if (formats.isEmpty) formats.addAll(noHeight.values);
    return formats;
  }

  Future<File> download({
    required String url,
    required String format,
    required String taskId,
    void Function(double? fraction, int? etaSeconds)? onProgress,
  }) async {
    await initialize();
    final appDir = await getApplicationDocumentsDirectory();
    final outputDir = Directory(p.join(appDir.path, 'downloads', taskId));
    await outputDir.create(recursive: true);
    StreamSubscription<dynamic>? subscription;
    if (onProgress != null) {
      subscription = _events.receiveBroadcastStream().listen((event) {
        if (event is! Map || event['taskId'] != taskId) return;
        final value = event['progress'];
        final percent = value is num ? value.toDouble() : -1.0;
        onProgress(
          percent < 0 ? null : (percent / 100).clamp(0.0, 1.0),
          event['etaSeconds'] is num
              ? (event['etaSeconds'] as num).toInt()
              : null,
        );
      });
    }
    try {
      final path = await _methods.invokeMethod<String>(
        'downloadAudio',
        <String, Object?>{
          'url': url,
          'outputDir': outputDir.path,
          'taskId': taskId,
          'format': format,
        },
      ).timeout(const Duration(hours: 6));
      if (path == null || path.trim().isEmpty) {
        throw Exception('انتهى محرك التنزيل دون إرجاع مسار الملف.');
      }
      final file = File(path);
      if (!await file.exists() || await file.length() <= 0) {
        throw Exception('لم يُنشأ ملف صالح بعد انتهاء التنزيل.');
      }
      return file;
    } on PlatformException catch (error) {
      if (error.code == 'CANCELLED') throw Exception('تم إلغاء التنزيل.');
      throw Exception(error.message ?? error.code);
    } finally {
      await subscription?.cancel();
    }
  }

  Future<bool> cancel(String taskId) async {
    try {
      return await _methods.invokeMethod<bool>(
            'cancel',
            <String, Object?>{'taskId': taskId},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}

class YtDlpFormat {
  const YtDlpFormat({
    required this.formatId,
    required this.ext,
    required this.label,
    required this.hasVideo,
    required this.hasAudio,
    this.height,
    this.fileSize,
  });
  final String formatId;
  final String ext;
  final String label;
  final bool hasVideo;
  final bool hasAudio;
  final int? height;
  final int? fileSize;

  factory YtDlpFormat.fromJson(Map<String, dynamic> json) {
    final id = (json['format_id'] ?? '').toString();
    final ext = (json['ext'] ?? 'ملف').toString();
    final vcodec = (json['vcodec'] ?? 'none').toString();
    final acodec = (json['acodec'] ?? 'none').toString();
    final h = json['height'];
    final height = h is num ? h.toInt() : int.tryParse('$h');
    final sizeValue = json['filesize'] ?? json['filesize_approx'];
    final size = sizeValue is num ? sizeValue.toInt() : int.tryParse('$sizeValue');
    final note = (json['format_note'] ?? '').toString();
    final quality = height != null
        ? '${height}p'
        : (note.isNotEmpty ? note : (json['resolution'] ?? 'جودة غير معلنة').toString());
    return YtDlpFormat(
      formatId: id,
      ext: ext,
      label: '$quality • $ext${acodec != 'none' && acodec.isNotEmpty ? ' • مع صوت' : ''}',
      hasVideo: vcodec != 'none' && vcodec.isNotEmpty,
      hasAudio: acodec != 'none' && acodec.isNotEmpty,
      height: height,
      fileSize: size,
    );
  }

  String selector() => hasAudio ? formatId : '$formatId+bestaudio/best';
}

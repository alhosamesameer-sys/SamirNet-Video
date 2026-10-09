import 'dart:convert';
import 'package:http/http.dart' as http;

class YouTubeVideo {
  const YouTubeVideo({required this.id, required this.title, required this.channel, required this.thumbnail, required this.publishedAt, required this.description, this.viewCount, this.likeCount, this.commentCount, this.duration = '', this.definition = ''});
  final String id;
  final String title;
  final String channel;
  final String thumbnail;
  final DateTime? publishedAt;
  final String description;
  final int? viewCount;
  final int? likeCount;
  final int? commentCount;
  final String duration;
  final String definition;
  String get watchUrl => 'https://www.youtube.com/watch?v=$id';

  factory YouTubeVideo.fromJson(Map<String, dynamic> json) {
    final snippet = (json['snippet'] as Map<String, dynamic>?) ?? const {};
    final thumbnails = (snippet['thumbnails'] as Map<String, dynamic>?) ?? const {};
    final medium = (thumbnails['high'] ?? thumbnails['medium'] ?? thumbnails['default']) as Map<String, dynamic>?;
    final rawId = json['id'];
    final idObject = rawId is Map<String, dynamic> ? rawId : const <String, dynamic>{};
    return YouTubeVideo(
      id: (idObject['videoId'] ?? (rawId is String ? rawId : '')).toString(),
      title: (snippet['title'] ?? 'بدون عنوان').toString(),
      channel: (snippet['channelTitle'] ?? '').toString(),
      thumbnail: (medium?['url'] ?? '').toString(),
      publishedAt: DateTime.tryParse((snippet['publishedAt'] ?? '').toString()),
      description: (snippet['description'] ?? '').toString(),
      viewCount: _intOrNull((json['statistics'] as Map<String, dynamic>?)?['viewCount']),
      likeCount: _intOrNull((json['statistics'] as Map<String, dynamic>?)?['likeCount']),
      commentCount: _intOrNull((json['statistics'] as Map<String, dynamic>?)?['commentCount']),
      duration: (json['contentDetails'] as Map<String, dynamic>?)?['duration']?.toString() ?? '',
      definition: (json['contentDetails'] as Map<String, dynamic>?)?['definition']?.toString() ?? '',
    );
  }
}

int? _intOrNull(dynamic value) => value == null ? null : int.tryParse(value.toString());

class YouTubeSearchService {
  YouTubeSearchService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _base = 'https://www.googleapis.com/youtube/v3/search';
  static const _videosBase = 'https://www.googleapis.com/youtube/v3/videos';

  Future<List<YouTubeVideo>> search({required String query, required String apiKey, int maxResults = 20}) async {
    final key = apiKey.trim();
    if (key.isEmpty) throw ArgumentError('أضف مفتاح YouTube Data API في الإعدادات أولًا.');
    if (query.trim().isEmpty) return [];
    final uri = Uri.parse(_base).replace(queryParameters: {
      'part': 'snippet', 'type': 'video', 'q': query.trim(),
      'maxResults': maxResults.clamp(1, 50).toString(), 'key': key,
      'regionCode': 'YE', 'relevanceLanguage': 'ar', 'safeSearch': 'moderate',
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      String message = 'تعذر البحث (HTTP ${response.statusCode}). تحقق من المفتاح وتفعيل YouTube Data API v3.';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final error = body['error'] as Map<String, dynamic>?;
        final apiMessage = error?['message'];
        if (apiMessage is String && apiMessage.isNotEmpty) message = apiMessage;
      } catch (_) {}
      throw Exception(message);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = body['items'] as List<dynamic>? ?? const [];
    return items.whereType<Map<String, dynamic>>().map(YouTubeVideo.fromJson).where((v) => v.id.isNotEmpty).toList();
  }


  Future<YouTubeVideo?> getVideoDetails({required String videoId, required String apiKey}) async {
    final key = apiKey.trim();
    if (key.isEmpty) throw ArgumentError('أضف مفتاح YouTube Data API في الإعدادات أولًا.');
    final uri = Uri.parse(_videosBase).replace(queryParameters: {
      'part': 'snippet,contentDetails,statistics',
      'id': videoId,
      'key': key,
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('تعذر جلب تفاصيل الفيديو (HTTP ${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = body['items'] as List<dynamic>? ?? const [];
    if (items.isEmpty || items.first is! Map<String, dynamic>) return null;
    return YouTubeVideo.fromJson(items.first as Map<String, dynamic>);
  }

  void close() => _client.close();
}

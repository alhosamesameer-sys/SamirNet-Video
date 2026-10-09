import 'dart:convert';
import 'package:http/http.dart' as http;

class YouTubeVideo {
  const YouTubeVideo({required this.id, required this.title, required this.channel, required this.thumbnail, required this.publishedAt, required this.description});
  final String id;
  final String title;
  final String channel;
  final String thumbnail;
  final DateTime? publishedAt;
  final String description;
  String get watchUrl => 'https://www.youtube.com/watch?v=$id';

  factory YouTubeVideo.fromJson(Map<String, dynamic> json) {
    final snippet = (json['snippet'] as Map<String, dynamic>?) ?? const {};
    final thumbnails = (snippet['thumbnails'] as Map<String, dynamic>?) ?? const {};
    final medium = (thumbnails['high'] ?? thumbnails['medium'] ?? thumbnails['default']) as Map<String, dynamic>?;
    final idObject = (json['id'] as Map<String, dynamic>?) ?? const {};
    return YouTubeVideo(
      id: (idObject['videoId'] ?? json['id'] ?? '').toString(),
      title: (snippet['title'] ?? 'بدون عنوان').toString(),
      channel: (snippet['channelTitle'] ?? '').toString(),
      thumbnail: (medium?['url'] ?? '').toString(),
      publishedAt: DateTime.tryParse((snippet['publishedAt'] ?? '').toString()),
      description: (snippet['description'] ?? '').toString(),
    );
  }
}

class YouTubeSearchService {
  YouTubeSearchService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _base = 'https://www.googleapis.com/youtube/v3/search';

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

  void close() => _client.close();
}

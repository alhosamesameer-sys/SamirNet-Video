import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:samirnet_videos/services/download/media_source_inspector.dart';

void main() {
  test('returns only the direct format confirmed by the server', () async {
    final client = MockClient((request) async {
      expect(request.method, 'HEAD');
      return http.Response(
        '',
        200,
        headers: {
          'content-type': 'video/mp4',
          'content-length': '2048',
        },
      );
    });
    final inspector = MediaSourceInspector(client: client);

    final result = await inspector.inspect(
      Uri.parse('https://cdn.example.test/sample.mp4'),
    );

    expect(result.hasFormats, isTrue);
    expect(result.formats, hasLength(1));
    expect(result.formats.single.container, 'MP4');
    expect(result.formats.single.fileSize, 2048);
    expect(result.formats.single.mimeType, 'video/mp4');
    client.close();
  });

  test('does not invent formats for a YouTube page URL', () async {
    final inspector = MediaSourceInspector(
      client: MockClient((_) async => throw StateError('network should not run')),
    );

    final result = await inspector.inspect(
      Uri.parse('https://www.youtube.com/watch?v=abc123'),
    );

    expect(result.hasFormats, isFalse);
    expect(result.sourceName, 'YouTube');
    expect(result.message, contains('ليس رابط ملف مباشر'));
  });

  test('rejects HTML pages even when the URL looks like an MP4', () async {
    final client = MockClient((_) async => http.Response(
          '',
          200,
          headers: {'content-type': 'text/html', 'content-length': '800'},
        ));
    final result = await MediaSourceInspector(client: client).inspect(
      Uri.parse('https://cdn.example.test/not-a-video.mp4'),
    );

    expect(result.hasFormats, isFalse);
    expect(result.message, contains('لا يعرّف هذا العنوان'));
    client.close();
  });

  test('does not claim formats when the server rejects HEAD', () async {
    final client = MockClient((_) async => http.Response('', 405));
    final result = await MediaSourceInspector(client: client).inspect(
      Uri.parse('https://cdn.example.test/sample.mp4'),
    );

    expect(result.hasFormats, isFalse);
    expect(result.message, contains('HTTP 405'));
    client.close();
  });
}

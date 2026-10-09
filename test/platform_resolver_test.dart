import 'package:flutter_test/flutter_test.dart';
import 'package:samirnet_videos/services/platform_resolver/platform_resolver.dart';

void main() {
  test('recognizes supported public platform domains', () {
    expect(PlatformResolver.resolve('https://youtu.be/abc'), MediaPlatform.youtube);
    expect(PlatformResolver.resolve('https://www.tiktok.com/@user/video/1'), MediaPlatform.tiktok);
    expect(PlatformResolver.resolve('https://instagram.com/reel/abc'), MediaPlatform.instagram);
  });

  test('rejects invalid and non-http links', () {
    expect(PlatformResolver.parseHttpUrl('not a url'), isNull);
    expect(PlatformResolver.parseHttpUrl('file:///etc/passwd'), isNull);
    expect(PlatformResolver.parseHttpUrl('javascript:alert(1)'), isNull);
  });
}

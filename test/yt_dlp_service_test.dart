import 'package:flutter_test/flutter_test.dart';
import 'package:samirnet_videos/services/download/yt_dlp_service.dart';

void main() {
  group('YtDlpService video format parsing', () {
    test('prefers a combined audio/video format for each available height', () {
      final formats = YtDlpService.instance.videoFormats({
        'formats': [
          {
            'format_id': '137',
            'ext': 'mp4',
            'height': 1080,
            'vcodec': 'avc1',
            'acodec': 'none',
            'filesize_approx': 10000000,
          },
          {
            'format_id': '399',
            'ext': 'mp4',
            'height': 1080,
            'vcodec': 'av01',
            'acodec': 'none',
            'filesize_approx': 8000000,
          },
          {
            'format_id': '22',
            'ext': 'mp4',
            'height': 720,
            'vcodec': 'avc1',
            'acodec': 'mp4a',
            'filesize': 6000000,
          },
        ],
      });

      expect(formats, hasLength(2));
      expect(formats.first.height, 1080);
      expect(formats.first.selector(), '137+bestaudio/best');
      expect(formats.last.height, 720);
      expect(formats.last.selector(), '22');
      expect(formats.last.hasAudio, isTrue);
    });

    test('ignores audio-only streams when building video quality options', () {
      final formats = YtDlpService.instance.videoFormats({
        'formats': [
          {'format_id': '140', 'ext': 'm4a', 'vcodec': 'none', 'acodec': 'mp4a'},
        ],
      });
      expect(formats, isEmpty);
    });
  });
}

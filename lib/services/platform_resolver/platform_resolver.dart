enum MediaPlatform { youtube, tiktok, instagram, snapchat, facebook, direct, unknown }

class PlatformResolver {
  static Uri? parseHttpUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !uri.hasAuthority || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return null;
    }
    if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
    return uri;
  }

  static MediaPlatform resolve(String input) {
    final uri = parseHttpUrl(input);
    if (uri == null) return MediaPlatform.unknown;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (host == 'youtube.com' || host == 'youtu.be' || host.endsWith('.youtube.com')) return MediaPlatform.youtube;
    if (host == 'tiktok.com' || host.endsWith('.tiktok.com')) return MediaPlatform.tiktok;
    if (host == 'instagram.com' || host.endsWith('.instagram.com')) return MediaPlatform.instagram;
    if (host == 'snapchat.com' || host.endsWith('.snapchat.com')) return MediaPlatform.snapchat;
    if (host == 'facebook.com' || host.endsWith('.facebook.com') || host == 'fb.watch') return MediaPlatform.facebook;
    return MediaPlatform.direct;
  }

  static String label(MediaPlatform platform) => switch (platform) {
    MediaPlatform.youtube => 'YouTube',
    MediaPlatform.tiktok => 'TikTok',
    MediaPlatform.instagram => 'Instagram',
    MediaPlatform.snapchat => 'Snapchat',
    MediaPlatform.facebook => 'Facebook',
    MediaPlatform.direct => 'رابط ويب مباشر',
    MediaPlatform.unknown => 'غير معروف',
  };
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import '../../services/download/direct_media_downloader.dart';
import '../../services/search/youtube_search_service.dart';
import '../../services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database/download_database.dart';
import '../../services/platform_resolver/platform_resolver.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.themeMode, required this.onThemeChanged});
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  final _url = TextEditingController();
  final _search = TextEditingController();
  bool _busy = false;
  List<Map<String, Object?>> _downloads = [];
  String _message = '';
  bool _searching = false;
  List<YouTubeVideo> _searchResults = [];
  String _apiKey = '';
  double? _downloadProgress;
  @override
  @override
  void initState() { super.initState(); _refresh(); SettingsService.loadYouTubeApiKey().then((key) { if (mounted) setState(() => _apiKey = key); }); }
  @override
  void dispose() { _url.dispose(); _search.dispose(); super.dispose(); }

  Future<void> _refresh() async {
    try {
      final rows = await DownloadDatabase.all();
      if (mounted) setState(() => _downloads = rows);
    } catch (_) {
      if (mounted) setState(() => _message = 'تعذر فتح سجل التنزيلات المحلي.');
    }
  }

  Future<void> _runYouTubeSearch() async {
    final query = _search.text.trim();
    if (query.isEmpty) { setState(() => _message = 'اكتب كلمات البحث أولًا.'); return; }
    if (_apiKey.isEmpty) { setState(() => _message = 'أضف مفتاح YouTube Data API من الإعدادات أولًا.'); return; }
    setState(() { _searching = true; _message = ''; _searchResults = []; });
    try {
      final results = await YouTubeSearchService().search(query: query, apiKey: _apiKey);
      if (mounted) setState(() { _searchResults = results; _message = results.isEmpty ? 'لم يتم العثور على نتائج.' : ''; });
    } catch (e) { if (mounted) setState(() => _message = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => _searching = false); }
  }

  Future<void> _downloadDirect(Map<String, Object?> row) async {
    final id = row['id'];
    if (id is! int) return;
    final uri = Uri.tryParse((row['url'] ?? '').toString());
    if (uri == null) return;
    setState(() { _busy = true; _downloadProgress = 0; _message = 'جارٍ تنزيل الملف المباشر...'; });
    try {
      final downloader = DirectMediaDownloader();
      final file = await downloader.download(uri: uri, fileName: (row['title'] ?? 'media').toString().replaceAll(RegExp(r'[^a-zA-Z0-9 _.-]'), '_'), onProgress: (received, total) { if (mounted) setState(() => _downloadProgress = total == null || total == 0 ? null : received / total); });
      await DownloadDatabase.updateDownload(id, status: 'تم التنزيل', filePath: file.path, fileSize: await file.length());
      await _refresh();
      if (mounted) setState(() => _message = 'اكتمل تنزيل الملف: ${p.basename(file.path)}');
    } catch (e) { if (mounted) setState(() => _message = e.toString().replaceFirst('HttpException: ', '')); }
    finally { if (mounted) setState(() { _busy = false; _downloadProgress = null; }); }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) setState(() => _url.text = data!.text!.trim());
  }

  Future<void> _analyzeLink() async {
    if (_busy) return;
    final uri = PlatformResolver.parseHttpUrl(_url.text);
    if (uri == null) {
      setState(() => _message = 'أدخل رابطًا صحيحًا يبدأ بـ http أو https.');
      return;
    }
    final platform = PlatformResolver.resolve(uri.toString());
    if (platform == MediaPlatform.unknown) {
      setState(() => _message = 'تعذر التعرّف على الرابط. تحقق من العنوان.');
      return;
    }
    setState(() { _busy = true; _message = ''; });
    try {
      final label = PlatformResolver.label(platform);
      await DownloadDatabase.add(
        url: uri.toString(),
        platform: label,
        title: 'رابط من $label',
        status: 'جاهز للتحليل',
      );
      await _refresh();
      if (!mounted) return;
      setState(() {
        _message = platform == MediaPlatform.direct
          ? 'تم حفظ الرابط. لم نتحقق بعد من أنه ملف وسائط مباشر.'
          : 'تم التعرف على $label وحفظ الرابط في السجل. تحليل الفيديو والتنزيل الفعلي يحتاجان إلى موفّر متوافق؛ لم يبدأ تنزيل وهمي.';
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'تعذر حفظ الرابط محليًا. تحقق من صلاحية قاعدة البيانات.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_home(), _searchPage(), _linkPage(), _downloadsPage()];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const _Brand(),
          actions: [IconButton(tooltip: 'الإعدادات', onPressed: _openSettings, icon: const Icon(Icons.settings_outlined))],
        ),
        body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() { _tab = value; _message = ''; }),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'تم تنزيلها'),
            NavigationDestination(icon: Icon(Icons.search), selectedIcon: Icon(Icons.search_rounded), label: 'البحث'),
            NavigationDestination(icon: Icon(Icons.add_circle, size: 38, color: AppTheme.red), selectedIcon: Icon(Icons.add_circle, size: 38, color: AppTheme.red), label: 'إرسال رابط'),
            NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'التنزيلات'),
          ],
        ),
      ),
    );
  }

  Widget _home() => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 22), children: [
      TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => setState(() => _tab = 1),
        decoration: InputDecoration(
          hintText: 'ابحث عن فيديو أو رابط...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(onPressed: () => setState(_search.clear), icon: const Icon(Icons.close)),
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFF625C), Color(0xFFED202B)], begin: Alignment.topRight, end: Alignment.bottomLeft),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: AppTheme.red.withValues(alpha: .18), blurRadius: 16, offset: const Offset(0, 7))],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('كل فيديوهاتك في مكان واحد', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('احفظ الروابط ونظّم مكتبتك بسهولة', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.red),
              onPressed: () => setState(() => _tab = 2),
              child: const Text('إرسال رابط  ←'),
            ),
          ])),
          const SizedBox(width: 8),
          Container(width: 76, height: 76, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .17), borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 60)),
        ]),
      ),
      const SizedBox(height: 18),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.42,
        children: [
          _quick(Icons.link_rounded, 'إرسال رابط', 'تحقق من المنصة', AppTheme.red, () => setState(() => _tab = 2)),
          _quick(Icons.search_rounded, 'البحث', 'ابحث عن فيديو', AppTheme.red, () => setState(() => _tab = 1)),
          _quick(Icons.downloading_rounded, 'التنزيلات', 'روابط قيد المتابعة', AppTheme.yellow, () => setState(() => _tab = 3)),
          _quick(Icons.video_library_rounded, 'تم تنزيلها', '${_downloads.length} سجل محفوظ', AppTheme.yellow, () => setState(() => _tab = 0)),
        ],
      ),
      const SizedBox(height: 22),
      Row(children: [
        const Expanded(child: Text('أحدث الروابط', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        TextButton(onPressed: () => setState(() => _tab = 0), child: const Text('عرض الكل')),
      ]),
      if (_downloads.isEmpty) const _EmptyState(text: 'لا توجد روابط بعد. أضف رابط فيديو للبدء.'),
      ..._downloads.take(3).map(_downloadTile),
      if (_message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: _MessageCard(message: _message)),
      const SizedBox(height: 8),
      const Wrap(alignment: WrapAlignment.center, spacing: 10, children: [
        _PlatformIcon(label: 'YouTube', icon: Icons.smart_display, color: Color(0xFFFF0033)),
        _PlatformIcon(label: 'TikTok', icon: Icons.music_note, color: Color(0xFF111827)),
        _PlatformIcon(label: 'Instagram', icon: Icons.camera_alt_outlined, color: Color(0xFFC13584)),
        _PlatformIcon(label: 'Facebook', icon: Icons.facebook, color: Color(0xFF1877F2)),
      ]),
    ]),
  );

  Widget _quick(IconData icon, String title, String subtitle, Color color, VoidCallback action) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20), onTap: action,
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 25)),
        const SizedBox(height: 9),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      ])),
    ),
  );

  Widget _linkPage() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('إرسال الرابط', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
    const SizedBox(height: 6),
    const Text('الصق رابط فيديو عام، وسنتعرف على المنصة ونحفظ الرابط في مكتبتك.'),
    const SizedBox(height: 18),
    TextField(controller: _url, minLines: 2, maxLines: 4, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'الصق الرابط هنا...', prefixIcon: Icon(Icons.link), alignLabelWithHint: true)),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste), label: const Text('لصق'))),
      const SizedBox(width: 10),
      Expanded(child: FilledButton.icon(onPressed: _busy ? null : _analyzeLink, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send), label: const Text('إرسال'))),
    ]),
    if (_message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: _MessageCard(message: _message)),
    const SizedBox(height: 22),
    const Text('المنصات المدعومة للتعرّف على الروابط', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
    const SizedBox(height: 10),
    const Wrap(spacing: 8, runSpacing: 8, children: [_PlatformChip('YouTube'), _PlatformChip('TikTok'), _PlatformChip('Instagram'), _PlatformChip('Snapchat'), _PlatformChip('Facebook')]),
    const SizedBox(height: 20),
    const _InfoCard(icon: Icons.verified_user_outlined, title: 'خصوصيتك أولًا', body: 'لا نطلب كلمات مرور ولا نتجاوز المحتوى الخاص أو أنظمة الحماية.'),
    const _InfoCard(icon: Icons.info_outline, title: 'حول التنزيل', body: 'التعرف على المنصة لا يعني أن التنزيل متاح. لن نعرض جودات وهمية أو ندّعي اكتمال تنزيل لم يحدث.'),
  ]);

  Widget _searchPage() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('البحث', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
    const SizedBox(height: 14),
    TextField(controller: _search, textInputAction: TextInputAction.search, onSubmitted: (_) => _showSearchNotice(), decoration: InputDecoration(hintText: 'ابحث في YouTube...', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: () => setState(_search.clear), icon: const Icon(Icons.close)))),
    const SizedBox(height: 10),
    FilledButton.icon(onPressed: _searching ? null : _runYouTubeSearch, icon: _searching ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search), label: const Text('بحث حقيقي في YouTube')),
    const SizedBox(height: 14),
    if (_message.isNotEmpty) _MessageCard(message: _message),
    if (_searchResults.isNotEmpty) ..._searchResults.map((video) => Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: video.thumbnail.isEmpty ? const Icon(Icons.play_circle_outline) : Image.network(video.thumbnail, width: 84, height: 60, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_outline)), title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text(video.channel), trailing: IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => Share.share(video.watchUrl)), onTap: () async { final id = await DownloadDatabase.add(url: video.watchUrl, platform: 'YouTube', title: video.title, status: 'رابط محفوظ - يلزم مصدر تنزيل متوافق'); await _refresh(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ رابط الفيديو في المكتبة'))); }))),
    if (_searchResults.isEmpty && _message.isEmpty) const _InfoCard(icon: Icons.public, title: 'البحث المباشر', body: 'يعرض نتائج YouTube الحقيقية باستخدام YouTube Data API بعد إضافة مفتاح API من الإعدادات.'),
  ]);

  void _showSearchNotice() => setState(() => _message = _search.text.trim().isEmpty
    ? 'اكتب كلمات البحث أولًا.'
    : 'البحث الحي غير مفعّل بعد. يلزم إعداد API رسمي للحصول على نتائج حقيقية.');

  Widget _downloadTile(Map<String, Object?> row) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      leading: Container(width: 46, height: 46, decoration: BoxDecoration(color: AppTheme.red.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.play_arrow_rounded, color: AppTheme.red, size: 30)),
      title: Text((row['title'] ?? 'رابط فيديو').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${row['platform']} • ${row['status']}\n${row['url']}', maxLines: 2, overflow: TextOverflow.ellipsis),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'share') await Share.share((row['url'] ?? '').toString());
          if (value == 'copy') { await Clipboard.setData(ClipboardData(text: (row['url'] ?? '').toString())); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الرابط'))); }
          if (value == 'download') await _downloadDirect(row);
          if (value == 'delete') { final id = row['id']; if (id is int) await DownloadDatabase.delete(id); await _refresh(); }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'share', child: Text('مشاركة الرابط')),
          PopupMenuItem(value: 'copy', child: Text('نسخ الرابط')),
          PopupMenuItem(value: 'download', child: Text('تنزيل ملف مباشر')),
          PopupMenuItem(value: 'delete', child: Text('حذف من السجل')),
        ],
      ),
    ),
  );

  Widget _downloadsPage() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('التنزيلات', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
    const SizedBox(height: 12),
    const _InfoCard(icon: Icons.downloading, title: 'إدارة التنزيلات', body: 'يمكن تنزيل الروابط المباشرة لملفات الصوت والفيديو. روابط صفحات YouTube وTikTok وغيرها ليست روابط ملفات مباشرة وتحتاج إلى مصدر رسمي متوافق.'),
    if (_busy && _downloadProgress != null) LinearProgressIndicator(value: _downloadProgress),
    if (_message.isNotEmpty) _MessageCard(message: _message),
    if (_downloads.isEmpty) const _EmptyState(text: 'لا توجد روابط في القائمة.'),
    ..._downloads.map(_downloadTile),
  ]);

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('الإعدادات', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12), const Text('المظهر'),
          RadioListTile<ThemeMode>(value: ThemeMode.system, groupValue: widget.themeMode, title: const Text('حسب النظام'), onChanged: (v) { if (v != null) { widget.onThemeChanged(v); Navigator.pop(context); } }),
          RadioListTile<ThemeMode>(value: ThemeMode.light, groupValue: widget.themeMode, title: const Text('الوضع النهاري'), onChanged: (v) { if (v != null) { widget.onThemeChanged(v); Navigator.pop(context); } }),
          RadioListTile<ThemeMode>(value: ThemeMode.dark, groupValue: widget.themeMode, title: const Text('الوضع الليلي'), onChanged: (v) { if (v != null) { widget.onThemeChanged(v); Navigator.pop(context); } }),
          const Divider(),
          const ListTile(leading: Icon(Icons.folder_outlined), title: Text('مجلد الحفظ'), subtitle: Text('إعداد مجلد الحفظ يحتاج إلى صلاحيات Android وربط إدارة الملفات.')),
          const ListTile(leading: Icon(Icons.notifications_active_outlined), title: Text('إشعارات التنزيل'), subtitle: Text('ستُفعّل عند إضافة محرك تنزيل فعلي.')),
          const ListTile(leading: Icon(Icons.key_outlined), title: Text('مفتاح YouTube Data API'), subtitle: Text('للبحث الحقيقي، أنشئ مفتاحًا في Google Cloud وفعّل YouTube Data API v3.')),
          TextFormField(initialValue: _apiKey, obscureText: true, decoration: const InputDecoration(labelText: 'API Key', hintText: 'أدخل مفتاح YouTube Data API'), onChanged: (v) => _apiKey = v.trim()),
          const SizedBox(height: 8),
          FilledButton(onPressed: () async { await SettingsService.saveYouTubeApiKey(_apiKey); if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('تم حفظ مفتاح البحث على الجهاز'))); } }, child: const Text('حفظ إعدادات البحث')),
          const SizedBox(height: 8),
          const ListTile(leading: Icon(Icons.info_outline), title: Text('حول SamirNet Videos'), subtitle: Text('الإصدار 1.0.0 • Flutter')),
        ]),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 34, height: 34, decoration: BoxDecoration(color: AppTheme.red, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.download_rounded, color: Colors.white, size: 23)),
    const SizedBox(width: 8),
    const Text('Samir', style: TextStyle(fontWeight: FontWeight.w900)),
    const Text('Net', style: TextStyle(color: AppTheme.red, fontWeight: FontWeight.w900)),
  ]);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Column(children: [const Icon(Icons.video_library_outlined, size: 38, color: AppTheme.muted), const SizedBox(height: 8), Text(text, textAlign: TextAlign.center)]))));
}
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});
  final IconData icon; final String title; final String body;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: AppTheme.red), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(body)]))])));
}
class _PlatformChip extends StatelessWidget {
  const _PlatformChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Chip(avatar: const Icon(Icons.public, size: 17), label: Text(label));
}
class _PlatformIcon extends StatelessWidget {
  const _PlatformIcon({required this.label, required this.icon, required this.color});
  final String label; final IconData icon; final Color color;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color)), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 10))]);
}
class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info_outline, color: AppTheme.red), const SizedBox(width: 10), Expanded(child: Text(message))])));
}

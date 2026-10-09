import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  @override
  void initState() { super.initState(); _refresh(); }
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
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) _url.text = data!.text!;
  }
  Future<void> _analyzeLink() async {
    if (_busy) return;
    final uri = PlatformResolver.parseHttpUrl(_url.text);
    if (uri == null) { setState(() => _message = 'أدخل رابطًا صحيحًا يبدأ بـ http أو https.'); return; }
    final platform = PlatformResolver.resolve(uri.toString());
    if (platform == MediaPlatform.unknown) { setState(() => _message = 'تعذر التعرّف على الرابط. تحقق من العنوان.'); return; }
    setState(() { _busy = true; _message = ''; });
    try {
      if (platform == MediaPlatform.direct) {
        setState(() => _message = 'رابط ويب مباشر؛ لم يتم التحقق من أنه ملف وسائط قابل للتنزيل. لم يبدأ أي تنزيل.');
      } else {
        setState(() => _message = 'تم التعرّف على ${PlatformResolver.label(platform)}. يلزم موفّر تحليل متوافق للحصول على بيانات وجودات حقيقية؛ لم يبدأ التنزيل.');
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_home(), _searchPage(), _linkPage(), _libraryPage()];
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(title: const _Brand(), actions: [IconButton(tooltip: 'الإعدادات', onPressed: _openSettings, icon: const Icon(Icons.settings_outlined))]),
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.downloading_outlined), selectedIcon: Icon(Icons.downloading), label: 'تنزيلاتي'),
          NavigationDestination(icon: Icon(Icons.search), label: 'البحث'),
          NavigationDestination(icon: Icon(Icons.add_circle, size: 34, color: AppTheme.red), label: 'إرسال رابط'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'تم تنزيلها'),
        ],
      ),
    ));
  }

  Widget _home() => RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.all(18), children: [
    Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.red, borderRadius: BorderRadius.circular(24)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.download_for_offline_outlined, color: Colors.white, size: 38), SizedBox(height: 12),
      Text('أسهل طريقة لتنظيم روابط الفيديوهات', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold)),
      SizedBox(height: 6), Text('ألصق الرابط لمعرفة المنصة وحالة الدعم المتاحة.', style: TextStyle(color: Colors.white)),
    ])),
    const SizedBox(height: 18),
    TextField(controller: _url, keyboardType: TextInputType.url, decoration: InputDecoration(hintText: 'ابحث أو الصق رابط فيديو', prefixIcon: const Icon(Icons.link), suffixIcon: IconButton(onPressed: _paste, icon: const Icon(Icons.content_paste), tooltip: 'لصق'))),
    const SizedBox(height: 12),
    SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { setState(() => _tab = 2); _analyzeLink(); }, icon: const Icon(Icons.link), label: const Text('تحليل الرابط'))),
    const SizedBox(height: 20), const Text('الوصول السريع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.25, children: [
      _quick(Icons.link, 'إرسال رابط', 'التعرّف على المنصة', () => setState(() => _tab = 2)),
      _quick(Icons.search, 'البحث', 'بحث الويب', () => setState(() => _tab = 1)),
      _quick(Icons.downloading, 'التنزيلات', '${_downloads.length} سجل محلي', () => setState(() => _tab = 0)),
      _quick(Icons.folder_open, 'تم تنزيلها', 'ملفات محفوظة', () => setState(() => _tab = 3)),
    ]),
    const SizedBox(height: 20), const Text('أحدث السجلات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    if (_downloads.isEmpty) const _EmptyState(text: 'لا توجد سجلات حتى الآن. أضف رابطًا للبدء.'),
    ..._downloads.take(4).map(_downloadTile),
    if (_message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_message, style: const TextStyle(color: AppTheme.red))),
  ]));

  Widget _quick(IconData icon, String title, String subtitle, VoidCallback action) => Card(child: InkWell(
    borderRadius: BorderRadius.circular(20), onTap: action,
    child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: AppTheme.red, size: 28), const SizedBox(height: 10), Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
    ])),
  ));

  Widget _linkPage() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('إرسال الرابط', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8), const Text('ألصق رابطًا عامًا. سيتعرف التطبيق على النطاق، لكن توفر بيانات الفيديو والتنزيل يعتمد على مصدر متوافق.'),
    const SizedBox(height: 18),
    TextField(controller: _url, minLines: 3, maxLines: 5, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://...', prefixIcon: Icon(Icons.link), alignLabelWithHint: true)),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste), label: const Text('لصق'))),
      const SizedBox(width: 10),
      Expanded(child: FilledButton.icon(onPressed: _busy ? null : _analyzeLink, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send), label: const Text('إرسال'))),
    ]),
    if (_message.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_message))),
    const SizedBox(height: 20), const Text('التعرّف على المنصة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
    const SizedBox(height: 10),
    const Wrap(spacing: 8, runSpacing: 8, children: [_PlatformChip('YouTube'), _PlatformChip('TikTok'), _PlatformChip('Instagram'), _PlatformChip('Snapchat'), _PlatformChip('Facebook')]),
    const SizedBox(height: 20),
    const _InfoCard(icon: Icons.shield_outlined, title: 'خصوصيتك أولًا', body: 'لا نطلب كلمات مرور ولا نتجاوز المحتوى الخاص أو أنظمة الحماية.'),
    const _InfoCard(icon: Icons.info_outline, title: 'مهم', body: 'التعرّف على المنصة لا يعني أن تنزيل محتواها متاح. لن تظهر جودات وهمية ولن ندّعي اكتمال تنزيل لم يحدث.'),
  ]);

  Widget _searchPage() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('البحث', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const _InfoCard(icon: Icons.search, title: 'البحث عن الفيديوهات', body: 'بحث YouTube المباشر يحتاج إلى API رسمي أو مزوّد بحث موثوق. لم تُضف مفاتيح أو نتائج ثابتة وهمية إلى التطبيق.'),
    TextField(controller: _search, decoration: InputDecoration(hintText: 'اكتب كلمات البحث', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: () => setState(_search.clear), icon: const Icon(Icons.close)))),
    const SizedBox(height: 10),
    FilledButton.icon(onPressed: () => setState(() => _message = 'البحث المباشر غير مفعّل بعد: يلزم إعداد مزوّد بحث رسمي.'), icon: const Icon(Icons.search), label: const Text('بحث')),
    if (_message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message)),
  ]);

  Widget _libraryPage() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('تم تنزيلها', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8), const Text('هذه سجلات محلية وليست إثباتًا لوجود ملف مكتمل.'),
    const SizedBox(height: 12),
    if (_downloads.isEmpty) const _EmptyState(text: 'لا توجد ملفات أو سجلات محفوظة.'),
    ..._downloads.map(_downloadTile),
  ]);

  Widget _downloadTile(Map<String, Object?> row) => Card(child: ListTile(
    leading: const CircleAvatar(child: Icon(Icons.insert_drive_file_outlined)),
    title: Text((row['title'] ?? 'رابط وسائط').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text('${row['platform']} • ${row['status']}\n${row['url']}', maxLines: 2, overflow: TextOverflow.ellipsis),
    isThreeLine: true,
    trailing: IconButton(tooltip: 'حذف السجل', icon: const Icon(Icons.delete_outline), onPressed: () async {
      final id = row['id']; if (id is int) await DownloadDatabase.delete(id); await _refresh();
    }),
  ));

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true,
      builder: (context) => Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('الإعدادات', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 12), const Text('المظهر'),
        RadioListTile<ThemeMode>(value: ThemeMode.system, groupValue: widget.themeMode, title: const Text('حسب النظام'), onChanged: (v) { if (v != null) { widget.onThemeChanged(v); Navigator.pop(context); } }),
        RadioListTile<ThemeMode>(value: ThemeMode.light, groupValue: widget.themeMode, title: const Text('فاتح'), onChanged: (v) { if (v != null) { widget.onThemeChanged(v); Navigator.pop(context); } }),
        RadioListTile<ThemeMode>(value: ThemeMode.dark, groupValue: widget.themeMode, title: const Text('داكن'), onChanged: (v) { if (v != null) { widget.onThemeChanged(v); Navigator.pop(context); } }),
        const Divider(), const ListTile(leading: Icon(Icons.info_outline), title: Text('حول SamirNet Videos'), subtitle: Text('الإصدار 1.0.0 • Flutter')),
      ])),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 36, height: 36, decoration: BoxDecoration(color: AppTheme.red, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.download_rounded, color: Colors.white)),
    const SizedBox(width: 9), const Text('Samir', style: TextStyle(fontWeight: FontWeight.w800)),
    const Text('Net', style: TextStyle(color: AppTheme.red, fontWeight: FontWeight.w800)),
    const SizedBox(width: 5), const Text('Videos', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
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
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: AppTheme.red), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(body)]))])));
}
class _PlatformChip extends StatelessWidget {
  const _PlatformChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Chip(avatar: const Icon(Icons.public, size: 17), label: Text(label));
}

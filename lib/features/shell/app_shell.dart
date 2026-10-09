// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:docman/docman.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/download/yt_dlp_service.dart';
import '../../services/download/direct_media_downloader.dart';
import '../../services/download/media_source_inspector.dart';
import '../../services/download/download_notification_service.dart';
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
  DirectMediaDownloader? _activeDownloader;
  String? _activeYtDlpTaskId;
  bool _cancelRequested = false;
  int _downloadReceived = 0;
  int? _downloadTotal;
  String? _saveFolderUri;
  String _saveFolderName = 'مجلد التطبيق الخاص';
  bool _notificationsEnabled = false;
  @override
  void initState() {
    super.initState();
    _refresh();
    SettingsService.loadYouTubeApiKey().then((key) {
      if (mounted) setState(() => _apiKey = key);
    });
    SettingsService.loadSaveFolderUri().then((uri) {
      if (mounted) setState(() => _saveFolderUri = uri);
    });
    SettingsService.loadSaveFolderName().then((name) {
      if (mounted && name != null && name.isNotEmpty) {
        setState(() => _saveFolderName = name);
      }
    });
    SettingsService.loadNotificationsEnabled().then((enabled) {
      if (mounted) setState(() => _notificationsEnabled = enabled);
    });
  }
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
    if (_busy) return;
    final id = row['id'];
    if (id is! int) return;
    final uri = PlatformResolver.parseHttpUrl((row['url'] ?? '').toString());
    if (uri == null) {
      setState(() => _message = 'الرابط المحفوظ غير صالح.');
      return;
    }

    final downloader = DirectMediaDownloader();
    _activeDownloader = downloader;
    _cancelRequested = false;
    setState(() {
      _busy = true;
      _downloadProgress = null;
      _downloadReceived = 0;
      _downloadTotal = null;
      _message = 'جارٍ فحص الملف وبدء التنزيل...';
    });

    try {
      await DownloadDatabase.updateDownload(
        id,
        status: 'جارٍ التنزيل',
        filePath: '',
        fileSize: 0,
      );
      await _refresh();
      final file = await downloader.download(
        uri: uri,
        fileName: (row['title'] ?? 'media')
            .toString()
            .replaceAll(RegExp(r'[^a-zA-Z0-9 _.-]'), '_'),
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _downloadReceived = received;
            _downloadTotal = total;
            _downloadProgress =
                total == null || total <= 0 ? null : received / total;
          });
        },
      );
      final size = await file.length();
      String? destinationUri;
      String? folderCopyError;
      final selectedFolderUri = _saveFolderUri;
      if (selectedFolderUri != null && selectedFolderUri.isNotEmpty) {
        try {
          final sourceFile = await DocumentFile.fromUri(file.path);
          final copiedFile = await sourceFile?.copyTo(
            selectedFolderUri,
            name: p.basename(file.path),
          );
          if (copiedFile == null) {
            throw Exception('لم يتمكن Android من إنشاء نسخة في المجلد المحدد.');
          }
          destinationUri = copiedFile.uri;
        } catch (error) {
          folderCopyError = error.toString().replaceFirst('Exception: ', '');
        }
      }
      await DownloadDatabase.updateDownload(
        id,
        status: 'اكتمل التنزيل',
        filePath: file.path,
        fileSize: size,
        destinationUri: destinationUri ?? '',
      );
      await _refresh();
      if (_notificationsEnabled) {
        try {
          await DownloadNotificationService.show(
            id: id,
            title: 'اكتمل التنزيل',
            body: p.basename(file.path),
          );
        } catch (_) {
          // A notification failure must not change a successful download to failed.
        }
      }
      if (mounted) {
        setState(() {
          _message = folderCopyError == null
              ? 'اكتمل تنزيل ${p.basename(file.path)} (${_formatBytes(size)}).'
              : 'اكتمل التنزيل داخل التطبيق، لكن تعذر النسخ إلى المجلد المحدد: $folderCopyError';
        });
      }
    } catch (error) {
      final cancelled = _cancelRequested;
      try {
        await DownloadDatabase.updateDownload(
          id,
          status: cancelled ? 'أُلغي التنزيل' : 'فشل التنزيل',
          filePath: '',
          fileSize: 0,
        );
        await _refresh();
      } catch (_) {
        // Preserve the original download error if the database is unavailable.
      }
      if (_notificationsEnabled && !cancelled) {
        try {
          await DownloadNotificationService.show(
            id: id,
            title: 'تعذر إكمال التنزيل',
            body: error.toString().replaceFirst('HttpException: ', ''),
          );
        } catch (_) {
          // Ignore notification failures.
        }
      }
      if (mounted) {
        setState(() {
          _message = cancelled
              ? 'تم إلغاء التنزيل وحذف الملف الجزئي.'
              : error
                  .toString()
                  .replaceFirst('HttpException: ', '')
                  .replaceFirst('ClientException: ', '');
        });
      }
    } finally {
      downloader.close();
      if (identical(_activeDownloader, downloader)) {
        _activeDownloader = null;
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _downloadProgress = null;
          _downloadReceived = 0;
          _downloadTotal = null;
        });
      }
    }
  }

  void _cancelDownload() {
    if (!_busy) return;
    _cancelRequested = true;
    final downloader = _activeDownloader;
    final taskId = _activeYtDlpTaskId;
    if (downloader != null) {
      downloader.close();
    } else if (taskId != null) {
      YtDlpService.instance.cancel(taskId);
    }
    if (mounted) {
      setState(() => _message = 'جارٍ إلغاء التنزيل وتنظيف الملف الجزئي...');
    }
  }

  Future<void> _downloadWithEngine(
    Map<String, Object?> row, {
    required String format,
  }) async {
    if (_busy) return;
    final id = row['id'];
    if (id is! int) return;
    final uri = PlatformResolver.parseHttpUrl((row['url'] ?? '').toString());
    if (uri == null) {
      setState(() => _message = 'الرابط المحفوظ غير صالح.');
      return;
    }
    final taskId = 'samirnet-${DateTime.now().microsecondsSinceEpoch}';
    _activeYtDlpTaskId = taskId;
    _cancelRequested = false;
    setState(() {
      _busy = true;
      _downloadProgress = null;
      _downloadReceived = 0;
      _downloadTotal = null;
      _message = 'جارٍ تهيئة محرك التنزيل وتحليل الصيغة...';
    });
    try {
      await DownloadDatabase.updateDownload(
        id,
        status: 'جارٍ التنزيل',
        filePath: '',
        fileSize: 0,
      );
      await _refresh();
      final file = await YtDlpService.instance.download(
        url: uri.toString(),
        format: format,
        taskId: taskId,
        onProgress: (fraction, eta) {
          if (!mounted || _activeYtDlpTaskId != taskId) return;
          setState(() {
            _downloadProgress = fraction;
            _message = fraction == null
                ? 'جارٍ التنزيل...'
                : 'جارٍ التنزيل: ${(fraction * 100).toStringAsFixed(1)}%'
                    '${eta != null && eta > 0 ? ' • متبقٍ نحو $eta ثانية' : ''}';
          });
        },
      );
      final size = await file.length();
      String? destinationUri;
      String? folderCopyError;
      final selectedFolderUri = _saveFolderUri;
      if (selectedFolderUri != null && selectedFolderUri.isNotEmpty) {
        try {
          final sourceFile = await DocumentFile.fromUri(file.path);
          final copiedFile = await sourceFile?.copyTo(
            selectedFolderUri,
            name: p.basename(file.path),
          );
          if (copiedFile == null) {
            throw Exception('لم يتمكن Android من إنشاء نسخة في المجلد المحدد.');
          }
          destinationUri = copiedFile.uri;
        } catch (error) {
          folderCopyError = error.toString().replaceFirst('Exception: ', '');
        }
      }
      await DownloadDatabase.updateDownload(
        id,
        status: 'اكتمل التنزيل',
        filePath: file.path,
        fileSize: size,
        destinationUri: destinationUri ?? '',
      );
      await _refresh();
      if (_notificationsEnabled) {
        try {
          await DownloadNotificationService.show(
            id: id,
            title: 'اكتمل التنزيل',
            body: p.basename(file.path),
          );
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _message = folderCopyError == null
              ? 'اكتمل تنزيل ${p.basename(file.path)} (${_formatBytes(size)}).'
              : 'اكتمل التنزيل داخل التطبيق، لكن تعذر النسخ إلى المجلد المحدد: $folderCopyError';
        });
      }
    } catch (error) {
      final cancelled = _cancelRequested ||
          error.toString().contains('إلغاء التنزيل') ||
          error.toString().contains('cancel');
      try {
        await DownloadDatabase.updateDownload(
          id,
          status: cancelled ? 'أُلغي التنزيل' : 'فشل التنزيل',
          filePath: '',
          fileSize: 0,
        );
        await _refresh();
      } catch (_) {}
      if (_notificationsEnabled && !cancelled) {
        try {
          await DownloadNotificationService.show(
            id: id,
            title: 'تعذر إكمال التنزيل',
            body: error.toString().replaceFirst('Exception: ', ''),
          );
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _message = cancelled
            ? 'تم إلغاء التنزيل.'
            : error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (_activeYtDlpTaskId == taskId) _activeYtDlpTaskId = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _downloadProgress = null;
          _downloadReceived = 0;
          _downloadTotal = null;
        });
      }
    }
  }

  Future<void> _showDownloadChoices(Map<String, Object?> row) async {
    if (_busy) return;
    final uri = PlatformResolver.parseHttpUrl((row['url'] ?? '').toString());
    if (uri == null) {
      setState(() => _message = 'الرابط المحفوظ غير صالح.');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'جارٍ جلب معلومات الفيديو والصيغ المتاحة...';
    });
    Map<String, dynamic> info;
    List<YtDlpFormat> formats;
    try {
      info = await YtDlpService.instance.inspect(uri.toString());
      formats = YtDlpService.instance.videoFormats(info);
    } catch (error) {
      if (mounted) {
        setState(() => _message =
            'تعذر الوصول إلى الفيديو أو استخراج صِيَغه: ${error.toString().replaceFirst('Exception: ', '')}');
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    String type = 'video';
    String selector = formats.isNotEmpty
        ? formats.first.selector()
        : 'bestvideo+bestaudio/best';
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('خيارات التنزيل'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((info['title'] ?? row['title'] ?? 'فيديو').toString(),
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 12),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'video',
                    groupValue: type,
                    title: const Text('تنزيل فيديو مع الصوت'),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => type = value);
                    },
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'audio',
                    groupValue: type,
                    title: const Text('تنزيل الصوت فقط'),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => type = value);
                    },
                  ),
                  if (type == 'video') ...[
                    const SizedBox(height: 6),
                    const Text('الجودة المتاحة من المصدر',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    if (formats.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('لم يعرض المصدر قائمة صيغ مفصلة؛ سيُستخدم أفضل تنسيق متاح.'),
                      )
                    else
                      ...formats.map((format) => RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            value: format.selector(),
                            groupValue: selector,
                            title: Text(format.label),
                            subtitle: format.fileSize == null
                                ? null
                                : Text(_formatBytes(format.fileSize!)),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => selector = value);
                              }
                            },
                          )),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                dialogContext,
                type == 'audio' ? 'bestaudio/best' : selector,
              ),
              icon: const Icon(Icons.download),
              label: const Text('بدء التنزيل'),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      await _downloadWithEngine(row, format: chosen);
    }
  }

  Future<void> _saveAndChooseVideo(YouTubeVideo video) async {
    final id = await DownloadDatabase.add(
      url: video.watchUrl,
      platform: 'YouTube',
      title: video.title,
      status: 'جاهز لاختيار الجودة',
    );
    await _refresh();
    final row = _downloads.firstWhere(
      (item) => item['id'] == id,
      orElse: () => <String, Object?>{
        'id': id,
        'url': video.watchUrl,
        'platform': 'YouTube',
        'title': video.title,
      },
    );
    if (mounted) await _showDownloadChoices(row);
  }


  Future<void> _inspectSource(Map<String, Object?> row) async {
    if (_busy) return;
    final uri = PlatformResolver.parseHttpUrl((row['url'] ?? '').toString());
    if (uri == null) {
      setState(() => _message = 'الرابط المحفوظ غير صالح.');
      return;
    }

    setState(() {
      _busy = true;
      _message = 'جارٍ فحص الصيغ المتاحة من المصدر...';
    });
    late final MediaSourceInspection inspection;
    try {
      inspection = await MediaSourceInspector().inspect(uri);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = '';
        });
      }
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('مصدر التنزيل: ${inspection.sourceName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(inspection.message),
              if (inspection.formats.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'الصيغ التي أكدها الخادم',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                ...inspection.formats.map(
                  (format) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.video_file_outlined),
                    title: Text(format.label),
                    subtitle: Text(
                      '${format.mimeType}\n'
                      '${format.fileSize == null ? 'الحجم غير معلن' : _formatBytes(format.fileSize!)}',
                    ),
                    trailing: const Text('الدقة غير معلنة'),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
          if (inspection.hasFormats)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _downloadDirect(row);
              },
              icon: const Icon(Icons.download),
              label: const Text('تنزيل الملف الأصلي'),
            ),
        ],
      ),
    );
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
    final label = PlatformResolver.label(platform);
    setState(() { _busy = true; _message = 'جارٍ تحليل الرابط العام...'; });
    int? rowId;
    Map<String, dynamic>? info;
    try {
      rowId = await DownloadDatabase.add(
        url: uri.toString(),
        platform: label,
        title: 'جارٍ تحليل رابط $label',
        status: 'جارٍ تحليل المصدر',
      );
      await _refresh();
      info = await YtDlpService.instance.inspect(uri.toString());
      final title = (info['title'] ?? info['fulltitle'] ?? 'فيديو من $label').toString();
      await DownloadDatabase.updateDownload(
        rowId,
        title: title,
        status: platform == MediaPlatform.youtube
            ? 'جاهز لاختيار الجودة'
            : 'جاهز للتنزيل التلقائي',
      );
      await _refresh();
    } catch (error) {
      if (rowId != null) {
        try {
          await DownloadDatabase.updateDownload(
            rowId,
            status: 'تعذر الوصول إلى المصدر',
          );
          await _refresh();
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _message =
            'تعذر الوصول إلى الفيديو العام أو استخراج معلوماته. قد يكون الرابط خاصًا أو غير مدعوم. التفاصيل: ${error.toString().replaceFirst('Exception: ', '')}');
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    _url.clear();
    final row = _downloads.firstWhere(
      (item) => item['id'] == rowId,
      orElse: () => <String, Object?>{
        'id': rowId,
        'url': uri.toString(),
        'platform': label,
        'title': info?['title'] ?? 'فيديو',
      },
    );
    if (platform == MediaPlatform.youtube) {
      await _showDownloadChoices(row);
    } else {
      await _downloadWithEngine(
        row,
        format: 'bestvideo+bestaudio/best',
      );
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
    if (_searchResults.isNotEmpty) ..._searchResults.map((video) => Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: video.thumbnail.isEmpty
            ? const Icon(Icons.play_circle_outline)
            : Image.network(video.thumbnail, width: 84, height: 60, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_outline)),
        title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(video.channel),
        trailing: IconButton(
          tooltip: 'تنزيل',
          icon: const Icon(Icons.download_outlined),
          onPressed: () => _saveAndChooseVideo(video),
        ),
        onTap: () => _showVideoDetails(video),
      ),
    )),
    if (_searchResults.isEmpty && _message.isEmpty) const _InfoCard(icon: Icons.public, title: 'البحث المباشر', body: 'يعرض نتائج YouTube الحقيقية باستخدام YouTube Data API بعد إضافة مفتاح API من الإعدادات.'),
  ]);

  void _showSearchNotice() {
    if (_search.text.trim().isEmpty) {
      setState(() => _message = 'اكتب كلمات البحث أولًا.');
    } else {
      _runYouTubeSearch();
    }
  }

  Future<void> _showVideoDetails(YouTubeVideo video) async {
    YouTubeVideo details = video;
    if (_apiKey.isNotEmpty) {
      try {
        final fresh = await YouTubeSearchService().getVideoDetails(
          videoId: video.id,
          apiKey: _apiKey,
        );
        if (fresh != null) details = fresh;
      } catch (error) {
        if (mounted) {
          setState(() => _message =
              error.toString().replaceFirst('Exception: ', ''));
        }
      }
    }
    if (!mounted) return;
    List<YouTubeVideo> related = [];
    if (_apiKey.isNotEmpty) {
      try {
        related = await YouTubeSearchService().search(
          query: '${details.title} ${details.channel}',
          apiKey: _apiKey,
          maxResults: 8,
        );
        related = related.where((item) => item.id != details.id).take(5).toList();
      } catch (_) {}
    }
    if (!mounted) return;
    final player = WebViewController();
    await player.setJavaScriptMode(JavaScriptMode.unrestricted);
    await player.setBackgroundColor(const Color(0xFF000000));
    await player.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (request) => request.url.contains('youtube.com/embed/')
          || request.url.contains('youtube.com')
          || request.url.contains('youtube-nocookie.com')
          || request.url.contains('google.com')
          ? NavigationDecision.navigate
          : NavigationDecision.prevent,
    ));
    await player.loadHtmlString('''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"></head>
<body style="margin:0;background:#000"><iframe width="100%" height="100%" src="https://www.youtube.com/embed/${details.id}?autoplay=1&rel=1&playsinline=1" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe></body></html>
''');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        title: Text(details.title, maxLines: 3, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * .72,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 210,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: WebViewWidget(controller: player),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('القناة: ${details.channel.isEmpty ? 'غير متاح' : details.channel}'),
                  if (details.publishedAt != null)
                    Text('تاريخ النشر: ${details.publishedAt!.toLocal().toString().split(' ').first}'),
                  if (details.duration.isNotEmpty)
                    Text('المدة: ${_formatDuration(details.duration)}'),
                  if (details.definition.isNotEmpty)
                    Text('الدقة الأصلية: ${details.definition.toUpperCase()}'),
                  if (details.viewCount != null)
                    Text('المشاهدات: ${_formatCount(details.viewCount!)}'),
                  if (details.likeCount != null)
                    Text('الإعجابات: ${_formatCount(details.likeCount!)}'),
                  if (details.commentCount != null)
                    Text('التعليقات: ${_formatCount(details.commentCount!)}'),
                  const SizedBox(height: 10),
                  Text(details.description.isEmpty ? 'لا يوجد وصف متاح.' : details.description),
                  const SizedBox(height: 14),
                  const Text('فيديوهات مشابهة', style: TextStyle(fontWeight: FontWeight.w800)),
                  if (related.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('لا تتوفر نتائج مشابهة الآن.'),
                    ),
                  ...related.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: item.thumbnail.isEmpty
                        ? const Icon(Icons.play_circle_outline)
                        : Image.network(item.thumbnail, width: 82, height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_outline)),
                    title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.channel, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _showVideoDetails(item);
                    },
                  )),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _saveAndChooseVideo(details);
            },
            icon: const Icon(Icons.download),
            label: const Text('تنزيل'),
          ),
        ],
      ),
    );
  }

  String _formatCount(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} مليون';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} ألف';
    return value.toString();
  }

  String _formatDuration(String iso) {
    final match = RegExp(r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$').firstMatch(iso);
    if (match == null) return iso;
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$minutes:$ss';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _downloadTile(Map<String, Object?> row) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      leading: Container(width: 46, height: 46, decoration: BoxDecoration(color: AppTheme.red.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.play_arrow_rounded, color: AppTheme.red, size: 30)),
      title: Text((row['title'] ?? 'رابط فيديو').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${row['platform']} • ${row['status']}'
        '${row['file_size'] is int && (row['file_size'] as int) > 0 ? '\\nالحجم: ${_formatBytes(row['file_size'] as int)}' : ''}'
        '${(row['file_path'] ?? '').toString().isNotEmpty ? '\\nالملف: ${(row['file_path'] ?? '').toString()}' : ''}'
        '${(row['destination_uri'] ?? '').toString().isNotEmpty ? '\\nنسخة محفوظة في المجلد المحدد' : ''}'
        '\\n${row['url']}',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'share') await Share.share((row['url'] ?? '').toString());
          if (value == 'copy') { await Clipboard.setData(ClipboardData(text: (row['url'] ?? '').toString())); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الرابط'))); }
          if (value == 'inspect') await _inspectSource(row);
          if (value == 'download') await _showDownloadChoices(row);
          if (value == 'delete') { final id = row['id']; if (id is int) await DownloadDatabase.delete(id); await _refresh(); }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'share', child: Text('مشاركة الرابط')),
          PopupMenuItem(value: 'copy', child: Text('نسخ الرابط')),
          PopupMenuItem(value: 'inspect', child: Text('فحص المصدر والصيغ')),
          PopupMenuItem(value: 'download', child: Text('تنزيل صوت أو فيديو')),
          PopupMenuItem(value: 'delete', child: Text('حذف من السجل')),
        ],
      ),
    ),
  );

  Widget _downloadsPage() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('التنزيلات', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
    const SizedBox(height: 12),
    const _InfoCard(icon: Icons.downloading, title: 'إدارة التنزيلات', body: 'تنزيل الروابط العامة المدعومة عبر محرك yt-dlp، مع اختيار جودة YouTube أو تنزيل الروابط الخارجية تلقائيًا بأفضل صيغة متاحة.'),
    if (_busy) ...[
      LinearProgressIndicator(value: _downloadProgress),
      const SizedBox(height: 6),
      Text(
        _activeYtDlpTaskId != null
            ? (_downloadProgress == null
                ? 'محرك yt-dlp يعمل...'
                : 'التقدم: ${(_downloadProgress! * 100).toStringAsFixed(1)}%')
            : 'تم استلام ${_formatBytes(_downloadReceived)}'
                '${_downloadTotal != null && _downloadTotal! > 0 ? ' من ${_formatBytes(_downloadTotal!)}' : ''}',
        textAlign: TextAlign.center,
      ),
      Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          onPressed: _cancelDownload,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('إلغاء التنزيل'),
        ),
      ),
    ],
    if (_message.isNotEmpty) _MessageCard(message: _message),
    if (_downloads.isEmpty) const _EmptyState(text: 'لا توجد روابط في القائمة.'),
    ..._downloads.map(_downloadTile),
  ]);

  Future<void> _chooseSaveFolder(BuildContext sheetContext) async {
    try {
      final selected = await DocMan.pick.directory();
      if (selected == null) {
        return;
      }
      final uri = selected.uri;
      if (uri.isEmpty) {
        throw Exception('لم يُرجع منتقي المجلد عنوانًا صالحًا.');
      }
      await SettingsService.saveSaveFolder(uri: uri, name: selected.name);
      if (!mounted || !sheetContext.mounted) return;
      setState(() {
        _saveFolderUri = uri;
        _saveFolderName = selected.name;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ مجلد التنزيلات.')),
      );
    } catch (error) {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(content: Text('تعذر اختيار المجلد: $error')),
        );
      }
    }
  }

  Future<void> _toggleNotifications(
    bool enabled,
    BuildContext sheetContext,
  ) async {
    if (enabled) {
      final granted = await DownloadNotificationService.requestPermission();
      if (!granted) {
        if (mounted) setState(() => _notificationsEnabled = false);
        if (sheetContext.mounted) {
          ScaffoldMessenger.of(sheetContext).showSnackBar(
            const SnackBar(content: Text('لم يتم منح إذن الإشعارات.')),
          );
        }
        return;
      }
    }
    await SettingsService.saveNotificationsEnabled(enabled);
    if (mounted) setState(() => _notificationsEnabled = enabled);
  }

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
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('مجلد الحفظ'),
            subtitle: Text(_saveFolderName),
            trailing: const Icon(Icons.folder_open),
            onTap: () => _chooseSaveFolder(context),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('إشعارات التنزيل'),
            subtitle: const Text('إشعار عند اكتمال التنزيل أو فشله'),
            value: _notificationsEnabled,
            onChanged: (enabled) => _toggleNotifications(enabled, context),
          ),
          const ListTile(leading: Icon(Icons.key_outlined), title: Text('مفتاح YouTube Data API'), subtitle: Text('للبحث الحقيقي، أنشئ مفتاحًا في Google Cloud وفعّل YouTube Data API v3.')),
          TextFormField(initialValue: _apiKey, obscureText: true, decoration: const InputDecoration(labelText: 'API Key', hintText: 'أدخل مفتاح YouTube Data API'), onChanged: (v) => _apiKey = v.trim()),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await SettingsService.saveYouTubeApiKey(_apiKey);
              if (!mounted || !context.mounted) return;
              Navigator.pop(context);
              messenger.showSnackBar(
                const SnackBar(content: Text('تم حفظ مفتاح البحث على الجهاز')),
              );
            },
            child: const Text('حفظ إعدادات البحث'),
          ),
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
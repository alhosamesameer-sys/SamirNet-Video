import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DownloadDatabase {
  static Database? _db;
  static Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, 'samirnet_videos.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE downloads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            platform TEXT NOT NULL,
            title TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            file_path TEXT,
            file_size INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE downloads ADD COLUMN file_path TEXT');
          await db.execute('ALTER TABLE downloads ADD COLUMN file_size INTEGER');
        }
      },
    );
    return _db!;
  }

  static Future<int> add({required String url, required String platform, String title = 'رابط وسائط', String status = 'queued'}) async {
    final db = await database;
    return db.insert('downloads', {
      'url': url, 'platform': platform, 'title': title,
      'status': status, 'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, Object?>>> all() async {
    final db = await database;
    return db.query('downloads', orderBy: 'id DESC');
  }

  static Future<void> updateDownload(int id, {String? status, String? filePath, int? fileSize}) async {
    final db = await database;
    final values = <String, Object?>{};
    if (status != null) values['status'] = status;
    if (filePath != null) values['file_path'] = filePath;
    if (fileSize != null) values['file_size'] = fileSize;
    if (values.isNotEmpty) await db.update('downloads', values, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> delete(int id) async {
    final db = await database;
    await db.delete('downloads', where: 'id = ?', whereArgs: [id]);
  }
}

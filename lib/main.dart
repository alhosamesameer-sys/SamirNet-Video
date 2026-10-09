import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/download/download_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await DownloadNotificationService.initialize();
  } catch (_) {
    // Notifications remain optional if the platform does not support them.
  }
  runApp(const ProviderScope(child: SamirNetApp()));
}

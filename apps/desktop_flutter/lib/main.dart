import 'package:flutter/material.dart';
import 'package:keeppass_nexus/src/app.dart';
import 'package:keeppass_nexus/src/rust/frb_generated.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  await RustLib.init();
  runApp(const KeePassNexusApp());
}

import 'package:flutter/material.dart';
import 'package:keeppass_nexus/src/app.dart';
import 'package:keeppass_nexus/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const KeePassNexusApp());
}

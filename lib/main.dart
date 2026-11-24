import 'package:flutter/material.dart';

import 'app_state.dart';
import 'home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(ClearRepostApp(state: state));
}

class ClearRepostApp extends StatelessWidget {
  final AppState state;
  const ClearRepostApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClearRepost',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(primary: Color(0xFF8B7CF6)),
      ),
      home: HomePage(s: state),
    );
  }
}

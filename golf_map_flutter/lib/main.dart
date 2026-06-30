import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  runApp(const GolfMapApp());
}

class GolfMapApp extends StatelessWidget {
  const GolfMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'South Texas Golf Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

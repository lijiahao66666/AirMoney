import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'presentation/pages/home/home_page.dart';
import 'presentation/providers/bill_provider.dart';
import 'presentation/providers/points_provider.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[main] FlutterError: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[main] Unhandled zone error: $error');
    debugPrint('$stack');
    return true;
  };

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await _safeInit('ApiService.initDeviceId', ApiService.initDeviceId);
  await _safeInit('AuthService.init', AuthService.init);

  runApp(
    MultiProvider(
      providers: <ChangeNotifierProvider<dynamic>>[
        ChangeNotifierProvider<BillProvider>(
          create: (_) => BillProvider(),
        ),
        ChangeNotifierProvider<PointsProvider>(
          create: (_) => PointsProvider(),
        ),
      ],
      child: const AirMoneyApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_safeInit('NotificationService.init', NotificationService.init));
  });
}

Future<void> _safeInit(String name, Future<void> Function() task) async {
  try {
    await task();
  } catch (error, stack) {
    debugPrint('[main] $name failed: $error');
    debugPrint('$stack');
  }
}

class AirMoneyApp extends StatelessWidget {
  const AirMoneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '哎呀，钱！',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
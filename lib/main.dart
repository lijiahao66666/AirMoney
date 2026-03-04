import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'presentation/pages/home/home_page.dart';
import 'presentation/providers/bill_provider.dart';
import 'presentation/providers/points_provider.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await ApiService.initDeviceId();
  await AuthService.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BillProvider()),
        ChangeNotifierProvider(create: (_) => PointsProvider()),
      ],
      child: const AirMoneyApp(),
    ),
  );
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

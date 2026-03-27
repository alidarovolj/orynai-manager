import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:chucker_flutter/chucker_flutter.dart';
import 'constants.dart';
import 'widgets/restart_widget.dart';
import 'services/auth_state_manager.dart';
import 'services/api_service.dart';
import 'pages/manager_login_page.dart';
import 'pages/manager_home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Полноэкранный режим — edge-to-edge, статусбар и навбар прозрачные
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await EasyLocalization.ensureInitialized();
  } catch (e) {
    debugPrint('EasyLocalization init error: $e');
  }

  try {
    await dotenv.load();
  } catch (e) {
    debugPrint('.env not found, using defaults');
    dotenv.env['API_URL'] = 'https://stage.ripservice.kz';
  }

  EasyLocalization.logger.enableLevels = [];

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('ru'), Locale('kk')],
      path: 'assets/translations',
      fallbackLocale: const Locale('ru'),
      startLocale: const Locale('ru'),
      useOnlyLangCode: true,
      assetLoader: const RootBundleAssetLoader(),
      child: const ManagerApp(),
    ),
  );

  _initServicesInBackground();
}

Future<void> _initServicesInBackground() async {
  try {
    await ApiService().initialize();
  } catch (e) {
    debugPrint('API service init error: $e');
  }

  try {
    await AuthStateManager().initialize();
  } catch (e) {
    debugPrint('AuthStateManager init error: $e');
  }
}

class ManagerApp extends StatefulWidget {
  const ManagerApp({super.key});

  @override
  State<ManagerApp> createState() => _ManagerAppState();
}

class _ManagerAppState extends State<ManagerApp> {
  @override
  Widget build(BuildContext context) {
    final env = dotenv.env['ENV'];
    final isDevMode = env == 'dev';

    final navigatorObservers = <NavigatorObserver>[];
    if (isDevMode) {
      navigatorObservers.add(ChuckerFlutter.navigatorObserver);
    }

    return RestartWidget(
      child: MaterialApp(
        title: 'Orynai Manager',
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        navigatorObservers: navigatorObservers,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.buttonBackground,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: AppColors.background,
          useMaterial3: true,
          fontFamily: 'Manrope',
          textTheme: const TextTheme(
            displayLarge: TextStyle(fontFamily: 'Manrope'),
            displayMedium: TextStyle(fontFamily: 'Manrope'),
            displaySmall: TextStyle(fontFamily: 'Manrope'),
            headlineLarge: TextStyle(fontFamily: 'Manrope'),
            headlineMedium: TextStyle(fontFamily: 'Manrope'),
            headlineSmall: TextStyle(fontFamily: 'Manrope'),
            titleLarge: TextStyle(fontFamily: 'Manrope'),
            titleMedium: TextStyle(fontFamily: 'Manrope'),
            titleSmall: TextStyle(fontFamily: 'Manrope'),
            bodyLarge: TextStyle(fontFamily: 'Manrope'),
            bodyMedium: TextStyle(fontFamily: 'Manrope'),
            bodySmall: TextStyle(fontFamily: 'Manrope'),
            labelLarge: TextStyle(fontFamily: 'Manrope'),
            labelMedium: TextStyle(fontFamily: 'Manrope'),
            labelSmall: TextStyle(fontFamily: 'Manrope'),
          ),
        ),
        home: const _AppEntryPoint(),
      ),
    );
  }
}

/// Определяет стартовый экран: если пользователь уже авторизован → домой,
/// иначе → экран входа.
class _AppEntryPoint extends StatefulWidget {
  const _AppEntryPoint();

  @override
  State<_AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<_AppEntryPoint> {
  bool _checking = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final isAuth = await AuthStateManager().initialize();
      setState(() {
        _isAuthenticated = isAuth;
        _checking = false;
      });
    } catch (e) {
      setState(() {
        _isAuthenticated = false;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.buttonBackground),
        ),
      );
    }

    if (_isAuthenticated) {
      return const ManagerHomePage();
    }

    return const ManagerLoginPage();
  }
}

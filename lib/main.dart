import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:yandex_maps_mapkit_lite/init.dart' as mapkit_init;
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

/// Глобальный ключ навигатора — используется для редиректа на логин при 401.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Готовность Yandex MapKit — карта рендерится только когда true.
final ValueNotifier<bool> mapkitReady = ValueNotifier(false);

/// Результат проверки сессии до runApp() — чтобы первый кадр
/// сразу показал нужный экран, не ожидая завершения async _checkAuth().
bool _preAuthResult = false;

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

  // Проверяем сессию до runApp() — SharedPreferences только читает кэш,
  // занимает < 5ms. Первый кадр сразу рендерит нужный экран без спиннера.
  try {
    _preAuthResult = await AuthStateManager().initialize();
  } catch (_) {}

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

  // Инициализация Yandex MapKit — только Android, запускаем после runApp()
  // чтобы не блокировать старт Flutter и VM service.
  _initServicesInBackground();
}

Future<void> _initServicesInBackground() async {
  if (Platform.isAndroid) {
    // initMapkit содержит синхронный leaf-FFI вызов (_init), который блокирует
    // Dart изолят. Ждём postFrameCallback — гарантирует что первый кадр
    // (экран входа / главный экран) уже отрисован до блокирующего вызова.
    final firstFrame = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!firstFrame.isCompleted) firstFrame.complete();
    });
    await firstFrame.future;

    try {
      await mapkit_init.initMapkit(
        apiKey: dotenv.env['YANDEX_MAPKIT_KEY'] ?? '',
        locale: 'ru_RU',
      );
      debugPrint('[MapKit] initialized');
    } catch (e) {
      debugPrint('[MapKit] init error: $e');
    } finally {
      mapkitReady.value = true;
    }
  }

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

  // Регистрируем обработчик 401: очищает сессию и редиректит на логин
  ApiService.setUnauthorizedCallback(() {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ManagerLoginPage()),
      (_) => false,
    );
  });
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
        navigatorKey: appNavigatorKey,
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
          appBarTheme: const AppBarTheme(
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
          ),
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
  // Auth уже проверен в main() через _preAuthResult — первый кадр
  // рендерится без спиннера, не блокируется leaf-FFI от initMapkit.
  late bool _isAuthenticated = _preAuthResult;

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated) {
      return const ManagerHomePage();
    }
    return const ManagerLoginPage();
  }
}

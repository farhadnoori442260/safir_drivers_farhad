import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:safir_drivers/utils/app_colors.dart';
import 'package:safir_drivers/pages/splash_screen.dart';
import 'package:safir_drivers/providers/authentication_provider.dart';
import 'package:safir_drivers/providers/dashboard_provider.dart';
import 'package:safir_drivers/providers/registration_provider.dart';
import 'package:safir_drivers/providers/trip_provider.dart';
import 'package:safir_drivers/controllers/navigation_controller.dart';
import 'package:safir_drivers/utils/lang_helper.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 📌 ثبت خطاهای فریم‌ورک برای جلوگیری از صفحه خاکستری
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  // 📌 لود ایمن سیستم چندزبانه
  try {
    await EasyLocalization.ensureInitialized();
  } catch (e) {
    debugPrint("EasyLocalization Error: $e");
  }

  // 📌 لود ایمن فایربیس
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }

  // 📌 درخواست مجوزها به صورت پس‌زمینه (بدون متوقف کردن اجرای UI)
  _requestPermissionsSafely();

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('fa'),
        Locale('ps'),
        Locale('en'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('fa'),
      startLocale: const Locale('fa'),
      child: const MyApp(),
    ),
  );
}

/// متد مجزا برای درخواست دسترسی‌ها بدون قفل کردن صفحه
Future<void> _requestPermissionsSafely() async {
  try {
    await Permission.locationWhenInUse.request();
    await Permission.notification.request();
  } catch (e) {
    debugPrint("Permission Request Error: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 📌 نمایش متن خطا روی صفحه گوشی در صورت بروز کرش در UI
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              "خطا در بارگذاری برنامه:\n${details.exception}",
              style: const TextStyle(color: Colors.red, fontSize: 13),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
          ),
        ),
      );
    };

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppLanguageProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => AuthenticationProvider()),
        ChangeNotifierProvider(create: (_) => RegistrationProvider()),
        ChangeNotifierProvider(create: (_) => TripProvider()),
        ChangeNotifierProvider(create: (_) => NavigationController()),
      ],
      child: Consumer<AppLanguageProvider>(
        builder: (context, appLanguage, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Safir Drivers',
            debugShowCheckedModeBanner: false,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: SafirColors.primary),
              primaryColor: SafirColors.primary,
              scaffoldBackgroundColor: const Color(0xFFFAFAFA),
              fontFamily: 'IranYekan',
              useMaterial3: true,
            ),
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

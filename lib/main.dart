import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:safir_drivers/utils/app_colors.dart'; // 📌 اتصال به پالت رنگی اصلی سفیر
import 'package:safir_drivers/pages/splash_screen.dart';
import 'package:safir_drivers/providers/authentication_provider.dart';
import 'package:safir_drivers/providers/dashboard_provider.dart';
import 'package:safir_drivers/providers/registration_provider.dart';
import 'package:safir_drivers/providers/trip_provider.dart';
import 'package:safir_drivers/controllers/navigation_controller.dart';
import 'package:safir_drivers/utils/lang_helper.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsBinding.instance;
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Firebase.initializeApp();
  
  try {
    await Permission.locationWhenInUse.request();
    await Permission.notification.request();
  } catch (_) {}

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('fa'), // دری
        Locale('ps'), // پشتو
        Locale('en'), // انگلیسی
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('fa'),
      startLocale: const Locale('fa'),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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
              // 📌 فراخوانی رنگ اصلی (سبز سفیر) از SafirColors
              colorScheme: ColorScheme.fromSeed(seedColor: SafirColors.primary),
              primaryColor: SafirColors.primary,
              scaffoldBackgroundColor: SafirColors.background,
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

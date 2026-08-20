import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:safir_drivers/pages/auth/register_screen.dart';
import 'package:safir_drivers/pages/dashboard.dart';

import 'package:safir_drivers/providers/authentication_provider.dart';
import 'package:safir_drivers/providers/dashboard_provider.dart';
import 'package:safir_drivers/providers/registration_provider.dart';
import 'package:safir_drivers/providers/trip_provider.dart';

import 'package:safir_drivers/widgets/blocked_screen.dart';
import 'package:safir_drivers/utils/lang_helper.dart'; // هیلپر زبان سفیر

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const Color safirColor = Color(0xFF145A41); // رنگ سازمانی سبز سفیر

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // درخواست مجوزهای موقعیت مکانی و اعلان‌ها
  await Permission.locationWhenInUse.isDenied.then((valueOfPermission) {
    if (valueOfPermission) {
      Permission.locationWhenInUse.request();
    }
  });
  await Permission.notification.isDenied.then((valueOfPermission) {
    if (valueOfPermission) {
      Permission.notification.request();
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppLanguageProvider(), // پرووایدر زبان پروژه سفیر
        ),
        ChangeNotifierProvider(
          create: (_) => DashboardProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthenticationProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => RegistrationProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => TripProvider(),
        ),
      ],
      child: Consumer<AppLanguageProvider>(
        builder: (context, appLanguage, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Safir Drivers',
            debugShowCheckedModeBanner: false,
            locale: appLanguage.appLocal, // زبان فعال برنامه
            supportedLocales: const [
              Locale('fa', 'AF'), // دری / فارسی
              Locale('ps', 'AF'), // پشتو
              Locale('en', 'US'), // انگلیسی
            ],
            localizationsDelegates: const [
              AppLocalizations.delegate, // لود فایل‌های JSON
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: safirColor),
              fontFamily: 'IranYekan',
              useMaterial3: true,
            ),
            home: const AuthCheck(),
          );
        },
      ),
    );
  }
}

/// 🛡️ چک‌کننده هوشمند و بدون لودینگ ابدی (الگوبرداری شده از منطق مسافر)
class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});

  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  bool _isLoading = true;
  bool _hasError = false;
  Widget? _targetScreen;

  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigation();
  }

  Future<void> _checkAuthAndNavigation() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // تاخیر کوتاه ۱ ثانیه‌ای برای روان‌تر شدن انیمیشن استارت‌آپ
      await Future.delayed(const Duration(seconds: 1));

      User? user = FirebaseAuth.instance.currentUser;

      if (!mounted) return;

      if (user == null) {
        // ۱. کاربر لاگین نیست -> هدایت به ثبت نام
        setState(() {
          _isLoading = false;
          _targetScreen = const RegisterScreen();
        });
        return;
      }

      // ۲. بررسی وجود کاربر و وضعیت او با تایم‌اوت مشخص جهت جلوگیری از لودینگ ابدی
      final authProvider = Provider.of<AuthenticationProvider>(context, listen: false);

      bool userExists = await authProvider.checkUserExistById().timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );

      if (!userExists) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _targetScreen = const RegisterScreen();
        });
        return;
      }

      // بررسی بلاک بودن
      bool isBlocked = false;
      try {
        isBlocked = await authProvider.checkIfDriverIsBlocked().timeout(
          const Duration(seconds: 3),
          onTimeout: () => false,
        );
      } catch (_) {
        isBlocked = false;
      }

      if (isBlocked) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _targetScreen = const BlockedScreen();
        });
        return;
      }

      // بررسی تکمیل اطلاعات راننده
      bool isDriverComplete = false;
      try {
        isDriverComplete = await authProvider.checkDriverFieldsFilled().timeout(
          const Duration(seconds: 3),
          onTimeout: () => true, // در صورت تایم‌اوت فرض بر ورود به داشبورد قرار می‌گیرد
        );
      } catch (_) {
        isDriverComplete = true;
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _targetScreen = isDriverComplete ? const Dashboard() : const RegisterScreen();
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ❌ صفحه خطا و تلاش مجدد (در صورت قطع شبکه یا بروز استثنا)
    if (_hasError) {
      return Scaffold(
        backgroundColor: safirColor,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'S',
                      style: TextStyle(
                        fontSize: 90,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 0.9,
                      ),
                    ),
                    Container(
                      width: 45,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40.0),
                      child: Text(
                        'مشکلی پیش آمده است. دوباره تلاش کنید.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _checkAuthAndNavigation, // تلاش مجدد
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'تلاش دوباره',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: safirColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ⏳ صفحه بارگذاری لوگوی سفیر (در طول بررسی وضعیت)
    if (_isLoading || _targetScreen == null) {
      return Scaffold(
        backgroundColor: safirColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'S',
                style: TextStyle(
                  fontSize: 90,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 0.9,
                ),
              ),
              Container(
                width: 45,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
            ],
          ),
        ),
      );
    }

    // ✅ نمایش صفحه نهایی (Dashboard / RegisterScreen / BlockedScreen)
    return _targetScreen!;
  }
}

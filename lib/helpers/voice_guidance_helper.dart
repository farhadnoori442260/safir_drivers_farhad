import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:easy_localization/easy_localization.dart';

class VoiceGuidanceHelper {
  static final FlutterTts _flutterTts = FlutterTts();
  static bool isMuted = false;
  static bool _isInitialized = false;

  /// مقداردهی اولیه و تنظیمات اسپیکر
  static Future<void> initTts(String languageCode) async {
    try {
      // 📌 تنظیم صدا روی اسپیکر اصلی دستگاه
      if (Platform.isIOS) {
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          ],
        );
      } else if (Platform.isAndroid) {
        await _flutterTts.setQueueMode(1); // لغو صدای قبلی و پخش صدای جدید
      }

      String primaryLang = 'fa-IR';
      if (languageCode == 'ps') {
        primaryLang = 'ps-AF';
      } else if (languageCode == 'en') {
        primaryLang = 'en-US';
      }

      // 📌 بررسی اینکه آیا زبان مورد نظر در موتور گوینده گوشی موجود است یا خیر
      bool isAvailable = await _flutterTts.isLanguageAvailable(primaryLang);

      if (isAvailable) {
        await _flutterTts.setLanguage(primaryLang);
      } else {
        // اگر فارسی/پشتو روی موتور TTS گوشی نصب نبود، به انگلیسی سوییچ می‌کند تا کلاً بی‌صدا نماند
        debugPrint("TTS Language $primaryLang not available. Falling back to en-US.");
        await _flutterTts.setLanguage('en-US');
      }

      await _flutterTts.setSpeechRate(0.45); // سرعت گفتار مناسب مسیریابی
      await _flutterTts.setVolume(1.0);      // حداکثر میزان صدا
      await _flutterTts.setPitch(1.0);       // لحن طبیعی
      _isInitialized = true;
    } catch (e) {
      debugPrint("Error initializing TTS: $e");
    }
  }

  /// پخش مستقیم متن صوتی
  static Future<void> speak(String text) async {
    if (isMuted || text.isEmpty) return;
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint("Error in speak: $e");
    }
  }

  /// تبدیل داده‌های مسیریابی به جملات صوتی
  static Future<void> speakStep(
    String modifier,
    String streetName,
    int distanceMeters,
    String langCode,
  ) async {
    if (isMuted) return;

    if (!_isInitialized) {
      await initTts(langCode);
    }

    String speechMessage = '';

    switch (modifier.toLowerCase()) {
      case 'right':
      case 'slight right':
      case 'sharp right':
        speechMessage = distanceMeters > 0
            ? 'voice_turn_right'.tr(args: [distanceMeters.toString()])
            : 'voice_turn_right_now'.tr();
        break;

      case 'left':
      case 'slight left':
      case 'sharp left':
        speechMessage = distanceMeters > 0
            ? 'voice_turn_left'.tr(args: [distanceMeters.toString()])
            : 'voice_turn_left_now'.tr();
        break;

      case 'uturn':
        speechMessage = distanceMeters > 0
            ? 'voice_u_turn'.tr(args: [distanceMeters.toString()])
            : 'voice_u_turn_now'.tr();
        break;

      case 'straight':
      default:
        speechMessage = distanceMeters == 0
            ? 'voice_start_navigation'.tr()
            : 'voice_continue_straight'.tr(args: [distanceMeters.toString()]);
        break;
    }

    if (speechMessage.isNotEmpty) {
      await speak(speechMessage);
    }
  }

  /// قطع صدا
  static Future<void> stop() async {
    await _flutterTts.stop();
  }

  /// تغییر وضعیت بی‌صدا / باصدا
  static void toggleMute() {
    isMuted = !isMuted;
    if (isMuted) {
      stop();
    }
  }
}

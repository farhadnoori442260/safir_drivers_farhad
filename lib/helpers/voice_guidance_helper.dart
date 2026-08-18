import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:easy_localization/easy_localization.dart';

class VoiceGuidanceHelper {
  static final FlutterTts _flutterTts = FlutterTts();
  static bool isMuted = false;

  /// مقداردهی اولیه سیستم صوتی
  static Future<void> initTts(String languageCode) async {
    String lang = 'fa-IR';
    if (languageCode == 'ps') {
      lang = 'ps-AF';
    } else if (languageCode == 'en') {
      lang = 'en-US';
    }

    try {
      await _flutterTts.setLanguage(lang);
      await _flutterTts.setSpeechRate(0.5); // سرعت گفتار
      await _flutterTts.setVolume(1.0);     // میزان صدا
      await _flutterTts.setPitch(1.0);      // لحن صدا
    } catch (e) {
      debugPrint("Error initializing TTS: $e");
    }
  }

  /// پخش پیام صوتی
  static Future<void> speak(String text) async {
    if (isMuted || text.isEmpty) return;
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  /// تبدیل داده‌های مسیریابی به جملات صوتی واقعی بر پایه easy_localization
  static Future<void> speakStep(
    String modifier,
    String streetName,
    int distanceMeters,
    String langCode,
  ) async {
    if (isMuted) return;

    await initTts(langCode);

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

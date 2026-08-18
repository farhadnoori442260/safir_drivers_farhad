import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:safir_drivers/constants/app_colors.dart';

class NavigationBannerWidget extends StatelessWidget {
  final String modifier;       // جهت چرخش (left, right, etc)
  final String nextStreet;     // نام خیابان بعدی
  final double distanceToNext; // فاصله تا مانور بعدی به متر
  final VoidCallback onMuteToggle;
  final bool isMuted;

  const NavigationBannerWidget({
    super.key,
    required this.modifier,
    required this.nextStreet,
    required this.distanceToNext,
    required this.onMuteToggle,
    required this.isMuted,
  });

  // انتخاب آیکون متناسب با مانور دقیق حرکت
  IconData _getTurnIcon(String modifier) {
    switch (modifier.toLowerCase()) {
      case 'right':
        return Icons.turn_right_rounded;
      case 'slight right':
        return Icons.turn_slight_right_rounded;
      case 'sharp right':
        return Icons.turn_sharp_right_rounded;
      case 'left':
        return Icons.turn_left_rounded;
      case 'slight left':
        return Icons.turn_slight_left_rounded;
      case 'sharp left':
        return Icons.turn_sharp_left_rounded;
      case 'uturn':
        return Icons.u_turn_left_rounded;
      case 'straight':
      default:
        return Icons.straight_rounded;
    }
  }

  // فرمت کردن فاصله (تبدیل متر به کیلومتر در صورت نیاز)
  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} ${'km'.tr()}';
    }
    return '${meters.toInt()} ${'m'.tr()}';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50,
      left: 15,
      right: 15,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: SafirColors.brandDark, // استفاده از پالت یکسان سفیر
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 5),
              )
            ],
          ),
          child: Row(
            children: [
              // آیکون راهنما (جهت چرخش)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getTurnIcon(modifier),
                  color: const Color(0xFFFF9900), // رنگ هشدار پویای مسیریابی
                  size: 34,
                ),
              ),
              const SizedBox(width: 14),
              
              // متن اطلاعات خیابان و فاصله
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatDistance(distanceToNext),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nextStreet.isEmpty 
                          ? 'continue_straight'.tr() 
                          : 'enter_street'.tr(args: [nextStreet]),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // دکمه قطع / وصل صدای گوینده
              IconButton(
                onPressed: onMuteToggle,
                icon: Icon(
                  isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryGreen = Color(0xFF2ECC71);
  static const Color primaryLight = Color(0xFFE8F8F5);
  static const Color primaryDark = Color(0xFF27AE60);
  static const Color neutralGrey = Color(0xFF95A5A6);
  static const Color backgroundLight = Color(0xFFF8FBF9);
  static const Color expenseRed = Color(0xFFE74C3C);
  static const Color pointsGold = Color(0xFFF39C12);
  static const Color deepText = Color(0xFF2C3E50);
  static const Color darkBg = Color(0xFF1A1F1C);

  /// 浅色模式卡片阴影
  static List<BoxShadow> get cardShadowLight => [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// 深色模式卡片「发光」
  static List<BoxShadow> get cardShadowDark => [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
}

import 'package:flutter/material.dart';

/// Central design tokens for SafeRise.
/// Kept as plain static colors (not ThemeData) so every screen can reach
/// them the same way regardless of Material version.
class AppColors {
  AppColors._();

  static const bg = Color(0xFFF5F6F8);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE7E9EE);

  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9CA3AF);

  static const blue = Color(0xFF1D5FC7);
  static const blueDark = Color(0xFF0F4CA8);
  static const blueTint = Color(0xFFE9F0FC);

  static const green = Color(0xFF16A34A);
  static const greenTint = Color(0xFFDCFCE7);
  static const greenText = Color(0xFF15803D);

  static const red = Color(0xFFDC2626);
  static const redTint = Color(0xFFFDE7E7);
  static const redBorder = Color(0xFFF6B9B9);
  static const redText = Color(0xFFB91C1C);

  static const amber = Color(0xFFD97706);
  static const amberTint = Color(0xFFFEF3E0);
  static const amberText = Color(0xFFB45309);
}

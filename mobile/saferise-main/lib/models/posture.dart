import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Posture (pose tubuh) yang dideteksi AI di payload MQTT:
/// field "posture" -> "normal" | "climbing" | "crouching"
enum Posture { normal, climbing, crouching }

extension PostureX on Posture {
  static Posture fromString(Object? value) {
    switch ('$value'.trim().toLowerCase()) {
      case 'climbing':
        return Posture.climbing;
      case 'crouching':
        return Posture.crouching;
      default:
        return Posture.normal;
    }
  }

  String get wireValue {
    switch (this) {
      case Posture.climbing:
        return 'climbing';
      case Posture.crouching:
        return 'crouching';
      case Posture.normal:
        return 'normal';
    }
  }

  /// Label pada badge "POSTUR TERDETEKSI".
  String get label {
    switch (this) {
      case Posture.climbing:
        return 'Indikasi Memanjat';
      case Posture.crouching:
        return 'Menunduk / Jongkok';
      case Posture.normal:
        return 'Normal';
    }
  }

  /// climbing -> merah (paling kritis), crouching -> amber/oranye
  /// (waspada tapi bukan paling kritis), normal -> tidak ditampilkan.
  Color get color {
    switch (this) {
      case Posture.climbing:
        return AppColors.red;
      case Posture.crouching:
        return AppColors.amber;
      case Posture.normal:
        return AppColors.green;
    }
  }
}

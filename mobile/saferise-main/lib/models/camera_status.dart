import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// The 3 states a camera/sector can be in.
/// Mirrors the `status` field of the MQTT payload exactly:
/// saferise/camera/{camera_id}/status -> "NORMAL" | "DANGER" | "OFFLINE"
enum CameraStatus { normal, danger, offline }

extension CameraStatusX on CameraStatus {
  static CameraStatus fromString(String value) {
    switch (value.toUpperCase()) {
      case 'DANGER':
        return CameraStatus.danger;
      case 'OFFLINE':
        return CameraStatus.offline;
      default:
        return CameraStatus.normal;
    }
  }

  String get wireValue {
    switch (this) {
      case CameraStatus.danger:
        return 'DANGER';
      case CameraStatus.offline:
        return 'OFFLINE';
      case CameraStatus.normal:
        return 'NORMAL';
    }
  }

  String get label {
    switch (this) {
      case CameraStatus.danger:
        return 'BAHAYA';
      case CameraStatus.offline:
        return 'OFFLINE';
      case CameraStatus.normal:
        return 'NORMAL';
    }
  }

  Color get color {
    switch (this) {
      case CameraStatus.danger:
        return AppColors.red;
      case CameraStatus.offline:
        return AppColors.amber;
      case CameraStatus.normal:
        return AppColors.green;
    }
  }

  Color get tint {
    switch (this) {
      case CameraStatus.danger:
        return AppColors.redTint;
      case CameraStatus.offline:
        return AppColors.amberTint;
      case CameraStatus.normal:
        return AppColors.greenTint;
    }
  }

  Color get textColor {
    switch (this) {
      case CameraStatus.danger:
        return AppColors.redText;
      case CameraStatus.offline:
        return AppColors.amberText;
      case CameraStatus.normal:
        return AppColors.greenText;
    }
  }
}

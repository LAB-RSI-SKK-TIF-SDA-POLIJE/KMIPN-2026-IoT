import 'package:flutter/material.dart';
import '../models/camera_status.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final CameraStatus status;

  @override
  Widget build(BuildContext context) {
    final isDanger = status == CameraStatus.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDanger ? status.color : status.tint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: isDanger ? Colors.white : status.textColor,
        ),
      ),
    );
  }
}

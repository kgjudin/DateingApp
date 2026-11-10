import 'package:flutter/material.dart';

/// App-level persistent wrapper.
///
/// Any lingering floating overlay banners have been removed so the UI
/// stays clean and never displays lingering banners after a call ends.
class ActiveCallOverlayWrapper extends StatelessWidget {
  final Widget? child;

  const ActiveCallOverlayWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child ?? const SizedBox.shrink();
  }
}

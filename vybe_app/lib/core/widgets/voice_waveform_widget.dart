import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class VoiceWaveformWidget extends StatefulWidget {
  final bool isSpeaking;
  final int barCount;
  final double maxHeight;
  final Color? barColor;

  const VoiceWaveformWidget({
    super.key,
    this.isSpeaking = true,
    this.barCount = 18,
    this.maxHeight = 60,
    this.barColor,
  });

  @override
  State<VoiceWaveformWidget> createState() => _VoiceWaveformWidgetState();
}

class _VoiceWaveformWidgetState extends State<VoiceWaveformWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(widget.barCount, (index) {
            final factor = widget.isSpeaking
                ? (sin((_controller.value * 2 * pi) + (index * 0.4)).abs() * 0.75 + 0.25)
                : 0.15;
            final height = widget.maxHeight * factor;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 3.5,
              height: max(6.0, height),
              decoration: BoxDecoration(
                gradient: widget.barColor != null
                    ? null
                    : LinearGradient(
                        colors: [
                          AppColors.primaryAccent,
                          AppColors.secondaryAccent,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                color: widget.barColor,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class OnlineBadge extends StatefulWidget {
  final double size;
  final bool isOnline;

  const OnlineBadge({
    super.key,
    this.size = 12,
    this.isOnline = true,
  });

  @override
  State<OnlineBadge> createState() => _OnlineBadgeState();
}

class _OnlineBadgeState extends State<OnlineBadge> with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOnline) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: AppColors.textMuted,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.cardBackground, width: 2),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Container(
          width: widget.size + (_anim.value * 4),
          height: widget.size + (_anim.value * 4),
          decoration: BoxDecoration(
            color: AppColors.online.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: AppColors.online,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primaryBackground, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.online.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

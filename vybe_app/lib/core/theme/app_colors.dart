import 'package:flutter/material.dart';

class AppColors {
  // Midnight Dark Design Tokens
  static const Color primaryBackground = Color(0xFF0B0B14);
  static const Color secondaryBackground = Color(0xFF141421);
  static const Color cardBackground = Color(0xFF1C1B2B);
  static const Color elevatedSurface = Color(0xFF232236);

  // Accents
  static const Color primaryAccent = Color(0xFFA855F7); // Electric Violet
  static const Color primaryAccentLight = Color(0xFFC084FC);
  static const Color secondaryAccent = Color(0xFFEC4899); // Neon Pink
  static const Color accentGradientStart = Color(0xFFA855F7);
  static const Color accentGradientEnd = Color(0xFFEC4899);

  // Status & Indicators
  static const Color online = Color(0xFF22C55E); // Emerald glow
  static const Color busy = Color(0xFFF59E0B); // Amber
  static const Color error = Color(0xFFEF4444); // Crimson red
  static const Color info = Color(0xFF3B82F6);

  // Typography
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA1A1B5);
  static const Color textMuted = Color(0xFF6B6B80);

  // Glassmorphic Borders & Highlights
  static const Color glassBorder = Color(0x1FFFFFFF);
  static const Color glassHighlight = Color(0x0FFFFFFF);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [accentGradientStart, accentGradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1C1B2B), Color(0xFF141421)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient voiceWaveGradient = LinearGradient(
    colors: [Color(0xFFA855F7), Color(0xFFEC4899), Color(0xFF8B5CF6)],
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
  );
}

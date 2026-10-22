import 'package:flutter/material.dart';

/// Illinois brand colors.
abstract final class IlliniColors {
  static const orange = Color(0xFFFF5F05);
  static const blue = Color(0xFF13294B);
  static const lightOrange = Color(0xFFFF8A4C);
  static const altgeldGray = Color(0xFF707372);
}

abstract final class AppTheme {
  static ThemeData light() => _build(ColorScheme.fromSeed(
        seedColor: IlliniColors.blue,
        brightness: Brightness.light,
        primary: IlliniColors.blue,
        secondary: IlliniColors.orange,
        onSecondary: Colors.white,
        tertiary: IlliniColors.orange,
      ));

  static ThemeData dark() => _build(ColorScheme.fromSeed(
        seedColor: IlliniColors.blue,
        brightness: Brightness.dark,
        primary: IlliniColors.lightOrange,
        onPrimary: const Color(0xFF2B1000),
        secondary: IlliniColors.lightOrange,
        tertiary: IlliniColors.lightOrange,
      ));

  static ThemeData _build(ColorScheme scheme) {
    final isLight = scheme.brightness == Brightness.light;
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? IlliniColors.blue : scheme.surface,
        foregroundColor: isLight ? Colors.white : scheme.onSurface,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: isLight
            ? IlliniColors.orange.withValues(alpha: 0.18)
            : scheme.primary.withValues(alpha: 0.24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: const ChipThemeData(showCheckmark: true),
    );
  }

  /// Color for "open now" indicators that reads well on either theme.
  static Color openColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFF1B7F3B)
          : const Color(0xFF6FD08C);
}

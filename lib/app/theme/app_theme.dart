import 'package:flutter/material.dart';

/// OpsClaw dark theme — red/black/cyan palette.
class AppTheme {
  AppTheme._();

  // Primary palette
  static const _red = Color(0xFFFF3B1F);        // main accent, buttons
  static const _deepRed = Color(0xFFB81200);     // depth, danger
  static const _cyan = Color(0xFF00E6FF);        // tech accent, connected state
  static const _softRed = Color(0xFFFF6A4D);    // warning / soft highlight

  // Neutral
  static const _black = Color(0xFF000000);       // background
  static const _darkGray = Color(0xFF2A2A2A);    // surface, cards, inputs
  static const _lightText = Color(0xFFE6E6E6);   // primary text
  static const _muted = Color(0xFF8A93A1);        // secondary text

  static Color get accent => _red;
  static Color get danger => _deepRed;
  static Color get warning => _softRed;
  static Color get muted => _muted;
  static Color get cyan => _cyan;

  static ThemeData dark() {
    const base = ColorScheme.dark(
      primary: _red,
      secondary: _cyan,
      surface: _black,
      error: _deepRed,
      onPrimary: _lightText,
      onSecondary: _black,
      onSurface: _lightText,
      onError: _lightText,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: base,
      scaffoldBackgroundColor: _black,
      canvasColor: _black,
      appBarTheme: const AppBarTheme(
        backgroundColor: _black,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: _lightText),
        titleTextStyle: TextStyle(
          color: _lightText,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: const CardThemeData(
        color: _darkGray,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkGray,
        hintStyle: const TextStyle(color: _muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF3A3A3A), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _red, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _red,
          foregroundColor: _lightText,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _lightText,
          side: const BorderSide(color: Color(0xFF3A3A3A), width: 1),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _cyan,
          minimumSize: const Size(44, 44),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: _darkGray,
          foregroundColor: _lightText,
          selectedBackgroundColor: _red,
          selectedForegroundColor: _lightText,
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF3A3A3A), thickness: 1),
      listTileTheme: const ListTileThemeData(
        iconColor: _lightText,
        textColor: _lightText,
      ),
      iconTheme: const IconThemeData(color: _lightText),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _darkGray,
        contentTextStyle: const TextStyle(color: _lightText),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(_darkGray),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: _lightText, fontSize: 16),
        bodyMedium: TextStyle(color: _lightText, fontSize: 14),
        bodySmall: TextStyle(color: _muted, fontSize: 12),
        titleLarge: TextStyle(color: _lightText, fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: _lightText, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Monospace text style for terminal/log output — JetBrains Mono.
  static TextStyle mono({double size = 13, Color? color, FontWeight? weight}) {
    return TextStyle(
      fontFamily: 'JetBrainsMono',
      fontFamilyFallback: const ['Courier New', 'monospace'],
      fontSize: size,
      color: color ?? _lightText,
      height: 1.45,
      fontWeight: weight ?? FontWeight.normal,
      letterSpacing: 0.3,
    );
  }
}

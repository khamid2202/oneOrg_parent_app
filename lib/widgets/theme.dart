import 'package:flutter/material.dart';

const kAccent = Color(0xFF7C3AED);

/// Extra colours the screens use beside the Material scheme.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.page,
    required this.surface,
    required this.sunken,
    required this.line,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.accentInk,
  });

  final Color page, surface, sunken, line, ink, muted, accent, accentSoft, accentInk;

  static const light = AppColors(
    page: Color(0xFFFAF9FF),
    surface: Colors.white,
    sunken: Color(0xFFF4F3FA),
    line: Color(0xFFE5E3F0),
    ink: Color(0xFF1E1B2E),
    muted: Color(0xFF6E6A82),
    accent: kAccent,
    accentSoft: Color(0xFFF5F3FF),
    accentInk: Color(0xFF6D28D9),
  );

  static const dark = AppColors(
    page: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    sunken: Color(0xFF172133),
    line: Color(0xFF334155),
    ink: Color(0xFFF1F5F9),
    muted: Color(0xFF94A3B8),
    accent: Color(0xFFA78BFA),
    accentSoft: Color(0xFF2E2752),
    accentInk: Color(0xFFC4B5FD),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension AppColorsX on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: kAccent,
    brightness: brightness,
    primary: colors.accent,
    surface: colors.surface,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: colors.line),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.page,
    extensions: [colors],
    dividerColor: colors.line,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.page,
      foregroundColor: colors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: BorderSide(color: colors.accent, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: colors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: colors.accent,
        foregroundColor: brightness == Brightness.dark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: colors.ink,
        side: BorderSide(color: colors.line),
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.accentSoft,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.selected) ? colors.accent : colors.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? colors.accent : colors.muted,
          )),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
  );
}

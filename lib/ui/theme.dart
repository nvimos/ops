import 'package:material_ui/material_ui.dart';

/// Colors: dense and calm, one strong accent (Linear-like, dark first).
class C {
  static const bg = Color(0xFF0F1117);
  static const surface = Color(0xFF16181F);
  static const surface2 = Color(0xFF1C1F28);
  static const hover = Color(0xFF232733);
  static const border = Color(0xFF262A36);
  static const text = Color(0xFFE6E8EC);
  static const muted = Color(0xFF8B90A0);
  static const faint = Color(0xFF5C6170);
  static const accent = Color(0xFF6C8CFF);

  /// Background of search matches.
  static const found = Color(0x66FFB84D);
  static const green = Color(0xFF4CC38A);
  /// The paler green of the + sign and the line numbers of an added line in diffs.
  static const addSign = Color(0xFF8FD3A8);
  static const red = Color(0xFFE5484D);
  static const yellow = Color(0xFFE6B450);
  static const purple = Color(0xFFA78BFA);

  static const addBg = Color(0xFF173626);
  static const delBg = Color(0xFF3A171D);
}

/// Syntax colors for code in diffs: readable on the plain background and on the diff's green and
/// red line backgrounds, so none of them is a pure green or red.
class Syn {
  static const keyword = Color(0xFFC792EA);
  static const string = Color(0xFFE6B450);
  static const number = Color(0xFFF2996B);
  static const comment = Color(0xFF7A8094);
  static const title = Color(0xFF82AAFF);
  static const type = Color(0xFF5CCFE6);
  static const attr = Color(0xFF9CC4FF);
  static const meta = Color(0xFFB39DDB);
  static const regexp = Color(0xFFD6A27A);
}

const mono = 'Consolas';

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.surface,
    dividerColor: C.border,
    colorScheme: base.colorScheme.copyWith(
      primary: C.accent,
      secondary: C.accent,
      surface: C.surface,
      onSurface: C.text,
      error: C.red,
    ),
    textTheme: base.textTheme.apply(fontFamily: 'Segoe UI', bodyColor: C.text, displayColor: C.text),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.all(Radius.circular(4))),
      textStyle: TextStyle(color: C.text, fontSize: 12),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: C.surface2,
      border: OutlineInputBorder(borderSide: BorderSide(color: C.border)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: C.border)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: C.accent)),
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.surface2,
      contentTextStyle: T.body,
      actionTextColor: C.accent,
      showCloseIcon: true,
      closeIconColor: C.muted,
      elevation: 6,
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: C.border),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(C.border),
      thickness: WidgetStateProperty.all(6),
    ),
  );
}

/// Small text styles used everywhere.
class T {
  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.text);
  static const body = TextStyle(fontSize: 13, color: C.text);
  static const small = TextStyle(fontSize: 12, color: C.muted);
  static const tiny = TextStyle(fontSize: 11, color: C.muted);
  static const section = TextStyle(fontSize: 11, color: C.muted, fontWeight: FontWeight.w600, letterSpacing: .6);
  static const code = TextStyle(fontSize: 12.5, fontFamily: mono, color: C.text, height: 1.35);
}

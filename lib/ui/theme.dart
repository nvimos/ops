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
  static const green = Color(0xFF4CC38A);
  static const red = Color(0xFFE5484D);
  static const yellow = Color(0xFFE6B450);
  static const purple = Color(0xFFA78BFA);

  static const addBg = Color(0xFF13261C);
  static const delBg = Color(0xFF2A1517);
  static const addGutter = Color(0xFF1B3A29);
  static const delGutter = Color(0xFF3E1D20);
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

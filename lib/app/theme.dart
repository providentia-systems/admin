import 'package:flutter/material.dart';

ThemeData buildAdminTheme() {
  const seed = Color(0xff325f52);
  final colors = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
  );
  return ThemeData(
    colorScheme: colors,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: const Color(0xfff6f8f7),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    dataTableTheme: const DataTableThemeData(
      columnSpacing: 28,
      horizontalMargin: 16,
    ),
  );
}

import 'package:flutter/material.dart';

const int _m3PrimaryValue = 0xFF6750A4;

enum AppColorSeed {
  baseColor(
    'Baseline',
    MaterialColor(_m3PrimaryValue, <int, Color>{
      50: Color(0xFFEADDFF),
      100: Color(0xFFD0BCFF),
      200: Color(0xFFB69DF8),
      300: Color(0xFF9A7EEA),
      400: Color(0xFF7F67D9),
      500: Color(_m3PrimaryValue),
      600: Color(0xFF5D4896),
      700: Color(0xFF4F3C7E),
      800: Color(0xFF413168),
      900: Color(0xFF332551),
    }),
  ),
  mintGreen(
    'Mint Green',
    MaterialColor(0xFF98FB98, <int, Color>{
      50: Color(0xFFE6FFFA),
      100: Color(0xFFC0FFEE),
      200: Color(0xFF98FB98),
      300: Color(0xFF70F2A0),
      400: Color(0xFF52EAA0),
      500: Color(0xFF38E298),
      600: Color(0xFF30D08A),
      700: Color(0xFF28BA7A),
      800: Color(0xFF20A86C),
      900: Color(0xFF108A52),
    }),
  ),
  skyBlue(
    'Sky Blue',
    MaterialColor(0xFF87CEEB, <int, Color>{
      50: Color(0xFFE1F5FE),
      100: Color(0xFFB3E5FC),
      200: Color(0xFF81D4FA),
      300: Color(0xFF4FC3F7),
      400: Color(0xFF29B6F6),
      500: Color(0xFF03A9F4),
      600: Color(0xFF039BE5),
      700: Color(0xFF0288D1),
      800: Color(0xFF0277BD),
      900: Color(0xFF01579B),
    }),
  ),
  softPink(
    'Soft Pink',
    MaterialColor(0xFFFFC0CB, <int, Color>{
      50: Color(0xFFFFE4E8),
      100: Color(0xFFFFCCD5),
      200: Color(0xFFFFB3BF),
      300: Color(0xFFFFA0AB),
      400: Color(0xFFFF8D9A),
      500: Color(0xFFFF7A87),
      600: Color(0xFFFF6A70),
      700: Color(0xFFFF5C67),
      800: Color(0xFFF84B5C),
      900: Color(0xFFF02D40),
    }),
  ),
  lightLavender(
    'Light Lavender',
    MaterialColor(0xFFB2A2E8, <int, Color>{
      50: Color(0xFFF3F0FF),
      100: Color(0xFFE0DBFA),
      200: Color(0xFFCEC4F6),
      300: Color(0xFFBCAEF1),
      400: Color(0xFFB2A2E8), // 0xFFB2A2E8 - Our Seed
      500: Color(0xFFA08CE0),
      600: Color(0xFF8E7ACA),
      700: Color(0xFF7C69B3),
      800: Color(0xFF6A589D),
      900: Color(0xFF584786),
    }),
  ),
  indigo('Indigo', Colors.indigo),
  blue('Blue', Colors.blue),
  teal('Teal', Colors.teal),
  green('Green', Colors.green),
  yellow('Yellow', Colors.yellow),
  amber('Amber', Colors.amber),
  lime('Lime', Colors.lime),
  orange('Orange', Colors.orange),
  deepOrange('Deep Orange', Colors.deepOrange),
  pink('Pink', Colors.pink),
  purple('Purple', Colors.purple),
  deepPurple('Deep Purple', Colors.deepPurple),
  red('Red', Colors.red);

  const AppColorSeed(this.label, this.color);
  final String label;
  final MaterialColor color;

  static Color getColor(String label) {
    return AppColorSeed.values
        .firstWhere(
          (e) => e.label == label,
          orElse: () => AppColorSeed.baseColor,
        )
        .color;
  }

  static String getLabel(Color color) {
    return AppColorSeed.values
        .firstWhere(
          (e) => e.color == color,
          orElse: () => AppColorSeed.baseColor,
        )
        .label;
  }

  static AppColorSeed getSeedByLabel(String label) {
    return AppColorSeed.values.firstWhere(
      (e) => e.label == label,
      orElse: () => AppColorSeed.baseColor,
    );
  }
}

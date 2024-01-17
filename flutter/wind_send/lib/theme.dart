import 'package:flutter/material.dart';

enum AppColorSeed {
  baseColor('Baseline', Color(0xff6750a4)),
  indigo('Indigo', Colors.indigo),
  blue('Blue', Colors.blue),
  teal('Teal', Colors.teal),
  green('Green', Colors.green),
  yellow('Yellow', Colors.yellow),
  orange('Orange', Colors.orange),
  deepOrange('Deep Orange', Colors.deepOrange),
  pink('Pink', Colors.pink);

  const AppColorSeed(this.label, this.color);
  final String label;
  final Color color;

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

import 'package:flutter/material.dart';

class SettingsSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const SettingsSection({super.key, this.title, required this.children});

  static Divider defaultDivider(BuildContext context) {
    return Divider(color: Theme.of(context).colorScheme.surface, height: 1);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 10, bottom: 6),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Card(
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 18),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

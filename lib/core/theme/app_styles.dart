import 'package:flutter/material.dart';

/// Shared spacing and building blocks so every screen uses the same rhythm.
abstract final class AppStyles {
  /// Horizontal margin for page-level content.
  static const pagePadding = EdgeInsets.symmetric(horizontal: 16);

  static final cardRadius = BorderRadius.circular(18);
  static const cardPadding = EdgeInsets.all(16);

  /// Gap between a section's label and its content.
  static const labelGap = SizedBox(height: 8);

  /// Gap between sections.
  static const sectionGap = SizedBox(height: 24);
}

/// Small caps-ish label that introduces a section ("MY LISTS", "COMPLETED").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

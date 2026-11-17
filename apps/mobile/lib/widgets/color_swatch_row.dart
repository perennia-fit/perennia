import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// One swatch a [ColorSwatchRow] offers.
class ColorSwatchOption {
  const ColorSwatchOption({required this.hex, required this.label, this.key});

  /// The `#RRGGBB` value chosen by tapping this swatch.
  final String hex;

  /// The swatch's tooltip and semantics label: a swatch is otherwise only a
  /// color, which is never the sole signal.
  final String label;
  final Key? key;
}

/// A wrapping row of color swatches, where a stored color is chosen. The
/// selected swatch is disabled, so tapping it again does nothing.
class ColorSwatchRow extends StatelessWidget {
  const ColorSwatchRow({
    super.key,
    required this.options,
    required this.selectedHex,
    required this.onSelected,
  });

  final List<ColorSwatchOption> options;
  final String? selectedHex;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final fallback = context.colors.categoryColor('other');
    return Wrap(
      spacing: AppDimens.dense,
      runSpacing: AppDimens.dense,
      children: [
        for (final option in options)
          IconButton(
            key: option.key,
            tooltip: option.label,
            onPressed:
                option.hex == selectedHex ? null : () => onSelected(option.hex),
            icon: Icon(
              Icons.circle,
              color: colorFromHex(option.hex, fallback: fallback),
            ),
          ),
      ],
    );
  }
}

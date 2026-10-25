import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// One bordered surface holding a run of rows, separated by hairlines
/// indented by the base gutter: a grouped list, never a stack of cards.
class GroupedRows extends StatelessWidget {
  const GroupedRows({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index += 1) ...[
            if (index > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppDimens.base,
                color: context.colors.divider,
              ),
            children[index],
          ],
        ],
      ),
    );
  }
}

/// A muted, tracked label heading a run of rows or tiles.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: context.textStyles.label.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

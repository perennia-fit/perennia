import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';

/// A text button on a Progress card: the trailing link to a detail screen,
/// or the one action of an empty state.
class ProgressCardAction {
  const ProgressCardAction({
    required this.label,
    required this.onPressed,
    this.key,
  });

  final String label;
  final VoidCallback onPressed;
  final Key? key;
}

/// The frame every Progress Overview card shares (D8): a DESIGN.md card
/// (surface color, `md` corners, no shadow) with an `h2` [title] and an
/// optional trailing [action] over its [child].
///
/// Use [ProgressCard.pending] until the card has data and
/// [ProgressCard.empty] when it has nothing to show. An empty state's own
/// action replaces the trailing one, so a card never offers more than one
/// action while it is empty.
class ProgressCard extends StatelessWidget {
  const ProgressCard({
    super.key,
    required this.title,
    this.action,
    required this.child,
  });

  /// A card without data: when its data [failed] to load, the one-line
  /// "Unavailable right now" with no action; otherwise the title over a
  /// fixed-height empty body, so a card that is still computing holds its
  /// place and moves the cards below it once, when its data arrives.
  const ProgressCard.pending({
    super.key,
    required this.title,
    bool failed = false,
  })  : action = null,
        child = failed
            ? const _UnavailableBody()
            : const SizedBox(height: loadingBodyHeight);

  /// The card's one-line empty state, with at most one action. Without an
  /// [emptyAction], the card keeps its trailing [action].
  ProgressCard.empty({
    super.key,
    required this.title,
    required String message,
    ProgressCardAction? emptyAction,
    ProgressCardAction? action,
  })  : action = emptyAction == null ? action : null,
        child = _EmptyBody(message: message, action: emptyAction);

  static const double loadingBodyHeight = 120;

  final String title;
  final ProgressCardAction? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Material(
      color: context.colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.base,
          AppDimens.dense / 2,
          AppDimens.base,
          AppDimens.base,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppDimens.touchTarget,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: context.textStyles.h2.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (action != null) ProgressTextButton(action: action),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.dense / 2),
            child,
          ],
        ),
      ),
    );
  }
}

/// A Progress text button in the primary text color: Signal Cyan text fails
/// AA on the light ground, and the screen keeps its one cyan mark for the
/// period control.
class ProgressTextButton extends StatelessWidget {
  const ProgressTextButton({super.key, required this.action});

  final ProgressCardAction action;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: action.key,
      style: TextButton.styleFrom(
        minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
        foregroundColor: context.colors.textPrimary,
      ),
      onPressed: action.onPressed,
      child: Text(action.label),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.message, this.action});

  final String message;
  final ProgressCardAction? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        if (action != null) Center(child: ProgressTextButton(action: action)),
      ],
    );
  }
}

class _UnavailableBody extends StatelessWidget {
  const _UnavailableBody();

  @override
  Widget build(BuildContext context) {
    return _EmptyBody(message: context.l10n.progressCardUnavailable);
  }
}

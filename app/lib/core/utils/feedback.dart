import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/firestore_refs.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// One place for the toast / haptic vocabulary so success and failure always
/// feel the same across the app.
class AppFeedback {
  const AppFeedback._();

  static void toast(
    BuildContext context,
    String message, {
    ToastKind kind = ToastKind.neutral,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: Duration(milliseconds: kind == ToastKind.error ? 4200 : 2600),
        backgroundColor: switch (kind) {
          ToastKind.error => FColors.danger,
          ToastKind.success => FColors.tealDarker,
          ToastKind.neutral => FColors.inkStrong,
        },
        content: Row(
          children: <Widget>[
            Icon(
              switch (kind) {
                ToastKind.error => Icons.error_outline_rounded,
                ToastKind.success => Icons.check_circle_outline_rounded,
                ToastKind.neutral => Icons.info_outline_rounded,
              },
              size: 16,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            const SizedBox(width: FSpace.lg),
            Expanded(
              child: Text(
                message,
                style: FType.bodyXs.copyWith(color: Colors.white, height: 1.4),
              ),
            ),
          ],
        ),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: FColors.accentOnDark,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  static void success(BuildContext context, String message) {
    HapticFeedback.lightImpact();
    toast(context, message, kind: ToastKind.success);
  }

  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    HapticFeedback.heavyImpact();
    toast(
      context,
      message,
      kind: ToastKind.error,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void tap() => HapticFeedback.selectionClick();

  /// Destructive confirmation sheet — used for log out, closing a listing,
  /// deleting a message and blocking a user.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title, style: FType.titleMd),
        content: Text(message, style: FType.bodySm),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              cancelLabel,
              style: FType.buttonSm
                  .copyWith(fontSize: 13, color: FColors.inkMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              confirmLabel,
              style: FType.buttonSm.copyWith(
                fontSize: 13,
                color: destructive ? FColors.danger : FColors.tealDeep,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Runs [action], reporting a failure instead of letting it disappear.
  ///
  /// Returns true when it completed. Use this for every repository call made
  /// in response to a tap.
  ///
  /// An audit found roughly a dozen `await someRepo.doThing()` calls with no
  /// try at all. On a denied write the exception unwound to nothing, so the
  /// user tapped "Close Listing" or "Shortlist", got no toast, no error and no
  /// state change, and had no way to tell the difference between "that
  /// silently failed" and "that isn't wired up". Reaching for this helper is
  /// less effort than hand-writing a try/catch, which is the point — the safe
  /// path has to be the easy one or it doesn't get taken.
  ///
  /// [onError] overrides the derived message when the screen has more context
  /// about what was being attempted.
  static Future<bool> guard(
    BuildContext context,
    Future<void> Function() action, {
    String? onError,
    String? onSuccess,
  }) async {
    try {
      await action();
      if (context.mounted && onSuccess != null) success(context, onSuccess);
      return true;
    } on Object catch (e) {
      if (context.mounted) {
        error(context, onError ?? describeFirestoreError(e));
      }
      return false;
    }
  }
}

enum ToastKind { neutral, success, error }

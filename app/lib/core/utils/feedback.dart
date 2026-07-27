import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
}

enum ToastKind { neutral, success, error }

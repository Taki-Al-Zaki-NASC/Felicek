import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

/// Assembles a [ThemeData] out of the design tokens.
///
/// The product is a single-mode (light) design — the palette is warm paper on
/// purpose — so there is no dark variant. System UI is styled to match so the
/// status bar and gesture pill read as part of the app.
class AppTheme {
  const AppTheme._();

  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: FColors.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: FColors.border,
  );

  static ThemeData build() {
    const ColorScheme scheme = ColorScheme.light(
      primary: FColors.teal,
      onPrimary: Colors.white,
      primaryContainer: FColors.tealTint,
      onPrimaryContainer: FColors.tealDarker,
      secondary: FColors.blue,
      onSecondary: Colors.white,
      secondaryContainer: FColors.blueTint,
      onSecondaryContainer: FColors.blue,
      tertiary: FColors.violet,
      onTertiary: Colors.white,
      tertiaryContainer: FColors.violetTint,
      onTertiaryContainer: FColors.violet,
      error: FColors.danger,
      onError: Colors.white,
      errorContainer: FColors.dangerTint,
      onErrorContainer: FColors.danger,
      surface: FColors.canvas,
      onSurface: FColors.ink,
      surfaceContainerLowest: FColors.surface,
      surfaceContainerLow: FColors.surfaceSunken,
      surfaceContainer: FColors.neutralTint,
      onSurfaceVariant: FColors.inkMuted,
      outline: FColors.borderStrong,
      outlineVariant: FColors.border,
      inverseSurface: FColors.inkStrong,
      onInverseSurface: FColors.canvas,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: FColors.canvas,
      canvasColor: FColors.canvas,
      fontFamily: FType.sans,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      // The design never uses Material's tonal elevation overlays.
      applyElevationOverlayColor: false,
      appBarTheme: const AppBarTheme(
        backgroundColor: FColors.canvas,
        foregroundColor: FColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: systemOverlay,
        titleTextStyle: FType.titleSm,
      ),
      dividerTheme: const DividerThemeData(
        color: FColors.border,
        thickness: 1,
        space: 1,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: FColors.teal,
        selectionColor: FColors.teal.withValues(alpha: 0.22),
        selectionHandleColor: FColors.teal,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: FColors.teal,
        linearTrackColor: FColors.border,
        circularTrackColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: FColors.inkStrong,
        contentTextStyle: FType.bodyXs.copyWith(color: FColors.canvas),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: FRadius.fieldR),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actionTextColor: FColors.accentOnDark,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: FColors.canvas,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: FColors.canvas,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(FRadius.sheet)),
        ),
        showDragHandle: true,
        dragHandleColor: FColors.radioRing,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: FColors.canvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: FRadius.cardLgR),
        titleTextStyle: FType.titleMd,
        contentTextStyle: FType.bodySm,
      ),
      listTileTheme: const ListTileThemeData(
        titleTextStyle: FType.bodyXs,
        subtitleTextStyle: FType.caption,
        iconColor: FColors.inkMuted,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> s) =>
              s.contains(WidgetState.selected) ? Colors.white : FColors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> s) => s.contains(WidgetState.selected)
              ? FColors.teal
              : FColors.neutralTint,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> s) => s.contains(WidgetState.selected)
              ? FColors.teal
              : FColors.borderStrong,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: FType.displayXl,
        displayMedium: FType.displayLg,
        displaySmall: FType.displayMd,
        headlineMedium: FType.displaySm,
        headlineSmall: FType.displayXs,
        titleLarge: FType.titleLg,
        titleMedium: FType.titleMd,
        titleSmall: FType.titleSm,
        bodyLarge: FType.body,
        bodyMedium: FType.bodySm,
        bodySmall: FType.support,
        labelLarge: FType.buttonSm,
        labelMedium: FType.fieldLabel,
        labelSmall: FType.caption,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The bordered input from the design:
/// `border:1px solid rgba(27,36,48,0.12); border-radius:10px; padding:12px 14px`.
class FField extends StatelessWidget {
  const FField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.multiline = false,
    this.height,
    this.keyboardType,
    this.obscure = false,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.textInputAction,
    this.inputFormatters,
    this.maxLength,
    this.prefix,
    this.suffix,
    this.focusNode,
    this.autofillHints,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final bool multiline;
  final double? height;
  final TextInputType? keyboardType;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final Widget? prefix;
  final Widget? suffix;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    final Widget field = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscure,
      keyboardType:
          keyboardType ?? (multiline ? TextInputType.multiline : null),
      textInputAction:
          textInputAction ?? (multiline ? TextInputAction.newline : null),
      maxLines: multiline ? null : 1,
      minLines: multiline ? null : 1,
      expands: multiline,
      textAlignVertical:
          multiline ? TextAlignVertical.top : TextAlignVertical.center,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      autofillHints: autofillHints,
      cursorColor: FColors.teal,
      cursorWidth: 1.5,
      style: FType.bodySm.copyWith(
        fontSize: multiline ? 13 : 13.5,
        height: multiline ? 1.5 : 1.2,
        color: FColors.ink,
      ),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        hintText: hint,
        hintStyle: FType.bodySm.copyWith(
          fontSize: multiline ? 13 : 13.5,
          height: multiline ? 1.5 : 1.2,
          color: FColors.inkFaint,
        ),
        filled: true,
        fillColor: enabled ? FColors.surface : FColors.neutralTint,
        prefixIcon: prefix,
        suffixIcon: suffix,
        prefixIconConstraints:
            const BoxConstraints(minWidth: 42, minHeight: 20),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 42, minHeight: 20),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: _border(FColors.borderStrong),
        enabledBorder:
            _border(hasError ? FColors.danger : FColors.borderStrong),
        disabledBorder: _border(FColors.border),
        focusedBorder:
            _border(hasError ? FColors.danger : FColors.teal, width: 1.4),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(label!, style: FType.fieldLabel),
          const SizedBox(height: FSpace.sm),
        ],
        if (multiline) SizedBox(height: height ?? 90, child: field) else field,
        if (hasError) ...<Widget>[
          const SizedBox(height: FSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 13, color: FColors.danger),
              const SizedBox(width: FSpace.sm),
              Expanded(
                child: Text(
                  errorText!,
                  style: FType.caption.copyWith(color: FColors.danger),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: FRadius.fieldR,
        borderSide: BorderSide(color: color, width: width),
      );
}

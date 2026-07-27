import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/f_button.dart';
import '../../core/widgets/f_field.dart';
import '../../core/widgets/f_logo.dart';
import '../../data/models/user_role.dart';
import '../../data/repositories/auth_repository.dart';

enum _AuthMode { signIn, signUp, reset }

/// Sign in / create account / reset password.
///
/// The design starts at role selection and assumes an account already exists,
/// so this screen is new. It reuses the onboarding composition — mark,
/// wordmark, promise line — so the very first screen still feels like Felicek.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  bool _obscure = true;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _formError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _nameError =
          _emailError = _passwordError = _confirmError = _formError = null;
    });
  }

  bool _validate() {
    final String? nameErr =
        _mode == _AuthMode.signUp ? Validate.name(_name.text) : null;
    final String? emailErr = Validate.email(_email.text);
    final String? passErr = switch (_mode) {
      _AuthMode.reset => null,
      _AuthMode.signIn =>
        _password.text.isEmpty ? 'Enter your password.' : null,
      _AuthMode.signUp => Validate.password(_password.text),
    };
    final String? confirmErr = _mode == _AuthMode.signUp
        ? Validate.confirmPassword(_confirm.text, _password.text)
        : null;

    setState(() {
      _nameError = nameErr;
      _emailError = emailErr;
      _passwordError = passErr;
      _confirmError = confirmErr;
      _formError = null;
    });
    return nameErr == null &&
        emailErr == null &&
        passErr == null &&
        confirmErr == null;
  }

  Future<void> _submit() async {
    if (_busy || !_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final AuthRepository auth = context.authRepo;
    try {
      switch (_mode) {
        case _AuthMode.signIn:
          await auth.signIn(email: _email.text, password: _password.text);
        case _AuthMode.signUp:
          await auth.signUp(
            email: _email.text,
            password: _password.text,
            displayName: _name.text,
            // The role picker is the next screen; this is only a starting point.
            role: UserRole.freelancer,
          );
        case _AuthMode.reset:
          await auth.sendPasswordReset(_email.text);
          if (mounted) {
            AppFeedback.success(
              context,
              'Password reset link sent to ${_email.text.trim()}.',
            );
            _setMode(_AuthMode.signIn);
          }
      }
      // On success the session gate swaps the screen out from under us.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } on Object {
      if (mounted) {
        setState(() => _formError = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSignUp = _mode == _AuthMode.signUp;
    final bool isReset = _mode == _AuthMode.reset;

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) =>
              SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 32, 26, 32),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Center(child: FLogo()),
                  const SizedBox(height: FSpace.x6),
                  const Center(child: Text('Felicek', style: FType.displayXl)),
                  const SizedBox(height: FSpace.sm),
                  Center(
                    child: Text(
                      'Verified talent. Zero spam.\nFair fees, always.',
                      textAlign: TextAlign.center,
                      style: FType.bodySm.copyWith(
                        fontSize: 13,
                        color: FColors.inkMuted,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: FSpace.x8),
                  if (isSignUp) ...<Widget>[
                    FField(
                      controller: _name,
                      label: 'Full name',
                      hint: 'e.g. Sadia Rahman',
                      errorText: _nameError,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.name],
                    ),
                    const SizedBox(height: FSpace.x2),
                  ],
                  FField(
                    controller: _email,
                    label: 'Email address',
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    errorText: _emailError,
                    textInputAction: TextInputAction.next,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    ],
                    autofillHints: const <String>[AutofillHints.email],
                  ),
                  if (!isReset) ...<Widget>[
                    const SizedBox(height: FSpace.x2),
                    FField(
                      controller: _password,
                      label: 'Password',
                      hint:
                          isSignUp ? 'At least 8 characters' : 'Your password',
                      obscure: _obscure,
                      errorText: _passwordError,
                      textInputAction: isSignUp
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onSubmitted: (_) => isSignUp ? null : _submit(),
                      autofillHints: <String>[
                        isSignUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      suffix: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 17,
                          color: FColors.inkFaint,
                        ),
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                      ),
                    ),
                  ],
                  if (isSignUp) ...<Widget>[
                    const SizedBox(height: FSpace.x2),
                    FField(
                      controller: _confirm,
                      label: 'Confirm password',
                      hint: 'Re-enter your password',
                      obscure: _obscure,
                      errorText: _confirmError,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                  if (_mode == _AuthMode.signIn) ...<Widget>[
                    const SizedBox(height: FSpace.lg),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FTextAction(
                        label: 'Forgot password?',
                        fontSize: 11.5,
                        onPressed: () => _setMode(_AuthMode.reset),
                      ),
                    ),
                  ],
                  if (_formError != null) ...<Widget>[
                    const SizedBox(height: FSpace.x2),
                    _FormError(message: _formError!),
                  ],
                  const SizedBox(height: FSpace.x5),
                  FButton(
                    label: switch (_mode) {
                      _AuthMode.signIn => 'Sign In',
                      _AuthMode.signUp => 'Create Account',
                      _AuthMode.reset => 'Send Reset Link',
                    },
                    busy: _busy,
                    onPressed: _submit,
                    fontSize: 14,
                  ),
                  const SizedBox(height: FSpace.x3),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(
                          switch (_mode) {
                            _AuthMode.signIn => 'New to Felicek? ',
                            _AuthMode.signUp => 'Already have an account? ',
                            _AuthMode.reset => 'Remembered it? ',
                          },
                          style: FType.supportSm,
                        ),
                        FTextAction(
                          label: _mode == _AuthMode.signUp
                              ? 'Sign in'
                              : 'Create one',
                          fontSize: 11.5,
                          onPressed: () => _setMode(
                            _mode == _AuthMode.signUp
                                ? _AuthMode.signIn
                                : _AuthMode.signUp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: FSpace.x6),
                  Text(
                    'Identity verification is required for every account. '
                    'Freelancer accounts additionally require a refundable '
                    r'$20 trust deposit.',
                    textAlign: TextAlign.center,
                    style: FType.caption.copyWith(fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormError extends StatelessWidget {
  const _FormError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: FColors.dangerTint,
        borderRadius: FRadius.fieldR,
        border: Border.all(color: FColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline_rounded,
              size: 15, color: FColors.danger),
          const SizedBox(width: FSpace.lg),
          Expanded(
            child: Text(
              message,
              style:
                  FType.supportSm.copyWith(color: FColors.danger, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

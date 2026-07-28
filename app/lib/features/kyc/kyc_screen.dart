import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/f_button.dart';
import '../../core/widgets/f_field.dart';
import '../../core/widgets/f_pill.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/app_user.dart';
import '../../data/models/payment_intent.dart';
import '../../data/models/user_role.dart';
import '../../data/models/wallet.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/services/payment_gateway_service.dart';

/// Identity verification and the mandatory deposit that unlocks the account.
///
/// This screen cannot be skipped — there is no "later" affordance by design.
/// A freelancer clears a refundable $20 trust bond; a client, agency or
/// startup clears a $50 job-posting balance (not a fee — it becomes what they
/// fund escrow with). Both require identity on file first, and the deposit
/// itself is handled entirely by [PaymentGatewayService], never simulated
/// with a button that just flips a flag.
class KycScreen extends StatefulWidget {
  const KycScreen({super.key, this.fromProfile = false});

  final bool fromProfile;

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  bool _payBusy = false;
  String? _pendingRef;

  AppUser? get _user => context.read<SessionController>().user;

  Future<void> _toggleDocument(IdDocumentType type) async {
    final AppUser? user = _user;
    if (user == null) return;
    if (user.kyc.idSubmitted) {
      await context.userRepo.clearIdentityDocument(user.uid);
      return;
    }
    final String? reference = await _askForReference(type);
    if (reference == null || !mounted) return;
    try {
      await context.userRepo.submitIdentityDocument(
        uid: user.uid,
        type: type,
        reference: reference,
      );
      if (mounted) {
        AppFeedback.success(context, '${type.label} submitted for review.');
      }
    } on Object {
      if (mounted) {
        AppFeedback.error(context, 'Could not save that. Try again.');
      }
    }
  }

  Future<void> _toggleBirthCert() async {
    final AppUser? user = _user;
    if (user == null) return;
    if (user.kyc.birthCertSubmitted) {
      await context.userRepo.clearBirthCertificate(user.uid);
      return;
    }
    final String? reference =
        await _askForReference(IdDocumentType.birthCertificate);
    if (reference == null || !mounted) return;
    await context.userRepo
        .submitBirthCertificate(uid: user.uid, reference: reference);
  }

  /// The document itself never leaves the device — only the number the
  /// verification partner needs is stored, and only for the account owner to
  /// read.
  Future<String?> _askForReference(IdDocumentType type) {
    final TextEditingController controller = TextEditingController();
    String? error;

    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setLocal) =>
            AlertDialog(
          title: Text(type.label, style: FType.titleMd),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Enter the document number. We store the number only — never a '
                'photo — and it is never shown to other users.',
                style: FType.supportSm,
              ),
              const SizedBox(height: FSpace.x2),
              FField(
                controller: controller,
                hint: type.hint,
                autofocus: true,
                errorText: error,
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: FType.buttonSm
                    .copyWith(fontSize: 13, color: FColors.inkMuted),
              ),
            ),
            TextButton(
              onPressed: () {
                final String value = controller.text.trim();
                if (value.length < type.minLength) {
                  setLocal(() => error = 'That number looks too short.');
                  return;
                }
                Navigator.of(ctx).pop(value);
              },
              child: Text(
                'Submit',
                style: FType.buttonSm
                    .copyWith(fontSize: 13, color: FColors.tealDeep),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _pay(UserRole role) async {
    final AppUser? user = _user;
    if (user == null || !user.kyc.idSubmitted || _payBusy) return;
    setState(() => _payBusy = true);

    final PaymentPurpose purpose = role.requiresProfilePhoto
        ? PaymentPurpose.trustDeposit
        : PaymentPurpose.postingBalance;

    try {
      final String ref = await context.paymentGateway.startCheckout(
        uid: user.uid,
        purpose: purpose,
        amountCents: role.depositCents,
        metadata: <String, String>{'role': role.key},
      );
      _pendingRef = ref;
      if (!mounted) return;
      AppFeedback.toast(
        context,
        'Complete the payment in your browser, then come back and tap "I\'ve paid — Verify".',
      );
    } on PaymentGatewayException catch (e) {
      if (mounted) {
        AppFeedback.error(context, e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _payBusy = false);
      }
    }
  }

  Future<void> _verifyPayment(UserRole role) async {
    final AppUser? user = _user;
    final String? ref = _pendingRef ?? user?.kyc.paymentRef;
    if (user == null || ref == null || _payBusy) {
      AppFeedback.error(context, 'Start a payment first.');
      return;
    }
    setState(() => _payBusy = true);
    // Resolve services before awaiting — reading them off `context` after an
    // await risks touching a disposed element.
    final PaymentGatewayService gateway = context.paymentGateway;
    final UserRepository users = context.userRepo;
    final WalletRepository wallet = context.walletRepo;
    try {
      final PaymentIntent? intent = await gateway.fetchStatus(ref);
      if (intent == null) {
        if (mounted) {
          AppFeedback.error(context, "We couldn't find that payment yet.");
        }
        return;
      }
      switch (intent.status) {
        case PaymentStatus.paid:
          await users.recordDeposit(
            uid: user.uid,
            method: intent.method ?? 'Gateway',
            amountCents: intent.amountCents,
            paymentRef: ref,
          );
          // Show the deposit in the wallet ledger too — money left the
          // person's account, so it belongs on their statement.
          await wallet.recordTrustDeposit(
            uid: user.uid,
            method: PayoutMethod.fromLabel(intent.method),
            amountCents: intent.amountCents,
            isTrustBond: role.depositKind == DepositKind.trustBond,
          );
          if (mounted) {
            AppFeedback.success(
                context, 'Payment confirmed. Account verified.');
          }
        case PaymentStatus.pending:
          if (mounted) {
            AppFeedback.toast(
              context,
              "Payment hasn't cleared yet — this can take a minute. Try again shortly.",
            );
          }
        case PaymentStatus.failed:
        case PaymentStatus.cancelled:
          if (mounted) {
            AppFeedback.error(
                context, 'That payment did not go through. Try again.');
          }
      }
    } on Object {
      if (mounted) {
        AppFeedback.error(context, 'Could not check payment status.');
      }
    } finally {
      if (mounted) {
        setState(() => _payBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppUser? user = context.select<SessionController, AppUser?>(
      (SessionController s) => s.user,
    );
    if (user == null) return const Scaffold(body: FLoading());

    final KycState kyc = user.kyc;
    final UserRole role = user.role;
    final int totalSteps = role.requiresProfilePhoto ? 3 : 2;
    final int step = kyc.idSubmitted ? 2 : 1;

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: Column(
        children: <Widget>[
          FTopBar(
            title: 'Step $step of $totalSteps · Verification',
            leading: widget.fromProfile
                ? FBackChevron(onTap: () => Navigator.of(context).maybePop())
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: <Widget>[
                _ProgressBar(value: kyc.progress),
                const SizedBox(height: FSpace.x3),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: FColors.amberTint,
                    borderRadius: FRadius.fieldR,
                    border:
                        Border.all(color: FColors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 15,
                        color: FColors.amber,
                      ),
                      const SizedBox(width: FSpace.md),
                      Expanded(
                        child: Text(
                          'Every Felicek account requires identity verification and '
                          'a cleared payment before it can be used — there is no '
                          'skip option.',
                          style: FType.captionSm
                              .copyWith(fontSize: 11, color: FColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FSpace.x3),
                const FSectionLabel('Identity verification'),
                const SizedBox(height: FSpace.lg),
                _DocumentPicker(kyc: kyc, onSelect: _toggleDocument),
                const SizedBox(height: FSpace.lg),
                _DocumentRow(
                  title: 'Birth Certificate',
                  subtitle: 'Optional secondary document',
                  done: kyc.birthCertSubmitted,
                  doneLabel: 'Uploaded',
                  onTap: _toggleBirthCert,
                ),
                const SizedBox(height: FSpace.x6),
                FSectionLabel(role.depositHeading),
                const SizedBox(height: FSpace.lg),
                _DepositCard(
                  role: role,
                  kyc: kyc,
                  busy: _payBusy,
                  hasPendingRef: _pendingRef != null,
                  onPay: () => _pay(role),
                  onVerify: () => _verifyPayment(role),
                ),
                const SizedBox(height: FSpace.xl),
                Text(role.depositExplanation,
                    style: FType.caption.copyWith(fontSize: 10.5)),
                const SizedBox(height: FSpace.x5),
                FButton(
                  label: 'Continue',
                  onPressed: kyc.isVerified
                      ? () {
                          if (widget.fromProfile) {
                            Navigator.of(context).maybePop();
                          }
                          // Otherwise the session gate advances on its own.
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: '${(value * 100).round()} percent complete',
      child: Container(
        height: 5,
        decoration: BoxDecoration(
          color: FColors.border,
          borderRadius: BorderRadius.circular(3),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: AnimatedContainer(
            duration: FMotion.slow,
            curve: FMotion.curve,
            decoration: BoxDecoration(
              color: FColors.teal,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentPicker extends StatelessWidget {
  const _DocumentPicker({required this.kyc, required this.onSelect});

  final KycState kyc;
  final ValueChanged<IdDocumentType> onSelect;

  @override
  Widget build(BuildContext context) {
    if (kyc.idSubmitted) {
      return _DocumentRow(
        title: (kyc.idDocumentType ?? IdDocumentType.nationalId).label,
        subtitle: kyc.idReference != null
            ? 'Ending ${_mask(kyc.idReference!)} · encrypted'
            : 'Encrypted · never shown to other users',
        done: true,
        doneLabel: kyc.isVerified ? 'Verified' : 'Submitted',
        onTap: () => onSelect(kyc.idDocumentType ?? IdDocumentType.nationalId),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Choose one primary document',
          style:
              FType.captionSm.copyWith(fontSize: 11, color: FColors.inkMuted),
        ),
        const SizedBox(height: FSpace.lg),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final IdDocumentType type in IdDocumentType.primary)
              FChoiceChip(
                label: type.label,
                selected: false,
                onTap: () => onSelect(type),
              ),
          ],
        ),
      ],
    );
  }

  static String _mask(String reference) => reference.length <= 4
      ? reference
      : '••••${reference.substring(reference.length - 4)}';
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.title,
    required this.subtitle,
    required this.done,
    required this.doneLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool done;
  final String doneLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FCard(
      radius: FRadius.button,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: FType.bodyXs
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: FSpace.xxs),
                Text(subtitle, style: FType.captionSm.copyWith(fontSize: 10.5)),
              ],
            ),
          ),
          const SizedBox(width: FSpace.xl),
          done ? FPill.teal(doneLabel) : FPill.neutral('Upload'),
        ],
      ),
    );
  }
}

class _DepositCard extends StatelessWidget {
  const _DepositCard({
    required this.role,
    required this.kyc,
    required this.busy,
    required this.hasPendingRef,
    required this.onPay,
    required this.onVerify,
  });

  final UserRole role;
  final KycState kyc;
  final bool busy;
  final bool hasPendingRef;
  final VoidCallback onPay;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final bool paid = kyc.depositPaid;
    final bool ready = kyc.idSubmitted;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FColors.tealTint,
        borderRadius: FRadius.cardLgR,
        border: Border.all(color: FColors.teal.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                Fmt.moneyExact(role.depositAmount),
                style: FType.titleLg
                    .copyWith(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              if (paid)
                FPill.teal('Verified ✓')
              else
                FPill(
                  ready ? 'Ready to Pay' : 'Verify ID First',
                  color: FColors.inkFaint,
                  background: FColors.neutralTint,
                ),
            ],
          ),
          const SizedBox(height: FSpace.x2),
          Text(
            paid
                ? 'Cleared via the Felicek payment gateway.'
                : 'Handled securely by our external payment gateway — never '
                    'entered inside this app.',
            style: FType.supportSm.copyWith(height: 1.6),
          ),
          const SizedBox(height: FSpace.x2),
          if (!paid) ...<Widget>[
            FButton(
              label: 'Pay with Felicek Gateway',
              icon: Icons.open_in_new_rounded,
              busy: busy,
              variant: ready ? FButtonVariant.primary : FButtonVariant.muted,
              onPressed: ready ? onPay : null,
              padding: const EdgeInsets.all(13),
              fontSize: 13,
            ),
            if (hasPendingRef) ...<Widget>[
              const SizedBox(height: FSpace.lg),
              FButton(
                label: "I've Paid — Verify",
                variant: FButtonVariant.secondary,
                busy: busy,
                onPressed: onVerify,
                padding: const EdgeInsets.all(13),
                fontSize: 13,
              ),
            ],
          ] else
            const FButton(
              label: 'Deposit Verified ✓',
              variant: FButtonVariant.success,
              onPressed: null,
              padding: EdgeInsets.all(13),
              fontSize: 13,
            ),
        ],
      ),
    );
  }
}

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
import '../../data/models/wallet.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/services/payment_gateway_service.dart';

/// "Wallet & Vault" — balance, the mandatory deposit vault (trust bond for
/// freelancers, posting balance for everyone else), payout method, and the
/// transaction ledger. Withdrawals and top-ups are handed off to the external
/// payment gateway rather than simulated with a button.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  /// The payout rail every money action on this screen uses — the fee is
  /// 1% on local rails and 2% on PayPal, so this selection actually matters.
  PayoutMethod method = PayoutMethod.bkash;

  @override
  Widget build(BuildContext context) {
    final AppUser? user =
        context.select<SessionController, AppUser?>((s) => s.user);
    if (user == null) return const FLoading();

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Container(
              width: double.infinity,
              color: FColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: const Text('Wallet & Vault', style: FType.displayMd),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: <Widget>[
                  _BalanceCard(user: user, method: method),
                  const SizedBox(height: FSpace.x2),
                  _VaultCard(user: user),
                  const SizedBox(height: FSpace.x3),
                  const FSectionLabel('Payout Method'),
                  const SizedBox(height: FSpace.lg),
                  _PayoutMethods(
                    selected: method,
                    onChanged: (PayoutMethod m) => setState(() => method = m),
                  ),
                  const SizedBox(height: FSpace.lg),
                  Text(
                    'Direct local payouts (bKash/Nagad/Bank) with zero platform '
                    'markup, or PayPal for international clients — only a flat '
                    '1%–2% maintenance fee applies. All movements of real money '
                    'go through the Felicek payment gateway, never through this '
                    'screen directly.',
                    style: FType.caption.copyWith(fontSize: 10.5),
                  ),
                  const SizedBox(height: FSpace.x2),
                  const FSectionLabel('Recent Activity'),
                  const SizedBox(height: FSpace.lg),
                  _Transactions(uid: user.uid),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatefulWidget {
  const _BalanceCard({required this.user, required this.method});

  final AppUser user;
  final PayoutMethod method;

  @override
  State<_BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<_BalanceCard> {
  bool _busy = false;

  /// The intent opened by the most recent "Add funds" tap, if any.
  String? _pendingTopUp;

  Future<void> _withdraw() async {
    final int? cents = await _promptAmount(context, title: 'Withdraw funds');
    if (cents == null || !mounted) return;
    final WalletRepository wallet = context.walletRepo;
    setState(() => _busy = true);
    try {
      await wallet.withdraw(
        uid: widget.user.uid,
        amountCents: cents,
        method: widget.method,
      );
      if (mounted) {
        AppFeedback.success(context, 'Withdrawal requested.');
      }
    } on InsufficientFunds catch (e) {
      if (mounted) {
        AppFeedback.error(context, e.message);
      }
    } on Object {
      if (mounted) {
        AppFeedback.error(context, 'Withdrawal failed. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFunds() async {
    final int? cents = await _promptAmount(context, title: 'Add funds');
    if (cents == null || !mounted) return;
    final PaymentGatewayService gateway = context.paymentGateway;
    setState(() => _busy = true);
    try {
      final String ref = await gateway.startCheckout(
        uid: widget.user.uid,
        purpose: PaymentPurpose.walletTopUp,
        amountCents: cents,
      );
      _pendingTopUp = ref;
      if (mounted) {
        AppFeedback.toast(
          context,
          'Complete the payment in your browser, then tap "Confirm top-up".',
        );
      }
    } on Object {
      if (mounted) {
        AppFeedback.error(context, 'Could not open the payment gateway.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Credits the wallet once the gateway's webhook has marked the intent
  /// paid. Nothing here can grant money on its own — the balance only moves
  /// after a status the client is not allowed to write.
  Future<void> _confirmTopUp() async {
    final String? ref = _pendingTopUp;
    if (ref == null || _busy) return;
    final PaymentGatewayService gateway = context.paymentGateway;
    final WalletRepository wallet = context.walletRepo;
    setState(() => _busy = true);
    try {
      final PaymentIntent? intent = await gateway.fetchStatus(ref);
      if (intent == null || intent.status == PaymentStatus.pending) {
        if (mounted) {
          AppFeedback.toast(
            context,
            "That payment hasn't cleared yet. Try again in a moment.",
          );
        }
        return;
      }
      if (intent.status != PaymentStatus.paid) {
        if (mounted) {
          AppFeedback.error(context, 'That payment did not go through.');
        }
        return;
      }
      await wallet.creditTopUp(
        uid: widget.user.uid,
        amountCents: intent.amountCents,
        method: PayoutMethod.fromLabel(intent.method),
      );
      _pendingTopUp = null;
      if (mounted) AppFeedback.success(context, 'Funds added.');
    } on Object {
      if (mounted) {
        AppFeedback.error(context, 'Could not confirm that top-up.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: FColors.inkStrong,
        borderRadius: FRadius.sheetR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'AVAILABLE BALANCE',
            style: FType.sectionLabel
                .copyWith(color: FColors.onDarkMuted, fontSize: 10.5),
          ),
          const SizedBox(height: FSpace.md),
          Text(
            Fmt.moneyExact(widget.user.walletBalance),
            style: FType.displayLg.copyWith(
                color: Colors.white, fontSize: 30, fontFamily: FType.sans),
          ),
          const SizedBox(height: FSpace.x2),
          Row(
            children: <Widget>[
              Expanded(
                child: FButton(
                  label: 'Withdraw',
                  variant: FButtonVariant.teal,
                  busy: _busy,
                  padding: const EdgeInsets.all(11),
                  fontSize: 12.5,
                  onPressed: _withdraw,
                ),
              ),
              const SizedBox(width: FSpace.lg),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: FColors.fillOnDark,
                    borderRadius: FRadius.buttonR,
                    border: Border.all(color: FColors.borderOnDark),
                  ),
                  child: FButton(
                    label: 'Add Funds',
                    variant: FButtonVariant.secondary,
                    busy: _busy,
                    padding: const EdgeInsets.all(11),
                    fontSize: 12.5,
                    onPressed: _addFunds,
                  ),
                ),
              ),
            ],
          ),
          if (_pendingTopUp != null) ...<Widget>[
            const SizedBox(height: FSpace.lg),
            FButton.compact(
              label: 'Confirm top-up',
              variant: FButtonVariant.teal,
              busy: _busy,
              onPressed: _confirmTopUp,
            ),
          ],
        ],
      ),
    );
  }
}

Future<int?> _promptAmount(BuildContext context,
    {required String title}) async {
  final TextEditingController controller = TextEditingController();
  final int? result = await showDialog<int>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title, style: FType.titleMd),
      content: FField(
        controller: controller,
        hint: 'Amount in USD',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        autofocus: true,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('Cancel',
              style: FType.buttonSm
                  .copyWith(fontSize: 13, color: FColors.inkMuted)),
        ),
        TextButton(
          onPressed: () {
            final double? v = double.tryParse(controller.text.trim());
            if (v == null || v <= 0) return;
            Navigator.of(ctx).pop((v * 100).round());
          },
          child: Text('Continue',
              style: FType.buttonSm
                  .copyWith(fontSize: 13, color: FColors.tealDeep)),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

class _VaultCard extends StatelessWidget {
  const _VaultCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final bool locked = user.vaultLocked;
    final bool isTrustBond = user.role.requiresProfilePhoto;

    return FCard(
      radius: FRadius.cardLg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                isTrustBond ? 'Trust Fund Vault' : 'Job Posting Balance',
                style: FType.titleXs,
              ),
              locked
                  ? FPill.amber(isTrustBond ? 'Locked' : 'Active')
                  : FPill.teal('Withdrawable'),
            ],
          ),
          const SizedBox(height: FSpace.sm),
          Text(
            Fmt.moneyExact(user.role.depositAmount),
            style: FType.titleLg
                .copyWith(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: FSpace.sm),
          Text(user.role.depositExplanation, style: FType.support),
        ],
      ),
    );
  }
}

class _PayoutMethods extends StatelessWidget {
  const _PayoutMethods({required this.selected, required this.onChanged});

  final PayoutMethod selected;
  final ValueChanged<PayoutMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final PayoutMethod m in PayoutMethod.values)
              FChoiceChip(
                label: m.label,
                selected: selected == m,
                onTap: () => onChanged(m),
              ),
          ],
        ),
        const SizedBox(height: FSpace.md),
        Text(
          'Maintenance fee on this rail: ${Fees.label(selected)}',
          style: FType.captionSm.copyWith(fontSize: 10.5),
        ),
      ],
    );
  }
}

class _Transactions extends StatelessWidget {
  const _Transactions({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WalletTransaction>>(
      stream: context.walletRepo.watchTransactions(uid),
      builder:
          (BuildContext context, AsyncSnapshot<List<WalletTransaction>> snap) {
        if (!snap.hasData) return const FLoading();
        final List<WalletTransaction> items = snap.data!;
        if (items.isEmpty) {
          return const FEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No activity yet',
            message: 'Escrow releases, fees and withdrawals will show up here.',
          );
        }
        return Column(
          children: <Widget>[
            for (final WalletTransaction t in items) ...<Widget>[
              FCard(
                radius: FRadius.row,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(t.label,
                              style: FType.bodyXs.copyWith(fontSize: 12.5)),
                          const SizedBox(height: 1),
                          Text(Fmt.relative(t.createdAt),
                              style: FType.captionSm),
                        ],
                      ),
                    ),
                    Text(
                      Fmt.signedMoney(t.amount),
                      style: FType.pill.copyWith(
                        fontSize: 12.5,
                        color: t.isCredit ? FColors.teal : FColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FSpace.md),
            ],
          ],
        );
      },
    );
  }
}

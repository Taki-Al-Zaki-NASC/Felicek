import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/message.dart';

/// One message row. Mine sit right in ink; theirs sit left on white with a
/// hairline border — exactly the shape the design specifies, with the
/// receipt, timestamp and edit affordances a real messenger needs layered on.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.status,
    required this.showTail,
    this.onRetry,
    this.onDiscard,
    this.onLongPress,
    this.onOfferResponse,
  });

  final Message message;
  final bool isMine;
  final MessageStatus status;

  /// False when the previous bubble is from the same sender — consecutive
  /// messages group into one visual block.
  final bool showTail;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;
  final VoidCallback? onLongPress;
  final void Function(bool accept)? onOfferResponse;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) return _SystemLine(text: message.text);

    final bool failed = status == MessageStatus.failed;
    final Color bubbleColor = isMine ? FColors.inkStrong : FColors.surface;
    final Color textColor = isMine ? FColors.canvas : FColors.ink;

    return Padding(
      padding: EdgeInsets.only(top: showTail ? FSpace.lg : 3),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: <Widget>[
              Flexible(
                child: GestureDetector(
                  onLongPress: onLongPress,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.75,
                    ),
                    padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
                    decoration: BoxDecoration(
                      color: failed ? FColors.dangerTint : bubbleColor,
                      border: isMine && !failed
                          ? null
                          : Border.all(
                              color: failed ? FColors.danger : FColors.border,
                            ),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(FRadius.card),
                        topRight: const Radius.circular(FRadius.card),
                        bottomLeft: Radius.circular(
                          isMine || !showTail ? FRadius.card : 4,
                        ),
                        bottomRight: Radius.circular(
                          !isMine || !showTail ? FRadius.card : 4,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (message.quote != null)
                          _Quote(
                              quote: message.quote!, onDark: isMine && !failed),
                        if (message.offer != null && !message.isDeleted)
                          _OfferCard(
                            offer: message.offer!,
                            onDark: isMine && !failed,
                            canRespond: !isMine && message.offer!.pending,
                            onRespond: onOfferResponse,
                          )
                        else
                          Text(
                            message.displayText,
                            style: FType.bodyXs.copyWith(
                              color: failed
                                  ? FColors.danger
                                  : message.isDeleted
                                      ? (isMine
                                          ? FColors.onDarkMuted
                                          : FColors.inkFaint)
                                      : textColor,
                              fontStyle: message.isDeleted
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        const SizedBox(height: 3),
                        _MetaLine(
                          message: message,
                          isMine: isMine,
                          status: status,
                          onDark: isMine && !failed,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (failed) ...<Widget>[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text('Not sent',
                    style: FType.captionSm.copyWith(color: FColors.danger)),
                const SizedBox(width: FSpace.md),
                if (onRetry != null)
                  _MiniAction(
                      label: 'Retry', color: FColors.tealDeep, onTap: onRetry!),
                if (onDiscard != null) ...<Widget>[
                  const SizedBox(width: FSpace.lg),
                  _MiniAction(
                      label: 'Discard',
                      color: FColors.inkFaint,
                      onTap: onDiscard!),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.message,
    required this.isMine,
    required this.status,
    required this.onDark,
  });

  final Message message;
  final bool isMine;
  final MessageStatus status;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final Color color = onDark ? FColors.onDarkMuted : FColors.inkFaint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (message.isEdited) ...<Widget>[
          Text('edited',
              style: FType.captionSm.copyWith(fontSize: 9, color: color)),
          const SizedBox(width: 5),
        ],
        Text(
          Fmt.clock(message.orderedAt),
          style: FType.captionSm.copyWith(fontSize: 9.5, color: color),
        ),
        if (isMine) ...<Widget>[
          const SizedBox(width: 4),
          _Receipt(status: status, onDark: onDark),
        ],
      ],
    );
  }
}

/// The tick states: a clock while queued, one tick sent, two ticks delivered,
/// two teal ticks read.
class _Receipt extends StatelessWidget {
  const _Receipt({required this.status, required this.onDark});

  final MessageStatus status;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final Color base = onDark ? FColors.onDarkMuted : FColors.inkFaint;
    return switch (status) {
      MessageStatus.sending =>
        Icon(Icons.schedule_rounded, size: 11, color: base),
      MessageStatus.failed => const Icon(Icons.error_outline_rounded,
          size: 11, color: FColors.danger),
      MessageStatus.sent => Icon(Icons.check_rounded, size: 12, color: base),
      MessageStatus.delivered =>
        Icon(Icons.done_all_rounded, size: 12, color: base),
      MessageStatus.read => const Icon(
          Icons.done_all_rounded,
          size: 12,
          color: FColors.accentOnDark,
        ),
    };
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.quote, required this.onDark});

  final MessageQuote quote;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: onDark ? FColors.fillOnDark : FColors.neutralTint,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        border: Border(
          left: BorderSide(
            color: onDark ? FColors.accentOnDark : FColors.teal,
            width: 2.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            quote.senderName,
            style: FType.captionSm.copyWith(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: onDark ? FColors.accentOnDark : FColors.tealDeep,
            ),
          ),
          Text(
            quote.preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: FType.captionSm.copyWith(
              fontSize: 10.5,
              color: onDark ? FColors.onDarkMuted : FColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.onDark,
    required this.canRespond,
    this.onRespond,
  });

  final MessageOffer offer;
  final bool onDark;
  final bool canRespond;
  final void Function(bool accept)? onRespond;

  @override
  Widget build(BuildContext context) {
    final Color label = onDark ? FColors.onDarkMuted : FColors.inkMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'MILESTONE OFFER',
          style: FType.captionSm.copyWith(
            fontSize: 9,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
            color: onDark ? FColors.accentOnDark : FColors.violet,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          Fmt.money(offer.amount),
          style: FType.titleLg.copyWith(
            fontSize: 19,
            color: onDark ? Colors.white : FColors.ink,
          ),
        ),
        if (offer.milestone.isNotEmpty)
          Text(
            offer.milestone,
            style: FType.captionSm.copyWith(fontSize: 11, color: label),
          ),
        if (offer.accepted || offer.declined) ...<Widget>[
          const SizedBox(height: 5),
          Text(
            offer.accepted ? 'Accepted' : 'Declined',
            style: FType.pill.copyWith(
              fontSize: 10,
              color: offer.accepted
                  ? (onDark ? FColors.accentOnDark : FColors.teal)
                  : FColors.danger,
            ),
          ),
        ],
        if (canRespond && onRespond != null) ...<Widget>[
          const SizedBox(height: FSpace.md),
          Row(
            children: <Widget>[
              _MiniAction(
                label: 'Accept',
                color: FColors.teal,
                onTap: () => onRespond!(true),
              ),
              const SizedBox(width: FSpace.x2),
              _MiniAction(
                label: 'Decline',
                color: FColors.inkFaint,
                onTap: () => onRespond!(false),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction(
      {required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: FType.pill.copyWith(fontSize: 11, color: color),
        ),
      ),
    );
  }
}

/// Centred event line ("Proposal submitted · $430").
class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FSpace.lg),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: FColors.neutralTint,
            borderRadius: BorderRadius.circular(FRadius.chip),
            border: Border.all(color: FColors.borderFaint),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: FType.captionSm
                .copyWith(fontSize: 10.5, color: FColors.inkMuted),
          ),
        ),
      ),
    );
  }
}

/// The "Today" / "Yesterday" separator.
class MessageDayDivider extends StatelessWidget {
  const MessageDayDivider({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FSpace.x2),
      child: Center(
        child: Text(
          Fmt.dayHeader(date),
          style: FType.captionSm.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: FColors.inkFaint,
          ),
        ),
      ),
    );
  }
}

/// The three-dot "typing…" pill.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, required this.name});

  final String name;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: FSpace.md),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: FColors.surface,
              border: Border.all(color: FColors.border),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(FRadius.card),
                topRight: Radius.circular(FRadius.card),
                bottomRight: Radius.circular(FRadius.card),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(3, (int i) {
                  final double t =
                      ((_controller.value * 3) - i).clamp(0.0, 1.0);
                  final double lift = (t < 0.5 ? t : 1 - t) * 2;
                  return Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
                    child: Transform.translate(
                      offset: Offset(0, -lift * 3),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: FColors.inkFaint
                              .withValues(alpha: 0.5 + lift * 0.5),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(width: FSpace.md),
          Text(
            '${widget.name.split(' ').first} is typing…',
            style:
                FType.captionSm.copyWith(fontSize: 10, color: FColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

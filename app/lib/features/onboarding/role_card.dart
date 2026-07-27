import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../data/models/user_role.dart';

/// The selectable account-type card from onboarding and "Switch Account Type".
///
/// Selected: `background:#eaf6f4` with a teal hairline and a filled dot.
/// Unselected: white with the standard border and a hollow ring.
class RoleCard extends StatelessWidget {
  const RoleCard({
    super.key,
    required this.role,
    required this.selected,
    required this.onTap,
    this.titleSize = 13.5,
  });

  final UserRole role;
  final bool selected;
  final VoidCallback onTap;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? FColors.tealTint : FColors.surface,
        borderRadius: FRadius.buttonR,
        child: InkWell(
          onTap: onTap,
          borderRadius: FRadius.buttonR,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: FRadius.buttonR,
              border: Border.all(
                color: selected
                    ? FColors.teal.withValues(alpha: 0.4)
                    : FColors.border,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          role.label,
                          style: FType.titleXs.copyWith(fontSize: titleSize),
                        ),
                        const SizedBox(height: FSpace.xxs),
                        Text(
                          role.description,
                          style: FType.captionSm.copyWith(
                            fontSize: 10.5,
                            color: FColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: FSpace.xl),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? FColors.teal : Colors.transparent,
                      border: selected
                          ? null
                          : Border.all(color: FColors.radioRing, width: 2),
                    ),
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

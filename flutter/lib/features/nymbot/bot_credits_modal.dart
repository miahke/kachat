// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter/material.dart';

import '../../core/theme/nym_colors.dart';
import '../payments/payment_notice.dart';
import 'nymbot_models.dart';

/// Purchase/gift UI removed; old routes show only a local explanation.
class BotCreditsModal extends StatelessWidget {
  const BotCreditsModal({
    super.key,
    required this.colors,
    this.giftRecipientPubkey,
    this.giftRecipientNym,
    this.initialTier = CreditTier.standard,
  });
  final NymColors colors;
  final String? giftRecipientPubkey, giftRecipientNym;
  final CreditTier initialTier;
  static Future<void> show(
    BuildContext context, {
    required NymColors colors,
    String? giftRecipientPubkey,
    String? giftRecipientNym,
    CreditTier initialTier = CreditTier.standard,
  }) => showPaymentsDisabled(context);
  @override
  Widget build(BuildContext context) => const PaymentDisabledNotice();
}

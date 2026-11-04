// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import 'payment_policy.dart';

class PaymentDisabledNotice extends StatelessWidget {
  const PaymentDisabledNotice({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(compact ? 6 : 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      tr(kPaymentsDisabled),
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

Future<void> showPaymentsDisabled(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(tr(kPaymentsDisabledTitle)),
    content: const PaymentDisabledNotice(),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Close')),
      ),
    ],
  ),
);

/// No persisted consent: each entry and payment action requires an explicit tap.
Future<bool> confirmPaymentRisk(BuildContext context, {String? detail}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Payment safety')),
        content: SingleChildScrollView(
          child: Text(
            '${tr(kPaymentRisk)}${detail == null ? '' : '\n\n$detail'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            key: const ValueKey('payment-risk-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('I understand, continue')),
          ),
        ],
      ),
    ) ??
    false;

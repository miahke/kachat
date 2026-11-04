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

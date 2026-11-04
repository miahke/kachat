// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter/material.dart';

import '../payments/payment_notice.dart';

/// Old call sites can only show the local notice; no invoice or wallet can open.
class ZapModal {
  static Future<void> show(
    BuildContext context, {
    required String recipientPubkey,
    required String recipientNym,
    required String lightningAddress,
    String? messageId,
    String? originalKind,
  }) => showPaymentsDisabled(context);
}

// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter/material.dart';

import '../payments/payment_notice.dart';
import 'shop_models.dart';

/// Compatibility entry for old saved routes; the commerce UI has been removed.
class ShopModal extends StatelessWidget {
  const ShopModal({super.key, this.initialTab = ShopTab.styles});
  final ShopTab initialTab;
  static Future<void> open(
    BuildContext context, {
    ShopTab tab = ShopTab.styles,
  }) => showPaymentsDisabled(context);
  @override
  Widget build(BuildContext context) => const PaymentDisabledNotice();
}

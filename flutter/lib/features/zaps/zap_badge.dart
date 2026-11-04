// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_state.dart';

import '../../models/message.dart';
import '../payments/payment_notice.dart';

/// Incoming receipts remain recognizable, without a quick-pay button or popup.
class ZapBadge extends ConsumerWidget {
  const ZapBadge({super.key, required this.message});
  final Message message;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(zapsProvider)[message.id];
    if (receipt == null || receipt.totalSats <= 0) {
      return const SizedBox.shrink();
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: const PaymentDisabledNotice(compact: true),
    );
  }
}

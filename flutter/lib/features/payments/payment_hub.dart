// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter/material.dart';

import '../../core/crypto/key_format.dart' show normalizePubkeyInput;
import '../../core/theme/nym_colors.dart';
import '../i18n/i18n.dart';
import '../nymbot/bot_credits_modal.dart';
import '../shop/shop_modal.dart';
import '../zaps/zap_modal.dart';
import 'payment_notice.dart';
import 'payment_policy.dart';

/// The single commerce entry point, appended after all About content.
class InformationPayments extends StatelessWidget {
  const InformationPayments({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('information-payments-end'),
    padding: const EdgeInsets.only(top: 24, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Text(
          tr(kPaymentsDisabledTitle),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(tr(kPaymentRisk), style: Theme.of(context).textTheme.bodySmall),
        TextButton(
          key: const ValueKey('information-open-shop'),
          onPressed: () => ShopModal.open(context, fromInformation: true),
          child: Text(tr('Open store')),
        ),
        TextButton(
          onPressed: () => BotCreditsModal.show(
            context,
            colors: context.nym,
            fromInformation: true,
          ),
          child: Text(tr('Nymbot credits')),
        ),
        TextButton(
          onPressed: () => _zapRecipient(context),
          child: Text(tr('Send a Lightning payment')),
        ),
      ],
    ),
  );

  Future<void> _zapRecipient(BuildContext context) async {
    if (!await confirmPaymentRisk(context) || !context.mounted) return;
    final recipient = await showDialog<({String pubkey, String address})>(
      context: context,
      builder: (_) => const _RecipientDialog(),
    );
    if (recipient == null || !context.mounted) return;
    await ZapModal.show(
      context,
      recipientPubkey: recipient.pubkey,
      recipientNym: recipient.pubkey,
      lightningAddress: recipient.address,
      fromInformation: true,
    );
  }
}

class _RecipientDialog extends StatefulWidget {
  const _RecipientDialog();
  @override
  State<_RecipientDialog> createState() => _RecipientDialogState();
}

class _RecipientDialogState extends State<_RecipientDialog> {
  final _pubkey = TextEditingController();
  final _address = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _pubkey.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Payment recipient')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr(
              'Verify the public key and Lightning address with the recipient through a trusted channel.',
            ),
          ),
          TextField(
            controller: _pubkey,
            decoration: InputDecoration(
              labelText: tr('Recipient public key (npub or hex)'),
            ),
          ),
          TextField(
            controller: _address,
            decoration: InputDecoration(labelText: tr('Lightning address')),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      TextButton(
        onPressed: () {
          final key = normalizePubkeyInput(_pubkey.text.trim());
          final address = _address.text.trim();
          if (key == null ||
              key.isEmpty ||
              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
            setState(
              () => _error = tr(
                'Enter a valid public key and Lightning address.',
              ),
            );
            return;
          }
          Navigator.pop(context, (pubkey: key, address: address));
        },
        child: Text(tr('Continue')),
      ),
    ],
  );
}

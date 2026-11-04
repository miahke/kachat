// SPDX-License-Identifier: AGPL-3.0-only
/// Retained names for chat call sites: payment entry belongs to Information.
const kPaymentsDisabled =
    'Payments and the store are at the very end of Information (i). Verify the recipient, amount and invoice independently. Transfers may be irreversible; kachat cannot guarantee a counterparty or refund a payment.';
const kPaymentsDisabledTitle = 'Payments and store';
const kPaymentRisk =
    'Verify the recipient, amount and invoice independently before continuing. Transfers may be irreversible. kachat cannot guarantee delivery, a counterparty or a refund. Never share your private key or recovery codes.';

/// Chat bot commerce commands cannot bypass the information screen entry.
class PaymentsDisabledException implements Exception {
  const PaymentsDisabledException();
  @override
  String toString() => 'Open payments from Information (i).';
}

/// Match encoded payment payloads, not ordinary discussion of money/Bitcoin.
final _paymentPayload = RegExp(
  r'(?:\b(?:lightning|bitcoin|ethereum|solana):[^\s<>]+|\bton://transfer[^\s<>]*|\b(?:lnbc|lntb|lnbcrt)[0-9a-z]{20,}|\blnurl1[0-9a-z]{20,}|\bcashu[AB][0-9A-Za-z_\-+=/]{16,}|\bcreqA[0-9A-Za-z_\-+=/]{16,})',
  caseSensitive: false,
);
bool hasPaymentPayload(String text) => _paymentPayload.hasMatch(text);

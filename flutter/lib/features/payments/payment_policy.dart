// SPDX-License-Identifier: AGPL-3.0-only
/// kachat has no payment, invoice, wallet or purchase execution surface.
const kPaymentsDisabled =
    'Payments are disabled in kachat. The app does not verify recipients or guarantee transfer safety.';
const kPaymentsDisabledTitle = 'Payments disabled';

class PaymentsDisabledException implements Exception {
  const PaymentsDisabledException();
  @override
  String toString() => 'PaymentsDisabledException';
}

void rejectPaymentAction(String action) {
  if ((action.startsWith('shop-') &&
          !const {
            'shop-status',
            'shop-get',
            'shop-set-active',
          }.contains(action)) ||
      const {
        'create-invoice',
        'check-invoice',
        'claim-credits',
        'transfer-credits',
        'zap-verify',
      }.contains(action)) {
    throw const PaymentsDisabledException();
  }
}

/// Match encoded payment payloads, not ordinary discussion of money/Bitcoin.
final _paymentPayload = RegExp(
  r'(?:\b(?:lightning|bitcoin|ethereum|solana):[^\s<>]+|\bton://transfer[^\s<>]*|\b(?:lnbc|lntb|lnbcrt)[0-9a-z]{20,}|\blnurl1[0-9a-z]{20,}|\bcashu[AB][0-9A-Za-z_\-+=/]{16,}|\bcreqA[0-9A-Za-z_\-+=/]{16,})',
  caseSensitive: false,
);
bool hasPaymentPayload(String text) => _paymentPayload.hasMatch(text);

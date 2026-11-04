import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nym_bar/features/payments/payment_policy.dart';
import 'package:nym_bar/services/api/api_client.dart';
import 'package:nym_bar/features/nymbot/nymbot_service.dart';
import 'package:nym_bar/features/nymbot/nymbot_models.dart';

void main() {
  test(
    'restored credits invoice uses shared socket and preserves recipient',
    () async {
      final service = NymbotService(
        client: MockClient((_) async => throw StateError('HTTP not expected')),
      );
      String? seen;
      Map<String, dynamic>? payload;
      service.setApiSocketRequest((action, extra, {timeout}) async {
        seen = action;
        payload = extra;
        return (
          status: 200,
          data: <String, dynamic>{'invoiceId': 'synthetic', 'pr': 'synthetic'},
        );
      });
      await service.buy(
        amountSats: 21,
        tier: CreditTier.standard,
        pubkey: 'synthetic',
        recipientPubkey: 'recipient',
      );
      expect(seen, 'create-invoice');
      expect(payload?['amountSats'], 21);
      expect(payload?['recipientPubkey'], 'recipient');
    },
  );
  test('shop and settlement actions reach injected transport', () async {
    final actions = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.queryParameters['action'] == 'zap-verify') {
          actions.add('zap-verify');
        } else {
          actions.add(jsonDecode(request.body)['action'] as String);
        }
        return http.Response('{"paid":true}', 200);
      }),
    );
    addTearDown(api.dispose);
    await api.storageAction({'action': 'shop-buy-invoice'}, socket: false);
    await api.botAction({'action': 'create-invoice'});
    expect(await api.zapVerify(pr: 'synthetic'), true);
    expect(actions, ['shop-buy-invoice', 'create-invoice', 'zap-verify']);
  });
  test('payment payloads are recognized without censoring normal chat', () {
    expect(hasPaymentPayload('hello, Bitcoin is a topic'), false);
    expect(
      hasPaymentPayload('lightning:lnbc1syntheticpayload1234567890'),
      true,
    );
    expect(hasPaymentPayload('cashuAabcdefghijklmnopqrstuvwx'), true);
    expect(hasPaymentPayload('bitcoin:bc1synthetic'), true);
    expect(hasPaymentPayload('https://example.invalid/image.png'), false);
  });
}

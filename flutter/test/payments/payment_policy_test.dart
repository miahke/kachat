import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nym_bar/features/payments/payment_policy.dart';
import 'package:nym_bar/services/api/api_client.dart';
import 'package:nym_bar/features/nymbot/nymbot_service.dart';
import 'package:nym_bar/features/nymbot/nymbot_models.dart';

void main() {
  test('credit purchases cannot bypass the barrier through a shared WebSocket or signer', () async {
    var requests=0, socket=0, signed=0;
    final service=NymbotService(client:MockClient((r)async{requests++;return http.Response('{}',200);}));
    service.setApiSocketRequest((action,extra,{timeout})async {socket++;return (status:200,data:<String,dynamic>{});});
    await expectLater(service.buy(amountSats:21,tier:CreditTier.standard,pubkey:'synthetic',auth:()async{signed++;return {}; }),throwsA(isA<PaymentsDisabledException>()));
    expect(requests,0);expect(socket,0);expect(signed,0);
  });
  test(
    'commerce actions fail before any transport or wallet request',
    () async {
      var requests = 0;
      final api = ApiClient(
        client: MockClient((r) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.dispose);
      for (final action in [
        'shop-buy-invoice',
        'shop-claim',
        'shop-transfer',
        'shop-redeem',
        'shop-supply',
      ]) {
        await expectLater(
          api.storageAction({'action': action}),
          throwsA(isA<PaymentsDisabledException>()),
        );
      }
      for (final action in [
        'create-invoice',
        'check-invoice',
        'claim-credits',
        'transfer-credits',
      ]) {
        await expectLater(
          api.botAction({'action': action}),
          throwsA(isA<PaymentsDisabledException>()),
        );
      }
      expect(await api.zapVerify(pr:'synthetic'),false);
      expect(requests, 0);
    },
  );
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

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nym_bar/features/zaps/lnurl.dart';
import 'package:nym_bar/services/api/api_client.dart';

void main() {
  const params = LnurlPayParams(
    callback: 'https://wallet.invalid/callback',
    minSendable: 1000,
    maxSendable: 100000,
  );
  test(
    'LNURL callback requests sats as millisats through injected configured API',
    () async {
      final calls = <Uri>[];
      final api = ApiClient(
        baseUrl: '',
        client: MockClient((request) async {
          calls.add(request.url);
          return http.Response('{"pr":"lnbc210n1synthetic"}', 200);
        }),
      );
      addTearDown(api.dispose);
      final invoice = await Lnurl.fetchInvoice(
        params: params,
        amountSats: 21,
        api: api,
      );
      expect(invoice.amountSats, 21);
      expect(calls.single.queryParameters['amount'], '21000');
    },
  );
  test(
    'LNURL rejects mismatched invoice amount and unsupported limits',
    () async {
      var calls = 0;
      final api = ApiClient(
        baseUrl: '',
        client: MockClient((_) async {
          calls++;
          return http.Response('{"pr":"lnbc100n1synthetic"}', 200);
        }),
      );
      addTearDown(api.dispose);
      await expectLater(
        Lnurl.fetchInvoice(params: params, amountSats: 21, api: api),
        throwsA(isA<LnurlException>()),
      );
      await expectLater(
        Lnurl.fetchInvoice(params: params, amountSats: 101, api: api),
        throwsA(isA<LnurlException>()),
      );
      expect(calls, 1);
    },
  );
}

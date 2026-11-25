import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../services/api/api_config.dart';
import '../qwdtt/qwdtt_controller.dart';

Uri? directImageTarget(String url) {
  final proxy = Uri.tryParse(url);
  final endpoint = Uri.parse(ApiConfig.proxyBaseUrl());
  if (proxy == null ||
      proxy.scheme != endpoint.scheme ||
      proxy.host != endpoint.host ||
      proxy.port != endpoint.port ||
      proxy.path != endpoint.path ||
      proxy.userInfo.isNotEmpty ||
      proxy.hasFragment ||
      proxy.queryParametersAll['url']?.length != 1 ||
      proxy.queryParametersAll.keys.any(
        (k) => k != 'url' && k != 'emoji' && k != '_r',
      )) {
    return null;
  }
  final target = Uri.tryParse(proxy.queryParameters['url']!);
  return _https(target) ? target : null;
}

bool _https(Uri? uri) =>
    uri != null &&
    uri.scheme == 'https' &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;

/// A request-scoped route lease prevents cache misses from crossing route changes.
class RoutedImageFileService extends FileService {
  RoutedImageFileService({QwdttController? controller, this.headersFor})
    : _controller = controller ?? QwdttController.instance;
  static const maximumBytes = 20 * 1024 * 1024;
  final QwdttController _controller;
  final Map<String, String> Function(String)? headersFor;
  final HttpFileService _fallback = HttpFileService();

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    if (!_controller.supported) {
      final response = await _fallback
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 12));
      if ((response.contentLength ?? 0) > maximumBytes) {
        throw const HttpException('Image too large');
      }
      return _BoundedResponse(response);
    }
    final session = _controller.beginMediaSession();
    if (session == null) throw StateError('Media route unavailable');
    try {
      var uri = Uri.parse(url);
      var permitSensitive = true;
      if (session.direct) {
        final target = directImageTarget(url);
        if (target != null) {
          uri = target;
          permitSensitive = false;
        }
      } else if (uri.host != ApiConfig.apiHost &&
          !ApiConfig.isOwnHost(uri.host)) {
        uri = Uri.parse(ApiConfig.proxyBaseUrl())
            .replace(queryParameters: {'url': url});
      }
      if (!_https(uri)) throw const FormatException('HTTPS media required');
      final client = IOClient(session.createClient());
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (!session.valid) throw StateError('Media route changed');
        final request = http.Request('GET', uri)..followRedirects = false;
        request.headers.addAll(headers ?? const {});
        request.headers.addAll(headersFor?.call(uri.toString()) ?? const {});
        if (!permitSensitive) {
          request.headers.removeWhere(
            (key, _) => const {
              'authorization',
              'cookie',
              'proxy-authorization',
              'proxy-authenticate',
              'www-authenticate',
            }.contains(key.toLowerCase()),
          );
        }
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 20));
        if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers['location'];
          if (location == null || redirects == 5) {
            throw const HttpException('Invalid image redirect');
          }
          final next = uri.resolve(location);
          if (!_https(next) ||
              (!session.direct &&
                  (next.host != uri.host || next.port != uri.port))) {
            throw const HttpException('Unsafe image redirect');
          }
          var redirectBytes = 0;
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 10),
          )) {
            redirectBytes += chunk.length;
            if (redirectBytes > maximumBytes) {
              throw const HttpException('Image redirect too large');
            }
          }
          if (next.host != uri.host ||
              next.port != uri.port ||
              next.scheme != uri.scheme) {
            permitSensitive = false;
          }
          uri = next;
          continue;
        }
        if (response.statusCode != 200 && response.statusCode != 202) {
          session.dispose();
          return HttpGetResponse(
            http.StreamedResponse(
              const Stream.empty(),
              response.statusCode,
              contentLength: response.contentLength,
              headers: response.headers,
              request: response.request,
              reasonPhrase: response.reasonPhrase,
            ),
          );
        }
        if ((response.contentLength ?? 0) > maximumBytes) {
          throw const HttpException('Image too large');
        }
        final unconsumed = Timer(const Duration(seconds: 30), session.dispose);
        Stream<List<int>> content() async* {
          unconsumed.cancel();
          var size = 0;
          try {
            await for (final chunk in response.stream.timeout(
              const Duration(seconds: 30),
            )) {
              size += chunk.length;
              if (size > maximumBytes) {
                throw const HttpException('Image too large');
              }
              yield chunk;
            }
          } finally {
            session.dispose();
          }
        }

        return HttpGetResponse(
          http.StreamedResponse(
            content(),
            response.statusCode,
            contentLength: response.contentLength,
            headers: response.headers,
            request: response.request,
            reasonPhrase: response.reasonPhrase,
          ),
        );
      }
      throw const HttpException('Too many image redirects');
    } catch (_) {
      session.dispose();
      rethrow;
    }
  }
}

class _BoundedResponse implements FileServiceResponse {
  _BoundedResponse(this._inner);
  final FileServiceResponse _inner;
  @override
  int get statusCode => _inner.statusCode;
  @override
  int? get contentLength => _inner.contentLength;
  @override
  DateTime get validTill => _inner.validTill;
  @override
  String? get eTag => _inner.eTag;
  @override
  String get fileExtension => _inner.fileExtension;
  @override
  Stream<List<int>> get content async* {
    var size = 0;
    await for (final chunk in _inner.content.timeout(
      const Duration(seconds: 30),
    )) {
      size += chunk.length;
      if (size > RoutedImageFileService.maximumBytes) {
        throw const HttpException('Image too large');
      }
      yield chunk;
    }
  }
}

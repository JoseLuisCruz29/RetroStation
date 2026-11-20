import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class HttpFetchException implements Exception {
  HttpFetchException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Descarga pequeña (metadatos, portadas, catálogos) con reintentos.
/// Las descargas de juegos usan el gestor de descargas, no esto.
Future<Uint8List> fetchBytes(
  Uri url, {
  int retries = 3,
  Duration timeout = const Duration(seconds: 30),
  int maxBytes = 16 * 1024 * 1024,
  Map<String, String> headers = const {},
}) async {
  Object? lastError;
  for (var attempt = 0; attempt <= retries; attempt++) {
    if (attempt > 0) await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'RetroStation/1.0');
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      if (response.statusCode == 404) {
        await response.drain<void>();
        throw HttpFetchException('No encontrado', statusCode: 404);
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpFetchException('HTTP ${response.statusCode}', statusCode: response.statusCode);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw HttpFetchException('Respuesta demasiado grande');
        }
      }
      return builder.takeBytes();
    } on HttpFetchException catch (e) {
      if (e.statusCode == 404) rethrow; // no tiene sentido reintentar
      lastError = e;
    } on SocketException catch (e) {
      lastError = e;
    } on TimeoutException catch (e) {
      lastError = e;
    } on HandshakeException catch (e) {
      lastError = e;
    } on HttpException catch (e) {
      lastError = e;
    } finally {
      client.close(force: true);
    }
  }
  throw HttpFetchException('Sin conexión con ${url.host}: $lastError');
}

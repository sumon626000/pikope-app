import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/env.dart';

/// Shared [http.Client] for API calls. Optional [Env.apiCertSha256] accepts
/// only that leaf certificate when the chain is not trusted (e.g. staging).
http.Client createApiHttpClient() {
  final httpClient = HttpClient();
  final pin = Env.apiCertSha256.trim().toLowerCase();
  if (pin.isNotEmpty) {
    final host = Uri.tryParse(Env.apiBaseUrl)?.host.toLowerCase() ?? '';
    httpClient.badCertificateCallback = (cert, h, port) {
      if (host.isEmpty || h.toLowerCase() != host) {
        return false;
      }
      return sha256.convert(cert.der).toString() == pin;
    };
  }
  return IOClient(httpClient);
}

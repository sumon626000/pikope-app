import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Browser fetch API — no certificate pinning (use HTTPS on the API host).
http.Client createApiHttpClient() => BrowserClient();

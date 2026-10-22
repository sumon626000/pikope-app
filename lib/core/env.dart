/// Build-time configuration, supplied with `--dart-define` (see .env.example).
/// Nothing secret belongs here: only public identifiers ship in the client.
class Env {
  static const cloudinaryCloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
  static const cloudinaryUploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');
  static const cloudinaryFolder =
      String.fromEnvironment('CLOUDINARY_FOLDER', defaultValue: 'billiard_poker');

  /// Base URL of the PHP backend, e.g. https://api.example.com (no trailing
  /// slash). Empty: the app runs offline only.
  ///
  /// Release APKs default to production so a build without `--dart-define-from-file`
  /// still reaches the live server. Override with `.env` or `--dart-define=API_BASE_URL=`
  /// for offline-only dev builds.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://adminnew.pikope.com',
  );

  /// Optional SHA-256 (hex) of the API TLS leaf certificate. Empty: default
  /// system trust only. Set only when you need to trust a custom/staging cert.
  static const apiCertSha256 = String.fromEnvironment('API_CERT_SHA256');

  /// WebSocket server for live play. Normally left empty: the app asks the
  /// backend (`GET /config`). Set it only to override that.
  static const wsUrl = String.fromEnvironment('WS_URL');

  static bool get hasBackend => apiBaseUrl.isNotEmpty;
  static bool get isDemo => !hasBackend;
}

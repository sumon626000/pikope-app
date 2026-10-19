import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'env.dart';

/// What gets stored (e.g. in Firestore) for an uploaded image.
class CloudinaryAsset {
  const CloudinaryAsset({
    required this.publicId,
    required this.secureUrl,
    this.width,
    this.height,
    this.format,
    this.bytes,
  });

  final String publicId;
  final String secureUrl;
  final int? width;
  final int? height;
  final String? format;
  final int? bytes;

  factory CloudinaryAsset.fromJson(Map<String, dynamic> j) => CloudinaryAsset(
        publicId: j['public_id'] as String,
        secureUrl: j['secure_url'] as String,
        width: j['width'] as int?,
        height: j['height'] as int?,
        format: j['format'] as String?,
        bytes: j['bytes'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'publicId': publicId,
        'secureUrl': secureUrl,
        'width': width,
        'height': height,
        'format': format,
        'bytes': bytes,
      };
}

class CloudinaryException implements Exception {
  CloudinaryException(this.message);
  final String message;
  @override
  String toString() => 'CloudinaryException: $message';
}

/// Single place that knows how Cloudinary URLs are built and how images are
/// uploaded. Uploads are unsigned (upload preset), so the API secret never
/// ships in the app.
class CloudinaryService {
  CloudinaryService({
    this.cloudName = Env.cloudinaryCloudName,
    this.uploadPreset = Env.cloudinaryUploadPreset,
    this.folder = Env.cloudinaryFolder,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String cloudName;
  final String uploadPreset;
  final String folder;
  final http.Client _client;

  bool get isConfigured => cloudName.isNotEmpty;
  bool get canUpload => isConfigured && uploadPreset.isNotEmpty;

  /// Delivery URL for [publicId] with an on-the-fly transformation.
  String imageUrl(String publicId, {int? width, int? height, String crop = 'fill'}) {
    final t = [
      'f_auto',
      'q_auto',
      if (width != null) 'w_$width',
      if (height != null) 'h_$height',
      if (width != null || height != null) 'c_$crop',
    ].join(',');
    return 'https://res.cloudinary.com/$cloudName/image/upload/$t/$publicId';
  }

  Future<CloudinaryAsset> uploadImage(Uint8List bytes,
      {required String filename, String? subfolder}) async {
    if (!canUpload) throw CloudinaryException('Cloudinary is not configured');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
    )
      ..fields['upload_preset'] = uploadPreset
      ..fields['folder'] = subfolder == null ? folder : '$folder/$subfolder'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await http.Response.fromStream(await _client.send(request));
    if (response.statusCode != 200) {
      throw CloudinaryException('Upload failed (${response.statusCode}): ${response.body}');
    }
    return CloudinaryAsset.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:image/image.dart' as img;

class FaceCompareResult {
  final bool matched;
  final double? score;
  final String? error;
  const FaceCompareResult({required this.matched, this.score, this.error});
}

class FaceCompareService {
  static const _apiUrl =
      'https://cloudapim.kiya.ai/apimgateway/1/FaceChannel/FaceSG/v1/compare';

  /// Compress a base64 image to max 800px wide at 70% quality — matches Angular compressImage()
  static Future<String> _compress(String base64Input) async {
    try {
      // strip data URI prefix if present
      final raw = base64Input.contains(',')
          ? base64Input.split(',').last
          : base64Input;
      final bytes = base64Decode(raw);
      final decoded = await compute(_decodeAndResize, bytes);
      return base64Encode(decoded);
    } catch (_) {
      // if compression fails, return stripped raw
      return base64Input.contains(',')
          ? base64Input.split(',').last
          : base64Input;
    }
  }

  static Uint8List _decodeAndResize(Uint8List bytes) {
    var image = img.decodeImage(bytes);
    if (image == null) return bytes;
    if (image.width > 800) {
      image = img.copyResize(image, width: 800);
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 70));
  }

  Future<FaceCompareResult> compare(
      String photoBase64, String idImageBase64) async {
    final photo   = await _compress(photoBase64);
    final idImage = await _compress(idImageBase64);

    final body = jsonEncode({
      'photo_base64':    photo,
      'id_image_base64': idImage,
    });

    try {
      // Bypass SSL cert chain issues (self-signed / missing intermediate CA)
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final client = IOClient(httpClient);
      final res = await client
          .post(
            Uri.parse(_apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 60));
      client.close();

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return FaceCompareResult(
        matched: data['matched'] == true && data['success'] == true,
        score:   (data['match_score'] as num?)?.toDouble(),
        error:   data['error'] as String?,
      );
    } catch (e) {
      return FaceCompareResult(matched: false, error: e.toString());
    }
  }
}

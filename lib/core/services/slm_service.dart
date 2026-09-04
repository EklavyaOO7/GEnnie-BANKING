import 'package:flutter/services.dart';

const _blobBase = 'https://humanintheloop.blob.core.windows.net/models';
const _blobSas  = 'sp=r&st=2026-08-06T07:35:02Z&se=2027-08-06T15:50:02Z&spr=https&sv=2026-02-06&sr=c&sig=myq3er5LPAGQmjXHZV9npv6p9D8wOyNRhGfPgQAorbE=';

class DownloadProgress {
  final String file;
  final int fileProgress;
  final int totalProgress;
  const DownloadProgress(this.file, this.fileProgress, this.totalProgress);
}

class SlmService {
  static final SlmService _instance = SlmService._();
  factory SlmService() => _instance;
  SlmService._();

  static const _channel = MethodChannel('com.kiya.bankinggenie/slm');

  bool _ready        = false;
  bool _initialising = false;
  bool _gemmaReady   = false;

  bool get isReady        => _ready;
  bool get isInitialising => _initialising;
  bool get isGemmaReady   => _gemmaReady;

  static const Map<String, String> modelUrls = {
    'all-MiniLM-L12-v2_quantized.onnx': '$_blobBase/all-MiniLM-L12-v2_quantized.onnx?$_blobSas',
    'vocab.txt':                         '$_blobBase/vocab.txt?$_blobSas',
    'gemma-4-E2B-it.litertlm':           '$_blobBase/gemma-4-E2B-it.litertlm?$_blobSas',
    'TB_Statement_meta.csv':             '$_blobBase/TB_Statement_meta.csv?$_blobSas',
  };

  Future<bool> checkModel() async {
    try {
      return await _channel.invokeMethod<bool>('checkModel') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> downloadModels(void Function(DownloadProgress) onProgress) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onProgress') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        onProgress(DownloadProgress(
          args['file'] as String,
          args['fileProgress'] as int,
          args['totalProgress'] as int,
        ));
      }
    });
    await _channel.invokeMethod('downloadModels', {'urls': modelUrls});
  }

  Future<void> init() async {
    if (_ready) return;
    _initialising = true;
    try {
      final res = await _channel.invokeMethod<Map>('init');
      _gemmaReady   = res?['gemmaReady'] as bool? ?? false;
      _ready        = true;
      _initialising = false;
    } catch (_) {
      _initialising = false;
      rethrow;
    }
  }

  Future<void> initSlm() async {
    try {
      await _channel.invokeMethod('initSlm');
    } catch (_) {}
  }

  Future<Map<String, dynamic>> querySlm(String question) async {
    try {
      final res = await _channel.invokeMethod<Map>('querySlm', question);
      if (res == null) return {'summary': '', 'chartImage': null, 'tableHtml': null};
      return Map<String, dynamic>.from(res);
    } catch (_) {
      rethrow;
    }
  }

  void closeSlm() {
    _channel.invokeMethod('closeSlm').catchError((_) {});
  }

  void resetInit() {
    _ready        = false;
    _initialising = false;
    _gemmaReady   = false;
  }

  // kept for home_page compatibility — no-op since chat/process removed
  void setSessionPayload(Map<String, dynamic> payload) {}
  void reset() {}
}

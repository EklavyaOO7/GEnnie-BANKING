import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

class RHConfig {
  String baseUrl;
  String botname;
  String groupOfficeName;
  String organisationName;
  String channeltype;
  String contexttype;
  String channelid;
  String display;
  String subdisplay;
  String sessionId;
  String ipaddress;

  RHConfig({
    required this.baseUrl,
    required this.botname,
    required this.groupOfficeName,
    required this.organisationName,
    required this.channeltype,
    required this.contexttype,
    required this.channelid,
    required this.display,
    required this.subdisplay,
    this.sessionId = '',
    this.ipaddress = '',
  });

  RHConfig copyWith({String? sessionId, String? channelid}) => RHConfig(
        baseUrl: baseUrl,
        botname: botname,
        groupOfficeName: groupOfficeName,
        organisationName: organisationName,
        channeltype: channeltype,
        contexttype: contexttype,
        channelid: channelid ?? this.channelid,
        display: display,
        subdisplay: subdisplay,
        sessionId: sessionId ?? this.sessionId,
        ipaddress: ipaddress,
      );
}

class RequestHandlerService {
  static const _passphrase = 'rmga@2018';
  static const _botInterface = '/botsUiService/requesthandler';

  static String genChannelId() {
    final rng = Random();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = rng.nextInt(999999999);
    return '$ts$rand';
  }

  String _toHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List _pbkdf2(String passphrase, Uint8List salt, int keyLen, int iterations) {
    final mac = HMac(SHA1Digest(), 64);
    final pbkdf2 = PBKDF2KeyDerivator(mac)
      ..init(Pbkdf2Parameters(salt, iterations, keyLen));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  String _encrypt(String text) {
    final rng = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    final iv = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    final key = _pbkdf2(_passphrase, salt, 16, 100);

    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), iv));

    // PKCS7 padding
    final input = Uint8List.fromList(utf8.encode(text));
    final padLen = 16 - (input.length % 16);
    final padded = Uint8List(input.length + padLen)
      ..setRange(0, input.length, input)
      ..fillRange(input.length, input.length + padLen, padLen);

    final output = Uint8List(padded.length);
    for (int i = 0; i < padded.length; i += 16) {
      cipher.processBlock(padded, i, output, i);
    }

    final saltHex = _toHex(salt);
    final ivHex = _toHex(iv);
    final encB64 = base64Encode(output);
    return '$saltHex~~~$ivHex~~~$encB64';
  }

  String _buildUrl(String userText, String msgType, String msgid,
      dynamic welcomeqr, RHConfig config) {
    final context = jsonEncode({
      'botname': config.botname,
      'channeltype': config.channeltype,
      'contextid': config.channelid,
      'groupOfficeName': config.groupOfficeName,
      'organizationName': config.organisationName,
      'contexttype': config.contexttype,
      'sessionId': config.sessionId,
    });
    final refmsgid = msgid == 'form' && !userText.startsWith('{') ? 'formText' : msgid;
    final message = jsonEncode({
      'referralParam': welcomeqr,
      'text': userText,
      'type': msgType,
      'refmsgid': refmsgid,
    });
    final sender = jsonEncode({
      'channelid': config.channelid,
      'channeltype': config.channeltype,
      'display': config.display,
      'subdisplay': config.subdisplay,
    });
    final configData = jsonEncode(
        {'lat': '0', 'lon': '0', 'ipaddress': config.ipaddress, 'profanity': ''});

    final raw = 'botname=${config.botname}'
        '&contextobj=${Uri.encodeComponent(context)}'
        '&messageobj=${Uri.encodeComponent(message)}'
        '&senderobj=${Uri.encodeComponent(sender)}'
        '&configobj=${Uri.encodeComponent(configData)}';

    final encrypted = _encrypt(raw);
    return '${config.baseUrl}$_botInterface?$encrypted';
  }

  Future<Map<String, dynamic>> call(String userText, String msgType,
      String msgid, dynamic welcomeqr, RHConfig config) async {
    final url = _buildUrl(userText, msgType, msgid, welcomeqr, config);
    final res = await http.get(Uri.parse(url));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchBotConfig(
      String botConfigUrl, String botname, String groupOfficeName, String organisationName) async {
    final url = '$botConfigUrl?name=${Uri.encodeComponent(botname)}'
        '&groupOfficeName=${Uri.encodeComponent(groupOfficeName)}'
        '&organisationName=${Uri.encodeComponent(organisationName)}';
    final res = await http.get(Uri.parse(url));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

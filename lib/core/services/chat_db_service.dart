import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _rng = Random.secure();

// ── Platform-adaptive chat storage ──────────────────────────────────────────
// Mobile  → SQLite + AES-GCM encryption via flutter_secure_storage key
// Web     → SharedPreferences (localStorage) — no encryption needed in browser
// ────────────────────────────────────────────────────────────────────────────

class ChatDbService {
  static final ChatDbService _instance = ChatDbService._();
  factory ChatDbService() => _instance;
  ChatDbService._();

  // Mobile
  Database? _db;
  Uint8List? _key;
  final _storage = const FlutterSecureStorage();

  // Web
  SharedPreferences? _prefs;

  bool get _isWeb => kIsWeb;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_isWeb) {
      _prefs ??= await SharedPreferences.getInstance();
      return;
    }
    if (_db != null) return;
    await _loadOrCreateKey();
    _db = await openDatabase(
      join(await getDatabasesPath(), 'mfx_chat.db'),
      version: 2,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE chat_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          from_role TEXT NOT NULL,
          message TEXT NOT NULL,
          file_name TEXT,
          created_at INTEGER NOT NULL
        )
      '''),
      onUpgrade: (db, oldV, newV) async {
        await db.execute('DROP TABLE IF EXISTS chat_messages');
        await db.execute('''
          CREATE TABLE chat_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            from_role TEXT NOT NULL,
            message TEXT NOT NULL,
            file_name TEXT,
            created_at INTEGER NOT NULL
          )
        ''');
        await _storage.delete(key: 'mfx_chat_key');
        await _loadOrCreateKey();
      },
    );
  }

  // ── Encryption (mobile only) ──────────────────────────────────────────────

  Future<void> _loadOrCreateKey() async {
    final stored = await _storage.read(key: 'mfx_chat_key');
    if (stored != null) {
      _key = base64Decode(stored);
    } else {
      final key = Uint8List.fromList(List.generate(32, (_) => _rng.nextInt(256)));
      _key = key;
      await _storage.write(key: 'mfx_chat_key', value: base64Encode(key));
    }
  }

  String _encrypt(String text) {
    final iv = Uint8List.fromList(List.generate(12, (_) => _rng.nextInt(256)));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(_key!), 128, iv, Uint8List(0)));
    final input = Uint8List.fromList(utf8.encode(text));
    final output = cipher.process(input);
    final combined = Uint8List(12 + output.length);
    combined.setRange(0, 12, iv);
    combined.setRange(12, combined.length, output);
    return base64Encode(combined);
  }

  String _decrypt(String b64) {
    final combined = base64Decode(b64);
    final iv = combined.sublist(0, 12);
    final data = combined.sublist(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(_key!), 128, iv, Uint8List(0)));
    return utf8.decode(cipher.process(data));
  }

  // ── Web helpers (SharedPreferences) ──────────────────────────────────────
  // Storage layout:
  //   'mfx_sessions'          → JSON list of session_id strings
  //   'mfx_session_<id>'      → JSON list of message objects

  List<String> _webGetSessionIds() {
    final raw = _prefs!.getString('mfx_sessions');
    if (raw == null) return [];
    return List<String>.from(jsonDecode(raw));
  }

  Future<void> _webSetSessionIds(List<String> ids) =>
      _prefs!.setString('mfx_sessions', jsonEncode(ids));

  List<Map<String, dynamic>> _webGetMessages(String sessionId) {
    final raw = _prefs!.getString('mfx_session_$sessionId');
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
  }

  Future<void> _webSetMessages(String sessionId, List<Map<String, dynamic>> msgs) =>
      _prefs!.setString('mfx_session_$sessionId', jsonEncode(msgs));

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> saveMessage(Map<String, dynamic> record) async {
    if (_db == null && _prefs == null) await init();

    if (_isWeb) {
      final sessionId = record['session_id'] as String;
      final msgs = _webGetMessages(sessionId);
      msgs.add({
        'session_id': sessionId,
        'from_role': record['from_role'],
        'message': record['message'],
        'file_name': record['file_name'],
        'created_at': record['created_at'],
      });
      await _webSetMessages(sessionId, msgs);
      // Register session if new
      final ids = _webGetSessionIds();
      if (!ids.contains(sessionId)) {
        ids.insert(0, sessionId);
        await _webSetSessionIds(ids);
      }
      return;
    }

    await _db!.insert('chat_messages', {
      'session_id': record['session_id'],
      'from_role': record['from_role'],
      'message': _encrypt(record['message']),
      'file_name': record['file_name'] != null ? _encrypt(record['file_name']) : null,
      'created_at': record['created_at'],
    });
  }

  Future<List<Map<String, dynamic>>> getSession(String sessionId) async {
    if (_db == null && _prefs == null) await init();

    if (_isWeb) {
      return _webGetMessages(sessionId);
    }

    final rows = await _db!.query('chat_messages',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'created_at ASC');
    return rows.map((r) {
      String msg = '...';
      String? file;
      try { msg = _decrypt(r['message'] as String); } catch (_) {}
      try { file = r['file_name'] != null ? _decrypt(r['file_name'] as String) : null; } catch (_) {}
      return {...r, 'message': msg, 'file_name': file};
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getAllSessions() async {
    if (_db == null && _prefs == null) await init();

    if (_isWeb) {
      final ids = _webGetSessionIds();
      return ids.map((id) {
        final msgs = _webGetMessages(id);
        final first = msgs.firstWhere(
            (m) => m['from_role'] == 'user',
            orElse: () => {'message': '...', 'created_at': 0});
        return {
          'session_id': id,
          'preview': first['message'] ?? '...',
          'created_at': first['created_at'] ?? 0,
        };
      }).toList();
    }

    final rows = await _db!.rawQuery('''
      SELECT session_id,
             MIN(created_at) AS created_at,
             MIN(message)    AS message
      FROM chat_messages
      WHERE from_role = 'user'
      GROUP BY session_id
      ORDER BY MIN(created_at) DESC
    ''');
    return rows.map((r) {
      String preview = '...';
      try { preview = _decrypt(r['message'] as String); } catch (_) {}
      return {'session_id': r['session_id'], 'preview': preview, 'created_at': r['created_at']};
    }).toList();
  }

  Future<void> insertTransfer(String recipient, double amount, {String transferType = 'Transfer'}) async {
    if (_isWeb || _db == null) return;
    try {
      final stmtRows = await _db!.rawQuery(
          'SELECT balance, account_no FROM TB_Statement ORDER BY id DESC LIMIT 1');
      if (stmtRows.isEmpty) return;
      final last = stmtRows.first;
      final newBalance = (last['balance'] as num).toDouble() - amount;
      final today = DateTime.now().toIso8601String().split('T')[0];
      final ref = '$transferType-TRF-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
      await _db!.insert('TB_Statement', {
        'txn_date': today,
        'value_date': today,
        'description': '$transferType to $recipient',
        'reference': ref,
        'type': 'DEBIT',
        'amount': amount,
        'balance': newBalance,
        'account_no': last['account_no'],
        'currency': 'INR',
      });
    } catch (_) {}
  }

  // ── 6-month statement: fetch CSV from blob, seed DB, return rows + raw CSV ──

  static const _blobBase = 'https://humanintheloop.blob.core.windows.net/models';
  static const _blobSas  = 'sp=r&st=2026-08-06T07:35:02Z&se=2027-08-06T15:50:02Z&spr=https&sv=2026-02-06&sr=c&sig=myq3er5LPAGQmjXHZV9npv6p9D8wOyNRhGfPgQAorbE=';

  Future<({List<Map<String, dynamic>> rows, String csv})> loadStatementFromBlob() async {
    if (_db == null) await init();
    final url = '$_blobBase/TB_Statement_6months.csv?$_blobSas';
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final csv = res.body;
    final lines = csv.trim().split('\n');
    final header = lines.first.split(',').map((h) => h.trim()).toList();
    final idx = {
      for (final col in ['txn_date','value_date','description','reference','type','amount','balance','account_no','currency'])
        col: header.indexOf(col)
    };
    if (!_isWeb && _db != null) {
      await _db!.execute('''
        CREATE TABLE IF NOT EXISTS TB_Statement (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          txn_date TEXT NOT NULL, value_date TEXT,
          description TEXT NOT NULL, reference TEXT,
          type TEXT NOT NULL, amount REAL NOT NULL,
          balance REAL NOT NULL, account_no TEXT NOT NULL,
          currency TEXT DEFAULT 'INR'
        )
      ''');
      await _db!.delete('TB_Statement');
      final batch = _db!.batch();
      for (final line in lines.skip(1)) {
        if (line.trim().isEmpty) continue;
        final v = line.split(',').map((c) => c.trim()).toList();
        if (v.length < header.length) continue;
        batch.rawInsert(
          'INSERT OR IGNORE INTO TB_Statement (txn_date,value_date,description,reference,type,amount,balance,account_no,currency) VALUES (?,?,?,?,?,?,?,?,?)',
          [
            v[idx['txn_date']!], v[idx['value_date']!], v[idx['description']!],
            v[idx['reference']!], v[idx['type']!].toUpperCase(),
            double.tryParse(v[idx['amount']!]) ?? 0.0,
            double.tryParse(v[idx['balance']!]) ?? 0.0,
            v[idx['account_no']!],
            v[idx['currency']!].isEmpty ? 'INR' : v[idx['currency']!],
          ],
        );
      }
      await batch.commit(noResult: true);
    }
    final rows = lines.skip(1).where((l) => l.trim().isNotEmpty).map((line) {
      final v = line.split(',').map((c) => c.trim()).toList();
      return { for (var i = 0; i < header.length && i < v.length; i++) header[i]: v[i] };
    }).toList();
    return (rows: rows, csv: csv);
  }

  Future<void> clearSession(String sessionId) async {
    if (_db == null && _prefs == null) await init();

    if (_isWeb) {
      await _prefs!.remove('mfx_session_$sessionId');
      final ids = _webGetSessionIds()..remove(sessionId);
      await _webSetSessionIds(ids);
      return;
    }

    await _db?.delete('chat_messages', where: 'session_id = ?', whereArgs: [sessionId]);
  }
}

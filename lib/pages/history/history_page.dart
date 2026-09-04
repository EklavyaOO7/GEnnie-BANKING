import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/services/chat_db_service.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _db = ChatDbService();
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  String? _activeSession;
  List<Map<String, dynamic>> _activeMessages = [];
  bool _showConfirm = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _db.init();
      final sessions = await _db.getAllSessions();
      setState(() { _sessions = sessions; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openSession(String sessionId) async {
    try {
      final msgs = await _db.getSession(sessionId);
      setState(() { _activeSession = sessionId; _activeMessages = msgs; });
    } catch (_) {}
  }

  void _closeSession() => setState(() { _activeSession = null; _activeMessages = []; });

  Future<void> _deleteSession() async {
    if (_activeSession == null) return;
    await _db.clearSession(_activeSession!);
    _closeSession();
    await _load();
  }

  Future<void> _clearAll() async {
    for (final s in _sessions) {
      await _db.clearSession(s['session_id']);
    }
    setState(() { _showConfirm = false; });
    await _load();
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _activeSession == null,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _closeSession(); },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: const Color(0xFFE8ECF0)),
          ),
          title: Text(_activeSession != null ? 'Session' : 'Chat History',
              style: TextStyle(color: Theme.of(context).appBarTheme.foregroundColor, fontWeight: FontWeight.w700)),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).appBarTheme.foregroundColor),
            onPressed: _activeSession != null ? _closeSession : () => Navigator.pop(context),
          ),
          actions: [
            if (_activeSession != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                onPressed: _deleteSession,
              )
            else if (_sessions.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Color(0xFFEF4444)),
                onPressed: () => setState(() => _showConfirm = true),
              ),
          ],
        ),
        body: Stack(
          children: [
            _activeSession != null ? _buildMessages() : _buildSessionList(),
            if (_showConfirm) _buildConfirmDialog(),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionList() {
    if (_loading) return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    if (_sessions.isEmpty) {
      return const Center(child: Text('No chat history yet.',
          style: TextStyle(color: Color(0xFF94A3B8))));
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _sessions.length,
      itemBuilder: (_, i) {
        final s = _sessions[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            tileColor: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: 0.12),
              ),
              child: Icon(Icons.chat_bubble_outline_rounded,
                  color: cs.primary, size: 20),
            ),
            title: Text(s['preview'] ?? '',
                style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_formatTime(s['created_at']),
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            onTap: () => _openSession(s['session_id']),
          ),
        );
      },
    );
  }

  Widget _buildMessages() {
    if (_activeMessages.isEmpty) {
      return const Center(child: Text('No messages.',
          style: TextStyle(color: Color(0xFF94A3B8))));
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _activeMessages.length,
      itemBuilder: (_, i) {
        final m = _activeMessages[i];
        final isUser = m['from_role'] == 'user';
        final rawMsg = m['message'] ?? '';
        // Try to parse as form card JSON
        List<Map<String, String>>? card;
        String? cardTitle;
        try {
          final decoded = jsonDecode(rawMsg);
          if (decoded is Map) {
            cardTitle = decoded['__title__']?.toString() ?? 'Form Submission';
            card = decoded.entries
                .where((e) => e.key != '__title__' && e.value.toString().trim().isNotEmpty)
                .map((e) => {'label': e.key.toString(), 'value': e.value.toString()})
                .toList();
          }
        } catch (_) {}

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * (card != null ? 0.65 : 0.78)),
            child: card != null && card.isNotEmpty
                ? _buildHistoryCard(cardTitle ?? 'Details', card, isUser)
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser ? cs.secondary : cs.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.07),
                          blurRadius: 4, offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(rawMsg,
                        style: TextStyle(
                            color: isUser ? Colors.white : cs.onSurface,
                            fontSize: 14)),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryCard(String title, List<Map<String, String>> rows, bool isUser) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: isUser ? cs.secondary : cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isUser ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.07),
              blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(
                  color: isUser
                      ? Colors.white.withValues(alpha: 0.15)
                      : const Color(0xFFE2E8F0))),
            ),
            child: Row(children: [
              Icon(Icons.check_circle_rounded,
                  size: 13,
                  color: isUser ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF16A34A)),
              const SizedBox(width: 5),
              Text(title,
                  style: TextStyle(
                      color: isUser ? Colors.white : cs.onSurface,
                      fontWeight: FontWeight.w700, fontSize: 11.5)),
            ]),
          ),
          ...rows.map((row) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 90,
                  child: Text(row['label'] ?? '',
                      style: TextStyle(
                          color: isUser
                              ? Colors.white.withValues(alpha: 0.6)
                              : const Color(0xFF64748B),
                          fontSize: 11)),
                ),
                Expanded(
                  child: Text(row['value'] ?? '',
                      style: TextStyle(
                          color: isUser ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          )),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildConfirmDialog() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 32),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Clear all history?',
                  style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('This cannot be undone.',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _showConfirm = false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _clearAll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Clear All', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

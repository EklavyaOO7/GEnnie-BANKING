import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';

const _kLoginUrl = 'https://meta.kiya.ai/login';

enum _Step { username, password, submitting, done, wrongCreds, invalidToken }

class RegisterPage extends StatefulWidget {
  final String branchID;
  final String token;
  const RegisterPage({super.key, required this.branchID, required this.token});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();

  _Step _step = _Step.username;
  String _username = '';

  final _messages = <Map<String, String>>[];

  @override
  void initState() {
    super.initState();
    _pushBot("Welcome! Please enter your username.");
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _pushBot(String text) {
    setState(() => _messages.add({'from': 'bot', 'text': text}));
    _scrollToBottom();
  }

  void _pushUser(String text) {
    setState(() => _messages.add({'from': 'user', 'text': text}));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  void _onSend() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _step == _Step.submitting || _step == _Step.done) return;
    _inputCtrl.clear();
    _pushUser(text);

    switch (_step) {
      case _Step.username:
        _username = text;
        setState(() => _step = _Step.password);
        _pushBot('Got it! Now enter your password.');
      case _Step.password:
        setState(() => _step = _Step.submitting);
        _pushBot('Authenticating…');
        _login(text);
      default:
        break;
    }
  }

  Future<void> _login(String password) async {
    try {
      final res = await http.post(
        Uri.parse(_kLoginUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _username,
          'password': password,
          'branchID': widget.branchID,
          'token': widget.token,
          'mode': 'VM',
        }),
      );
      if (!mounted) return;

      if (res.statusCode == 500) {
        setState(() => _step = _Step.invalidToken);
        _pushBot('Invalid token. Please try again.');
        return;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['resoponse'] == 'SUCCESS') {
        setState(() => _step = _Step.done);
        _pushBot('✅ User authenticated successfully!');
      } else {
        setState(() => _step = _Step.wrongCreds);
        _pushBot('Incorrect username or password. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.invalidToken);
      _pushBot('Network error. Please try again.');
    }
  }

  void _retryCredentials() {
    setState(() {
      _step = _Step.username;
      _username = '';
      _messages.clear();
    });
    _pushBot("Please enter your username.");
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final surface = Theme.of(context).appBarTheme.backgroundColor ?? cs.surface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.lock_rounded, color: cs.primary, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Sign In',
              style: TextStyle(color: onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: onSurface.withValues(alpha: 0.08)),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                itemCount: _messages.length,
                itemBuilder: (_, i) {
                  final m = _messages[i];
                  return _ChatBubble(text: m['text']!, isUser: m['from'] == 'user');
                },
              ),
            ),
            if (_step == _Step.submitting)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Text('Authenticating…',
                      style: TextStyle(color: onSurface.withValues(alpha: 0.5), fontSize: 13)),
                ]),
              ),
            if (_step == _Step.done)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.home_rounded, size: 18),
                    label: const Text('Go to Home', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            if (_step == _Step.wrongCreds || _step == _Step.invalidToken)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _retryCredentials,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            if (_step == _Step.username || _step == _Step.password)
              _InputBar(
                ctrl: _inputCtrl,
                focusNode: _focusNode,
                obscure: _step == _Step.password,
                hint: _step == _Step.username ? 'Enter your username…' : 'Enter your password…',
                onSend: _onSend,
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  const _ChatBubble({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: 0.12),
              ),
              child: Icon(Icons.smart_toy_rounded, color: cs.primary, size: 15),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
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
                    color: cs.onSurface.withValues(alpha: 0.06),
                    blurRadius: 4, offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isUser ? Colors.white : cs.onSurface,
                  fontSize: 14, height: 1.5,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final FocusNode focusNode;
  final bool obscure;
  final String hint;
  final VoidCallback onSend;
  const _InputBar({
    required this.ctrl,
    required this.focusNode,
    required this.obscure,
    required this.hint,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final surface = Theme.of(context).appBarTheme.backgroundColor ?? cs.surface;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: onSurface.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        top: false,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44, maxHeight: 100),
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: onSurface.withValues(alpha: 0.12)),
              ),
              child: TextField(
                controller: ctrl,
                focusNode: focusNode,
                obscureText: obscure,
                style: TextStyle(color: onSurface, fontSize: 14),
                maxLines: obscure ? 1 : null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.35), fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [cs.primary, cs.secondary],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: cs.primary.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 19),
            ),
          ),
        ]),
      ),
    );
  }
}

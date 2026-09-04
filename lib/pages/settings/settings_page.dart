import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../main.dart' show themeNotifier;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _kBlue = Color(0xFF329AD6);
  static const _kDark = Color(0xFF0F172A);
  static const _kSub = Color(0xFF64748B);
  static const _kBorder = Color(0xFFE2E8F0);

  static const _keyModelDownload = 'slm_model_download';
  static const _keyVoiceLang = 'voice_language';
  static const _keyBiometric = 'biometric_enabled';
  static const _keyTheme = 'app_theme'; // 'light' | 'dark' | 'blue' | 'green'

  String _modelDownload = 'wifi_only';
  String _voiceLang = 'en_US';
  bool _biometricEnabled = true;
  String _theme = 'light';
  bool _loading = true;

  // Theme definitions: key → {name, bg, primary, accent}
  static const _themes = [
    {'key': 'light',  'name': 'Light Blue',   'bg': 0xFFF0F6FF, 'primary': 0xFF329AD6, 'accent': 0xFF1A6FA8},
    {'key': 'dark',   'name': 'Dark',          'bg': 0xFF0F172A, 'primary': 0xFF329AD6, 'accent': 0xFF1E40AF},
    {'key': 'green',  'name': 'Forest Green',  'bg': 0xFFF0FFF4, 'primary': 0xFF16A34A, 'accent': 0xFF15803D},
    {'key': 'purple', 'name': 'Royal Purple',  'bg': 0xFFF5F3FF, 'primary': 0xFF7C3AED, 'accent': 0xFF6D28D9},
    {'key': 'slate',  'name': 'Slate',         'bg': 0xFFF8FAFC, 'primary': 0xFF475569, 'accent': 0xFF334155},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _modelDownload = prefs.getString(_keyModelDownload) ?? 'wifi_only';
      _voiceLang = prefs.getString(_keyVoiceLang) ?? 'en_US';
      _biometricEnabled = prefs.getBool(_keyBiometric) ?? true;
      _theme = prefs.getString(_keyTheme) ?? 'light';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModelDownload, _modelDownload);
    await prefs.setString(_keyVoiceLang, _voiceLang);
    await prefs.setBool(_keyBiometric, _biometricEnabled);
    await prefs.setString(_keyTheme, _theme);
    themeNotifier.value = _theme; // live update
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: theme.appBarTheme.foregroundColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Settings',
            style: TextStyle(color: theme.appBarTheme.foregroundColor, fontSize: 16, fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kBorder),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section('AI Model', [
                  _radioTile(
                    icon: Icons.wifi_rounded, iconColor: _kBlue,
                    title: 'Wi-Fi Only', subtitle: 'Download AI models only on Wi-Fi',
                    value: 'wifi_only', groupValue: _modelDownload,
                    onChanged: (v) => setState(() { _modelDownload = v!; _save(); }),
                  ),
                  _divider(),
                  _radioTile(
                    icon: Icons.signal_cellular_alt_rounded, iconColor: const Color(0xFF16A34A),
                    title: 'Any Network', subtitle: 'Allow download on mobile data too',
                    value: 'any', groupValue: _modelDownload,
                    onChanged: (v) => setState(() { _modelDownload = v!; _save(); }),
                  ),
                  _divider(),
                  _radioTile(
                    icon: Icons.block_rounded, iconColor: const Color(0xFFEF4444),
                    title: 'Disabled', subtitle: 'Do not download AI models',
                    value: 'disabled', groupValue: _modelDownload,
                    onChanged: (v) => setState(() { _modelDownload = v!; _save(); }),
                  ),
                ]),
                const SizedBox(height: 16),
                _section('Voice Recognition', [
                  _radioTile(
                    icon: Icons.language_rounded, iconColor: _kBlue,
                    title: 'English (US)', subtitle: 'en-US locale',
                    value: 'en_US', groupValue: _voiceLang,
                    onChanged: (v) => setState(() { _voiceLang = v!; _save(); }),
                  ),
                  _divider(),
                  _radioTile(
                    icon: Icons.language_rounded, iconColor: _kBlue,
                    title: 'English (UK)', subtitle: 'en-GB locale',
                    value: 'en_GB', groupValue: _voiceLang,
                    onChanged: (v) => setState(() { _voiceLang = v!; _save(); }),
                  ),
                  _divider(),
                  _radioTile(
                    icon: Icons.language_rounded, iconColor: _kBlue,
                    title: 'English (India)', subtitle: 'en-IN locale',
                    value: 'en_IN', groupValue: _voiceLang,
                    onChanged: (v) => setState(() { _voiceLang = v!; _save(); }),
                  ),
                ]),
                const SizedBox(height: 16),
                _section('Security', [
                  _switchTile(
                    icon: Icons.fingerprint_rounded, iconColor: _kBlue,
                    title: 'Biometric Login',
                    subtitle: 'Use fingerprint or face ID to unlock',
                    value: _biometricEnabled,
                    onChanged: (v) => setState(() { _biometricEnabled = v; _save(); }),
                  ),
                ]),
                const SizedBox(height: 16),
                _section('Theme', [_buildThemePicker()]),
                const SizedBox(height: 16),
                _section('About', [
                  _infoTile(icon: Icons.info_outline_rounded, iconColor: _kSub,
                      title: 'Version', trailing: '1.0.0'),
                  _divider(),
                  _infoTile(icon: Icons.account_balance_rounded, iconColor: _kBlue,
                      title: 'Powered by', trailing: 'KiyaAI'),
                ]),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildThemePicker() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _iconBox(Icons.palette_rounded, cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('App Theme', style: TextStyle(color: cs.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
                Text('Choose your preferred colour scheme', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _themes.map((t) {
              final key = t['key'] as String;
              final name = t['name'] as String;
              final bg = Color(t['bg'] as int);
              final primary = Color(t['primary'] as int);
              final accent = Color(t['accent'] as int);
              final selected = _theme == key;
              return GestureDetector(
                onTap: () => setState(() { _theme = key; _save(); }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 90,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? primary : _kBorder,
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected ? [
                      BoxShadow(color: primary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2)),
                    ] : [],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // Mini preview
                    Container(
                      width: 44, height: 28,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Column(children: [
                        Container(height: 8, decoration: BoxDecoration(
                          color: primary,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                        )),
                        const SizedBox(height: 3),
                        Container(margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 3, decoration: BoxDecoration(color: accent.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
                        const SizedBox(height: 2),
                        Container(margin: const EdgeInsets.symmetric(horizontal: 6),
                            height: 3, decoration: BoxDecoration(color: accent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2))),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    Text(name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? primary : _kSub,
                        )),
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(Icons.check_circle_rounded, color: primary, size: 14),
                      ),
                  ]),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title.toUpperCase(),
              style: const TextStyle(color: _kSub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ),
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _divider() =>
      const Divider(height: 1, indent: 56, endIndent: 0, color: Color(0xFFF1F5F9));

  Widget _radioTile<T>({
    required IconData icon, required Color iconColor,
    required String title, required String subtitle,
    required T value, required T groupValue,
    required ValueChanged<T?> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: cs.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
            Text(subtitle, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 12)),
          ])),
          Radio<T>(
            value: value, groupValue: groupValue, onChanged: onChanged,
            activeColor: cs.primary, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ]),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon, required Color iconColor,
    required String title, required String subtitle,
    required bool value, required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        _iconBox(icon, iconColor),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: cs.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
          Text(subtitle, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 12)),
        ])),
        Switch(value: value, onChanged: onChanged, activeColor: cs.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ]),
    );
  }

  Widget _infoTile({
    required IconData icon, required Color iconColor,
    required String title, required String trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        _iconBox(icon, iconColor),
        const SizedBox(width: 12),
        Expanded(child: Text(title,
            style: TextStyle(color: cs.onSurface, fontSize: 14, fontWeight: FontWeight.w600))),
        Text(trailing, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)),
      ]),
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../core/models/chat_message.dart';

class FormPanel extends StatelessWidget {
  final List<JourneyFormGroup> groups;
  final int groupIndex;
  final bool hasErrors;
  final String voiceTranscript;
  final String voiceFieldTarget;
  final void Function(int gi, String varName, dynamic value) onFieldChange;
  final void Function(int gi, String varName, String value) onCheckboxToggle;
  final VoidCallback onConfirm;
  final VoidCallback onPrev;

  const FormPanel({
    super.key,
    required this.groups,
    required this.groupIndex,
    required this.hasErrors,
    this.voiceTranscript = '',
    this.voiceFieldTarget = '',
    required this.onFieldChange,
    required this.onCheckboxToggle,
    required this.onConfirm,
    required this.onPrev,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty || groupIndex >= groups.length) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final grp = groups[groupIndex];

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(children: [
              Expanded(
                child: Text(grp.name,
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              if (groups.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${groupIndex + 1} / ${groups.length}',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          if (voiceTranscript.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Container(
                    width: 7, height: 7,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(color: Color(0xFFF97316), shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Text('"$voiceTranscript"',
                        style: const TextStyle(color: Color(0xFF92400E), fontSize: 12, fontStyle: FontStyle.italic)),
                  ),
                ]),
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: grp.fields.map<Widget>((f) => _buildField(context, f, grp, groupIndex)).toList(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (groupIndex > 0) ...[
                  OutlinedButton(
                    onPressed: onPrev,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Previous', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 2,
                    shadowColor: cs.primary.withValues(alpha: 0.3),
                  ),
                  child: Text(
                    groupIndex < groups.length - 1 ? 'Next' : 'Submit',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(BuildContext context, JourneyFormField f, JourneyFormGroup grp, int gi) {
    final cs = Theme.of(context).colorScheme;
    final error = grp.errors[f.variableName] ?? '';
    final dt = f.dataType;
    final isVoiceFocus = voiceFieldTarget == f.variableName;

    // Consent toggle: checkbox first, then label inline
    if (dt == 'checkbox' && f.options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              _buildConsentToggle(context, f, grp, gi),
              const SizedBox(width: 10),
              Expanded(
                child: Text(f.label,
                    style: TextStyle(
                        color: isVoiceFocus ? cs.primary : const Color(0xFF64748B),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ),
              if (f.isOptional == 'N')
                const Text(' *', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11.5)),
            ]),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(error, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(f.label,
                style: TextStyle(
                    color: isVoiceFocus ? cs.primary : const Color(0xFF64748B),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
            if (f.isOptional == 'N')
              const Text(' *', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11.5)),
            if (isVoiceFocus)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text('● filling',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.w500)),
              ),
          ]),
          const SizedBox(height: 3),
          if (dt == 'radio')
            _buildPillOptions(context, f, grp, gi, multi: false)
          else if (dt == 'checkbox')
            _buildPillOptions(context, f, grp, gi, multi: true)
          else if (dt == 'select')
            _buildDropdown(context, f, grp, gi)
          else if (dt == 'textarea')
            _buildTextArea(context, f, grp, gi)
          else if (dt == 'date')
            _buildDateField(context, f, grp, gi)
          else
            _buildTextField(context, f, grp, gi),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(error, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField(BuildContext context, JourneyFormField f, JourneyFormGroup grp, int gi) {
    final cs = Theme.of(context).colorScheme;
    final hasError = (grp.errors[f.variableName] ?? '').isNotEmpty;
    final currentVal = grp.values[f.variableName]?.toString() ?? '';
    return _UncontrolledTextField(
      key: ValueKey('tf_${f.variableName}'),
      externalValue: currentVal,
      keyboardType: f.dataType == 'number' ? TextInputType.number : TextInputType.text,
      textStyle: TextStyle(color: cs.onSurface, fontSize: 13),
      decoration: _inputDeco(context, 'Enter ${f.label}', hasError: hasError),
      onChanged: (v) => onFieldChange(gi, f.variableName, v),
    );
  }

  Widget _buildTextArea(BuildContext context, JourneyFormField f, JourneyFormGroup grp, int gi) {
    final cs = Theme.of(context).colorScheme;
    final hasError = (grp.errors[f.variableName] ?? '').isNotEmpty;
    final currentVal = grp.values[f.variableName]?.toString() ?? '';
    return _UncontrolledTextField(
      key: ValueKey('ta_${f.variableName}'),
      externalValue: currentVal,
      maxLines: 3,
      textStyle: TextStyle(color: cs.onSurface, fontSize: 13),
      decoration: _inputDeco(context, 'Enter ${f.label}', hasError: hasError),
      onChanged: (v) => onFieldChange(gi, f.variableName, v),
    );
  }

  Widget _buildDropdown(BuildContext context, JourneyFormField f, JourneyFormGroup grp, int gi) {
    final cs = Theme.of(context).colorScheme;
    final val = grp.values[f.variableName]?.toString();
    final validVal = f.options.any((o) => o['value'] == val) ? val : null;
    final hasError = (grp.errors[f.variableName] ?? '').isNotEmpty;
    return DropdownButtonFormField<String>(
      key: ValueKey('dd_${f.variableName}_$validVal'),
      value: validVal,
      dropdownColor: cs.surface,
      isDense: true,
      style: TextStyle(color: cs.onSurface, fontSize: 13),
      hint: Text('Select ${f.label}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
      decoration: _inputDeco(context, '', hasError: hasError),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8), size: 18),
      items: f.options
          .map((o) => DropdownMenuItem(
                value: o['value'],
                child: Text(o['name'] ?? o['value'] ?? '', style: TextStyle(color: cs.onSurface, fontSize: 13)),
              ))
          .toList(),
      onChanged: (v) => onFieldChange(gi, f.variableName, v ?? ''),
    );
  }

  Widget _buildPillOptions(BuildContext context, JourneyFormField f, JourneyFormGroup grp, int gi,
      {required bool multi}) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: f.options.map((o) {
        final val = o['value'] ?? '';
        final name = o['name'] ?? val;
        final bool selected = multi
            ? ((grp.values[f.variableName] as List?)?.contains(val) ?? false)
            : grp.values[f.variableName]?.toString() == val;
        return GestureDetector(
          onTap: () => multi
              ? onCheckboxToggle(gi, f.variableName, val)
              : onFieldChange(gi, f.variableName, val),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? cs.primary.withValues(alpha: 0.07) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? cs.primary : const Color(0xFFE2E8F0), width: selected ? 1.5 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 14, height: 14,
                margin: const EdgeInsets.only(right: 6),
                decoration: multi
                    ? BoxDecoration(
                        color: selected ? cs.primary : Colors.transparent,
                        border: Border.all(color: selected ? cs.primary : const Color(0xFFCBD5E1), width: 2),
                        borderRadius: BorderRadius.circular(3),
                      )
                    : BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? cs.primary : const Color(0xFFCBD5E1), width: 2),
                      ),
                child: selected ? Icon(multi ? Icons.check_rounded : null, size: 9, color: Colors.white) : null,
              ),
              Text(name,
                  style: TextStyle(
                      color: selected ? cs.secondary : const Color(0xFF1E293B),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildConsentToggle(BuildContext context, JourneyFormField f, JourneyFormGroup grp, int gi, {String label = ''}) {
    final cs = Theme.of(context).colorScheme;
    final checked = grp.values[f.variableName] == true ||
        grp.values[f.variableName]?.toString() == 'true';
    final hasError = (grp.errors[f.variableName] ?? '').isNotEmpty;
    return GestureDetector(
      onTap: () => onFieldChange(gi, f.variableName, !checked),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: checked ? cs.primary : Colors.transparent,
          border: Border.all(
            color: hasError ? const Color(0xFFEF4444) : (checked ? cs.primary : const Color(0xFFCBD5E1)),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: checked
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : null,
      ),
    );
  }

  Widget _buildDateField(BuildContext context, JourneyFormField f, JourneyFormGroup grp, int gi) {
    final cs = Theme.of(context).colorScheme;
    final val = grp.values[f.variableName]?.toString() ?? '';
    final hasError = (grp.errors[f.variableName] ?? '').isNotEmpty;
    return GestureDetector(
      onTap: () => onFieldChange(gi, f.variableName, '__pick_date__'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: hasError ? const Color(0xFFFFF5F5) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hasError ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(val.isEmpty ? 'Select date' : val,
                style: TextStyle(color: val.isEmpty ? const Color(0xFF94A3B8) : cs.onSurface, fontSize: 13)),
          ),
          const Icon(Icons.calendar_today_rounded, color: Color(0xFF94A3B8), size: 15),
        ]),
      ),
    );
  }

  InputDecoration _inputDeco(BuildContext context, String hint, {bool hasError = false}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      filled: true,
      fillColor: hasError ? const Color(0xFFFFF5F5) : const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hasError ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hasError ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      isDense: true,
    );
  }
}

class _UncontrolledTextField extends StatefulWidget {
  final String externalValue;
  final TextInputType keyboardType;
  final int? maxLines;
  final TextStyle textStyle;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;

  const _UncontrolledTextField({
    super.key,
    required this.externalValue,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    required this.textStyle,
    required this.decoration,
    required this.onChanged,
  });

  @override
  State<_UncontrolledTextField> createState() => _UncontrolledTextFieldState();
}

class _UncontrolledTextFieldState extends State<_UncontrolledTextField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.externalValue);
  }

  @override
  void didUpdateWidget(_UncontrolledTextField old) {
    super.didUpdateWidget(old);
    // Only sync when the external value changed AND differs from what the
    // controller already has — this means voice filled it, not the user typing.
    if (widget.externalValue != old.externalValue &&
        widget.externalValue != _ctrl.text) {
      _ctrl.value = TextEditingValue(
        text: widget.externalValue,
        selection: TextSelection.collapsed(offset: widget.externalValue.length),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      style: widget.textStyle,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
    );
  }
}

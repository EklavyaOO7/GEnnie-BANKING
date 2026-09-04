import 'package:flutter/material.dart';
import '../../../core/models/chat_message.dart';

class ChoicePanel extends StatelessWidget {
  final String question;
  final List<JourneyChoice> choices;
  final String choiceType;
  final String selectedChoice;
  final List<String> selectedChoices;
  final String voiceTranscript;
  final String voiceMatchValue;
  final void Function(JourneyChoice) onSelect;
  final VoidCallback onConfirm;

  const ChoicePanel({
    super.key,
    required this.question,
    required this.choices,
    required this.choiceType,
    required this.selectedChoice,
    required this.selectedChoices,
    this.voiceTranscript = '',
    this.voiceMatchValue = '',
    required this.onSelect,
    required this.onConfirm,
  });

  bool _isSelected(String value) => choiceType == 'radio'
      ? selectedChoice == value
      : selectedChoices.contains(value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasSelection = choiceType == 'radio'
        ? selectedChoice.isNotEmpty
        : selectedChoices.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.45,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Text(question,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          if (voiceTranscript.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(children: [
                Container(
                  width: 7, height: 7,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF97316), shape: BoxShape.circle),
                ),
                Expanded(
                  child: Text('"$voiceTranscript"',
                      style: const TextStyle(
                          color: Color(0xFF92400E),
                          fontSize: 12,
                          fontStyle: FontStyle.italic)),
                ),
              ]),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Column(
                children: choices.map((c) {
                  final selected = _isSelected(c.value);
                  final isVoiceMatch = voiceMatchValue == c.value;
                  return GestureDetector(
                    onTap: () => onSelect(c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isVoiceMatch
                            ? const Color(0xFFFFF7ED)
                            : selected
                                ? cs.primary.withValues(alpha: 0.07)
                                : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isVoiceMatch
                              ? const Color(0xFFF97316)
                              : selected
                                  ? cs.primary
                                  : const Color(0xFFE2E8F0),
                          width: (selected || isVoiceMatch) ? 1.5 : 1,
                        ),
                      ),
                      child: Row(children: [
                        if (choiceType == 'checkbox')
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 16, height: 16,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: selected ? cs.primary : Colors.transparent,
                              border: Border.all(
                                  color: selected ? cs.primary : const Color(0xFFCBD5E1),
                                  width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: selected
                                ? const Icon(Icons.check_rounded, size: 10, color: Colors.white)
                                : null,
                          )
                        else
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 16, height: 16,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: selected ? cs.primary : const Color(0xFFCBD5E1),
                                  width: 2),
                            ),
                            child: selected
                                ? Center(
                                    child: Container(
                                      width: 7, height: 7,
                                      decoration: BoxDecoration(
                                          color: cs.primary, shape: BoxShape.circle),
                                    ),
                                  )
                                : null,
                          ),
                        Expanded(
                          child: Text(c.displayText,
                              style: TextStyle(
                                  color: selected ? cs.secondary : const Color(0xFF1E293B),
                                  fontSize: 13,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                        ),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: hasSelection ? onConfirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: hasSelection ? 2 : 0,
                    shadowColor: cs.primary.withValues(alpha: 0.3),
                  ),
                  child: const Text('Next',
                      style: TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

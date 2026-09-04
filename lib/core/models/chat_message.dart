class ChatMessage {
  final String from; // 'bot' | 'user'
  final String text;
  final String time;
  final String? fileName;
  final String? imageUrl;
  final bool scanned;
  final List<Map<String, String>>? card;
  final List<JourneyChoice>? choices;
  final String? choiceType;
  bool choiceDone;
  final List<Map<String, String>>? quickReplies;
  final String? metaRoom; // 'qr' | 'authenticated' | 'error'
  String? metaRoomPhase; // 'skeleton' | 'ready'
  String? metaRoomQrUrl;
  Map<String, dynamic>? metaRoomSession;
  String? metaRoomError;
  final String? chartImage;  // base64 PNG from SlmEngine
  final String? tableHtml;   // HTML table string from SlmEngine
  final String? csvData;     // raw CSV for 6-month statement preview + download

  ChatMessage({
    required this.from,
    required this.text,
    required this.time,
    this.fileName,
    this.imageUrl,
    this.scanned = false,
    this.card,
    this.choices,
    this.choiceType,
    this.choiceDone = false,
    this.quickReplies,
    this.metaRoom,
    this.metaRoomPhase,
    this.metaRoomQrUrl,
    this.metaRoomSession,
    this.metaRoomError,
    this.chartImage,
    this.tableHtml,
    this.csvData,
  });

  ChatMessage copyWith({
    String? metaRoom,
    String? metaRoomPhase,
    String? metaRoomQrUrl,
    Map<String, dynamic>? metaRoomSession,
    String? metaRoomError,
    String? csvData,
  }) {
    return ChatMessage(
      from: from,
      text: text,
      time: time,
      fileName: fileName,
      imageUrl: imageUrl,
      scanned: scanned,
      card: card,
      choices: choices,
      choiceType: choiceType,
      choiceDone: choiceDone,
      quickReplies: quickReplies,
      metaRoom: metaRoom ?? this.metaRoom,
      metaRoomPhase: metaRoomPhase ?? this.metaRoomPhase,
      metaRoomQrUrl: metaRoomQrUrl ?? this.metaRoomQrUrl,
      metaRoomSession: metaRoomSession ?? this.metaRoomSession,
      metaRoomError: metaRoomError ?? this.metaRoomError,
      chartImage: chartImage ?? this.chartImage,
      tableHtml: tableHtml ?? this.tableHtml,
      csvData: csvData ?? this.csvData,
    );
  }
}

class JourneyChoice {
  final String value;
  final String displayText;
  JourneyChoice({required this.value, required this.displayText});
}

class JourneyFormField {
  final String variableName;
  final String label;
  final String dataType;
  final String isOptional;
  final List<Map<String, String>> options;
  JourneyFormField({
    required this.variableName,
    required this.label,
    required this.dataType,
    required this.isOptional,
    required this.options,
  });
}

class JourneyFormGroup {
  final String name;
  final List<JourneyFormField> fields;
  Map<String, dynamic> values;
  Map<String, String> errors;
  JourneyFormGroup({
    required this.name,
    required this.fields,
    required this.values,
    required this.errors,
  });
}

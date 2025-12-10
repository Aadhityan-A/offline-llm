class ChatMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  final String? reasoning; // For models with thinking/reasoning output (DeepSeek R1, Qwen QwQ, etc.)
  final List<String>? sourceDocuments; // For RAG - list of source document references

  ChatMessage({
    required this.content,
    required this.isUser,
    DateTime? timestamp,
    this.isError = false,
    this.reasoning,
    this.sourceDocuments,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Check if this message has reasoning/thinking content
  bool get hasReasoning => reasoning != null && reasoning!.isNotEmpty;

  /// Check if this message has RAG source documents
  bool get hasSources => sourceDocuments != null && sourceDocuments!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'content': content,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
        'isError': isError,
        if (reasoning != null) 'reasoning': reasoning,
        if (sourceDocuments != null) 'sourceDocuments': sourceDocuments,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        content: json['content'] as String,
        isUser: json['isUser'] as bool,
        timestamp: DateTime.parse(json['timestamp'] as String),
        isError: json['isError'] as bool? ?? false,
        reasoning: json['reasoning'] as String?,
        sourceDocuments: json['sourceDocuments'] != null
            ? List<String>.from(json['sourceDocuments'] as List)
            : null,
      );

  /// Create a copy with modified fields
  ChatMessage copyWith({
    String? content,
    bool? isUser,
    DateTime? timestamp,
    bool? isError,
    String? reasoning,
    List<String>? sourceDocuments,
  }) {
    return ChatMessage(
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isError: isError ?? this.isError,
      reasoning: reasoning ?? this.reasoning,
      sourceDocuments: sourceDocuments ?? this.sourceDocuments,
    );
  }
}

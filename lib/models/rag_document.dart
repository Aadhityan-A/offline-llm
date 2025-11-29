/// Enum for document types
enum DocumentType {
  pdf,
  docx,
  txt,
}

/// Extension to convert DocumentType to/from string
extension DocumentTypeExtension on DocumentType {
  String get name {
    switch (this) {
      case DocumentType.pdf:
        return 'pdf';
      case DocumentType.docx:
        return 'docx';
      case DocumentType.txt:
        return 'txt';
    }
  }

  static DocumentType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'pdf':
        return DocumentType.pdf;
      case 'docx':
      case 'doc':
        return DocumentType.docx;
      case 'txt':
      default:
        return DocumentType.txt;
    }
  }
}

/// Model for a RAG document stored in the database
class RagDocument {
  final int? id;
  final String name;
  final DocumentType fileType;
  final String fullText;
  final DateTime createdAt;
  final int chunkCount;

  RagDocument({
    this.id,
    required this.name,
    required this.fileType,
    required this.fullText,
    required this.createdAt,
    this.chunkCount = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'file_type': fileType.name,
        'full_text': fullText,
        'created_at': createdAt.millisecondsSinceEpoch,
        'chunk_count': chunkCount,
      };

  factory RagDocument.fromMap(Map<String, dynamic> map) => RagDocument(
        id: map['id'] as int?,
        name: map['name'] as String,
        fileType: DocumentTypeExtension.fromString(map['file_type'] as String),
        fullText: map['full_text'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        chunkCount: map['chunk_count'] as int? ?? 0,
      );

  RagDocument copyWith({
    int? id,
    String? name,
    DocumentType? fileType,
    String? fullText,
    DateTime? createdAt,
    int? chunkCount,
  }) {
    return RagDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      fileType: fileType ?? this.fileType,
      fullText: fullText ?? this.fullText,
      createdAt: createdAt ?? this.createdAt,
      chunkCount: chunkCount ?? this.chunkCount,
    );
  }
}

/// Model for a document chunk used in RAG retrieval
class DocumentChunk {
  final int? id;
  final int documentId;
  final String documentName;
  final int chunkIndex;
  final String content;

  DocumentChunk({
    this.id,
    required this.documentId,
    required this.documentName,
    required this.chunkIndex,
    required this.content,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'document_id': documentId,
        'document_name': documentName,
        'chunk_index': chunkIndex,
        'content': content,
      };

  factory DocumentChunk.fromMap(Map<String, dynamic> map) => DocumentChunk(
        id: map['id'] as int?,
        documentId: map['document_id'] as int,
        documentName: map['document_name'] as String,
        chunkIndex: map['chunk_index'] as int,
        content: map['content'] as String,
      );
}

/// Result from RAG retrieval with relevance score
class RetrievalResult {
  final DocumentChunk chunk;
  final double score;
  final String sourceReference;

  RetrievalResult({
    required this.chunk,
    required this.score,
    String? sourceReference,
  }) : sourceReference = sourceReference ?? chunk.documentName;
}

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart' as xml;
import 'package:offline_llm/models/rag_document.dart';
import 'package:offline_llm/services/database_service.dart';

/// Service for document text extraction and chunking
/// Supports PDF, TXT, DOCX, and DOC files across all platforms
class DocumentService {
  /// Chunk size in characters (approximate)
  static const int _chunkSize = 500;
  
  /// Overlap between chunks in characters
  static const int _chunkOverlap = 50;

  final DatabaseService _db = DatabaseService.instance;

  /// Extract text from a file based on its extension
  /// Supports: PDF, TXT, DOCX, DOC
  Future<String> extractText(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final extension = filePath.toLowerCase().split('.').last;

    switch (extension) {
      case 'txt':
        return await _extractTxtText(file);
      case 'pdf':
        return await _extractPdfText(file);
      case 'docx':
        return await _extractDocxText(file);
      case 'doc':
        // DOC files are binary and harder to parse
        // Try reading as text, fallback to error message
        return await _extractDocText(file);
      default:
        throw Exception('Unsupported file type: $extension');
    }
  }

  /// Extract text from a plain text file
  Future<String> _extractTxtText(File file) async {
    try {
      return await file.readAsString();
    } catch (e) {
      // Try with different encoding
      final bytes = await file.readAsBytes();
      return String.fromCharCodes(bytes);
    }
  }

  /// Extract text from a PDF file using Syncfusion
  Future<String> _extractPdfText(File file) async {
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    
    try {
      final extractor = PdfTextExtractor(document);
      final buffer = StringBuffer();
      
      for (int i = 0; i < document.pages.count; i++) {
        final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
        if (text.isNotEmpty) {
          buffer.writeln(text);
        }
      }
      
      return buffer.toString().trim();
    } finally {
      document.dispose();
    }
  }

  /// Extract text from a DOCX file (ZIP containing XML)
  Future<String> _extractDocxText(File file) async {
    final bytes = await file.readAsBytes();
    
    try {
      // DOCX is a ZIP archive
      final archive = ZipDecoder().decodeBytes(bytes);
      
      // Find document.xml which contains the main content
      final documentFile = archive.files.firstWhere(
        (f) => f.name == 'word/document.xml',
        orElse: () => throw Exception('Invalid DOCX: document.xml not found'),
      );
      
      final content = String.fromCharCodes(documentFile.content as Uint8List);
      
      // Parse XML and extract text from <w:t> elements
      final document = xml.XmlDocument.parse(content);
      final textElements = document.findAllElements('w:t');
      
      final buffer = StringBuffer();
      String? lastParagraph;
      
      for (final element in textElements) {
        final text = element.innerText;
        if (text.isNotEmpty) {
          buffer.write(text);
          
          // Check if we need to add space
          final parent = element.parent;
          if (parent is xml.XmlElement && parent.name.local == 'r') {
            // Check if next sibling is a new run
            final nextSibling = parent.nextElementSibling;
            if (nextSibling != null) {
              buffer.write(' ');
            }
          }
        }
        
        // Check for paragraph breaks
        final paragraph = _findParentParagraph(element);
        if (paragraph != lastParagraph && lastParagraph != null) {
          buffer.writeln();
        }
        lastParagraph = paragraph;
      }
      
      return buffer.toString().trim();
    } catch (e) {
      throw Exception('Failed to extract text from DOCX: $e');
    }
  }

  String? _findParentParagraph(xml.XmlElement element) {
    xml.XmlElement? current = element;
    while (current != null) {
      if (current.name.local == 'p') {
        return current.hashCode.toString();
      }
      current = current.parent as xml.XmlElement?;
    }
    return null;
  }

  /// Extract text from a DOC file (legacy binary format)
  /// Note: Full DOC support requires complex binary parsing
  Future<String> _extractDocText(File file) async {
    // DOC is a binary format (OLE Compound Document)
    // For simplicity, we try to extract readable ASCII text
    final bytes = await file.readAsBytes();
    
    final buffer = StringBuffer();
    final textBuffer = StringBuffer();
    
    for (int i = 0; i < bytes.length; i++) {
      final byte = bytes[i];
      // Check for printable ASCII characters
      if (byte >= 32 && byte < 127) {
        textBuffer.writeCharCode(byte);
      } else if (byte == 10 || byte == 13) {
        // Newline characters
        if (textBuffer.length > 5) { // Only keep meaningful text
          buffer.write(textBuffer.toString());
          buffer.write(' ');
        }
        textBuffer.clear();
      } else {
        // Non-printable character ends current word
        if (textBuffer.length > 5) {
          buffer.write(textBuffer.toString());
          buffer.write(' ');
        }
        textBuffer.clear();
      }
    }
    
    // Add remaining text
    if (textBuffer.length > 5) {
      buffer.write(textBuffer.toString());
    }
    
    final result = buffer.toString().trim();
    if (result.isEmpty) {
      throw Exception('Could not extract text from DOC file. Consider converting to DOCX or PDF.');
    }
    
    return result;
  }

  /// Split text into chunks with overlap for better context
  List<String> chunkText(String text) {
    if (text.isEmpty) return [];
    
    final chunks = <String>[];
    final sentences = _splitIntoSentences(text);
    
    if (sentences.isEmpty) {
      // Fallback: split by fixed size if no sentences detected
      return _chunkBySize(text);
    }
    
    final currentChunk = StringBuffer();
    
    for (final sentence in sentences) {
      // If adding this sentence exceeds chunk size and we have content
      if (currentChunk.length + sentence.length > _chunkSize && currentChunk.isNotEmpty) {
        // Save current chunk
        chunks.add(currentChunk.toString().trim());
        
        // Start new chunk with overlap from previous chunk
        final prevContent = currentChunk.toString();
        currentChunk.clear();
        
        // Add overlap (last N characters)
        if (prevContent.length > _chunkOverlap) {
          // Try to start at a word boundary
          final overlapStart = prevContent.length - _chunkOverlap;
          final overlapText = prevContent.substring(overlapStart);
          final spaceIndex = overlapText.indexOf(' ');
          if (spaceIndex > 0) {
            currentChunk.write(overlapText.substring(spaceIndex + 1));
          } else {
            currentChunk.write(overlapText);
          }
          currentChunk.write(' ');
        }
      }
      
      currentChunk.write('$sentence ');
    }
    
    // Add the last chunk if it has content
    if (currentChunk.isNotEmpty) {
      final lastChunk = currentChunk.toString().trim();
      if (lastChunk.length > 20) { // Only keep meaningful chunks
        chunks.add(lastChunk);
      }
    }
    
    return chunks;
  }

  /// Split text into sentences
  List<String> _splitIntoSentences(String text) {
    // Normalize whitespace
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // Split on sentence boundaries while keeping the delimiter
    final sentences = normalized
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
    
    return sentences;
  }

  /// Fallback chunking by fixed size
  List<String> _chunkBySize(String text) {
    final chunks = <String>[];
    
    for (int i = 0; i < text.length; i += _chunkSize - _chunkOverlap) {
      final end = (i + _chunkSize).clamp(0, text.length);
      final chunk = text.substring(i, end).trim();
      if (chunk.length > 20) {
        chunks.add(chunk);
      }
    }
    
    return chunks;
  }

  /// Add a document: extract text, chunk it, and store everything
  Future<RagDocument> addDocument(String filePath, String fileName) async {
    // Extract text from the file
    final text = await extractText(filePath);
    
    if (text.isEmpty) {
      throw Exception('No text content could be extracted from the file');
    }
    
    final fileType = DocumentTypeExtension.fromString(
      filePath.split('.').last.toLowerCase(),
    );
    
    // Create document record
    final doc = RagDocument(
      name: fileName,
      fileType: fileType,
      fullText: text,
      createdAt: DateTime.now(),
    );
    
    // Insert document and get ID
    final docId = await _db.insertDocument(doc);
    
    // Create and store chunks
    final textChunks = chunkText(text);
    final chunks = textChunks.asMap().entries.map((entry) => DocumentChunk(
      documentId: docId,
      documentName: fileName,
      chunkIndex: entry.key,
      content: entry.value,
    )).toList();
    
    if (chunks.isNotEmpty) {
      await _db.insertChunks(chunks);
    }
    
    // Update chunk count
    await _db.updateDocumentChunkCount(docId, chunks.length);
    
    // Return the complete document with ID and chunk count
    return RagDocument(
      id: docId,
      name: fileName,
      fileType: fileType,
      fullText: text,
      createdAt: doc.createdAt,
      chunkCount: chunks.length,
    );
  }

  /// Get all documents
  Future<List<RagDocument>> getDocuments() => _db.getAllDocuments();

  /// Delete a document and its chunks
  Future<void> deleteDocument(int id) => _db.deleteDocument(id);

  /// Get document count
  Future<int> getDocumentCount() => _db.getDocumentCount();

  /// Get total chunk count
  Future<int> getChunkCount() => _db.getChunkCount();
}

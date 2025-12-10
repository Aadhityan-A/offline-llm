import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/rag_document.dart';
import '../services/database_service.dart';
import '../services/document_service.dart';
import '../services/retrieval_service.dart';

/// Provider for managing RAG documents.
/// Handles document upload, storage, and retrieval operations.
class DocumentProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService.instance;
  final DocumentService _documentService = DocumentService();
  final RetrievalService _retrievalService = RetrievalService();

  List<RagDocument> _documents = [];
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;

  List<RagDocument> get documents => _documents;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasDocuments => _documents.isNotEmpty;

  /// Initialize the document provider.
  /// Must be called before using any other methods.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Database initializes on first access via the getter
      await _loadDocuments();
      _isInitialized = true;
    } catch (e) {
      _error = 'Failed to initialize document storage: $e';
      debugPrint('DocumentProvider initialization error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load all documents from the database.
  Future<void> _loadDocuments() async {
    _documents = await _databaseService.getAllDocuments();
    // Load chunks into retrieval service for search
    for (final doc in _documents) {
      if (doc.id != null) {
        final chunks = await _databaseService.getChunksForDocument(doc.id!);
        _retrievalService.loadChunks(chunks);
      }
    }
  }

  /// Pick and add documents using file picker.
  /// Supports PDF, DOCX, DOC, and TXT files.
  Future<void> pickAndAddDocuments() async {
    try {
      _error = null;

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'doc', 'txt'],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      _isLoading = true;
      notifyListeners();

      for (final file in result.files) {
        await _processFile(file);
      }
    } catch (e) {
      _error = 'Failed to add documents: $e';
      debugPrint('Document pick error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Process a single file and add it to the database.
  Future<void> _processFile(PlatformFile file) async {
    try {
      String? filePath = file.path;

      // On some platforms, we might need to use bytes instead of path
      if (filePath == null) {
        if (file.bytes != null) {
          // Create a temporary file from bytes
          final tempDir = Directory.systemTemp;
          final tempFile = File('${tempDir.path}/${file.name}');
          await tempFile.writeAsBytes(file.bytes!);
          filePath = tempFile.path;
        } else {
          throw Exception('Cannot access file: ${file.name}');
        }
      }

      // Check if document already exists
      final existingDocs = _documents.where((d) => d.name == file.name);
      if (existingDocs.isNotEmpty) {
        // Remove existing document first
        final existingDoc = existingDocs.first;
        if (existingDoc.id != null) {
          await deleteDocument(existingDoc.id!);
        }
      }

      // Use document service to add document (handles extraction, chunking, and storage)
      final doc = await _documentService.addDocument(filePath, file.name);

      // Load chunks into retrieval service
      if (doc.id != null) {
        final chunks = await _databaseService.getChunksForDocument(doc.id!);
        _retrievalService.loadChunks(chunks);
      }

      // Update local list
      _documents.add(doc);

      debugPrint(
        'Added document: ${file.name} with ${doc.chunkCount} chunks',
      );
    } catch (e) {
      debugPrint('Error processing file ${file.name}: $e');
      rethrow;
    }
  }

  /// Delete a document by ID.
  Future<void> deleteDocument(int documentId) async {
    try {
      _error = null;

      await _databaseService.deleteDocument(documentId);
      _retrievalService.removeDocument(documentId);
      _documents.removeWhere((d) => d.id == documentId);

      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete document: $e';
      debugPrint('Document delete error: $e');
      notifyListeners();
    }
  }

  /// Delete all documents.
  Future<void> deleteAllDocuments() async {
    try {
      _error = null;
      _isLoading = true;
      notifyListeners();

      for (final doc in List.from(_documents)) {
        if (doc.id != null) {
          await _databaseService.deleteDocument(doc.id!);
          _retrievalService.removeDocument(doc.id!);
        }
      }
      _documents.clear();
    } catch (e) {
      _error = 'Failed to delete all documents: $e';
      debugPrint('Delete all documents error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Retrieve relevant context for a query.
  /// Returns a list of [RetrievalResult] sorted by relevance.
  Future<List<RetrievalResult>> retrieveContext(
    String query, {
    int topK = 3,
    double minScore = 0.1,
  }) async {
    if (!_isInitialized || _documents.isEmpty) {
      return [];
    }

    return _retrievalService.search(
      query,
      topK: topK,
      minScore: minScore,
    );
  }

  /// Build context string from retrieval results for LLM prompt.
  String buildContextString(List<RetrievalResult> results) {
    if (results.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    buffer.writeln('Relevant context from uploaded documents:');
    buffer.writeln();

    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      buffer.writeln('[${result.sourceReference}]:');
      buffer.writeln(result.chunk.content);
      if (i < results.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Get unique source references from retrieval results.
  List<String> getSourceReferences(List<RetrievalResult> results) {
    final sources = <String>{};
    for (final result in results) {
      sources.add(result.sourceReference);
    }
    return sources.toList();
  }

  @override
  void dispose() {
    _databaseService.close();
    super.dispose();
  }
}

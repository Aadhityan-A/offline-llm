import 'dart:io';
import 'dart:ffi';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:offline_llm/models/rag_document.dart';

/// Service for managing SQLite database operations for RAG documents
/// Works across all platforms (Android, iOS, Windows, Linux, macOS)
class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Initialize FFI for desktop platforms (Windows, Linux, macOS)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // On Linux, preload the sqlite3 library from system path
      if (Platform.isLinux) {
        try {
          DynamicLibrary.open('/usr/lib/x86_64-linux-gnu/libsqlite3.so');
        } catch (_) {
          // Try alternate paths
          try {
            DynamicLibrary.open('libsqlite3.so.0');
          } catch (_) {
            // Let sqfliteFfiInit handle it
          }
        }
      }
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(documentsDir.path, 'offline_llm_rag.db');

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create documents table
    await db.execute('''
      CREATE TABLE documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        file_type TEXT NOT NULL,
        full_text TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        chunk_count INTEGER DEFAULT 0
      )
    ''');

    // Create chunks table with foreign key
    await db.execute('''
      CREATE TABLE chunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        document_name TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        content TEXT NOT NULL,
        FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
      )
    ''');

    // Create index for faster chunk retrieval
    await db.execute('CREATE INDEX idx_chunks_document ON chunks(document_id)');
  }

  // ============== Document Operations ==============

  /// Insert a new document and return its ID
  Future<int> insertDocument(RagDocument doc) async {
    final db = await database;
    final map = doc.toMap();
    map.remove('id'); // Let SQLite auto-generate the ID
    return await db.insert('documents', map);
  }

  /// Get all documents ordered by creation date (newest first)
  Future<List<RagDocument>> getAllDocuments() async {
    final db = await database;
    final maps = await db.query('documents', orderBy: 'created_at DESC');
    return maps.map((m) => RagDocument.fromMap(m)).toList();
  }

  /// Get a document by ID
  Future<RagDocument?> getDocument(int id) async {
    final db = await database;
    final maps = await db.query('documents', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return RagDocument.fromMap(maps.first);
  }

  /// Delete a document and its chunks
  Future<void> deleteDocument(int id) async {
    final db = await database;
    // Delete chunks first (or rely on CASCADE)
    await db.delete('chunks', where: 'document_id = ?', whereArgs: [id]);
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
  }

  /// Update the chunk count for a document
  Future<void> updateDocumentChunkCount(int docId, int count) async {
    final db = await database;
    await db.update(
      'documents',
      {'chunk_count': count},
      where: 'id = ?',
      whereArgs: [docId],
    );
  }

  // ============== Chunk Operations ==============

  /// Insert multiple chunks efficiently using batch
  Future<void> insertChunks(List<DocumentChunk> chunks) async {
    final db = await database;
    final batch = db.batch();
    for (final chunk in chunks) {
      final map = chunk.toMap();
      map.remove('id'); // Let SQLite auto-generate the ID
      batch.insert('chunks', map);
    }
    await batch.commit(noResult: true);
  }

  /// Get all chunks (for retrieval indexing)
  Future<List<DocumentChunk>> getAllChunks() async {
    final db = await database;
    final maps = await db.query('chunks');
    return maps.map((m) => DocumentChunk.fromMap(m)).toList();
  }

  /// Get chunks for a specific document
  Future<List<DocumentChunk>> getChunksForDocument(int documentId) async {
    final db = await database;
    final maps = await db.query(
      'chunks',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'chunk_index ASC',
    );
    return maps.map((m) => DocumentChunk.fromMap(m)).toList();
  }

  /// Delete all chunks for a document
  Future<void> deleteChunksForDocument(int documentId) async {
    final db = await database;
    await db.delete('chunks', where: 'document_id = ?', whereArgs: [documentId]);
  }

  // ============== Utility Operations ==============

  /// Get total count of documents
  Future<int> getDocumentCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM documents');
    return sqflite.Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total count of chunks
  Future<int> getChunkCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM chunks');
    return sqflite.Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clear all data (for testing/reset)
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('chunks');
    await db.delete('documents');
  }

  /// Close the database connection
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}

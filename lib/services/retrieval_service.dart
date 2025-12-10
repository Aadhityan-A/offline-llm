import 'dart:math';
import 'package:offline_llm/models/rag_document.dart';

/// Service for retrieving relevant document chunks using keyword/TF-IDF matching
/// Works completely offline without requiring embedding models
class RetrievalService {
  // Cached chunks and IDF values for performance
  List<DocumentChunk> _cachedChunks = [];
  Map<String, double>? _idfScores;
  Map<int, Set<String>>? _chunkTerms;

  /// Load chunks into the search index
  void loadChunks(List<DocumentChunk> chunks) {
    _cachedChunks.addAll(chunks);
    // Invalidate IDF cache to trigger rebuild on next search
    _idfScores = null;
    _chunkTerms = null;
  }

  /// Remove chunks for a specific document
  void removeDocument(int documentId) {
    _cachedChunks.removeWhere((chunk) => chunk.documentId == documentId);
    // Invalidate IDF cache to trigger rebuild on next search
    _idfScores = null;
    _chunkTerms = null;
  }

  /// Search for relevant chunks based on a query
  /// Returns a list of RetrievalResult sorted by relevance
  List<RetrievalResult> search(String query, {int topK = 3, double minScore = 0.1}) {
    if (_cachedChunks.isEmpty) {
      return [];
    }

    // Build index if needed
    if (_idfScores == null) {
      _buildIndex();
    }
    
    final queryTerms = _tokenize(query.toLowerCase());
    if (queryTerms.isEmpty) return [];
    
    // Score each chunk based on query relevance
    final scored = <RetrievalResult>[];
    
    for (int i = 0; i < _cachedChunks.length; i++) {
      final chunk = _cachedChunks[i];
      final chunkTermSet = _chunkTerms?[i] ?? {};
      
      final score = _calculateTfIdfScore(queryTerms, chunkTermSet, chunk.content);
      
      if (score > minScore) {
        scored.add(RetrievalResult(
          chunk: chunk,
          score: score,
          sourceReference: chunk.documentName,
        ));
      }
    }
    
    // Sort by score descending
    scored.sort((a, b) => b.score.compareTo(a.score));
    
    // Return top K results
    return scored.take(topK).toList();
  }

  /// Build the search index with IDF scores
  void _buildIndex() {
    if (_cachedChunks.isEmpty) {
      return;
    }
    
    // Calculate document frequency for each term
    final docFreq = <String, int>{};
    _chunkTerms = {};
    
    for (int i = 0; i < _cachedChunks.length; i++) {
      final terms = _tokenize(_cachedChunks[i].content.toLowerCase());
      _chunkTerms![i] = terms;
      
      for (final term in terms) {
        docFreq[term] = (docFreq[term] ?? 0) + 1;
      }
    }
    
    // Calculate IDF scores: log(N / df)
    final n = _cachedChunks.length;
    _idfScores = {};
    
    for (final entry in docFreq.entries) {
      // Add smoothing to avoid division by zero
      _idfScores![entry.key] = log((n + 1) / (entry.value + 1)) + 1;
    }
  }

  /// Tokenize text into terms
  Set<String> _tokenize(String text) {
    // Remove punctuation and split into words
    return text
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2) // Skip very short words
        .where((w) => !_isStopWord(w)) // Skip common stop words
        .toSet();
  }

  /// Calculate TF-IDF based relevance score
  double _calculateTfIdfScore(Set<String> queryTerms, Set<String> chunkTerms, String chunkContent) {
    if (queryTerms.isEmpty || chunkTerms.isEmpty) return 0;
    
    // Find matching terms
    final matchingTerms = queryTerms.intersection(chunkTerms);
    if (matchingTerms.isEmpty) return 0;
    
    double score = 0;
    final chunkLower = chunkContent.toLowerCase();
    
    for (final term in matchingTerms) {
      // Term frequency in chunk (normalized)
      final tf = _countOccurrences(chunkLower, term) / (chunkContent.length / 100);
      
      // Inverse document frequency
      final idf = _idfScores?[term] ?? 1.0;
      
      score += tf * idf;
    }
    
    // Normalize by query length for fair comparison
    score /= queryTerms.length;
    
    // Boost score based on query coverage (what % of query terms matched)
    final coverage = matchingTerms.length / queryTerms.length;
    score *= (1 + coverage);
    
    return score;
  }

  /// Count occurrences of a term in text
  int _countOccurrences(String text, String term) {
    int count = 0;
    int index = 0;
    
    while ((index = text.indexOf(term, index)) != -1) {
      count++;
      index += term.length;
    }
    
    return count;
  }

  /// Check if a word is a common stop word
  bool _isStopWord(String word) {
    const stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
      'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were', 'been',
      'be', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
      'could', 'should', 'may', 'might', 'must', 'shall', 'can', 'need',
      'this', 'that', 'these', 'those', 'it', 'its', 'they', 'them', 'their',
      'we', 'our', 'you', 'your', 'he', 'she', 'his', 'her', 'him',
      'what', 'which', 'who', 'whom', 'whose', 'where', 'when', 'why', 'how',
      'all', 'each', 'every', 'both', 'few', 'more', 'most', 'other', 'some',
      'such', 'no', 'nor', 'not', 'only', 'own', 'same', 'so', 'than', 'too',
      'very', 'just', 'also', 'now', 'here', 'there', 'then', 'once',
    };
    
    return stopWords.contains(word.toLowerCase());
  }

  /// Clear the cache when documents change
  void clearCache() {
    _cachedChunks.clear();
    _idfScores = null;
    _chunkTerms = null;
  }

  /// Get cache status (for debugging)
  Map<String, dynamic> getCacheStatus() {
    return {
      'chunksLoaded': _cachedChunks.length,
      'termsIndexed': _idfScores?.length ?? 0,
      'isCached': _idfScores != null,
    };
  }
}

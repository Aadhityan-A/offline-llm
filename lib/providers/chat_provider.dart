import 'package:flutter/material.dart';
import 'package:offline_llm/models/chat_message.dart';
import 'package:offline_llm/services/llm_service.dart';

class ChatProvider extends ChangeNotifier {
  final LLMService _llmService = LLMService();
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  bool _isModelLoaded = false;
  String? _loadedModelName;
  String _currentResponse = '';
  String? _error;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isGenerating => _isGenerating;
  bool get isModelLoaded => _isModelLoaded;
  String? get loadedModelName => _loadedModelName;
  String get currentResponse => _currentResponse;
  String? get error => _error;
  LLMService get llmService => _llmService;

  Future<void> loadModel(String modelPath) async {
    try {
      _error = null;
      await _llmService.loadModel(modelPath);
      _isModelLoaded = true;
      _loadedModelName = modelPath.split('/').last.split('\\').last;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load model: $e';
      _isModelLoaded = false;
      _loadedModelName = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;
    if (!_isModelLoaded) {
      _error = 'Please load a model first';
      notifyListeners();
      return;
    }

    // Add user message
    _messages.add(ChatMessage(content: content, isUser: true));
    _isGenerating = true;
    _currentResponse = '';
    _error = null;
    notifyListeners();

    try {
      // Build conversation context
      final prompt = _buildPrompt(content);
      
      // Stream response
      await for (final chunk in _llmService.generateStream(prompt)) {
        _currentResponse += chunk;
        notifyListeners();
      }

      // Add assistant message
      _messages.add(ChatMessage(
        content: _currentResponse.trim(),
        isUser: false,
      ));
    } catch (e) {
      _error = 'Error generating response: $e';
      _messages.add(ChatMessage(
        content: 'Error: $e',
        isUser: false,
        isError: true,
      ));
    } finally {
      _isGenerating = false;
      _currentResponse = '';
      notifyListeners();
    }
  }

  String _buildPrompt(String userMessage) {
    // Build a simple chat prompt
    final buffer = StringBuffer();
    
    // Add system context
    buffer.writeln('You are a helpful AI assistant. Respond concisely and helpfully.');
    buffer.writeln();
    
    // Add recent conversation history (last 4 exchanges)
    final recentMessages = _messages.length > 8 
        ? _messages.sublist(_messages.length - 8) 
        : _messages;
    
    for (final msg in recentMessages) {
      if (msg.isUser) {
        buffer.writeln('User: ${msg.content}');
      } else if (!msg.isError) {
        buffer.writeln('Assistant: ${msg.content}');
      }
    }
    
    // Add current user message
    buffer.writeln('User: $userMessage');
    buffer.writeln('Assistant:');
    
    return buffer.toString();
  }

  void stopGeneration() {
    _llmService.stopGeneration();
    _isGenerating = false;
    if (_currentResponse.isNotEmpty) {
      _messages.add(ChatMessage(
        content: '${_currentResponse.trim()} [stopped]',
        isUser: false,
      ));
    }
    _currentResponse = '';
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    _error = null;
    notifyListeners();
  }

  void unloadModel() {
    _llmService.unloadModel();
    _isModelLoaded = false;
    _loadedModelName = null;
    clearMessages();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _llmService.dispose();
    super.dispose();
  }
}

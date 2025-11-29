import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:offline_llm/models/chat_message.dart';
import 'package:offline_llm/services/llm_service.dart';

/// Enum for different model prompt formats
/// These map to llama.cpp's built-in chat templates
enum PromptFormat {
  llama3,      // Llama 3.x/3.1/3.2/3.3 Instruct format
  llama2,      // Llama 2 format with [INST]
  chatml,      // ChatML format (Qwen 2.5, Yi, many others)
  phi3,        // Phi-3/3.5/4 format
  mistral,     // Mistral v1/v3/v7/Nemo format
  deepseek,    // DeepSeek V2/V3 format
  deepseekR1,  // DeepSeek R1 with thinking tags
  gemma,       // Google Gemma format
  alpaca,      // Alpaca format
  vicuna,      // Vicuna format  
  generic,     // Simple User/Assistant format
}

class ChatProvider extends ChangeNotifier {
  final LLMService _llmService = LLMService();
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  bool _isModelLoaded = false;
  String? _loadedModelName;
  String _currentResponse = '';
  String? _error;
  PromptFormat _promptFormat = PromptFormat.llama3;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isGenerating => _isGenerating;
  bool get isModelLoaded => _isModelLoaded;
  String? get loadedModelName => _loadedModelName;
  String get currentResponse => _currentResponse;
  String? get error => _error;
  LLMService get llmService => _llmService;
  PromptFormat get promptFormat => _promptFormat;

  void setPromptFormat(PromptFormat format) {
    _promptFormat = format;
    notifyListeners();
  }

  Future<void> loadModel(String modelPath) async {
    try {
      _error = null;
      await _llmService.loadModel(modelPath);
      _isModelLoaded = true;
      _loadedModelName = modelPath.split('/').last.split('\\').last;
      
      // Auto-detect prompt format based on model name
      _promptFormat = _detectPromptFormat(modelPath.toLowerCase());
      
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load model: $e';
      _isModelLoaded = false;
      _loadedModelName = null;
      notifyListeners();
      rethrow;
    }
  }

  /// Auto-detect the prompt format based on model filename
  PromptFormat _detectPromptFormat(String modelPath) {
    final lowerPath = modelPath.toLowerCase();
    
    // Llama 3.x series
    if (lowerPath.contains('llama-3') || 
        lowerPath.contains('llama3') ||
        lowerPath.contains('llama32') ||
        lowerPath.contains('llama-32') ||
        lowerPath.contains('llama31') ||
        lowerPath.contains('llama-31') ||
        lowerPath.contains('llama33') ||
        lowerPath.contains('llama-33')) {
      return PromptFormat.llama3;
    }
    
    // Llama 2 series
    if (lowerPath.contains('llama-2') || lowerPath.contains('llama2')) {
      return PromptFormat.llama2;
    }
    
    // DeepSeek R1 (with thinking)
    if (lowerPath.contains('deepseek-r1') || 
        lowerPath.contains('deepseek_r1') ||
        lowerPath.contains('deepseekr1')) {
      return PromptFormat.deepseekR1;
    }
    
    // DeepSeek (without thinking)
    if (lowerPath.contains('deepseek')) {
      return PromptFormat.deepseek;
    }
    
    // Phi-3/4 series
    if (lowerPath.contains('phi-3') || 
        lowerPath.contains('phi3') ||
        lowerPath.contains('phi-4') ||
        lowerPath.contains('phi4')) {
      return PromptFormat.phi3;
    }
    
    // Mistral series
    if (lowerPath.contains('mistral') || lowerPath.contains('mixtral')) {
      return PromptFormat.mistral;
    }
    
    // Gemma series
    if (lowerPath.contains('gemma')) {
      return PromptFormat.gemma;
    }
    
    // ChatML models (Qwen, Yi, etc.)
    if (lowerPath.contains('chatml') || 
        lowerPath.contains('qwen') ||
        lowerPath.contains('yi-') ||
        lowerPath.contains('qwq')) {
      return PromptFormat.chatml;
    }
    
    // Alpaca
    if (lowerPath.contains('alpaca')) {
      return PromptFormat.alpaca;
    }
    
    // Vicuna
    if (lowerPath.contains('vicuna')) {
      return PromptFormat.vicuna;
    }
    
    // Default to Llama 3 format for modern models
    return PromptFormat.llama3;
  }

  /// Get the llama.cpp chat template name for the current format
  String? getChatTemplateName() {
    switch (_promptFormat) {
      case PromptFormat.llama3:
        return 'llama3';
      case PromptFormat.llama2:
        return 'llama2';
      case PromptFormat.chatml:
        return 'chatml';
      case PromptFormat.phi3:
        return 'phi3';
      case PromptFormat.mistral:
        return 'mistral-v3';
      case PromptFormat.deepseek:
        return 'deepseek3';
      case PromptFormat.deepseekR1:
        return 'deepseek3';
      case PromptFormat.gemma:
        return 'gemma';
      case PromptFormat.alpaca:
      case PromptFormat.vicuna:
      case PromptFormat.generic:
        return null; // Use manual formatting
    }
  }

  Future<void> sendMessage(String content, {String? ragContext, List<String>? sourceDocuments}) async {
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
      // Build conversation context with proper format (with optional RAG context)
      final prompt = _buildPrompt(content, ragContext: ragContext);
      
      // Stream response
      await for (final chunk in _llmService.generateStream(prompt)) {
        _currentResponse += chunk;
        notifyListeners();
      }

      // Clean up the response (remove special tokens, extract reasoning)
      final result = _cleanResponseWithReasoning(_currentResponse);

      // Add assistant message if we have content
      if (result.content.isNotEmpty) {
        _messages.add(ChatMessage(
          content: result.content,
          isUser: false,
          reasoning: result.reasoning,
          sourceDocuments: sourceDocuments,
        ));
      }
    } catch (e) {
      _error = 'Error generating response: $e';
      if (_currentResponse.isNotEmpty) {
        // Save partial response if we have one
        _messages.add(ChatMessage(
          content: '${_cleanResponse(_currentResponse)} [incomplete]',
          isUser: false,
          isError: true,
        ));
      } else {
        _messages.add(ChatMessage(
          content: 'Error: $e',
          isUser: false,
          isError: true,
        ));
      }
    } finally {
      _isGenerating = false;
      _currentResponse = '';
      notifyListeners();
    }
  }

  /// Clean the model response by removing special tokens and artifacts
  /// Returns a record with cleaned content and optional extracted reasoning
  ({String content, String? reasoning}) _cleanResponseWithReasoning(String response) {
    String cleaned = response;
    String? reasoning;
    
    // Extract thinking/reasoning content for DeepSeek R1 and similar models
    final thinkingPatterns = [
      RegExp(r'<think>(.*?)</think>', dotAll: true),
      RegExp(r'<thinking>(.*?)</thinking>', dotAll: true),
      RegExp(r'<｜thinking｜>(.*?)<｜/thinking｜>', dotAll: true),
    ];
    
    for (final pattern in thinkingPatterns) {
      final match = pattern.firstMatch(cleaned);
      if (match != null) {
        reasoning = match.group(1)?.trim();
        cleaned = cleaned.replaceAll(pattern, '').trim();
        break;
      }
    }
    
    // Remove common special tokens from various model formats
    final tokensToRemove = [
      // Llama 3.x tokens
      '<|eot_id|>',
      '<|end_of_text|>',
      '<|eom_id|>',
      '<|begin_of_text|>',
      '<|start_header_id|>',
      '<|end_header_id|>',
      '<|python_tag|>',
      
      // ChatML tokens
      '<|im_end|>',
      '<|im_start|>',
      
      // Phi-3/4 tokens
      '<|end|>',
      '<|system|>',
      '<|user|>',
      '<|assistant|>',
      
      // Mistral tokens
      '</s>',
      '<s>',
      '[INST]',
      '[/INST]',
      '[AVAILABLE_TOOLS]',
      '[/AVAILABLE_TOOLS]',
      '[TOOL_CALLS]',
      
      // DeepSeek tokens (with Unicode special chars)
      '<｜end▁of▁sentence｜>',
      '<｜User｜>',
      '<｜Assistant｜>',
      '<｜tool▁calls▁begin｜>',
      '<｜tool▁call▁begin｜>',
      '<｜tool▁sep｜>',
      '<｜tool▁call▁end｜>',
      '<｜tool▁calls▁end｜>',
      
      // Gemma tokens
      '<start_of_turn>',
      '<end_of_turn>',
      
      // Generic tokens
      '### Response:',
      '### Assistant:',
      'ASSISTANT:',
      'USER:',
    ];
    
    for (final token in tokensToRemove) {
      cleaned = cleaned.replaceAll(token, '');
    }
    
    // Remove any lines that only contain special markup
    final lines = cleaned.split('\n');
    final cleanedLines = lines.where((line) {
      final trimmed = line.trim();
      return !trimmed.startsWith('<|') && 
             !trimmed.endsWith('|>') &&
             !trimmed.startsWith('<｜') &&
             !trimmed.endsWith('｜>') &&
             trimmed != 'assistant' &&
             trimmed != 'user' &&
             trimmed != 'system' &&
             trimmed != 'model';
    }).toList();
    
    cleaned = cleanedLines.join('\n');
    
    // Trim whitespace
    cleaned = cleaned.trim();
    
    return (content: cleaned, reasoning: reasoning);
  }

  /// Clean the model response (backward compatible wrapper)
  String _cleanResponse(String response) {
    return _cleanResponseWithReasoning(response).content;
  }

  String _buildPrompt(String userMessage, {String? ragContext}) {
    switch (_promptFormat) {
      case PromptFormat.llama3:
        return _buildLlama3Prompt(userMessage, ragContext: ragContext);
      case PromptFormat.llama2:
        return _buildLlama2Prompt(userMessage, ragContext: ragContext);
      case PromptFormat.chatml:
        return _buildChatMLPrompt(userMessage, ragContext: ragContext);
      case PromptFormat.phi3:
        return _buildPhi3Prompt(userMessage, ragContext: ragContext);
      case PromptFormat.mistral:
        return _buildMistralPrompt(userMessage, ragContext: ragContext);
      case PromptFormat.deepseek:
        return _buildDeepSeekPrompt(userMessage, ragContext: ragContext);
      case PromptFormat.deepseekR1:
        return _buildDeepSeekR1Prompt(userMessage, ragContext: ragContext);
      case PromptFormat.gemma:
        return _buildGemmaPrompt(userMessage, ragContext: ragContext);
      case PromptFormat.alpaca:
        return _buildAlpacaPrompt(userMessage, ragContext: ragContext);
      case PromptFormat.vicuna:
        return _buildVicunaPrompt(userMessage, ragContext: ragContext);
      case PromptFormat.generic:
        return _buildGenericPrompt(userMessage, ragContext: ragContext);
    }
  }

  /// Build the RAG-enhanced system prompt
  String _buildRagSystemPrompt(String basePrompt, String? ragContext) {
    if (ragContext == null || ragContext.isEmpty) {
      return basePrompt;
    }
    return '''$basePrompt

$ragContext

When answering, if you use information from the uploaded documents, reference the source document in brackets like [document_name.pdf] at the end of the relevant sentence or paragraph.''';
  }

  /// Build Llama 2 format prompt
  String _buildLlama2Prompt(String userMessage, {String? ragContext}) {
    final buffer = StringBuffer();
    
    final systemPrompt = _buildRagSystemPrompt(
      'You are a helpful, concise AI assistant. Provide clear and accurate responses.',
      ragContext,
    );
    
    buffer.write('<s>[INST] <<SYS>>\n');
    buffer.write('$systemPrompt\n');
    buffer.write('<</SYS>>\n\n');
    
    // Add conversation history
    final recentMessages = _messages.length > 6 
        ? _messages.sublist(_messages.length - 6) 
        : _messages;
    
    bool firstUser = true;
    for (final msg in recentMessages) {
      if (msg.isUser) {
        if (!firstUser) {
          buffer.write('<s>[INST] ');
        }
        buffer.write('${msg.content} [/INST]');
        firstUser = false;
      } else if (!msg.isError) {
        buffer.write(' ${msg.content} </s>');
      }
    }
    
    // Current user message
    if (!firstUser) {
      buffer.write('<s>[INST] ');
    }
    buffer.write('$userMessage [/INST]');
    
    return buffer.toString();
  }

  /// Build Phi-3/4 format prompt
  String _buildPhi3Prompt(String userMessage, {String? ragContext}) {
    final buffer = StringBuffer();
    
    final systemPrompt = _buildRagSystemPrompt(
      'You are a helpful, concise AI assistant.',
      ragContext,
    );
    
    buffer.writeln('<|system|>');
    buffer.writeln(systemPrompt);
    buffer.writeln('<|end|>');
    
    // Add conversation history
    final recentMessages = _messages.length > 6 
        ? _messages.sublist(_messages.length - 6) 
        : _messages;
    
    for (final msg in recentMessages) {
      if (msg.isUser) {
        buffer.writeln('<|user|>');
        buffer.writeln(msg.content);
        buffer.writeln('<|end|>');
      } else if (!msg.isError) {
        buffer.writeln('<|assistant|>');
        buffer.writeln(msg.content);
        buffer.writeln('<|end|>');
      }
    }
    
    // Current user message
    buffer.writeln('<|user|>');
    buffer.writeln(userMessage);
    buffer.writeln('<|end|>');
    buffer.write('<|assistant|>\n');
    
    return buffer.toString();
  }

  /// Build Mistral format prompt
  String _buildMistralPrompt(String userMessage, {String? ragContext}) {
    final buffer = StringBuffer();
    
    // Mistral uses [INST] format, add RAG context as part of first instruction
    final recentMessages = _messages.length > 6 
        ? _messages.sublist(_messages.length - 6) 
        : _messages;
    
    bool isFirst = true;
    for (final msg in recentMessages) {
      if (msg.isUser) {
        if (isFirst && ragContext != null && ragContext.isNotEmpty) {
          buffer.write('[INST] $ragContext\n\nWhen answering, if you use information from the uploaded documents, reference the source document in brackets like [document_name.pdf].\n\n${msg.content} [/INST]');
          isFirst = false;
        } else {
          buffer.write('[INST] ${msg.content} [/INST]');
        }
      } else if (!msg.isError) {
        buffer.write('${msg.content}</s>');
      }
    }
    
    // Current user message
    if (isFirst && ragContext != null && ragContext.isNotEmpty) {
      buffer.write('[INST] $ragContext\n\nWhen answering, if you use information from the uploaded documents, reference the source document in brackets like [document_name.pdf].\n\n$userMessage [/INST]');
    } else {
      buffer.write('[INST] $userMessage [/INST]');
    }
    
    return buffer.toString();
  }

  /// Build DeepSeek format prompt (without thinking)
  String _buildDeepSeekPrompt(String userMessage, {String? ragContext}) {
    final buffer = StringBuffer();
    
    final systemPrompt = _buildRagSystemPrompt(
      'You are a helpful, concise AI assistant.',
      ragContext,
    );
    
    buffer.write('<｜begin▁of▁sentence｜>');
    
    // System message
    buffer.write('<｜System｜>$systemPrompt<｜end▁of▁sentence｜>');
    
    // Add conversation history
    final recentMessages = _messages.length > 6 
        ? _messages.sublist(_messages.length - 6) 
        : _messages;
    
    for (final msg in recentMessages) {
      if (msg.isUser) {
        buffer.write('<｜User｜>${msg.content}<｜end▁of▁sentence｜>');
      } else if (!msg.isError) {
        buffer.write('<｜Assistant｜>${msg.content}<｜end▁of▁sentence｜>');
      }
    }
    
    // Current user message
    buffer.write('<｜User｜>$userMessage<｜end▁of▁sentence｜>');
    buffer.write('<｜Assistant｜>');
    
    return buffer.toString();
  }

  /// Build DeepSeek R1 format prompt (with thinking enabled)
  String _buildDeepSeekR1Prompt(String userMessage, {String? ragContext}) {
    final buffer = StringBuffer();
    
    final systemPrompt = _buildRagSystemPrompt(
      'You are a helpful AI assistant. Think step by step before answering.',
      ragContext,
    );
    
    buffer.write('<｜begin▁of▁sentence｜>');
    
    // System message
    buffer.write('<｜System｜>$systemPrompt<｜end▁of▁sentence｜>');
    
    // Add conversation history
    final recentMessages = _messages.length > 6 
        ? _messages.sublist(_messages.length - 6) 
        : _messages;
    
    for (final msg in recentMessages) {
      if (msg.isUser) {
        buffer.write('<｜User｜>${msg.content}<｜end▁of▁sentence｜>');
      } else if (!msg.isError) {
        // Include reasoning if available
        if (msg.hasReasoning) {
          buffer.write('<｜Assistant｜><think>${msg.reasoning}</think>${msg.content}<｜end▁of▁sentence｜>');
        } else {
          buffer.write('<｜Assistant｜>${msg.content}<｜end▁of▁sentence｜>');
        }
      }
    }
    
    // Current user message
    buffer.write('<｜User｜>$userMessage<｜end▁of▁sentence｜>');
    buffer.write('<｜Assistant｜>');
    
    return buffer.toString();
  }

  /// Build Gemma format prompt
  String _buildGemmaPrompt(String userMessage, {String? ragContext}) {
    final buffer = StringBuffer();
    
    // Gemma doesn't have a system turn, so prepend RAG context to first user turn
    final recentMessages = _messages.length > 6 
        ? _messages.sublist(_messages.length - 6) 
        : _messages;
    
    bool isFirst = true;
    for (final msg in recentMessages) {
      if (msg.isUser) {
        if (isFirst && ragContext != null && ragContext.isNotEmpty) {
          buffer.write('<start_of_turn>user\n$ragContext\n\nWhen answering, if you use information from the uploaded documents, reference the source document in brackets like [document_name.pdf].\n\n${msg.content}<end_of_turn>\n');
          isFirst = false;
        } else {
          buffer.write('<start_of_turn>user\n${msg.content}<end_of_turn>\n');
        }
      } else if (!msg.isError) {
        buffer.write('<start_of_turn>model\n${msg.content}<end_of_turn>\n');
      }
    }
    
    // Current user message
    if (isFirst && ragContext != null && ragContext.isNotEmpty) {
      buffer.write('<start_of_turn>user\n$ragContext\n\nWhen answering, if you use information from the uploaded documents, reference the source document in brackets like [document_name.pdf].\n\n$userMessage<end_of_turn>\n');
    } else {
      buffer.write('<start_of_turn>user\n$userMessage<end_of_turn>\n');
    }
    buffer.write('<start_of_turn>model\n');
    
    return buffer.toString();
  }

  /// Build Llama 3.x Instruct format prompt
  String _buildLlama3Prompt(String userMessage, {String? ragContext}) {
    final buffer = StringBuffer();
    
    final systemPrompt = _buildRagSystemPrompt(
      'You are a helpful, concise AI assistant. Provide clear and accurate responses.',
      ragContext,
    );
    
    // Begin of text token
    buffer.write('<|begin_of_text|>');
    
    // System message
    buffer.write('<|start_header_id|>system<|end_header_id|>\n\n');
    buffer.write(systemPrompt);
    buffer.write('<|eot_id|>');
    
    // Add conversation history (last 6 messages to avoid context overflow)
    final recentMessages = _messages.length > 6 
        ? _messages.sublist(_messages.length - 6) 
        : _messages;
    
    for (final msg in recentMessages) {
      if (msg.isUser) {
        buffer.write('<|start_header_id|>user<|end_header_id|>\n\n');
        buffer.write(msg.content);
        buffer.write('<|eot_id|>');
      } else if (!msg.isError) {
        buffer.write('<|start_header_id|>assistant<|end_header_id|>\n\n');
        buffer.write(msg.content);
        buffer.write('<|eot_id|>');
      }
    }
    
    // Current user message
    buffer.write('<|start_header_id|>user<|end_header_id|>\n\n');
    buffer.write(userMessage);
    buffer.write('<|eot_id|>');
    
    // Assistant turn start
    buffer.write('<|start_header_id|>assistant<|end_header_id|>\n\n');
    
    return buffer.toString();
  }

  /// Build ChatML format prompt
  String _buildChatMLPrompt(String userMessage, {String? ragContext}) {
    final buffer = StringBuffer();
    
    final systemPrompt = _buildRagSystemPrompt(
      'You are a helpful, concise AI assistant.',
      ragContext,
    );
    
    // System message
    buffer.writeln('<|im_start|>system');
    buffer.writeln(systemPrompt);
    buffer.writeln('<|im_end|>');
    
    // Add conversation history
    final recentMessages = _messages.length > 6 
        ? _messages.sublist(_messages.length - 6) 
        : _messages;
    
    for (final msg in recentMessages) {
      if (msg.isUser) {
        buffer.writeln('<|im_start|>user');
        buffer.writeln(msg.content);
        buffer.writeln('<|im_end|>');
      } else if (!msg.isError) {
        buffer.writeln('<|im_start|>assistant');
        buffer.writeln(msg.content);
        buffer.writeln('<|im_end|>');
      }
    }
    
    // Current user message
    buffer.writeln('<|im_start|>user');
    buffer.writeln(userMessage);
    buffer.writeln('<|im_end|>');
    
    // Assistant turn start
    buffer.write('<|im_start|>assistant\n');
    
    return buffer.toString();
  }

  /// Build Alpaca format prompt
  String _buildAlpacaPrompt(String userMessage, {String? ragContext}) {
    final buffer = StringBuffer();
    
    buffer.writeln('Below is an instruction that describes a task. Write a response that appropriately completes the request.');
    buffer.writeln();
    
    // Add RAG context if available
    if (ragContext != null && ragContext.isNotEmpty) {
      buffer.writeln('### Context:');
      buffer.writeln(ragContext);
      buffer.writeln('When answering, if you use information from the uploaded documents, reference the source document in brackets like [document_name.pdf].');
      buffer.writeln();
    }
    
    // Add conversation history as context
    final recentMessages = _messages.length > 4 
        ? _messages.sublist(_messages.length - 4) 
        : _messages;
    
    if (recentMessages.isNotEmpty) {
      buffer.writeln('### Previous conversation:');
      for (final msg in recentMessages) {
        if (msg.isUser) {
          buffer.writeln('User: ${msg.content}');
        } else if (!msg.isError) {
          buffer.writeln('Assistant: ${msg.content}');
        }
      }
      buffer.writeln();
    }
    
    buffer.writeln('### Instruction:');
    buffer.writeln(userMessage);
    buffer.writeln();
    buffer.write('### Response:\n');
    
    return buffer.toString();
  }

  /// Build Vicuna format prompt
  String _buildVicunaPrompt(String userMessage, {String? ragContext}) {
    final buffer = StringBuffer();
    
    buffer.writeln('A chat between a curious user and an artificial intelligence assistant. The assistant gives helpful, detailed, and polite answers to the user\'s questions.');
    buffer.writeln();
    
    // Add RAG context if available
    if (ragContext != null && ragContext.isNotEmpty) {
      buffer.writeln('CONTEXT: $ragContext');
      buffer.writeln('When answering, if you use information from the uploaded documents, reference the source document in brackets like [document_name.pdf].');
      buffer.writeln();
    }
    
    // Add conversation history
    final recentMessages = _messages.length > 6 
        ? _messages.sublist(_messages.length - 6) 
        : _messages;
    
    for (final msg in recentMessages) {
      if (msg.isUser) {
        buffer.writeln('USER: ${msg.content}');
      } else if (!msg.isError) {
        buffer.writeln('ASSISTANT: ${msg.content}');
      }
    }
    
    buffer.writeln('USER: $userMessage');
    buffer.write('ASSISTANT: ');
    
    return buffer.toString();
  }

  /// Build simple generic format prompt
  String _buildGenericPrompt(String userMessage, {String? ragContext}) {
    final buffer = StringBuffer();
    
    buffer.writeln('You are a helpful AI assistant. Respond concisely and helpfully.');
    buffer.writeln();
    
    // Add RAG context if available
    if (ragContext != null && ragContext.isNotEmpty) {
      buffer.writeln('Context from uploaded documents:');
      buffer.writeln(ragContext);
      buffer.writeln('When answering, if you use information from the uploaded documents, reference the source document in brackets like [document_name.pdf].');
      buffer.writeln();
    }
    
    // Add conversation history
    final recentMessages = _messages.length > 6 
        ? _messages.sublist(_messages.length - 6) 
        : _messages;
    
    for (final msg in recentMessages) {
      if (msg.isUser) {
        buffer.writeln('User: ${msg.content}');
      } else if (!msg.isError) {
        buffer.writeln('Assistant: ${msg.content}');
      }
    }
    
    buffer.writeln('User: $userMessage');
    buffer.write('Assistant: ');
    
    return buffer.toString();
  }

  void stopGeneration() {
    _llmService.stopGeneration();
    _isGenerating = false;
    if (_currentResponse.isNotEmpty) {
      final cleaned = _cleanResponse(_currentResponse);
      if (cleaned.isNotEmpty) {
        _messages.add(ChatMessage(
          content: '$cleaned [stopped]',
          isUser: false,
        ));
      }
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

  /// Export chat history to JSON file
  Future<bool> exportChatToJson() async {
    if (_messages.isEmpty) {
      _error = 'No messages to export';
      notifyListeners();
      return false;
    }

    try {
      final exportData = {
        'version': '1.0',
        'appName': 'Offline LLM',
        'exportedAt': DateTime.now().toIso8601String(),
        'modelName': _loadedModelName,
        'promptFormat': _promptFormat.name,
        'messageCount': _messages.length,
        'messages': _messages.map((m) => m.toJson()).toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      
      // Generate default filename with timestamp
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final defaultName = 'chat_export_$timestamp.json';

      // Use FilePicker for cross-platform save dialog
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Chat History',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputPath != null) {
        final file = File(outputPath);
        await file.writeAsString(jsonString);
        return true;
      }
      return false;
    } catch (e) {
      _error = 'Failed to export chat: $e';
      notifyListeners();
      return false;
    }
  }

  /// Import chat history from JSON file
  Future<bool> importChatFromJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
        dialogTitle: 'Import Chat History',
      );

      if (result == null || result.files.isEmpty) {
        return false;
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        _error = 'Could not access the selected file';
        notifyListeners();
        return false;
      }

      final file = File(filePath);
      final jsonString = await file.readAsString();
      final data = json.decode(jsonString) as Map<String, dynamic>;

      // Validate the import data
      if (!data.containsKey('messages') || !data.containsKey('version')) {
        _error = 'Invalid chat export file format';
        notifyListeners();
        return false;
      }

      final messagesData = data['messages'] as List<dynamic>;
      final importedMessages = messagesData
          .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
          .toList();

      // Optionally restore prompt format if model matches
      if (data.containsKey('promptFormat')) {
        final formatName = data['promptFormat'] as String;
        try {
          _promptFormat = PromptFormat.values.firstWhere(
            (f) => f.name == formatName,
            orElse: () => PromptFormat.llama3,
          );
        } catch (_) {}
      }

      // Add imported messages to current chat
      _messages.addAll(importedMessages);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to import chat: $e';
      notifyListeners();
      return false;
    }
  }

  /// Get export data as JSON string (for sharing, clipboard, etc.)
  String getExportJsonString() {
    final exportData = {
      'version': '1.0',
      'appName': 'Offline LLM',
      'exportedAt': DateTime.now().toIso8601String(),
      'modelName': _loadedModelName,
      'promptFormat': _promptFormat.name,
      'messageCount': _messages.length,
      'messages': _messages.map((m) => m.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  @override
  void dispose() {
    _llmService.dispose();
    super.dispose();
  }
}

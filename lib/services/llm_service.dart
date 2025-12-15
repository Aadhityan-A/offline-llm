import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

/// Configuration for LLM generation parameters
class LLMConfig {
  final int maxTokens;
  final int contextSize;
  final double temperature;
  final double repeatPenalty;
  final int repeatLastN;
  final double topP;
  final int topK;
  final List<String> stopSequences;

  const LLMConfig({
    this.maxTokens = 512,
    this.contextSize = 2048,
    this.temperature = 0.7,
    this.repeatPenalty = 1.1,
    this.repeatLastN = 64,
    this.topP = 0.9,
    this.topK = 40,
    this.stopSequences = const [],
  });

  LLMConfig copyWith({
    int? maxTokens,
    int? contextSize,
    double? temperature,
    double? repeatPenalty,
    int? repeatLastN,
    double? topP,
    int? topK,
    List<String>? stopSequences,
  }) {
    return LLMConfig(
      maxTokens: maxTokens ?? this.maxTokens,
      contextSize: contextSize ?? this.contextSize,
      temperature: temperature ?? this.temperature,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      repeatLastN: repeatLastN ?? this.repeatLastN,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      stopSequences: stopSequences ?? this.stopSequences,
    );
  }
}

/// A wrapper service that manages llama.cpp operations
/// Uses Process to run llama-cli for maximum compatibility
class LLMService {
  String? _modelPath;
  bool _isLoaded = false;
  Process? _process;
  String? _llamaCliPath;
  bool _isGenerating = false;
  
  // Default configuration
  LLMConfig config = const LLMConfig();
  
  bool get isLoaded => _isLoaded;
  String? get modelPath => _modelPath;
  bool get isGenerating => _isGenerating;

  /// Load a GGUF model file
  Future<bool> loadModel(String modelPath) async {
    try {
      // Validate model file exists
      final file = File(modelPath);
      if (!await file.exists()) {
        throw Exception('Model file not found: $modelPath');
      }
      
      // Validate file extension
      if (!modelPath.toLowerCase().endsWith('.gguf')) {
        throw Exception('Invalid model format. Please use a .gguf file.');
      }
      
      // Validate file size (should be at least a few MB)
      final stat = await file.stat();
      if (stat.size < 1024 * 1024) { // Less than 1MB
        throw Exception('Model file appears to be corrupted or incomplete.');
      }
      
      // Find llama-cli before confirming model load
      _llamaCliPath = await _findLlamaCli();
      if (_llamaCliPath == null) {
        throw Exception(
          'llama-cli not found. Please ensure llama.cpp is properly installed.\n'
          'Expected locations: bin/llama-cli, lib/llama-cli, or system PATH.'
        );
      }
      
      _modelPath = modelPath;
      _isLoaded = true;
      return true;
    } catch (e) {
      _isLoaded = false;
      _modelPath = null;
      _llamaCliPath = null;
      rethrow;
    }
  }

  /// Build command line arguments for llama-cli
  /// If chatTemplate is provided, uses llama.cpp's built-in chat template
  List<String> _buildArgs(String prompt, LLMConfig cfg, {String? chatTemplate}) {
    final args = <String>[
      '-m', _modelPath!,
      '-p', prompt,
      '-n', cfg.maxTokens.toString(),
      '-c', cfg.contextSize.toString(),
      '--temp', cfg.temperature.toString(),
      '--repeat-penalty', cfg.repeatPenalty.toString(),
      '--repeat-last-n', cfg.repeatLastN.toString(),
      '--top-p', cfg.topP.toString(),
      '--top-k', cfg.topK.toString(),
      '--no-display-prompt',
      '-no-cnv',
    ];
    
    // On Windows, add --simple-io flag for unbuffered output (fixes streaming issues)
    if (Platform.isWindows) {
      args.add('--simple-io');
    }
    
    // Use native chat template if specified
    if (chatTemplate != null && chatTemplate.isNotEmpty) {
      args.addAll(['--chat-template', chatTemplate]);
    }
    
    // Add stop sequences using --reverse-prompt (correct llama-cli argument)
    for (final stop in cfg.stopSequences) {
      if (stop.isNotEmpty) {
        args.addAll(['-r', stop]);
      }
    }
    
    return args;
  }

  /// Set up environment variables for the process
  Map<String, String> _buildEnvironment() {
    final env = Map<String, String>.from(Platform.environment);
    final execDir = path.dirname(_llamaCliPath!);
    
    if (Platform.isLinux) {
      final existingLdPath = env['LD_LIBRARY_PATH'] ?? '';
      env['LD_LIBRARY_PATH'] = '$execDir:$existingLdPath';
    } else if (Platform.isMacOS) {
      final existingDylibPath = env['DYLD_LIBRARY_PATH'] ?? '';
      env['DYLD_LIBRARY_PATH'] = '$execDir:$existingDylibPath';
    }
    
    return env;
  }

  /// Generate a response using the loaded model (streaming)
  /// chatTemplate: optional llama.cpp chat template name (e.g., 'llama3', 'chatml', 'phi3')
  Stream<String> generateStream(String prompt, {LLMConfig? overrideConfig, String? chatTemplate}) async* {
    if (!_isLoaded || _modelPath == null) {
      throw Exception('No model loaded. Please load a model first.');
    }
    
    if (_llamaCliPath == null) {
      throw Exception('llama-cli not available.');
    }
    
    if (_isGenerating) {
      throw Exception('Generation already in progress. Please wait or stop the current generation.');
    }

    _isGenerating = true;
    
    try {
      // Use provided config or defaults (no stop sequences - rely on model's EOS token)
      final cfg = overrideConfig ?? config;
      
      final args = _buildArgs(prompt, cfg, chatTemplate: chatTemplate);
      final env = _buildEnvironment();

      // On Windows, use runInShell to help with stdout buffering issues
      _process = await Process.start(
        _llamaCliPath!, 
        args,
        environment: env,
        runInShell: Platform.isWindows,
      );
      
      // Buffer for detecting repetition
      final outputBuffer = StringBuffer();
      String lastChunk = '';
      int repetitionCount = 0;
      const maxRepetitions = 3;
      
      // On Windows, use a custom stream transformer for better streaming
      // Windows often has buffering issues with stdout
      if (Platform.isWindows) {
        // Use byte-level streaming for Windows to get real-time output
        final byteBuffer = <int>[];
        await for (final bytes in _process!.stdout) {
          byteBuffer.addAll(bytes);
          
          // Try to decode available bytes, handling incomplete UTF-8 sequences
          String decoded = '';
          int validEnd = byteBuffer.length;
          
          // Find the last valid UTF-8 boundary
          while (validEnd > 0) {
            try {
              decoded = utf8.decode(byteBuffer.sublist(0, validEnd));
              break;
            } catch (e) {
              validEnd--;
            }
          }
          
          if (decoded.isNotEmpty && validEnd > 0) {
            byteBuffer.removeRange(0, validEnd);
            
            // Detect repetitive output (model looping)
            if (decoded == lastChunk && decoded.length > 20) {
              repetitionCount++;
              if (repetitionCount >= maxRepetitions) {
                stopGeneration();
                break;
              }
            } else {
              repetitionCount = 0;
            }
            lastChunk = decoded;
            
            outputBuffer.write(decoded);
            yield decoded;
          }
        }
        
        // Flush any remaining bytes in buffer
        if (byteBuffer.isNotEmpty) {
          try {
            final remaining = utf8.decode(byteBuffer, allowMalformed: true);
            if (remaining.isNotEmpty) {
              yield remaining;
            }
          } catch (_) {}
        }
      } else {
        // Linux/macOS: Use standard stream transformer
        await for (final chunk in _process!.stdout.transform(const Utf8Decoder(allowMalformed: true))) {
          // Detect repetitive output (model looping)
          if (chunk == lastChunk && chunk.length > 20) {
            repetitionCount++;
            if (repetitionCount >= maxRepetitions) {
              // Model is looping, stop generation
              stopGeneration();
              break;
            }
          } else {
            repetitionCount = 0;
          }
          lastChunk = chunk;
          
          outputBuffer.write(chunk);
          yield chunk;
        }
      }

      // Collect stderr but don't throw for info messages
      final stderrOutput = await _process?.stderr.transform(utf8.decoder).join() ?? '';
      _processStderr(stderrOutput);

      await _process?.exitCode;
    } catch (e) {
      if (e.toString().contains('Process was killed')) {
        // User stopped generation, not an error
        return;
      }
      rethrow;
    } finally {
      _isGenerating = false;
      _process = null;
    }
  }

  /// Process stderr output, filtering out info messages and throwing on real errors
  void _processStderr(String stderr) {
    if (stderr.isEmpty) return;
    
    // Patterns that indicate info/warning messages, not errors
    final infoPatterns = [
      RegExp(r'^llama_', multiLine: true),
      RegExp(r'^llm_', multiLine: true),
      RegExp(r'^ggml_', multiLine: true),
      RegExp(r'^gguf', multiLine: true),
      RegExp(r'sampling', caseSensitive: false),
      RegExp(r'main:', caseSensitive: false),
      RegExp(r'sampler', caseSensitive: false),
      RegExp(r'generate:', caseSensitive: false),
      RegExp(r'n_predict', caseSensitive: false),
      RegExp(r'vocab', caseSensitive: false),
      RegExp(r'model size', caseSensitive: false),
      RegExp(r'warmup', caseSensitive: false),
      RegExp(r'load time', caseSensitive: false),
      RegExp(r'eval time', caseSensitive: false),
      RegExp(r'total time', caseSensitive: false),
      RegExp(r'tokens per second', caseSensitive: false),
      RegExp(r'^\s*$', multiLine: true), // empty lines
      RegExp(r'^\[', multiLine: true), // log prefixes like [timestamp]
      RegExp(r'ctx_size', caseSensitive: false),
      RegExp(r'batch', caseSensitive: false),
      RegExp(r'threads', caseSensitive: false),
      RegExp(r'memory', caseSensitive: false),
      RegExp(r'kv_cache', caseSensitive: false),
      RegExp(r'loading', caseSensitive: false),
    ];
    
    final lines = stderr.split('\n');
    final realErrors = <String>[];
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      
      bool isInfoMessage = false;
      for (final pattern in infoPatterns) {
        if (pattern.hasMatch(trimmed)) {
          isInfoMessage = true;
          break;
        }
      }
      
      if (!isInfoMessage) {
        realErrors.add(trimmed);
      }
    }
    
    // Only throw if there are actual error messages
    if (realErrors.isNotEmpty) {
      final errorMsg = realErrors.join('\n');
      // Check for common recoverable situations
      if (errorMsg.contains('context window') || errorMsg.contains('too long')) {
        throw Exception('Input too long for model context. Try a shorter message.');
      }
      // Don't throw for everything, just log warnings
      // throw Exception(errorMsg);
    }
  }

  /// Generate a complete response (non-streaming)
  Future<String> generate(String prompt, {LLMConfig? overrideConfig, String? chatTemplate}) async {
    final buffer = StringBuffer();
    await for (final chunk in generateStream(prompt, overrideConfig: overrideConfig, chatTemplate: chatTemplate)) {
      buffer.write(chunk);
    }
    return buffer.toString().trim();
  }

  /// Find llama-cli executable
  Future<String?> _findLlamaCli() async {
    // Get the executable's directory (for bundled apps)
    final execDir = path.dirname(Platform.resolvedExecutable);
    
    // Determine executable name based on platform
    final exeName = Platform.isWindows ? 'llama-cli.exe' : 'llama-cli';
    
    // Check common locations in order of priority
    final possiblePaths = <String>[
      // Bundled with app (most common for distributed apps)
      path.join(execDir, 'lib', exeName),
      path.join(execDir, exeName),
      path.join(execDir, 'bin', exeName),
      path.join(execDir, '..', 'lib', exeName),
      path.join(execDir, '..', 'Resources', exeName), // macOS app bundle
      
      // Development paths
      path.join(Directory.current.path, 'bin', exeName),
      path.join(Directory.current.path, exeName),
      
      // System paths
      '/usr/local/bin/llama-cli',
      '/usr/bin/llama-cli',
    ];

    // Check explicit paths first
    for (final p in possiblePaths) {
      try {
        if (await File(p).exists()) {
          // Verify it's executable
          if (!Platform.isWindows) {
            final result = await Process.run('test', ['-x', p]);
            if (result.exitCode != 0) continue;
          }
          return p;
        }
      } catch (_) {
        continue;
      }
    }

    // Check system PATH
    try {
      final command = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(command, ['llama-cli']);
      if (result.exitCode == 0) {
        final foundPath = (result.stdout as String).trim().split('\n').first;
        if (foundPath.isNotEmpty) {
          return foundPath;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Stop any ongoing generation
  void stopGeneration() {
    if (_process != null) {
      try {
        _process!.kill(ProcessSignal.sigterm);
      } catch (_) {
        try {
          _process!.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
      _process = null;
    }
    _isGenerating = false;
  }

  /// Unload the current model
  void unloadModel() {
    stopGeneration();
    _modelPath = null;
    _isLoaded = false;
    _llamaCliPath = null;
  }

  /// Dispose resources
  void dispose() {
    unloadModel();
  }
  
  /// Get model info (file name and size)
  Future<Map<String, dynamic>?> getModelInfo() async {
    if (_modelPath == null) return null;
    
    try {
      final file = File(_modelPath!);
      final stat = await file.stat();
      final sizeInMB = (stat.size / (1024 * 1024)).toStringAsFixed(1);
      
      return {
        'path': _modelPath,
        'name': path.basename(_modelPath!),
        'size': stat.size,
        'sizeFormatted': '${sizeInMB} MB',
      };
    } catch (_) {
      return null;
    }
  }
}

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
    StreamSubscription<String>? stderrSub;
    final stderrBuffer = StringBuffer();
    
    try {
      // Use provided config or defaults (no stop sequences - rely on model's EOS token)
      final cfg = overrideConfig ?? config;
      
      final args = _buildArgs(prompt, cfg, chatTemplate: chatTemplate);
      final env = _buildEnvironment();

      final process = await Process.start(
        _llamaCliPath!, 
        args,
        environment: env,
      );
      _process = process;

      // IMPORTANT:
      // Drain stderr concurrently while streaming stdout.
      // On Windows, if stderr isn't drained, the pipe buffer can fill and block
      // the process, making stdout appear to "not stream".
      stderrSub = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(stderrBuffer.write);
      
      // Buffer for detecting repetition
      final outputBuffer = StringBuffer();
      String lastChunk = '';
      int repetitionCount = 0;
      const maxRepetitions = 3;
      
      // Stream stdout with repetition detection
      await for (final chunk in process.stdout.transform(const Utf8Decoder(allowMalformed: true))) {
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

      final exitCode = await process.exitCode;

      // Ensure stderr is fully consumed before processing it.
      if (stderrSub != null) {
        try {
          await stderrSub.asFuture<void>();
        } catch (_) {
          // Ignore stderr stream errors.
        }
      }

      final stderrOutput = stderrBuffer.toString();
      _processStderr(stderrOutput);

      // If stopped by user (or loop detection), don't treat non-zero exit as error.
      if (!_isGenerating) return;

      if (exitCode != 0) {
        final msg = stderrOutput.trim();
        throw Exception(msg.isNotEmpty ? msg : 'llama-cli exited with code $exitCode');
      }
    } catch (e) {
      if (e.toString().contains('Process was killed')) {
        // User stopped generation, not an error
        return;
      }
      rethrow;
    } finally {
      if (stderrSub != null) {
        try {
          await stderrSub.cancel();
        } catch (_) {}
      }
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
    final execDir = path.dirname(Platform.resolvedExecutable);
    
    // Base executable name without extension
    const baseExeName = 'llama-cli';
    
    // Determine executable name based on platform
    final exeName = Platform.isWindows ? '$baseExeName.exe' : baseExeName;
    
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
    ];
    
    // On Windows, only check Windows-specific paths
    if (Platform.isWindows) {
      // Check explicit paths first
      for (final p in possiblePaths) {
        try {
          if (await File(p).exists()) {
            return p;
          }
        } catch (_) {
          continue;
        }
      }
      
      // Check system PATH
      try {
        final result = await Process.run('where', [baseExeName]);
        if (result.exitCode == 0) {
          final foundPath = (result.stdout as String).trim().split('\n').first;
          if (foundPath.isNotEmpty) {
            return foundPath;
          }
        }
      } catch (_) {}
    } else {
      // On Unix-like systems (Linux, macOS), also check system paths
      possiblePaths.addAll([
        path.join('/usr/local/bin', exeName),
        path.join('/usr/bin', exeName),
      ]);
      
      // Check explicit paths first
      for (final p in possiblePaths) {
        try {
          if (await File(p).exists()) {
            // Verify it's executable
            final result = await Process.run('test', ['-x', p]);
            if (result.exitCode != 0) continue;
            return p;
          }
        } catch (_) {
          continue;
        }
      }

      // Check system PATH
      try {
        final result = await Process.run('which', [baseExeName]);
        if (result.exitCode == 0) {
          final foundPath = (result.stdout as String).trim().split('\n').first;
          if (foundPath.isNotEmpty) {
            return foundPath;
          }
        }
      } catch (_) {}
    }

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

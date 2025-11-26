import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

/// A wrapper service that manages llama.cpp operations
/// Uses Process to run llama-cli for maximum compatibility
class LLMService {
  String? _modelPath;
  bool _isLoaded = false;
  Process? _process;
  
  bool get isLoaded => _isLoaded;
  String? get modelPath => _modelPath;

  /// Load a GGUF model file
  Future<bool> loadModel(String modelPath) async {
    try {
      if (!await File(modelPath).exists()) {
        throw Exception('Model file not found: $modelPath');
      }
      
      _modelPath = modelPath;
      _isLoaded = true;
      return true;
    } catch (e) {
      _isLoaded = false;
      rethrow;
    }
  }

  /// Generate a response using the loaded model
  /// Uses llama-cli subprocess for cross-platform compatibility
  Stream<String> generateStream(String prompt, {int maxTokens = 512}) async* {
    if (!_isLoaded || _modelPath == null) {
      throw Exception('Model not loaded');
    }

    // Find llama-cli executable
    final llamaCliPath = await _findLlamaCli();
    if (llamaCliPath == null) {
      throw Exception('llama-cli not found. Please ensure llama.cpp is installed or bundled with the app.');
    }

    final args = [
      '-m', _modelPath!,
      '-p', prompt,
      '-n', maxTokens.toString(),
      '--no-display-prompt',
      '-c', '2048',
      '--temp', '0.7',
      '--repeat-penalty', '1.1',
    ];

    // Set LD_LIBRARY_PATH to find shared libraries
    final execDir = path.dirname(llamaCliPath);
    final env = Map<String, String>.from(Platform.environment);
    if (Platform.isLinux) {
      final existingLdPath = env['LD_LIBRARY_PATH'] ?? '';
      env['LD_LIBRARY_PATH'] = '$execDir:$existingLdPath';
    } else if (Platform.isMacOS) {
      final existingDylibPath = env['DYLD_LIBRARY_PATH'] ?? '';
      env['DYLD_LIBRARY_PATH'] = '$execDir:$existingDylibPath';
    }

    _process = await Process.start(
      llamaCliPath, 
      args,
      environment: env,
    );
    
    // Stream stdout
    await for (final chunk in _process!.stdout.transform(utf8.decoder)) {
      yield chunk;
    }

    // Check for errors
    final errors = await _process!.stderr.transform(utf8.decoder).join();
    if (errors.isNotEmpty) {
      // Filter out llama.cpp info messages
      final realErrors = errors.split('\n')
          .where((line) => 
              !line.startsWith('llama_') && 
              !line.startsWith('llm_') &&
              !line.startsWith('ggml_') &&
              !line.startsWith('gguf') &&
              !line.contains('sampling') &&
              !line.contains('main:') &&
              !line.contains('sampler') &&
              !line.contains('generate:') &&
              !line.contains('n_predict') &&
              !line.contains('vocab') &&
              !line.contains('model size') &&
              !line.contains('warmup') &&
              line.trim().isNotEmpty)
          .join('\n');
      if (realErrors.isNotEmpty) {
        throw Exception(realErrors);
      }
    }

    await _process!.exitCode;
    _process = null;
  }

  /// Generate a complete response (non-streaming)
  Future<String> generate(String prompt, {int maxTokens = 512}) async {
    final buffer = StringBuffer();
    await for (final chunk in generateStream(prompt, maxTokens: maxTokens)) {
      buffer.write(chunk);
    }
    return buffer.toString().trim();
  }

  /// Find llama-cli executable
  Future<String?> _findLlamaCli() async {
    // Get the executable's directory (for bundled apps)
    final execDir = path.dirname(Platform.resolvedExecutable);
    
    // Check common locations
    final possiblePaths = [
      // Bundled with app
      path.join(execDir, 'llama-cli'),
      path.join(execDir, 'bin', 'llama-cli'),
      path.join(execDir, 'lib', 'llama-cli'),
      path.join(execDir, '..', 'lib', 'llama-cli'),
      path.join(execDir, '..', 'Resources', 'llama-cli'), // macOS app bundle
      // Current directory
      path.join(Directory.current.path, 'llama-cli'),
      path.join(Directory.current.path, 'bin', 'llama-cli'),
      // System paths
      '/usr/local/bin/llama-cli',
      '/usr/bin/llama-cli',
      // Windows variants
      path.join(execDir, 'llama-cli.exe'),
      path.join(execDir, 'bin', 'llama-cli.exe'),
      path.join(Directory.current.path, 'llama-cli.exe'),
      path.join(Directory.current.path, 'bin', 'llama-cli.exe'),
    ];

    // Check explicit paths first
    for (final p in possiblePaths) {
      if (await File(p).exists()) {
        return p;
      }
    }

    // Check if in PATH (Linux/macOS)
    if (!Platform.isWindows) {
      try {
        final result = await Process.run('which', ['llama-cli']);
        if (result.exitCode == 0) {
          return (result.stdout as String).trim();
        }
      } catch (_) {}
    }

    // Windows: use where instead
    if (Platform.isWindows) {
      try {
        final result = await Process.run('where', ['llama-cli']);
        if (result.exitCode == 0) {
          return (result.stdout as String).trim().split('\n').first;
        }
      } catch (_) {}
    }

    return null;
  }

  /// Stop any ongoing generation
  void stopGeneration() {
    _process?.kill();
    _process = null;
  }

  /// Unload the current model
  void unloadModel() {
    stopGeneration();
    _modelPath = null;
    _isLoaded = false;
  }

  /// Dispose resources
  void dispose() {
    unloadModel();
  }
}

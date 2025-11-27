import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:offline_llm/providers/chat_provider.dart';
import 'package:offline_llm/widgets/chat_message_widget.dart';
import 'package:offline_llm/widgets/chat_input_widget.dart';
import 'package:offline_llm/widgets/model_status_widget.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _scrollController.positions.isNotEmpty) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickAndLoadModel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        dialogTitle: 'Select a GGUF Model File',
      );

      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.first.path;
        if (filePath != null) {
          if (!filePath.endsWith('.gguf')) {
            _showError('Please select a .gguf model file');
            return;
          }
          
          if (!mounted) return;
          
          // Show loading dialog
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Loading model...'),
                ],
              ),
            ),
          );

          try {
            await context.read<ChatProvider>().loadModel(filePath);
            if (mounted) Navigator.of(context).pop();
            _showSuccess('Model loaded successfully!');
          } catch (e) {
            if (mounted) Navigator.of(context).pop();
            _showError('Failed to load model: $e');
          }
        }
      }
    } catch (e) {
      _showError('Error picking file: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.psychology),
            SizedBox(width: 8),
            Text('Offline LLM'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A cross-platform offline Large Language Model chat application.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              'Features:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('• Run GGUF models locally'),
            Text('• No internet required'),
            Text('• Privacy-focused'),
            Text('• Cross-platform support'),
            SizedBox(height: 16),
            Text(
              'Powered by llama.cpp',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.psychology),
            SizedBox(width: 8),
            Text('Offline LLM'),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Consumer<ChatProvider>(
            builder: (context, provider, _) => IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Load Model',
              onPressed: provider.isGenerating ? null : _pickAndLoadModel,
            ),
          ),
          Consumer<ChatProvider>(
            builder: (context, provider, _) => IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear Chat',
              onPressed: provider.messages.isEmpty 
                  ? null 
                  : () => provider.clearMessages(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: _showAboutDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Model status bar
          const ModelStatusWidget(),
          
          // Chat messages
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, provider, _) {
                _scrollToBottom();
                
                if (provider.messages.isEmpty && !provider.isModelLoaded) {
                  return _buildWelcomeScreen();
                }
                
                if (provider.messages.isEmpty && provider.isModelLoaded) {
                  return _buildStartChatScreen();
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.messages.length + 
                      (provider.isGenerating ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < provider.messages.length) {
                      return ChatMessageWidget(
                        message: provider.messages[index],
                      );
                    } else {
                      // Show streaming response
                      return ChatMessageWidget(
                        message: null,
                        streamingContent: provider.currentResponse,
                      );
                    }
                  },
                );
              },
            ),
          ),

          // Error display
          Consumer<ChatProvider>(
            builder: (context, provider, _) {
              if (provider.error != null) {
                return Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          provider.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => provider.clearError(),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // Input area
          const ChatInputWidget(),
        ],
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.psychology,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome to Offline LLM',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Run large language models locally on your device.\nNo internet connection required.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _pickAndLoadModel,
              icon: const Icon(Icons.folder_open),
              label: const Text('Load a GGUF Model'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Supports GGUF format models from Hugging Face',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartChatScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Model Loaded!',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Type a message below to start chatting.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

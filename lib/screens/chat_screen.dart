import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:offline_llm/models/rag_document.dart';
import 'package:offline_llm/providers/chat_provider.dart';
import 'package:offline_llm/providers/document_provider.dart';
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
  void initState() {
    super.initState();
    // Initialize document provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DocumentProvider>().initialize();
    });
  }

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

  Future<void> _exportChat() async {
    final provider = context.read<ChatProvider>();
    final success = await provider.exportChatToJson();
    if (success) {
      _showSuccess('Chat exported successfully!');
    } else if (provider.error != null) {
      _showError(provider.error!);
    }
  }

  Future<void> _importChat() async {
    final provider = context.read<ChatProvider>();
    final success = await provider.importChatFromJson();
    if (success) {
      _showSuccess('Chat imported successfully!');
    } else if (provider.error != null) {
      _showError(provider.error!);
    }
  }

  void _showExportImportMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('Export Chat'),
              subtitle: const Text('Save chat history as JSON file'),
              onTap: () {
                Navigator.pop(context);
                _exportChat();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('Import Chat'),
              subtitle: const Text('Load chat history from JSON file'),
              onTap: () {
                Navigator.pop(context);
                _importChat();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDocumentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Consumer<DocumentProvider>(
          builder: (context, docProvider, _) => Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.description,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'RAG Documents',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (docProvider.documents.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete All Documents'),
                              content: const Text(
                                'Are you sure you want to delete all uploaded documents?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    docProvider.deleteAllDocuments();
                                  },
                                  child: const Text('Delete All'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.delete_forever, size: 18),
                        label: const Text('Clear All'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Add documents button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: docProvider.isLoading
                        ? null
                        : () => docProvider.pickAndAddDocuments(),
                    icon: docProvider.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(
                      docProvider.isLoading ? 'Processing...' : 'Add Documents',
                    ),
                  ),
                ),
              ),
              // Info text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Supported formats: PDF, DOCX, TXT',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              // Error display
              if (docProvider.error != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          docProvider.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 16),
              // Document list
              Expanded(
                child: docProvider.documents.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No documents uploaded',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add documents to enable RAG',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: docProvider.documents.length,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemBuilder: (context, index) {
                          final doc = docProvider.documents[index];
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                _getDocumentIcon(doc.fileType),
                                color: _getDocumentColor(doc.fileType),
                              ),
                              title: Text(
                                doc.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${doc.chunkCount} chunks',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: doc.id != null
                                    ? () => docProvider.deleteDocument(doc.id!)
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getDocumentIcon(DocumentType fileType) {
    switch (fileType) {
      case DocumentType.pdf:
        return Icons.picture_as_pdf;
      case DocumentType.docx:
        return Icons.article;
      case DocumentType.txt:
        return Icons.text_snippet;
    }
  }

  Color _getDocumentColor(DocumentType fileType) {
    switch (fileType) {
      case DocumentType.pdf:
        return Colors.red;
      case DocumentType.docx:
        return Colors.blue;
      case DocumentType.txt:
        return Colors.grey;
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
          // RAG Documents button
          Consumer<DocumentProvider>(
            builder: (context, docProvider, _) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.description),
                  tooltip: 'RAG Documents',
                  onPressed: _showDocumentsSheet,
                ),
                if (docProvider.hasDocuments)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${docProvider.documents.length}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Consumer<ChatProvider>(
            builder: (context, provider, _) => IconButton(
              icon: const Icon(Icons.swap_vert),
              tooltip: 'Export/Import Chat',
              onPressed: provider.isGenerating ? null : _showExportImportMenu,
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

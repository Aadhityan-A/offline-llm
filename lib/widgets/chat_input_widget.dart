import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:offline_llm/providers/chat_provider.dart';
import 'package:offline_llm/providers/document_provider.dart';

class ChatInputWidget extends StatefulWidget {
  const ChatInputWidget({super.key});

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final chatProvider = context.read<ChatProvider>();
    final docProvider = context.read<DocumentProvider>();
    
    // If documents are uploaded, retrieve relevant context
    String? ragContext;
    List<String>? sourceDocuments;
    
    if (docProvider.hasDocuments) {
      final results = await docProvider.retrieveContext(text, topK: 3, minScore: 0.1);
      if (results.isNotEmpty) {
        ragContext = docProvider.buildContextString(results);
        sourceDocuments = docProvider.getSourceReferences(results);
      }
    }
    
    // Send message with RAG context if available
    chatProvider.sendMessage(
      text,
      ragContext: ragContext,
      sourceDocuments: sourceDocuments,
    );
    
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        final isEnabled = provider.isModelLoaded && !provider.isGenerating;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: isEnabled,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: isEnabled ? (_) => _sendMessage() : null,
                    decoration: InputDecoration(
                      hintText: provider.isModelLoaded
                          ? 'Type your message...'
                          : 'Load a model to start chatting',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (provider.isGenerating)
                  IconButton.filled(
                    onPressed: () => provider.stopGeneration(),
                    icon: const Icon(Icons.stop),
                    tooltip: 'Stop Generation',
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                  )
                else
                  IconButton.filled(
                    onPressed: isEnabled ? _sendMessage : null,
                    icon: const Icon(Icons.send),
                    tooltip: 'Send',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

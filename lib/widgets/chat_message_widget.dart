import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offline_llm/models/chat_message.dart';

class ChatMessageWidget extends StatefulWidget {
  final ChatMessage? message;
  final String? streamingContent;

  const ChatMessageWidget({
    super.key,
    this.message,
    this.streamingContent,
  });

  @override
  State<ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<ChatMessageWidget> {
  bool _isReasoningExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message?.isUser ?? false;
    final content = widget.message?.content ?? widget.streamingContent ?? '';
    final isError = widget.message?.isError ?? false;
    final isStreaming = widget.message == null && widget.streamingContent != null;
    final hasReasoning = widget.message?.hasReasoning ?? false;
    final reasoning = widget.message?.reasoning;
    final hasSources = widget.message?.hasSources ?? false;
    final sourceDocuments = widget.message?.sourceDocuments;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: isError 
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
              child: Icon(
                isError ? Icons.error : Icons.psychology,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primaryContainer
                    : isError
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomLeft: isUser ? null : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : null,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Reasoning/Thinking section (collapsible)
                  if (hasReasoning && reasoning != null) ...[
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isReasoningExpanded = !_isReasoningExpanded;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              size: 16,
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Thinking',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _isReasoningExpanded 
                                  ? Icons.expand_less 
                                  : Icons.expand_more,
                              size: 16,
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isReasoningExpanded) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.tertiary.withOpacity(0.3),
                          ),
                        ),
                        child: SelectableText(
                          reasoning,
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                  // Main content
                  SelectableText(
                    content.isEmpty && isStreaming ? '...' : content,
                    style: TextStyle(
                      color: isUser
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : isError
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  // Source documents section
                  if (!isUser && hasSources && sourceDocuments != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        Icon(
                          Icons.source,
                          size: 14,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 2),
                        ...sourceDocuments.map((source) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            '[$source]',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )),
                      ],
                    ),
                  ],
                  if (isStreaming && content.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
          if (!isUser && !isStreaming && content.isNotEmpty) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy',
              onPressed: () {
                // Copy both reasoning and content if available
                final copyText = hasReasoning && reasoning != null
                    ? 'Thinking:\n$reasoning\n\nResponse:\n$content'
                    : content;
                Clipboard.setData(ClipboardData(text: copyText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

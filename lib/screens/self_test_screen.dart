import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_palette.dart';
import '../models/ai_server_models.dart';
import '../providers/ai_server_provider.dart';

class SelfTestScreen extends ConsumerStatefulWidget {
  const SelfTestScreen({super.key});

  @override
  ConsumerState<SelfTestScreen> createState() => _SelfTestScreenState();
}

class _SelfTestScreenState extends ConsumerState<SelfTestScreen> {
  final input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiServerProvider);
    final running = state.status == ServerStatus.running;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              if (state.chat.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      running
                          ? 'Self test — calls your running server at '
                              'http://127.0.0.1:${state.port}/v1/chat/completions '
                              '(same API as Postman from your laptop).'
                          : 'Start the AI server, then use this tab to verify it answers.',
                      style: const TextStyle(color: AppPalette.muted),
                    ),
                  ),
                ),
              for (final message in state.chat)
                Align(
                  alignment:
                      message.fromUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.75,
                    ),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          message.fromUser
                              ? AppPalette.primary
                              : AppPalette.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                          message.fromUser
                              ? AppPalette.primary
                              : AppPalette.border,
                      ),
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color:
                            message.fromUser ? AppPalette.bg : AppPalette.text,
                        fontWeight:
                            message.fromUser
                                ? FontWeight.w700
                                : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              if (_sending)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppPalette.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppPalette.border),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppPalette.teal,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'thinking…',
                          style: TextStyle(color: AppPalette.muted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    enabled: running && !_sending,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText:
                          !running
                              ? 'Server offline'
                              : (_sending ? 'Waiting for reply…' : 'Prompt'),
                      filled: true,
                      fillColor: AppPalette.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppPalette.border),
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send test prompt',
                  onPressed: (running && !_sending) ? _send : null,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _send() async {
    if (_sending) return;
    final prompt = input.text;
    if (prompt.trim().isEmpty) return;
    input.clear();
    setState(() => _sending = true);
    _scrollToBottom();
    try {
      await ref.read(aiServerProvider.notifier).sendPrompt(prompt);
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }
}

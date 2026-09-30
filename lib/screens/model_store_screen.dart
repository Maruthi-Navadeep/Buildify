import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_palette.dart';
import '../providers/ai_server_provider.dart';
import '../widgets/model_tile.dart';

class ModelStoreScreen extends ConsumerStatefulWidget {
  const ModelStoreScreen({super.key});

  @override
  ConsumerState<ModelStoreScreen> createState() => _ModelStoreScreenState();
}

class _ModelStoreScreenState extends ConsumerState<ModelStoreScreen> {
  bool _refreshing = false;

  Future<void> _refreshCatalog() async {
    setState(() => _refreshing = true);
    try {
      await ref.read(aiServerProvider.notifier).refreshCatalog();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiServerProvider);
    final controller = ref.read(aiServerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle('Model Store')),
            IconButton.filledTonal(
              tooltip: 'Update model catalog',
              onPressed: _refreshing ? null : _refreshCatalog,
              icon: _refreshing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final model in state.models) ...[
          ModelTile(
            model: model,
            download: state.downloads[model.id] ??
                const ModelDownload(
                  status: ModelDownloadStatus.notDownloaded,
                  progress: 0,
                ),
            selected: state.selectedModelId == model.id,
            onSelect: () => controller.selectModel(model.id),
            onDownload: () => controller.downloadModel(model.id),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: AppPalette.text,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_palette.dart';
import '../models/ai_server_models.dart';

class ModelTile extends ConsumerWidget {
  const ModelTile({
    required this.model,
    required this.download,
    this.selected = false,
    this.compact = false,
    this.onSelect,
    this.onDownload,
    this.onCancel,
    this.onDelete,
    super.key,
  });

  final ModelProfile model;
  final ModelDownload download;
  final bool selected;
  final bool compact;
  final VoidCallback? onSelect;
  final VoidCallback? onDownload;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = download.status == ModelDownloadStatus.downloaded;
    final downloading = download.status == ModelDownloadStatus.downloading;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      model.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle,
                      color: AppPalette.teal,
                      size: 20,
                    ),
                  if (downloaded && onDelete != null && !compact)
                    IconButton(
                      tooltip: 'Delete model',
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 20, color: AppPalette.muted),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                model.description,
                style: const TextStyle(color: AppPalette.muted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Tag(icon: Icons.sd_storage_outlined, label: model.sizeLabel),
                  _Tag(icon: Icons.speed, label: model.speed),
                  _Tag(icon: Icons.auto_awesome, label: model.quality),
                  _Tag(
                    icon: Icons.memory,
                    label: '${model.requiredRamGb}GB RAM',
                  ),
                ],
              ),
              if (!compact) ...[
                const SizedBox(height: 12),
                if (downloading)
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: download.progress,
                            minHeight: 8,
                            backgroundColor: AppPalette.border,
                            color: AppPalette.primary,
                          ),
                        ),
                      ),
                      if (onCancel != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Cancel download',
                          visualDensity: VisualDensity.compact,
                          onPressed: onCancel,
                          icon: const Icon(Icons.close, size: 18, color: AppPalette.muted),
                        ),
                      ],
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onSelect,
                          icon: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          label: Text(selected ? 'Selected' : 'Select'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: downloaded ? null : onDownload,
                          icon: Icon(
                            downloaded
                                ? Icons.download_done
                                : Icons.download_outlined,
                          ),
                          label: Text(downloaded ? 'Downloaded' : 'Download'),
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppPalette.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppPalette.muted),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

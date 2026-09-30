import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_palette.dart';
import '../models/ai_server_models.dart';
import '../providers/ai_server_provider.dart';
import '../widgets/model_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiServerProvider);
    final controller = ref.read(aiServerProvider.notifier);

    // Guard: models list is populated asynchronously — show a spinner until ready.
    if (state.models.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final selected = state.models.firstWhere(
      (m) => m.id == state.selectedModelId,
      orElse: () => state.models.first,
    );
    final download = state.downloads[selected.id] ??
        const ModelDownload(status: ModelDownloadStatus.notDownloaded, progress: 0);
    final canStart = download.status == ModelDownloadStatus.downloaded;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _ServerStatusPanel(
          state: state,
          selected: selected,
          apiBaseUrl: controller.apiBaseUrl,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed:
                    canStart
                        ? () {
                          final ctrl = ref.read(aiServerProvider.notifier);
                          state.status == ServerStatus.running
                              ? unawaited(ctrl.stopServer())
                              : unawaited(ctrl.startServer());
                        }
                        : null,
                icon: Icon(
                  state.status == ServerStatus.running
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                ),
                label: Text(
                  state.status == ServerStatus.running
                      ? 'Stop AI Server'
                      : 'Start AI Server',
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: 'Copy API URL',
              onPressed: () => _copyApiUrl(context, controller.apiBaseUrl),
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
        if (!canStart) ...[
          const SizedBox(height: 8),
          Text(
            'Download the selected model first.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.amber,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 18),
        const _SectionTitle('Device'),
        const SizedBox(height: 8),
        _DeviceGrid(device: state.device),
        const SizedBox(height: 18),
        const _SectionTitle('Selected Model'),
        const SizedBox(height: 8),
        ModelTile(model: selected, download: download, compact: true),
        const SizedBox(height: 18),
        const _SectionTitle('Runtime'),
        const SizedBox(height: 8),
        _RuntimeControls(state: state),
        const SizedBox(height: 18),
        const _SectionTitle('Security & Safety'),
        const SizedBox(height: 8),
        const _SecurityCard(),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(child: _SectionTitle('Logs')),
            IconButton.filledTonal(
              tooltip: 'Copy logs',
              onPressed:
                  state.logs.isEmpty
                      ? null
                      : () => _copyLogs(context, state.logs),
              icon: const Icon(Icons.copy, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _LogPanel(logs: state.logs),
      ],
    );
  }
}

class _ServerStatusPanel extends StatelessWidget {
  const _ServerStatusPanel({
    required this.state,
    required this.selected,
    required this.apiBaseUrl,
  });

  final AiServerState state;
  final ModelProfile selected;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final running = state.status == ServerStatus.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusDot(status: state.status),
                const SizedBox(width: 8),
                Text(
                  _statusTitle(state.status),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Model', value: selected.name),
            _InfoRow(label: 'API', value: running ? apiBaseUrl : 'offline'),
            _InfoRow(label: 'Uptime', value: _formatDuration(state.uptime)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MetricPill(
                    label: 'Requests',
                    value: '${state.requestCount}',
                    color: AppPalette.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricPill(
                    label: 'RPS',
                    value: state.requestsPerSecond.toStringAsFixed(1),
                    color: AppPalette.teal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RuntimeControls extends ConsumerWidget {
  const _RuntimeControls({required this.state});

  final AiServerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(aiServerProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            SwitchListTile(
              value: state.lowPowerMode,
              onChanged: controller.setLowPowerMode,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Low-power mode'),
              secondary: const Icon(Icons.battery_saver),
            ),
            _SliderRow(
              label: 'Token limit',
              valueLabel: '${state.tokenLimit}',
              value: state.tokenLimit.toDouble(),
              min: 32,
              max: 256,
              divisions: 7,
              onChanged: controller.setTokenLimit,
            ),
            _SliderRow(
              label: 'Temperature',
              valueLabel: state.temperature.toStringAsFixed(1),
              value: state.temperature,
              min: 0.1,
              max: 1.2,
              divisions: 11,
              onChanged: controller.setTemperature,
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityCard extends ConsumerStatefulWidget {
  const _SecurityCard();

  @override
  ConsumerState<_SecurityCard> createState() => _SecurityCardState();
}

class _SecurityCardState extends ConsumerState<_SecurityCard> {
  bool _revealKey = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiServerProvider);
    final controller = ref.read(aiServerProvider.notifier);
    final sec = state.security;
    final running = state.status == ServerStatus.running;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SubSectionTitle(
              icon: Icons.vpn_key_outlined,
              text: 'API key',
            ),
            SwitchListTile(
              value: sec.requireApiKey,
              onChanged: (v) => controller.setRequireApiKey(v),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Require API key'),
              subtitle: const Text(
                'Clients must send Authorization: Bearer <key>',
                style: TextStyle(color: AppPalette.muted, fontSize: 12),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppPalette.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _revealKey
                          ? (sec.apiKey.isEmpty ? '—' : sec.apiKey)
                          : sec.maskedApiKey,
                      style: const TextStyle(
                        color: AppPalette.teal,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _revealKey ? 'Hide key' : 'Show key',
                    onPressed: sec.apiKey.isEmpty
                        ? null
                        : () => setState(() => _revealKey = !_revealKey),
                    icon: Icon(
                      _revealKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy key',
                    onPressed: sec.apiKey.isEmpty
                        ? null
                        : () => _copyKey(context, sec.apiKey),
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Regenerate key',
                    onPressed: () => controller.regenerateApiKey(),
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
            ),
            if (running && sec.requireApiKey) ...[
              const SizedBox(height: 6),
              const Text(
                'Restart the server for key changes to take effect.',
                style: TextStyle(color: AppPalette.amber, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            const _SubSectionTitle(
              icon: Icons.shield_outlined,
              text: 'Auto-stop',
            ),
            _SliderRow(
              label: 'Idle timeout',
              valueLabel:
                  sec.idleTimeoutMinutes == 0 ? 'Off' : '${sec.idleTimeoutMinutes} min',
              value: sec.idleTimeoutMinutes.toDouble(),
              min: 0,
              max: 60,
              divisions: 12,
              onChanged: (v) => controller.setIdleTimeoutMinutes(v.round()),
            ),
            _SliderRow(
              label: 'Stop below battery',
              valueLabel:
                  sec.batteryStopPercent == 0 ? 'Off' : '${sec.batteryStopPercent}%',
              value: sec.batteryStopPercent.toDouble(),
              min: 0,
              max: 50,
              divisions: 10,
              onChanged: (v) => controller.setBatteryStopPercent(v.round()),
            ),
            SwitchListTile(
              value: sec.thermalStop,
              onChanged: (v) => controller.setThermalStop(v),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Stop on thermal warning'),
              subtitle: const Text(
                'Stops the server if the device gets too hot (Android 10+).',
                style: TextStyle(color: AppPalette.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyKey(BuildContext context, String key) async {
    await Clipboard.setData(ClipboardData(text: key));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key copied')),
    );
  }
}

class _SubSectionTitle extends StatelessWidget {
  const _SubSectionTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppPalette.teal),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceGrid extends StatelessWidget {
  const _DeviceGrid({required this.device});

  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.25,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        _MetricPill(
          label: 'RAM',
          value: '${device.availRamGb.toStringAsFixed(1)} / ${device.ramGb} GB',
          color: AppPalette.teal,
        ),
        _MetricPill(
          label: 'Storage',
          value: '${device.freeStorageGb.toStringAsFixed(1)} GB free',
          color: AppPalette.blue,
        ),
        _MetricPill(
          label: 'Battery',
          value: '${device.batteryPercent}%${device.batteryCharging ? ' ⚡' : ''}',
          color: AppPalette.amber,
        ),
        _MetricPill(
          label: 'CPU',
          value: device.cpuLabel,
          color: AppPalette.primary,
        ),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppPalette.muted, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(label),
            const Spacer(),
            Text(valueLabel, style: const TextStyle(color: AppPalette.teal)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _LogPanel extends StatefulWidget {
  const _LogPanel({required this.logs});

  final List<ServerLog> logs;

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void didUpdateWidget(_LogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.length != oldWidget.logs.length) _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 188,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: ListView.builder(
        controller: _scroll,
        itemCount: widget.logs.length,
        itemBuilder: (context, index) {
          final log = widget.logs[index];
          return Text(
            log.message,
            style: TextStyle(
              color: switch (log.type) {
                LogType.system => AppPalette.muted,
                LogType.request => AppPalette.teal,
                LogType.warning => AppPalette.amber,
              },
              fontSize: 12,
              height: 1.35,
            ),
          );
        },
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final ServerStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ServerStatus.running => AppPalette.teal,
      ServerStatus.starting => AppPalette.amber,
      ServerStatus.stopping => AppPalette.amber,
      ServerStatus.stopped => AppPalette.error,
    };
    return Container(
      height: 12,
      width: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: const TextStyle(color: AppPalette.muted)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
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

String _statusTitle(ServerStatus status) {
  return switch (status) {
    ServerStatus.stopped => 'Server Stopped',
    ServerStatus.starting => 'Starting Server',
    ServerStatus.running => 'Server Running',
    ServerStatus.stopping => 'Stopping Server',
  };
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

void _copyApiUrl(BuildContext context, String baseUrl) {
  unawaited(Clipboard.setData(ClipboardData(text: baseUrl)));
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('API URL copied')));
}

void _copyLogs(BuildContext context, List<ServerLog> logs) {
  if (logs.isEmpty) return;
  final text = logs.map((l) => '[${l.type.name}] ${l.message}').join('\n');
  unawaited(Clipboard.setData(ClipboardData(text: text)));
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Logs copied')));
}

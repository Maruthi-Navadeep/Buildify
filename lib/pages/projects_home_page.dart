import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ai_server_models.dart';
import '../providers/ai_server_provider.dart';
import '../backend/embedded_backend.dart';
import '../services/guided_tour_service.dart';
import '../widgets/guided_tour_overlay.dart';
import 'host_project_wizard.dart';
import 'service_detail_page.dart';
import 'project_detail_page.dart';

/// Projects dashboard — visual match for the buildify HTML mock.
class ProjectsHomePage extends ConsumerStatefulWidget {
  const ProjectsHomePage({super.key, this.onRunAiModel});

  /// Navigates to the existing AI server shell without coupling imports.
  final VoidCallback? onRunAiModel;

  @override
  ConsumerState<ProjectsHomePage> createState() => _ProjectsHomePageState();
}

class _ProjectsHomePageState extends ConsumerState<ProjectsHomePage>
    with TickerProviderStateMixin {
  static const _filters = ['all', 'services'];

  int _selectedFilter = 0;
  bool _productionExpanded = true;
  final _searchController = TextEditingController();
  late final AnimationController _meshController;

  final _topBarKey = GlobalKey();
  final _searchKey = GlobalKey();
  final _addServiceKey = GlobalKey();
  final _serviceCardKey = GlobalKey();

  List<_ServiceData> getServices(
    AiServerState state,
    List<BackendProject> customProjects,
  ) {
    final isRunning = state.status == ServerStatus.running;
    final isStarting = state.status == ServerStatus.starting;

    final selectedModel = state.models.firstWhere(
      (m) => m.id == state.selectedModelId,
      orElse: () => state.models.isNotEmpty
          ? state.models.first
          : const ModelProfile(
              id: 'llama-3-8b',
              name: 'Llama 3 8B',
              fileName: 'llama-3-8b.gguf',
              downloadUrl: '',
              sizeLabel: '4.7 GB',
              speed: 'Fast',
              quality: 'High',
              requiredRamGb: 6,
              description: 'Llama 3 model',
            ),
    );

    final aiCard = _ServiceData(
      name: 'project---x',
      statusIcon: isRunning
          ? Icons.check_circle_outline
          : (isStarting ? Icons.sync : Icons.offline_bolt_outlined),
      statusIconColor: isRunning
          ? const Color(0xFF10B981)
          : (isStarting ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF)),
      statusLabel: isRunning ? 'online' : (isStarting ? 'starting' : 'offline'),
      statusColor: isRunning
          ? const Color(0xFF065F46)
          : (isStarting ? const Color(0xFF78350F) : const Color(0xFF374151)),
      version: selectedModel.name.toLowerCase(),
      runtime: 'llama.cpp',
      region: 'localhost:${state.port}',
      updated: isRunning ? 'active' : 'stopped',
      actionLabel: isRunning
          ? 'active (tap to manage)'
          : 'start server (tap to manage)',
      actionIcon: isRunning ? Icons.insights_outlined : Icons.play_arrow,
      actionPrimary: !isRunning,
      metadataBorderBright: isRunning,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ServiceDetailPage(),
          ),
        );
      },
    );
    final activeSession = ref.watch(backendStateProvider).value?.activeSession;

    final customCards = customProjects.map((p) {
      final isThisProjectActive = activeSession != null && activeSession.projectId == p.id;
      final liveUrl = isThisProjectActive
          ? activeSession.publicUrl
          : (p.isLive ? 'http://localhost:${p.port}' : 'stopped');

      return _ServiceData(
        name: p.name,
        statusIcon:
            p.isLive ? Icons.check_circle_outline : Icons.offline_bolt_outlined,
        statusIconColor:
            p.isLive ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
        statusLabel: p.isLive ? 'online' : 'offline',
        statusColor:
            p.isLive ? const Color(0xFF065F46) : const Color(0xFF374151),
        version: p.hostingMode == HostingMode.ephemeral ? 'sandbox' : 'prod-sqlite',
        runtime: p.repoProvider,
        region: liveUrl,
        updated: p.lastDeployedAt != null ? 'active' : 'just created',
        actionLabel: p.isLive
            ? 'active (tap to manage)'
            : 'start server (tap to manage)',
        actionIcon: p.isLive ? Icons.insights_outlined : Icons.play_arrow,
        actionPrimary: !p.isLive,
        metadataBorderBright: p.isLive,
        isEphemeral: p.hostingMode == HostingMode.ephemeral,
        projectId: p.id,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProjectDetailPage(projectId: p.id),
            ),
          );
        },
        onDelete: () async {
          await ref.read(embeddedBackendProvider).deleteProject(p.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Deleted ${p.name}')),
            );
          }
        },
      );
    }).toList();

    return [aiCard, ...customCards];
  }

  @override
  void initState() {
    super.initState();
    _meshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(reverse: true);
    _searchController.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndStartTour();
    });
  }

  List<GuidedTourStep> _buildTourSteps() {
    return [
      GuidedTourStep(
        title: 'Welcome to Buildify',
        description:
            'Host fullstack web applications and run local GGUF LLM models right on your mobile device.',
        targetKey: _topBarKey,
        tooltipPosition: TooltipPosition.bottom,
      ),
      GuidedTourStep(
        title: 'Deploy & Host Services',
        description:
            'Tap "+ Add New" to deploy a web app (Node.js, Python, Flask, Static) or launch a local AI model.',
        targetKey: _addServiceKey,
        tooltipPosition: TooltipPosition.bottom,
      ),
      GuidedTourStep(
        title: 'Search & Quick Filters',
        description:
            'Filter running microservices or search across your active resource ecosystem.',
        targetKey: _searchKey,
        tooltipPosition: TooltipPosition.bottom,
      ),
      GuidedTourStep(
        title: 'Telemetry & Control',
        description:
            'Tap any service card to view live server logs, hardware metrics, thermal limits, and API endpoints.',
        targetKey: _serviceCardKey,
        tooltipPosition: TooltipPosition.top,
      ),
    ];
  }

  void _checkAndStartTour() {
    ref
        .read(guidedTourNotifierProvider.notifier)
        .checkAndAutoStartTour(_buildTourSteps());
  }

  void _triggerReplayTour() {
    ref.read(guidedTourNotifierProvider.notifier).startTour(_buildTourSteps());
  }

  @override
  void dispose() {
    _meshController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<_ServiceData> _filteredServices(List<_ServiceData> services) {
    List<_ServiceData> filtered = services;
    if (_selectedFilter == 1) { // 'services' tab
      filtered = services.where((s) => s.statusLabel == 'online').toList();
    }
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return filtered;
    return filtered.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  void _openNewServiceModal() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => _NewServiceModal(
        onHostProject: () {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const HostProjectSourcePage(),
            ),
          );
        },
        onRunAiModel: () {
          Navigator.pop(ctx);
          widget.onRunAiModel?.call();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiServerProvider);
    final customProjectsAsync = ref.watch(backendProjectsProvider);
    final customProjects = customProjectsAsync.value ?? const [];
    final horizontalPadding = MediaQuery.sizeOf(context).width >= 768 ? 32.0 : 16.0;

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _ProjectsPalette.surfaceBody,
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
      ),
      child: GuidedTourOverlay(
        child: Scaffold(
          backgroundColor: _ProjectsPalette.surfaceBody,
          body: Stack(
            children: [
              _MeshBackground(animation: _meshController),
              SafeArea(
                child: Column(
                  children: [
                    _ProjectsTopBar(
                      key: _topBarKey,
                      horizontalPadding: horizontalPadding,
                      onReplayTour: _triggerReplayTour,
                    ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          24,
                          horizontalPadding,
                          96,
                        ),
                        children: [
                          _StaggeredFadeIn(
                            children: [
                              _SearchSection(
                                key: _searchKey,
                                controller: _searchController,
                                filters: _filters,
                                selectedFilter: _selectedFilter,
                                onFilterSelected: (i) =>
                                    setState(() => _selectedFilter = i),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _StaggeredFadeIn(
                            delayOffset: 1,
                            children: [
                              _EnvironmentSection(
                                expanded: _productionExpanded,
                                onToggle: () => setState(
                                  () => _productionExpanded = !_productionExpanded,
                                ),
                                services: _filteredServices(
                                  getServices(state, customProjects),
                                ),
                                onNewService: _openNewServiceModal,
                                newServiceKey: _addServiceKey,
                                firstCardKey: _serviceCardKey,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectsPalette {
  static const surface = Color(0xFF131312);
  static const surfaceBody = Color(0xFF1F1F1E);
  static const surfaceContainer = Color(0xFF20201F);
  static const surfaceContainerHigh = Color(0xFF2A2A29);
  static const surfaceMeta = Color(0xFF20201E);
  static const onSurface = Color(0xFFE5E2E0);
  static const onSurfaceVariant = Color(0xFFDDC0BA);
  static const primary = Color(0xFFFFFFFF);
  static const outline = Color(0xFFA48B86);
}

class _ServiceData {
  const _ServiceData({
    required this.name,
    required this.statusIcon,
    required this.statusIconColor,
    required this.statusLabel,
    required this.statusColor,
    required this.version,
    required this.runtime,
    required this.region,
    required this.updated,
    required this.actionLabel,
    required this.actionIcon,
    required this.actionPrimary,
    this.metadataBorderBright = false,
    this.isEphemeral = false,
    this.projectId,
    this.onTap,
    this.onDelete,
  });

  final String name;
  final IconData statusIcon;
  final Color statusIconColor;
  final String statusLabel;
  final Color statusColor;
  final String version;
  final String runtime;
  final String region;
  final String updated;
  final String actionLabel;
  final IconData actionIcon;
  final bool actionPrimary;
  final bool metadataBorderBright;
  final bool isEphemeral;
  final String? projectId;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
}

class _MeshBackground extends StatelessWidget {
  const _MeshBackground({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        final scale = 1.0 + (t * 0.1);
        final rotation = t * 0.035;
        return Transform.scale(
          scale: scale,
          child: Transform.rotate(angle: rotation, child: child),
        );
      },
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: _ProjectsPalette.surface),
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _cornerGlow(context, Alignment.topLeft),
                      _cornerGlow(context, Alignment.topRight),
                      _cornerGlow(context, Alignment.bottomRight),
                      _cornerGlow(context, Alignment.bottomLeft),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cornerGlow(BuildContext context, Alignment alignment) {
    final size = MediaQuery.sizeOf(context);
    return Align(
      alignment: alignment,
      child: Container(
        width: size.width * 0.7,
        height: size.height * 0.5,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.03),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectsTopBar extends StatelessWidget {
  const _ProjectsTopBar({
    super.key,
    required this.horizontalPadding,
    this.onReplayTour,
  });

  final double horizontalPadding;
  final VoidCallback? onReplayTour;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: _ProjectsPalette.surface.withValues(alpha: 0.8),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _ProjectsPalette.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              shape: const RoundedRectangleBorder(
                side: BorderSide(color: Color(0x0DFFFFFF)),
              ),
            ),
            onPressed: () {},
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.more_horiz, size: 20, color: _ProjectsPalette.onSurface),
                Text(
                  'more',
                  style: GoogleFonts.spaceMono(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: _ProjectsPalette.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.architecture, color: _ProjectsPalette.primary, size: 28),
          const SizedBox(width: 8),
          Text(
            'buildify',
            style: GoogleFonts.spaceMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: _ProjectsPalette.primary,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onReplayTour,
            icon: const Icon(Icons.help_outline, color: _ProjectsPalette.onSurface),
            tooltip: 'Guided Tour',
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.person_outline, color: _ProjectsPalette.onSurface),
          ),
        ],
      ),
    );
  }
}

class _SearchSection extends StatelessWidget {
  const _SearchSection({
    super.key,
    required this.controller,
    required this.filters,
    required this.selectedFilter,
    required this.onFilterSelected,
  });

  final TextEditingController controller;
  final List<String> filters;
  final int selectedFilter;
  final ValueChanged<int> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          style: GoogleFonts.spaceMono(
            fontSize: 14,
            color: _ProjectsPalette.onSurface,
          ),
          decoration: InputDecoration(
            hintText: 'search resources...',
            hintStyle: GoogleFonts.spaceMono(
              fontSize: 14,
              color: _ProjectsPalette.outline.withValues(alpha: 0.3),
            ),
            prefixIcon: Icon(
              Icons.search,
              color: _ProjectsPalette.outline.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.all(16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _ProjectsPalette.primary.withValues(alpha: 0.5)),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: List.generate(filters.length, (i) {
            final selected = i == selectedFilter;
            return Padding(
              padding: EdgeInsets.only(right: i < filters.length - 1 ? 32 : 0),
              child: InkWell(
                onTap: () => onFilterSelected(i),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: selected
                            ? _ProjectsPalette.primary
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Text(
                    filters[i],
                    style: GoogleFonts.spaceMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: selected
                          ? _ProjectsPalette.primary
                          : _ProjectsPalette.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
      ],
    );
  }
}

class _EnvironmentSection extends StatelessWidget {
  const _EnvironmentSection({
    required this.expanded,
    required this.onToggle,
    required this.services,
    required this.onNewService,
    this.newServiceKey,
    this.firstCardKey,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final List<_ServiceData> services;
  final VoidCallback onNewService;
  final Key? newServiceKey;
  final Key? firstCardKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    color: _ProjectsPalette.outline.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'production',
                  style: GoogleFonts.spaceMono(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: _ProjectsPalette.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.1),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (expanded) ...[
          ...services.asMap().entries.map((entry) {
            final idx = entry.key;
            final s = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ServiceCard(
                key: idx == 0 ? firstCardKey : null,
                data: s,
              ),
            );
          }),
          _NewServiceButton(
            key: newServiceKey,
            onPressed: onNewService,
          ),
        ],
      ],
    );
  }
}

class _ServiceCard extends StatefulWidget {
  const _ServiceCard({
    super.key,
    required this.data,
  });

  final _ServiceData data;

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  Offset? _glowPosition;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    return GestureDetector(
      onTap: () {
        if (data.onTap != null) {
          data.onTap!();
        } else if (data.name == 'project---x') {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ServiceDetailPage(),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${data.name} is a demo/mock service'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _glowPosition = null;
        }),
        child: Listener(
          onPointerHover: (e) => setState(() => _glowPosition = e.localPosition),
          onPointerMove: (e) => setState(() => _glowPosition = e.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: _ProjectsPalette.surfaceContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Stack(
                  children: [
                    if (_glowPosition != null && _hovered)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(
                                  (_glowPosition!.dx / 320) * 2 - 1,
                                  (_glowPosition!.dy / 200) * 2 - 1,
                                ),
                                radius: 0.45,
                                colors: [
                                  Colors.white.withValues(alpha: 0.1),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final stacked = constraints.maxWidth < 520;
                              final meta = _MetadataGrid(
                                runtime: data.runtime,
                                region: data.region,
                                updated: data.updated,
                                brightBorder: data.metadataBorderBright,
                              );
                              final info = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(data.statusIcon, color: data.statusIconColor, size: 24),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          data.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.spaceMono(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.36,
                                            color: _ProjectsPalette.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: data.statusColor,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          data.statusLabel,
                                          style: GoogleFonts.spaceMono(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        data.version,
                                        style: GoogleFonts.spaceMono(
                                          fontSize: 10,
                                          color: _ProjectsPalette.onSurfaceVariant
                                              .withValues(alpha: 0.4),
                                        ),
                                      ),
                                      if (data.isEphemeral) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF5B21B6),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: const Color(0xFF8B5CF6),
                                            ),
                                          ),
                                          child: Text(
                                            '⚡ EPHEMERAL',
                                            style: GoogleFonts.spaceMono(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFFDDD6FE),
                                            ),
                                          ),
                                        ),
                                      ] else if (data.projectId != null) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF064E3B),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: const Color(0xFF059669),
                                            ),
                                          ),
                                          child: Text(
                                            '📌 PERSISTENT',
                                            style: GoogleFonts.spaceMono(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFFA7F3D0),
                                            ),
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      if (data.onDelete != null)
                                        IconButton(
                                          onPressed: data.onDelete,
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Color(0xFFF87171),
                                            size: 18,
                                          ),
                                          tooltip: 'Delete / Destroy Project',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                    ],
                                  ),
                                ],
                              );

                              if (stacked) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [info, const SizedBox(height: 24), meta],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: info),
                                  const SizedBox(width: 24),
                                  Flexible(child: meta),
                                ],
                              );
                            },
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: _hovered ? 1 : 0.6,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              border: Border(
                                top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  data.actionLabel,
                                  style: GoogleFonts.spaceMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                    color: data.actionPrimary
                                        ? _ProjectsPalette.primary
                                        : _ProjectsPalette.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  data.actionIcon,
                                  size: 18,
                                  color: data.actionPrimary
                                      ? _ProjectsPalette.primary
                                      : _ProjectsPalette.onSurface,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetadataGrid extends StatelessWidget {
  const _MetadataGrid({
    required this.runtime,
    required this.region,
    required this.updated,
    required this.brightBorder,
  });

  final String runtime;
  final String region;
  final String updated;
  final bool brightBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: brightBorder ? 0.1 : 0.05),
        ),
        color: Colors.white.withValues(alpha: 0.05),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(child: _MetaCell(label: 'runtime', value: runtime, alt: false)),
            Container(width: 1, color: Colors.white.withValues(alpha: 0.05)),
            Expanded(child: _MetaCell(label: 'region', value: region, alt: true)),
            Container(width: 1, color: Colors.white.withValues(alpha: 0.05)),
            Expanded(child: _MetaCell(label: 'updated', value: updated, alt: false)),
          ],
        ),
      ),
    );
  }
}

class _MetaCell extends StatelessWidget {
  const _MetaCell({
    required this.label,
    required this.value,
    required this.alt,
  });

  final String label;
  final String value;
  final bool alt;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: alt ? _ProjectsPalette.surfaceContainerHigh : _ProjectsPalette.surfaceMeta,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceMono(
              fontSize: 8,
              letterSpacing: 0.8,
              color: _ProjectsPalette.outline.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 2),
          Tooltip(
            message: value,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _ProjectsPalette.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewServiceButton extends StatefulWidget {
  const _NewServiceButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  State<_NewServiceButton> createState() => _NewServiceButtonState();
}

class _NewServiceButtonState extends State<_NewServiceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shineController;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _shineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: MouseRegion(
        onEnter: (_) => _shineController.repeat(),
        onExit: (_) {
          _shineController.stop();
          _shineController.reset();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: const Duration(milliseconds: 100),
          child: AnimatedBuilder(
            animation: _shineController,
            builder: (context, child) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    style: BorderStyle.solid,
                  ),
                  color: Colors.white.withValues(alpha: 0.02),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment(_shineController.value * 2 - 1, 0),
                    end: Alignment(_shineController.value * 2, 0),
                    colors: [
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: child,
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add,
                  color: _ProjectsPalette.outline.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 12),
                Text(
                  'new service',
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: _ProjectsPalette.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewServiceModal extends StatelessWidget {
  const _NewServiceModal({
    required this.onHostProject,
    required this.onRunAiModel,
  });

  final VoidCallback onHostProject;
  final VoidCallback onRunAiModel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 448),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _ProjectsPalette.surfaceBody,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'select service type',
                        style: GoogleFonts.spaceMono(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: _ProjectsPalette.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: _ProjectsPalette.primary.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          color: Color(0xFF10B981), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Choose how you want to deploy on Buildify:',
                          style: GoogleFonts.spaceMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ModalOption(
                  icon: Icons.rocket_launch_outlined,
                  label: 'host a project',
                  subtitle:
                      'Deploy web applications (Node.js, Python, Flask, Static HTML)',
                  onTap: onHostProject,
                ),
                const SizedBox(height: 12),
                _ModalOption(
                  icon: Icons.psychology_outlined,
                  label: 'run an ai model',
                  subtitle:
                      'Launch a local GGUF AI model server (Llama 3 8B, etc.)',
                  onTap: onRunAiModel,
                ),
                const SizedBox(height: 24),
                Divider(color: Colors.white.withValues(alpha: 0.05)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'cancel',
                    style: GoogleFonts.spaceMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: _ProjectsPalette.primary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModalOption extends StatelessWidget {
  const _ModalOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            color: Colors.white.withValues(alpha: 0.03),
          ),
          child: Row(
            children: [
              Icon(icon, color: _ProjectsPalette.primary.withValues(alpha: 0.8), size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.spaceMono(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: _ProjectsPalette.primary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: GoogleFonts.spaceMono(
                          fontSize: 10,
                          color: const Color(0xFF8B949E),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF8B949E), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaggeredFadeIn extends StatefulWidget {
  const _StaggeredFadeIn({
    required this.children,
    this.delayOffset = 0,
  });

  final List<Widget> children;
  final int delayOffset;

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(widget.children.length, (i) {
        final delay = (widget.delayOffset + i) * 0.1;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(
              ((_controller.value - delay) / (1 - delay)).clamp(0.0, 1.0),
            );
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - t)),
                child: child,
              ),
            );
          },
          child: widget.children[i],
        );
      }),
    );
  }
}

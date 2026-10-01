import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_palette.dart';
import '../services/guided_tour_service.dart';
import '../widgets/guided_tour_overlay.dart';
import 'home_screen.dart';
import 'model_store_screen.dart';
import 'self_test_screen.dart';
import 'network_screen.dart';

class AiServerShell extends ConsumerStatefulWidget {
  const AiServerShell({super.key});

  @override
  ConsumerState<AiServerShell> createState() => _AiServerShellState();
}

class _AiServerShellState extends ConsumerState<AiServerShell> {
  int index = 0;

  final _titleKey = GlobalKey();
  final _navKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final steps = [
        GuidedTourStep(
          title: 'Welcome to Buildify AI',
          description:
              'Run an AI model on this device and expose it as an API. This quick tour shows you around.',
          targetKey: _titleKey,
          tooltipPosition: TooltipPosition.bottom,
        ),
        GuidedTourStep(
          title: 'Four tabs, one flow',
          description:
              'Home starts/stops your server. Models downloads and manages models. '
              'Self test verifies it answers. Network exposes it over a tunnel.',
          targetKey: _navKey,
          tooltipPosition: TooltipPosition.top,
        ),
      ];
      ref.read(guidedTourNotifierProvider.notifier).checkAndAutoStartTour(
            steps,
            tourKey: 'buildify_tour_ai_shell',
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = const [
      HomeScreen(),
      ModelStoreScreen(),
      SelfTestScreen(),
      NetworkScreen(),
    ];

    return GuidedTourOverlay(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppPalette.bg,
          titleSpacing: 16,
          title: Row(
            key: _titleKey,
            children: const [
              Icon(Icons.memory, color: AppPalette.primary),
              SizedBox(width: 8),
              Text('Buildify AI'),
            ],
          ),
        ),
        body: pages[index],
        bottomNavigationBar: NavigationBar(
          key: _navKey,
          selectedIndex: index,
          onDestinationSelected: (next) => setState(() => index = next),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.storage_outlined),
              selectedIcon: Icon(Icons.storage),
              label: 'Models',
            ),
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check),
              label: 'Self test',
            ),
            NavigationDestination(
              icon: Icon(Icons.lan_outlined),
              selectedIcon: Icon(Icons.lan),
              label: 'Network',
            ),
          ],
        ),
      ),
    );
  }
}

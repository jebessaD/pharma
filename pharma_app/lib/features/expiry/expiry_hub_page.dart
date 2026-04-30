import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/pharmacy_hub_scaffold.dart';
import 'expired_panel.dart';
import 'near_expiry_panel.dart';

enum ExpiryHubTab { near, expired }

/// Single route `/pharmacy/expiry?tab=near|expired` (default near).
class ExpiryHubPage extends ConsumerStatefulWidget {
  const ExpiryHubPage({super.key, required this.initialTab});

  final ExpiryHubTab initialTab;

  @override
  ConsumerState<ExpiryHubPage> createState() => _ExpiryHubPageState();
}

class _ExpiryHubPageState extends ConsumerState<ExpiryHubPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == ExpiryHubTab.expired ? 1 : 0,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final tab = _tabController.index == 0 ? 'near' : 'expired';
    final loc = GoRouterState.of(context).uri;
    if (loc.queryParameters['tab'] != tab) {
      context.go('/pharmacy/expiry?tab=$tab');
    }
  }

  @override
  void didUpdateWidget(ExpiryHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      final idx = widget.initialTab == ExpiryHubTab.expired ? 1 : 0;
      if (_tabController.index != idx) {
        _tabController.animateTo(idx);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PharmacyHubScaffold(
      title: '',
      subtitle: null,
      tabController: _tabController,
      tabs: const [
        Tab(text: 'Near expiry', icon: Icon(Icons.event_busy_rounded)),
        Tab(text: 'Expired', icon: Icon(Icons.hourglass_disabled_rounded)),
      ],
      tabBarViewChildren: [
        NearExpiryPanel(
          onViewExpired: () {
            _tabController.animateTo(1);
            context.go('/pharmacy/expiry?tab=expired');
          },
        ),
        ExpiredPanel(
          onViewNear: () {
            _tabController.animateTo(0);
            context.go('/pharmacy/expiry?tab=near');
          },
        ),
      ],
    );
  }
}

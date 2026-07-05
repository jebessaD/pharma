import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/pharmacy_page_app_bar.dart';
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: HubPageHeader(title: 'Expiry'),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Near expiry'),
              Tab(text: 'Expired'),
            ],
            dividerColor: cs.outlineVariant.withValues(alpha: 0.5),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
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
            ),
          ),
        ],
      ),
    );
  }
}

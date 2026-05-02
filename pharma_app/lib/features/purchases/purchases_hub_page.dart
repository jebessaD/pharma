import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/pharmacy_hub_scaffold.dart';
import 'create_purchase_page.dart';
import 'purchase_drafts_list_body.dart';

enum PurchasesHubTab { drafts, newPurchase }

/// `/pharmacy/purchases?tab=drafts|new` (default drafts). Legacy `/purchases/drafts` and `/purchases/new` redirect here.
class PurchasesHubPage extends ConsumerStatefulWidget {
  const PurchasesHubPage({super.key, required this.initialTab});

  final PurchasesHubTab initialTab;

  @override
  ConsumerState<PurchasesHubPage> createState() => _PurchasesHubPageState();
}

class _PurchasesHubPageState extends ConsumerState<PurchasesHubPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex:
          widget.initialTab == PurchasesHubTab.newPurchase ? 1 : 0,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final tab = _tabController.index == 0 ? 'drafts' : 'new';
    final loc = GoRouterState.of(context).uri;
    if (loc.queryParameters['tab'] != tab) {
      context.go('/pharmacy/purchases?tab=$tab');
    }
  }

  @override
  void didUpdateWidget(PurchasesHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      final idx = widget.initialTab == PurchasesHubTab.newPurchase ? 1 : 0;
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
      title: 'Purchases',
      subtitle: 'Drafts and new orders',
      tabController: _tabController,
      tabs: const [
        Tab(text: 'Drafts', icon: Icon(Icons.edit_note_rounded)),
        Tab(text: 'New purchase', icon: Icon(Icons.receipt_long_rounded)),
      ],
      tabBarViewChildren: [
        PurchaseDraftsListBody(
          onSwitchToNewTab: () {
            _tabController.animateTo(1);
            context.go('/pharmacy/purchases?tab=new');
          },
        ),
        const CreatePurchasePage(),
      ],
    );
  }
}

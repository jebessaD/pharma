import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/pharmacy_hub_scaffold.dart';
import '../staff/staff_list_page.dart';
import 'branch_list_page.dart';
import 'team_profile_page.dart';

enum OrganizationHubTab { profile, branches, staff }

/// Admin: `/pharmacy/organization?tab=profile|branches|staff`.
class OrganizationHubPage extends ConsumerStatefulWidget {
  const OrganizationHubPage({super.key, required this.initialTab});

  final OrganizationHubTab initialTab;

  @override
  ConsumerState<OrganizationHubPage> createState() => _OrganizationHubPageState();
}

class _OrganizationHubPageState extends ConsumerState<OrganizationHubPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  int get _initialIndex => switch (widget.initialTab) {
        OrganizationHubTab.profile => 0,
        OrganizationHubTab.branches => 1,
        OrganizationHubTab.staff => 2,
      };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: _initialIndex);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
    final tab = switch (_tabController.index) {
      0 => 'profile',
      1 => 'branches',
      _ => 'staff',
    };
    final loc = GoRouterState.of(context).uri;
    if (loc.queryParameters['tab'] != tab) {
      context.go('/pharmacy/organization?tab=$tab');
    }
  }

  @override
  void didUpdateWidget(OrganizationHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      final idx = _initialIndex;
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
      title: 'Organization',
      subtitle: 'Team, locations, and access',
      tabController: _tabController,
      tabs: const [
        Tab(text: 'Profile', icon: Icon(Icons.apartment_rounded)),
        Tab(text: 'Branches', icon: Icon(Icons.store_mall_directory_rounded)),
        Tab(text: 'Staff', icon: Icon(Icons.groups_rounded)),
      ],
      tabBarViewChildren: [
        const TeamProfilePage(),
        const BranchListPage(embedInHub: true),
        const StaffListPage(embedInHub: true),
      ],
      floatingActionButton: _buildFab(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget? _buildFab(BuildContext context) {
    switch (_tabController.index) {
      case 1:
        return FloatingActionButton.extended(
          onPressed: () => context.push('/pharmacy/branches/new'),
          icon: const Icon(Icons.add),
          label: const Text('Branch'),
        );
      case 2:
        return FloatingActionButton.extended(
          onPressed: () => context.push('/pharmacy/staff/new'),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add staff'),
        );
      default:
        return null;
    }
  }
}

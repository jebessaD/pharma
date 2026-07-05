import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/providers/branches_list_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/widgets/pharmacy_hub_scaffold.dart';
import '../staff/staff_create_form.dart';
import '../staff/staff_credentials_dialog.dart';
import '../staff/staff_list_page.dart';
import 'branch_list_page.dart';
import 'team_profile_page.dart';

enum OrganizationHubTab { profile, branches, staff }

/// Admin: `/pharmacy/organization?tab=profile|branches|staff`.
class OrganizationHubPage extends ConsumerStatefulWidget {
  const OrganizationHubPage({
    super.key,
    required this.initialTab,
    this.autoOpenStaffAdd = false,
  });

  final OrganizationHubTab initialTab;
  final bool autoOpenStaffAdd;

  @override
  ConsumerState<OrganizationHubPage> createState() =>
      _OrganizationHubPageState();
}

class _OrganizationHubPageState extends ConsumerState<OrganizationHubPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _staffRefreshTick = 0;

  int get _initialIndex => switch (widget.initialTab) {
    OrganizationHubTab.profile => 0,
    OrganizationHubTab.branches => 1,
    OrganizationHubTab.staff => 2,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: _initialIndex,
    );
    _tabController.addListener(_onTabChanged);
    if (widget.autoOpenStaffAdd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddStaffInline(context);
      });
    }
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
      subtitle: 'Team, branches, and access',
      tabController: _tabController,
      tabs: const [
        Tab(text: 'Profile', icon: Icon(Icons.apartment_rounded)),
        Tab(text: 'Branches', icon: Icon(Icons.store_mall_directory_rounded)),
        Tab(text: 'Staff', icon: Icon(Icons.groups_rounded)),
      ],
      tabBarViewChildren: [
        const TeamProfilePage(),
        const BranchListPage(embedInHub: true),
        StaffListPage(
          key: ValueKey('staff-list-$_staffRefreshTick'),
          embedInHub: true,
        ),
      ],
      floatingActionButton: _buildFab(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget? _buildFab(BuildContext context) {
    switch (_tabController.index) {
      case 1:
        return FloatingActionButton.extended(
          onPressed: () => _showAddBranchInline(context),
          icon: const Icon(Icons.add),
          label: const Text('Branch'),
        );
      case 2:
        return FloatingActionButton.extended(
          onPressed: () => _showAddStaffInline(context),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add staff'),
        );
      default:
        return null;
    }
  }

  Future<void> _showAddBranchInline(BuildContext context) async {
    debugPrint('[OrganizationHub] FAB Branch tapped -> inline sheet');
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final branches = (teamId == null || teamId.isEmpty)
        ? const <Map<String, dynamic>>[]
        : (ref.read(branchesListProvider(teamId)).value ?? const []);
    final formKey = GlobalKey<FormState>();
    final nameCtl = TextEditingController();
    final codeCtl = TextEditingController();
    final addressCtl = TextEditingController();
    bool duplicateCatalog = false;
    String? sourceBranchId;
    String? errorText;
    bool loading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (formKey.currentState?.validate() != true) return;
              if (teamId == null || teamId.isEmpty) {
                setSheetState(() {
                  errorText =
                      'Your team profile is not ready yet. Re-open organization or sign in again.';
                });
                return;
              }
              if (duplicateCatalog && sourceBranchId == null) {
                setSheetState(() {
                  errorText = 'Choose a source branch to copy medicines from.';
                });
                return;
              }
              setSheetState(() {
                loading = true;
                errorText = null;
              });
              try {
                final created = await Supabase.instance.client
                    .from('branches')
                    .insert({
                      'team_id': teamId,
                      'name': nameCtl.text.trim(),
                      'code': codeCtl.text.trim(),
                      'address': addressCtl.text.trim().isEmpty
                          ? null
                          : addressCtl.text.trim(),
                    })
                    .select('id')
                    .single();
                final createdBranchId = created['id'] as String?;
                String copySummary = '';
                if (duplicateCatalog &&
                    createdBranchId != null &&
                    sourceBranchId != null) {
                  final dup = await Supabase.instance.client.rpc(
                    'duplicate_branch_medicines',
                    params: {
                      'p_source_branch_id': sourceBranchId,
                      'p_target_branch_id': createdBranchId,
                      'p_skip_existing': true,
                    },
                  );
                  if (dup is Map) {
                    final copied =
                        (dup['copied_count'] as num?)?.toInt() ?? 0;
                    final skipped =
                        (dup['skipped_count'] as num?)?.toInt() ?? 0;
                    copySummary =
                        ' Copied $copied catalog item(s); $skipped skipped (already on target).';
                  }
                }
                if (!sheetContext.mounted) return;
                ref.invalidate(branchesListProvider(teamId));
                AppFeedback.success(
                  sheetContext,
                  duplicateCatalog && copySummary.isNotEmpty
                      ? 'Branch created.$copySummary'
                      : 'Branch created',
                );
                Navigator.of(sheetContext).pop();
              } catch (e) {
                setSheetState(() => errorText = mapFormError(e));
              } finally {
                if (mounted) {
                  setSheetState(() => loading = false);
                }
              }
            }

            final insets = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Add branch',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      AppTextFormField(
                        controller: nameCtl,
                        label: 'Branch name',
                        validator: (v) => FormValidators.requiredText(
                          v,
                          label: 'Branch name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppTextFormField(
                        controller: codeCtl,
                        label: 'Branch code (unique per team)',
                        validator: (v) => FormValidators.requiredText(
                          v,
                          label: 'Branch code',
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppTextFormField(
                        controller: addressCtl,
                        label: 'Address',
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Copy medicines from another branch'),
                        subtitle: const Text(
                          'Catalog only. Existing medicines in the new branch are skipped.',
                        ),
                        value: duplicateCatalog,
                        onChanged: loading
                            ? null
                            : (v) => setSheetState(() {
                                duplicateCatalog = v;
                                if (!v) sourceBranchId = null;
                              }),
                      ),
                      if (duplicateCatalog) ...[
                        const SizedBox(height: 8),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Source branch',
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: sourceBranchId,
                              isExpanded: true,
                              hint: const Text('Select source branch'),
                              items: branches
                                  .map(
                                    (b) => DropdownMenuItem<String>(
                                      value: b['id'] as String,
                                      child: Text(b['name'] as String? ?? ''),
                                    ),
                                  )
                                  .toList(),
                              onChanged: loading
                                  ? null
                                  : (v) => setSheetState(() => sourceBranchId = v),
                            ),
                          ),
                        ),
                      ],
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        FormErrorBanner(message: errorText!),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: loading ? null : submit,
                        child: loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Create'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

  }

  Future<void> _showAddStaffInline(BuildContext context) async {
    debugPrint('[OrganizationHub] FAB Staff tapped -> inline sheet');
    final profile = ref.read(pharmacyProfileProvider).value;
    final viewerRole = profile?['role'] as String? ?? '';
    final canAssignAdmin = viewerRole == 'owner';
    final teamId = profile?['team_id'] as String? ?? '';
    final branches = teamId.isEmpty
        ? <Map<String, dynamic>>[]
        : (ref.read(branchesListProvider(teamId)).value ?? const []);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final insets = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add staff',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                StaffCreateForm(
                  teamId: teamId,
                  branches: branches,
                  canAssignAdmin: canAssignAdmin,
                  compact: true,
                  onCreated: (username, password) async {
                    if (mounted) setState(() => _staffRefreshTick++);
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                    if (!context.mounted) return;
                    await showStaffCredentialsDialog(
                      context: context,
                      username: username,
                      password: password,
                    );
                    if (!context.mounted) return;
                    AppFeedback.success(context, 'Staff user created');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

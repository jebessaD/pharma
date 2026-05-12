import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/staff_username_availability.dart';
import '../../core/forms/form_error_mapper.dart';
import '../../core/forms/form_validators.dart';
import '../../core/providers/branches_list_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/form_error_banner.dart';
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
        return _OrganizationAddStaffSheet(
          teamId: teamId,
          branches: branches,
          canAssignAdmin: canAssignAdmin,
          onCreated: () {
            if (mounted) setState(() => _staffRefreshTick++);
          },
        );
      },
    );
  }
}

/// Owns [TextEditingController]s so they are disposed only after the modal
/// subtree unmounts (avoids use-after-dispose when the sheet closes).
class _OrganizationAddStaffSheet extends StatefulWidget {
  const _OrganizationAddStaffSheet({
    required this.teamId,
    required this.branches,
    required this.canAssignAdmin,
    required this.onCreated,
  });

  final String teamId;
  final List<Map<String, dynamic>> branches;
  final bool canAssignAdmin;
  final VoidCallback onCreated;

  @override
  State<_OrganizationAddStaffSheet> createState() =>
      _OrganizationAddStaffSheetState();
}

class _OrganizationAddStaffSheetState extends State<_OrganizationAddStaffSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameCtl;
  late final TextEditingController _usernameCtl;
  late final TextEditingController _passwordCtl;
  Timer? _usernameDebounce;
  int _usernameCheckSeq = 0;
  bool? _usernameAvailable;
  String _role = 'pharmacist';
  late String? _branchId;
  String? _errorText;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _fullNameCtl = TextEditingController();
    _usernameCtl = TextEditingController();
    _passwordCtl = TextEditingController();
    _branchId = widget.branches.length == 1
        ? widget.branches.first['id'] as String
        : null;
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _fullNameCtl.dispose();
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  void _scheduleUsernameCheck(String _) {
    _usernameDebounce?.cancel();
    final currentText = _usernameCtl.text;
    _usernameDebounce = Timer(const Duration(milliseconds: 400), () async {
      final seq = ++_usernameCheckSeq;
      final avail = await queryStaffUsernameAvailable(
        Supabase.instance.client,
        currentText,
      );
      if (!mounted || seq != _usernameCheckSeq) return;
      setState(() => _usernameAvailable = avail);
    });
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    if (_usernameAvailable == false) return;
    if (_branchId == null) {
      setState(() => _errorText = 'Please assign a branch.');
      return;
    }
    if (widget.teamId.isEmpty) {
      setState(() {
        _errorText =
            'Your team profile is not ready yet. Re-open organization or sign in again.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    var closed = false;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'admin-create-user',
        body: {
          'username': _usernameCtl.text.trim().toLowerCase(),
          'password': _passwordCtl.text,
          'full_name': _fullNameCtl.text.trim(),
          'role': _role,
          'branch_id': _branchId,
        },
      );
      if (res.status >= 400) {
        throw FunctionException(status: res.status, details: res.data);
      }
      if (!mounted) return;
      widget.onCreated();
      AppFeedback.success(context, 'Staff user created');
      Navigator.of(context).pop();
      closed = true;
    } catch (e) {
      if (mounted) setState(() => _errorText = userFacingError(e));
    } finally {
      if (mounted && !closed) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add staff', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              AppTextFormField(
                controller: _fullNameCtl,
                label: 'Full name',
                validator: (v) =>
                    FormValidators.requiredText(v, label: 'Full name'),
              ),
              const SizedBox(height: 12),
              AppTextFormField(
                controller: _usernameCtl,
                label: 'Username',
                textCapitalization: TextCapitalization.none,
                onChanged: _scheduleUsernameCheck,
                validator: (v) {
                  final base = FormValidators.staffUsername(v);
                  if (base != null) return base;
                  if (_usernameAvailable == false) {
                    return 'This username is already taken';
                  }
                  return null;
                },
              ),
              const Text(
                'Unique across all pharmacies (3–32 chars: letters, numbers, underscores).',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtl,
                obscureText: _obscurePassword,
                validator: (v) => FormValidators.passwordMinLength(v, min: 8),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Role'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _role,
                    isExpanded: true,
                    items: [
                      if (widget.canAssignAdmin)
                        const DropdownMenuItem(
                          value: 'admin',
                          child: Text('Admin'),
                        ),
                      const DropdownMenuItem(
                        value: 'pharmacist',
                        child: Text('Pharmacist'),
                      ),
                      const DropdownMenuItem(
                        value: 'seller',
                        child: Text('Seller (counter)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _role = value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Branch *'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _branchId,
                    isExpanded: true,
                    hint: const Text('Select a branch'),
                    items: widget.branches
                        .map(
                          (b) => DropdownMenuItem<String?>(
                            value: b['id'] as String,
                            child: Text(b['name'] as String? ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _branchId = value),
                  ),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                FormErrorBanner(message: _errorText!),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create user'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

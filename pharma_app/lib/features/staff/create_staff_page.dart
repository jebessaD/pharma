import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/branches_list_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';
import 'staff_create_form.dart';
import 'staff_credentials_dialog.dart';

class CreateStaffPage extends ConsumerWidget {
  const CreateStaffPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(pharmacyProfileProvider).value;
    final viewerRole = profile?['role'] as String? ?? '';
    final canAssignAdmin = viewerRole == 'owner';
    final teamId = profile?['team_id'] as String? ?? '';
    final branches = ref.watch(branchesListProvider(teamId)).value ?? const [];

    return Scaffold(
      appBar: pharmacyPageAppBar(context, title: 'Add staff'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          StaffCreateForm(
            teamId: teamId,
            branches: branches,
            canAssignAdmin: canAssignAdmin,
            onCreated: (username, password) async {
              AppFeedback.success(context, 'Staff user created');
              await showStaffCredentialsDialog(
                context: context,
                username: username,
                password: password,
              );
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
    );
  }
}

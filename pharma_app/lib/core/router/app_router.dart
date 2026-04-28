import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers.dart';
import '../../features/audit/activity_log_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/expiry/expiry_hub_page.dart';
import '../../features/home/pharmacy_home_page.dart';
import '../../features/inventory/stock_adjust_page.dart';
import '../../features/inventory/stock_hub_page.dart';
import '../../features/inventory/stock_in_page.dart';
import '../../features/inventory/stock_movements_page.dart';
import '../../features/medicines/create_medicine_page.dart';
import '../../features/medicines/edit_medicine_page.dart';
import '../../features/medicines/medicine_detail_page.dart';
import '../../features/medicines/medicine_list_page.dart';
import '../../features/notifications/notification_list_page.dart';
import '../../features/pharmacy/pharmacy_shell.dart';
import '../../features/platform_admin/create_team_page.dart';
import '../../features/platform_admin/team_detail_page.dart';
import '../../features/platform_admin/team_list_page.dart';
import '../../features/pos/pos_page.dart';
import '../../features/pos/sale_receipt_page.dart';
import '../../features/purchases/create_purchase_page.dart';
import '../../features/purchases/edit_supplier_page.dart';
import '../../features/purchases/supplier_list_page.dart';
import '../../features/reports/report_viewer_page.dart';
import '../../features/reports/reports_home_page.dart';
import '../../features/staff/create_staff_page.dart';
import '../../features/staff/edit_staff_page.dart';
import '../../features/shell/landing_page.dart';
import '../../features/shell/team_suspended_page.dart';
import '../../features/team/create_branch_page.dart';
import '../../features/team/edit_branch_page.dart';
import '../../features/team/organization_hub_page.dart';
import '../../features/dashboard/dashboard_home_page.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.read(supabaseAuthRefreshProvider);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final loc = state.matchedLocation;
      final userId = Supabase.instance.client.auth.currentUser?.id;

      bool isAllowedForRole(String role, String path) {
        const adminAllowed = <String>['/pharmacy'];
        const pharmacistAllowed = <String>[
          '/pharmacy/home',
          '/pharmacy/pos',
          '/pharmacy/medicines',
          '/pharmacy/stock',
          '/pharmacy/low-stock',
          '/pharmacy/stock-in',
          '/pharmacy/adjust-stock',
          '/pharmacy/stock-movements',
          '/pharmacy/expiry',
          '/pharmacy/dashboard',
          '/pharmacy/reports',
          '/pharmacy/receipt',
        ];
        const cashierAllowed = <String>[
          '/pharmacy/home',
          '/pharmacy/pos',
          '/pharmacy/receipt',
        ];
        final allowed = switch (role) {
          'admin' => adminAllowed,
          'pharmacist' => pharmacistAllowed,
          'cashier' => cashierAllowed,
          _ => const <String>[],
        };
        return allowed.any((prefix) => path.startsWith(prefix));
      }

      if (loc.startsWith('/admin')) {
        if (session == null) return '/login';
        final admin = await Supabase.instance.client
            .from('platform_admins')
            .select('is_active')
            .eq('id', userId ?? '')
            .maybeSingle();
        final isActiveAdmin = admin?['is_active'] == true;
        if (!isActiveAdmin) return '/pharmacy/home';
        return null;
      }

      if (loc.startsWith('/pharmacy')) {
        if (session == null) return '/login';
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('role, team_id, is_active')
            .eq('id', userId ?? '')
            .maybeSingle();
        final role = profile?['role'] as String?;
        final isActiveUser = profile?['is_active'] != false;
        final teamId = profile?['team_id'] as String?;
        if (!isActiveUser) return '/login';
        if (teamId != null) {
          final team = await Supabase.instance.client
              .from('teams')
              .select('status')
              .eq('id', teamId)
              .maybeSingle();
          if (team?['status'] == 'suspended') return '/suspended';
        }
        if (role != null && !isAllowedForRole(role, loc)) return '/pharmacy/home';
        return null;
      }

      if (loc == '/login') return null;
      if (loc == '/suspended') return null;
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LandingPage(),
      ),
      GoRoute(
        path: '/admin/teams',
        builder: (context, state) => const TeamListPage(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const CreateTeamPage(),
          ),
          GoRoute(
            path: ':teamId',
            builder: (context, state) {
              final id = state.pathParameters['teamId']!;
              return TeamDetailPage(teamId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/suspended',
        builder: (context, state) => const TeamSuspendedPage(),
      ),
      GoRoute(
        path: '/pharmacy',
        redirect: (context, state) =>
            state.uri.path == '/pharmacy' ? '/pharmacy/home' : null,
        routes: [
          ShellRoute(
            builder: (context, state, child) => PharmacyShell(child: child),
            routes: [
          GoRoute(
            path: 'home',
            builder: (context, state) => const PharmacyHomePage(),
          ),
          GoRoute(
            path: 'team-profile',
            redirect: (context, state) => '/pharmacy/organization?tab=profile',
          ),
          GoRoute(
            path: 'organization',
            redirect: (context, state) async {
              final user = Supabase.instance.client.auth.currentUser;
              if (user == null) return '/login';
              final profile = await Supabase.instance.client
                  .from('profiles')
                  .select('role')
                  .eq('id', user.id)
                  .maybeSingle();
              final role = profile?['role'] as String?;
              if (role != 'admin') return '/pharmacy/home';
              return null;
            },
            builder: (context, state) {
              final tab = state.uri.queryParameters['tab'];
              final initial = switch (tab) {
                'branches' => OrganizationHubTab.branches,
                'staff' => OrganizationHubTab.staff,
                _ => OrganizationHubTab.profile,
              };
              return OrganizationHubPage(initialTab: initial);
            },
          ),
          GoRoute(
            path: 'staff',
            redirect: (context, state) async {
              final user = Supabase.instance.client.auth.currentUser;
              if (user == null) return '/login';
              final profile = await Supabase.instance.client
                  .from('profiles')
                  .select('role')
                  .eq('id', user.id)
                  .maybeSingle();
              final role = profile?['role'] as String?;
              if (role != 'admin') return '/pharmacy/home';
              if (state.matchedLocation == '/pharmacy/staff') {
                return '/pharmacy/organization?tab=staff';
              }
              return null;
            },
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const CreateStaffPage(),
              ),
              GoRoute(
                path: ':staffId/edit',
                builder: (context, state) =>
                    EditStaffPage(staffId: state.pathParameters['staffId']!),
              ),
            ],
          ),
          GoRoute(
            path: 'branches',
            redirect: (context, state) {
              if (state.matchedLocation == '/pharmacy/branches') {
                return '/pharmacy/organization?tab=branches';
              }
              return null;
            },
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const CreateBranchPage(),
              ),
              GoRoute(
                path: ':branchId/edit',
                builder: (context, state) =>
                    EditBranchPage(branchId: state.pathParameters['branchId']!),
              ),
            ],
          ),
          GoRoute(
            path: 'medicines',
            builder: (context, state) => const MedicineListPage(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const CreateMedicinePage(),
              ),
              GoRoute(
                path: ':medicineId/edit',
                builder: (context, state) => EditMedicinePage(
                  medicineId: state.pathParameters['medicineId']!,
                ),
              ),
              GoRoute(
                path: ':medicineId',
                builder: (context, state) {
                  final id = state.pathParameters['medicineId']!;
                  return MedicineDetailPage(medicineId: id);
                },
              ),
            ],
          ),
          GoRoute(
            path: 'low-stock',
            redirect: (context, state) => '/pharmacy/stock?tab=low',
          ),
          GoRoute(
            path: 'stock',
            builder: (context, state) {
              final tab = state.uri.queryParameters['tab'];
              final initial = tab == 'low' ? StockHubTab.low : StockHubTab.balances;
              return StockHubPage(initialTab: initial);
            },
          ),
          GoRoute(
            path: 'stock-in',
            builder: (context, state) {
              final bulk = state.uri.queryParameters['tab'] == 'bulk';
              return StockInPage(openBulkTab: bulk);
            },
          ),
          GoRoute(
            path: 'bulk-stock-in',
            redirect: (context, state) => '/pharmacy/stock-in?tab=bulk',
          ),
          GoRoute(
            path: 'stock-movements',
            builder: (context, state) => const StockMovementsPage(),
          ),
          GoRoute(
            path: 'adjust-stock',
            builder: (context, state) => const StockAdjustPage(),
          ),
          GoRoute(
            path: 'pos',
            builder: (context, state) => const PosPage(),
          ),
          GoRoute(
            path: 'receipt/:saleId',
            builder: (context, state) {
              final id = state.pathParameters['saleId']!;
              return SaleReceiptPage(saleId: id);
            },
          ),
          GoRoute(
            path: 'expiry/near',
            redirect: (context, state) => '/pharmacy/expiry?tab=near',
          ),
          GoRoute(
            path: 'expiry/expired',
            redirect: (context, state) => '/pharmacy/expiry?tab=expired',
          ),
          GoRoute(
            path: 'expiry',
            builder: (context, state) {
              final tab = state.uri.queryParameters['tab'];
              final initial = tab == 'expired' ? ExpiryHubTab.expired : ExpiryHubTab.near;
              return ExpiryHubPage(initialTab: initial);
            },
          ),
          GoRoute(
            path: 'notifications',
            builder: (context, state) => const NotificationListPage(),
          ),
          GoRoute(
            path: 'suppliers',
            builder: (context, state) => const SupplierListPage(),
            routes: [
              GoRoute(
                path: ':supplierId/edit',
                builder: (context, state) =>
                    EditSupplierPage(supplierId: state.pathParameters['supplierId']!),
              ),
            ],
          ),
          GoRoute(
            path: 'purchases/new',
            builder: (context, state) => const CreatePurchasePage(),
          ),
          GoRoute(
            path: 'dashboard',
            builder: (context, state) => const DashboardHomePage(),
          ),
          GoRoute(
            path: 'reports',
            builder: (context, state) => const ReportsHomePage(),
            routes: [
              GoRoute(
                path: ':reportType',
                builder: (context, state) {
                  final t = state.pathParameters['reportType']!;
                  return ReportViewerPage(reportType: t);
                },
              ),
            ],
          ),
          GoRoute(
            path: 'audit',
            builder: (context, state) => const ActivityLogPage(),
          ),
            ],
          ),
        ],
      ),
    ],
  );
});

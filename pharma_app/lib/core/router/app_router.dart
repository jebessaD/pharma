import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_persistence.dart';
import '../providers/app_update_gate_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/pharmacy_redirect_cache_provider.dart';
import '../providers.dart';
import '../shared_preferences_provider.dart';
import '../../features/audit/activity_log_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/reset_password_page.dart';
import '../../features/auth/signup_page.dart';
import '../../features/expiry/expiry_hub_page.dart';
import '../../features/home/pharmacy_home_page.dart';
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
import '../../features/shell/auth_callback_page.dart';
import '../../features/shell/billing_blocked_page.dart';
import '../../features/shell/animated_splash_page.dart';
import '../../features/shell/landing_page.dart';
import '../../features/shell/contact_us_page.dart';
import '../../features/shell/platform_messages_page.dart';
import '../../features/shell/team_suspended_page.dart';
import '../../features/shell/trial_ended_page.dart';
import '../../features/shell/update_required_page.dart';
import '../../features/team/create_branch_page.dart';
import '../../features/team/edit_branch_page.dart';
import '../../features/team/organization_hub_page.dart';
import '../../features/dashboard/dashboard_home_page.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = Listenable.merge([
    ref.read(supabaseAuthRefreshProvider),
    ref.read(appUpdateRefreshProvider),
  ]);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final loc = state.matchedLocation;
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final isOnline = ref.read(connectivityProvider).value ?? true;

      // Redirect precedence: force update → auth → team suspended → billing block
      // → trial ended → role allowlists.
      if (loc == '/update-required') {
        await ref.read(appUpdateGateNotifierProvider.notifier).ensureHydrated();
        final ug = ref.read(appUpdateGateNotifierProvider);
        if (ug?.blocked != true) {
          return session != null ? '/pharmacy/home' : '/login';
        }
        return null;
      }

      await ref.read(appUpdateGateNotifierProvider.notifier).ensureHydrated();
      final ug = ref.read(appUpdateGateNotifierProvider);
      if (ug?.blocked == true) return '/update-required';

      bool isConnectivityRelated(Object error) {
        final lower = error.toString().toLowerCase();
        return lower.contains('socket') ||
            lower.contains('network') ||
            lower.contains('failed host lookup') ||
            lower.contains('connection') ||
            lower.contains('timed out') ||
            lower.contains('clientexception') ||
            lower.contains('failed to fetch');
      }

      bool isAllowedForRole(String role, String path) {
        const adminAllowed = <String>['/pharmacy'];
        const ownerAllowed = <String>['/pharmacy'];
        const pharmacistAllowed = <String>[
          '/pharmacy/home',
          '/pharmacy/pos',
          '/pharmacy/medicines',
          '/pharmacy/stock',
          '/pharmacy/low-stock',
          '/pharmacy/stock-in',
          '/pharmacy/stock-movements',
          '/pharmacy/expiry',
          '/pharmacy/dashboard',
          '/pharmacy/reports',
          '/pharmacy/receipt',
          '/pharmacy/platform-messages',
          '/pharmacy/contact',
        ];
        const cashierAllowed = <String>[
          '/pharmacy/home',
          '/pharmacy/pos',
          '/pharmacy/receipt',
          '/pharmacy/platform-messages',
          '/pharmacy/contact',
        ];
        final allowed = switch (role) {
          'admin' => adminAllowed,
          'owner' => ownerAllowed,
          'pharmacist' => pharmacistAllowed,
          'cashier' => cashierAllowed,
          'seller' => cashierAllowed,
          _ => const <String>[],
        };
        return allowed.any((prefix) => path.startsWith(prefix));
      }

      if (loc == '/trial-ended' && session == null) return '/login';
      if (loc == '/billing-blocked' && session == null) return '/login';
      if (loc == '/signup' && session != null) return '/pharmacy/home';

      if (loc == '/trial-ended' && session != null && userId != null) {
        try {
          await ref
              .read(pharmacyRedirectCacheProvider.notifier)
              .hydrate(userId);
          final g = ref.read(pharmacyRedirectCacheProvider);
          if (g != null && !g.shouldShowTrialEndedRoute) {
            return '/pharmacy/home';
          }
        } catch (_) {
          /* offline: allow staying on trial page */
        }
      }

      if (loc == '/billing-blocked' && session != null && userId != null) {
        try {
          await ref
              .read(pharmacyRedirectCacheProvider.notifier)
              .hydrate(userId);
          final g = ref.read(pharmacyRedirectCacheProvider);
          if (g != null && !g.shouldShowBillingBlockedRoute) {
            return '/pharmacy/home';
          }
        } catch (_) {
          /* offline */
        }
      }

      if (loc.startsWith('/admin')) {
        if (session == null) return '/login';
        try {
          final admin = await Supabase.instance.client
              .from('platform_admins')
              .select('is_active')
              .eq('id', userId ?? '')
              .maybeSingle();
          final isActiveAdmin = admin?['is_active'] == true;
          if (!isActiveAdmin) return '/pharmacy/home';
        } catch (e) {
          if (!isOnline || isConnectivityRelated(e)) return '/pharmacy/home';
          rethrow;
        }
        return null;
      }

      if (loc.startsWith('/pharmacy')) {
        if (session == null) return '/login';
        try {
          await ref
              .read(pharmacyRedirectCacheProvider.notifier)
              .hydrate(userId);
          final gate = ref.read(pharmacyRedirectCacheProvider);
          if (gate == null) return '/login';
          if (!gate.isActiveUser) return '/login';
          if (gate.teamId != null && gate.teamStatus == 'suspended') {
            return '/suspended';
          }
          if (gate.teamId != null && gate.shouldShowBillingBlockedRoute) {
            return '/billing-blocked';
          }
          if (gate.teamId != null && gate.shouldShowTrialEndedRoute) {
            return '/trial-ended';
          }
          if (gate.role != null && !isAllowedForRole(gate.role!, loc)) {
            return '/pharmacy/home';
          }
        } catch (e) {
          if (!isOnline || isConnectivityRelated(e)) return null;
          rethrow;
        }
        return null;
      }

      if (loc == '/splash') return null;
      if (loc == '/' && session != null) return '/pharmacy/home';

      final authRefresh = ref.read(supabaseAuthRefreshProvider);

      // PKCE email links open pharmaapp://auth/callback → path /callback.
      // Route password recovery to reset page, otherwise bootstrap profile
      // for first-time signups that went through email verification.
      if (loc == '/callback') {
        if (authRefresh.passwordRecoveryPending) return '/reset-password';
        if (session != null) {
          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            final existing = await Supabase.instance.client
                .from('profiles')
                .select('id')
                .eq('id', user.id)
                .maybeSingle();
            if (existing == null) {
              final prefs = ref.read(sharedPreferencesProvider);
              final pending = readPendingOwnerSignup(prefs);
              final meta = user.userMetadata ?? const <String, dynamic>{};
              final authEmail = user.email?.trim().toLowerCase() ?? '';
              final pendingEmail =
                  (pending.email ?? '').trim().toLowerCase();
              final isPending =
                  authEmail.isNotEmpty && authEmail == pendingEmail;

              final teamName =
                  (isPending ? pending.teamName : null) ??
                  (meta['team_name'] as String?) ??
                  '';
              final fullName =
                  (isPending ? pending.fullName : null) ??
                  (meta['full_name'] as String?) ??
                  '';

              if (teamName.trim().length >= 2 &&
                  fullName.trim().isNotEmpty) {
                try {
                  await Supabase.instance.client.rpc(
                    'bootstrap_owner_team',
                    params: {
                      'p_team_name': teamName.trim(),
                      'p_full_name': fullName.trim(),
                    },
                  );
                  await clearPendingOwnerSignup(prefs);
                } catch (_) {
                  // bootstrap failed — login page can retry
                }
              }
            }
          }
          ref.invalidate(pharmacyRedirectCacheProvider);
          return '/pharmacy/home';
        }
        return null;
      }

      if (loc == '/reset-password') {
        if (session == null) return '/login';
        if (!authRefresh.passwordRecoveryPending) return '/pharmacy/home';
        return null;
      }

      // After deep-link email verification, supabase_flutter exchanges the
      // PKCE code and fires onAuthStateChange. Redirect authenticated users
      // away from auth screens automatically.
      if ((loc == '/login' || loc == '/signup') && session != null) {
        return '/pharmacy/home';
      }
      if (loc == '/login') return null;
      if (loc == '/signup') return null;
      if (loc == '/suspended') return null;
      if (loc == '/trial-ended') return null;
      if (loc == '/billing-blocked') return null;
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const AnimatedSplashPage()),
      GoRoute(path: '/', builder: (context, state) => const LandingPage()),
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
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/callback',
        builder: (context, state) => const AuthCallbackPage(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordPage(),
      ),
      GoRoute(path: '/signup', builder: (context, state) => const SignupPage()),
      GoRoute(
        path: '/suspended',
        builder: (context, state) => const TeamSuspendedPage(),
      ),
      GoRoute(
        path: '/trial-ended',
        builder: (context, state) => const TrialEndedPage(),
      ),
      GoRoute(
        path: '/billing-blocked',
        builder: (context, state) => const BillingBlockedPage(),
      ),
      GoRoute(
        path: '/update-required',
        builder: (context, state) => const UpdateRequiredPage(),
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
                redirect: (context, state) =>
                    '/pharmacy/organization?tab=profile',
              ),
              GoRoute(
                path: 'organization',
                redirect: (context, state) async {
                  final user = Supabase.instance.client.auth.currentUser;
                  if (user == null) return '/login';
                  await ref
                      .read(pharmacyRedirectCacheProvider.notifier)
                      .hydrate(user.id);
                  final role = ref.read(pharmacyRedirectCacheProvider)?.role;
                  if (role != 'admin' && role != 'owner') {
                    return '/pharmacy/home';
                  }
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
                  await ref
                      .read(pharmacyRedirectCacheProvider.notifier)
                      .hydrate(user.id);
                  final role = ref.read(pharmacyRedirectCacheProvider)?.role;
                  if (role != 'admin' && role != 'owner') {
                    return '/pharmacy/home';
                  }
                  if (state.uri.path == '/pharmacy/staff') {
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
                    builder: (context, state) => EditStaffPage(
                      staffId: state.pathParameters['staffId']!,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'branches',
                redirect: (context, state) {
                  if (state.uri.path == '/pharmacy/branches') {
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
                    builder: (context, state) => EditBranchPage(
                      branchId: state.pathParameters['branchId']!,
                    ),
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
                  final initial = tab == 'low'
                      ? StockHubTab.low
                      : StockHubTab.balances;
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
                  final initial = tab == 'expired'
                      ? ExpiryHubTab.expired
                      : ExpiryHubTab.near;
                  return ExpiryHubPage(initialTab: initial);
                },
              ),
              GoRoute(
                path: 'notifications',
                builder: (context, state) => const NotificationListPage(),
              ),
              GoRoute(
                path: 'platform-messages',
                builder: (context, state) => const PlatformMessagesPage(),
              ),
              GoRoute(
                path: 'contact',
                builder: (context, state) => const ContactUsPage(),
              ),
              GoRoute(
                path: 'suppliers',
                builder: (context, state) => const SupplierListPage(),
                routes: [
                  GoRoute(
                    path: ':supplierId/edit',
                    builder: (context, state) => EditSupplierPage(
                      supplierId: state.pathParameters['supplierId']!,
                    ),
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

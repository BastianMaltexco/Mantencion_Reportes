import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/history/presentation/report_detail_page.dart';
import '../../features/history/presentation/report_history_page.dart';
import '../../features/reports/presentation/create_maintenance_report_page.dart';

final appRouterProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, _) => const _SessionGate()),
      GoRoute(path: '/login', builder: (context, _) => const LoginPage()),
      GoRoute(
        path: '/reports/new',
        builder: (context, _) => const CreateMaintenanceReportPage(),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, _) => const ReportHistoryPage(),
      ),
      GoRoute(
        path: '/reports/:id',
        builder: (context, state) =>
            ReportDetailPage(reportId: int.parse(state.pathParameters['id']!)),
      ),
    ],
  ),
);

class _SessionGate extends ConsumerWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => const LoginPage(),
      data: (user) => user == null ? const LoginPage() : HomePage(user: user),
    );
  }
}

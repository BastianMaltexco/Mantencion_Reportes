import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/domain/authenticated_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalogs/presentation/catalogs_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, required this.user});
  final AuthenticatedUser user;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[_HomeMenu(user: widget.user), const CatalogsPage()];
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'Inicio' : 'Catálogos'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.precision_manufacturing_outlined),
            selectedIcon: Icon(Icons.precision_manufacturing),
            label: 'Catálogos',
          ),
        ],
      ),
    );
  }
}

class _HomeMenu extends StatelessWidget {
  const _HomeMenu({required this.user});
  final AuthenticatedUser user;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
    children: [
      Text(
        'Hola, ${user.fullName}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 6),
      Text('Rol: ${user.role}', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 28),
      _MenuAction(
        icon: Icons.add_circle_outline,
        label: 'Nuevo reporte',
        onTap: () => context.push('/new-report'),
      ),
      const SizedBox(height: 14),
      _MenuAction(
        icon: Icons.history,
        label: 'Historial',
        onTap: () => context.push('/history'),
      ),
      const SizedBox(height: 14),
      _MenuAction(
        icon: Icons.dashboard_outlined,
        label: 'Dashboard',
        onTap: () => context.push('/dashboard'),
      ),
      if (user.isAdministrator) ...[
        const SizedBox(height: 14),
        _MenuAction(
          icon: Icons.people_outline,
          label: 'Usuarios',
          onTap: () => context.push('/users'),
        ),
      ],
      const SizedBox(height: 36),
      const _MaltexcoBrand(),
    ],
  );
}

class _MaltexcoBrand extends StatelessWidget {
  const _MaltexcoBrand();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Desarrollado por Maltexco',
    child: Column(
      children: [
        Opacity(
          opacity: .78,
          child: Image.asset(
            'assets/images/logo_maltexco.png',
            width: 104,
            height: 52,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Desarrollado por Maltexco',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Row(
              children: [
                Icon(icon, color: colors.onPrimaryContainer, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

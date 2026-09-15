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
    final pages = <Widget>[
      _WelcomePage(user: widget.user),
      const CatalogsPage(),
      if (widget.user.isAdministrator) const _AdminPlaceholder(),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Inicio',
      ),
      const NavigationDestination(
        icon: Icon(Icons.precision_manufacturing_outlined),
        selectedIcon: Icon(Icons.precision_manufacturing),
        label: 'Catálogos',
      ),
      if (widget.user.isAdministrator)
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Administración',
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes Mantención'),
        actions: [
          IconButton(
            tooltip: 'Historial de reportes',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/reports'),
          ),
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
      body: pages[_index],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/reports/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo reporte'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: destinations,
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.user});
  final AuthenticatedUser user;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hola, ${user.fullName}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text('Rol: ${user.role}'),
        const SizedBox(height: 28),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'La creación de reportes, cargas de petróleo, fotografías y funcionamiento sin conexión se incorporarán en las siguientes etapas.',
            ),
          ),
        ),
      ],
    ),
  );
}

class _AdminPlaceholder extends StatelessWidget {
  const _AdminPlaceholder();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Las funciones administrativas móviles se habilitarán en una etapa posterior.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_controller.dart';

class NewReportPage extends StatelessWidget {
  const NewReportPage({super.key});

  @override
  Widget build(BuildContext context) => _ChoiceScaffold(
    title: 'Nuevo reporte',
    description: 'Selecciona el tipo de reporte que deseas registrar.',
    choices: [
      _Choice(
        icon: Icons.build_outlined,
        label: 'Mantención',
        onTap: () => context.push('/reports/new'),
      ),
      _Choice(
        icon: Icons.local_gas_station_outlined,
        label: 'Carga de petróleo',
        onTap: () => context.push('/fuel-loads/new'),
      ),
    ],
  );
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) => _ChoiceScaffold(
    title: 'Historial',
    description: 'Consulta los registros enviados y sus evidencias privadas.',
    filters: true,
    choices: [
      _Choice(
        icon: Icons.assignment_outlined,
        label: 'Mantención',
        onTap: () => context.push('/reports'),
      ),
      _Choice(
        icon: Icons.local_gas_station_outlined,
        label: 'Carga de petróleo',
        onTap: () => context.push('/fuel-loads'),
      ),
    ],
  );
}

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final allowed = user?.isAdministrator == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  allowed ? Icons.people_outline : Icons.lock_outline,
                  size: 52,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  allowed
                      ? 'Administración de usuarios'
                      : 'Acceso no autorizado',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  allowed
                      ? 'La administración móvil se habilitará cuando exista un contrato API específico y autorizado.'
                      : 'Esta sección está disponible únicamente para Administrador.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceScaffold extends StatelessWidget {
  const _ChoiceScaffold({
    required this.title,
    required this.description,
    required this.choices,
    this.filters = false,
  });
  final String title;
  final String description;
  final List<_Choice> choices;
  final bool filters;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(description, style: Theme.of(context).textTheme.bodyLarge),
          if (filters) ...[
            const SizedBox(height: 16),
            const _CollapsedFilters(),
          ],
          const SizedBox(height: 24),
          ...choices.expand(
            (choice) => [
              _ChoiceCard(choice: choice),
              const SizedBox(height: 14),
            ],
          ),
        ],
      ),
    ),
  );
}

class _CollapsedFilters extends StatelessWidget {
  const _CollapsedFilters();
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: const ExpansionTile(
      initiallyExpanded: false,
      leading: Icon(Icons.filter_list_outlined),
      title: Text('Filtros'),
      subtitle: Text('Sin filtros aplicados'),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            'Los filtros se mantendrán dentro de esta sección al incorporarse a cada historial o al dashboard.',
          ),
        ),
      ],
    ),
  );
}

class _Choice {
  const _Choice({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.choice});
  final _Choice choice;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: choice.onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Row(
            children: [
              Icon(choice.icon, color: colors.onPrimaryContainer, size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  choice.label,
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
    );
  }
}

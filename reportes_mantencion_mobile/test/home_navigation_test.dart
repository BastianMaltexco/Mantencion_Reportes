import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_mantencion_mobile/features/auth/domain/authenticated_user.dart';
import 'package:reportes_mantencion_mobile/features/home/presentation/home_page.dart';
import 'package:reportes_mantencion_mobile/features/home/presentation/navigation_pages.dart';

void main() {
  testWidgets(
    'Inicio muestra acciones principales y restringe Usuarios por rol',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: HomePage(
              user: const AuthenticatedUser(
                id: 2,
                username: 'tecnico',
                fullName: 'Técnico móvil',
                role: 'Técnico',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Nuevo reporte'), findsOneWidget);
      expect(find.text('Historial'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Usuarios'), findsNothing);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: HomePage(
              user: const AuthenticatedUser(
                id: 1,
                username: 'admin',
                fullName: 'Administrador',
                role: 'Administrador',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Usuarios'), findsOneWidget);
    },
  );

  testWidgets('selección de historial inicia con filtros cerrados', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HistoryPage())),
    );
    expect(find.text('Filtros'), findsOneWidget);
    expect(find.textContaining('Los filtros se mantendrán'), findsNothing);
  });
}

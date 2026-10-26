import 'package:flutter/material.dart';

import 'auth_servicio.dart';
import 'pestana_concursos.dart';
import 'pestana_usuarios.dart';
import 'utiles.dart';

/// Pantalla principal tras iniciar sesión. Las pestañas dependen del rol:
/// todos ven Concursos y Cuenta; el organizador además ve Usuarios.
class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  late Future<Map<String, dynamic>> _futuro;
  int _pestana = 0;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<Map<String, dynamic>> _cargar() async {
    final usuario = db.auth.currentUser;
    if (usuario == null) throw StateError('No hay sesión iniciada');
    // Cada usuario solo puede leer su propio perfil (regla de seguridad en la base).
    return db.from('perfil').select().eq('id', usuario.id).single();
  }

  void _recargar() => setState(() => _futuro = _cargar());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _futuro,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('CaliFy'),
              actions: [
                IconButton(
                  tooltip: 'Cerrar sesión',
                  icon: const Icon(Icons.logout),
                  onPressed: AuthServicio.salir,
                ),
              ],
            ),
            body: ErrorCarga(
              detalle: mensajeDeError(snapshot.error!),
              alReintentar: _recargar,
            ),
          );
        }
        final perfil = snapshot.data!;
        if (perfil['activo'] == false) return _CuentaDesactivada(alSalir: AuthServicio.salir);
        return _Principal(
          perfil: perfil,
          pestana: _pestana,
          alCambiarPestana: (i) => setState(() => _pestana = i),
        );
      },
    );
  }
}

class _Principal extends StatelessWidget {
  const _Principal({
    required this.perfil,
    required this.pestana,
    required this.alCambiarPestana,
  });
  final Map<String, dynamic> perfil;
  final int pestana;
  final ValueChanged<int> alCambiarPestana;

  @override
  Widget build(BuildContext context) {
    final esOrganizador = perfil['rol'] == 'ORGANIZADOR';

    final titulos = <String>['Concursos', if (esOrganizador) 'Usuarios', 'Cuenta'];
    final destinos = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.emoji_events_outlined),
        selectedIcon: Icon(Icons.emoji_events),
        label: 'Concursos',
      ),
      if (esOrganizador)
        const NavigationDestination(
          icon: Icon(Icons.group_outlined),
          selectedIcon: Icon(Icons.group),
          label: 'Usuarios',
        ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Cuenta',
      ),
    ];
    final paginas = <Widget>[
      PestanaConcursos(esOrganizador: esOrganizador, rol: '${perfil['rol']}'),
      if (esOrganizador) const PestanaUsuarios(),
      _PestanaCuenta(perfil: perfil),
    ];
    final actual = pestana < paginas.length ? pestana : 0;

    return Scaffold(
      appBar: AppBar(title: Text(titulos[actual])),
      body: IndexedStack(index: actual, children: paginas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: actual,
        onDestinationSelected: alCambiarPestana,
        destinations: destinos,
      ),
    );
  }
}

class _PestanaCuenta extends StatelessWidget {
  const _PestanaCuenta({required this.perfil});
  final Map<String, dynamic> perfil;

  @override
  Widget build(BuildContext context) {
    final nombre = '${perfil['nombre_completo'] ?? ''}';
    final usuario = '${perfil['usuario'] ?? ''}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(nombre.isEmpty ? '?' : nombre[0].toUpperCase()),
            ),
            title: Text(nombre),
            subtitle: Text('@$usuario'),
            trailing: Chip(label: Text(nombreRol(perfil['rol'] as String?))),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: AuthServicio.salir,
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}

class _CuentaDesactivada extends StatelessWidget {
  const _CuentaDesactivada({required this.alSalir});
  final Future<void> Function() alSalir;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CaliFy')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Tu cuenta está desactivada. Habla con el organizador.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: alSalir, child: const Text('Cerrar sesión')),
            ],
          ),
        ),
      ),
    );
  }
}

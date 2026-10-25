import 'package:flutter/material.dart';

import 'auth_servicio.dart';

/// Lo que se carga al entrar: el perfil de quien inició sesión y los concursos.
class _DatosInicio {
  _DatosInicio(this.perfil, this.concursos);
  final Map<String, dynamic> perfil;
  final List<Map<String, dynamic>> concursos;
}

/// Pantalla de inicio. Por ahora muestra quién eres y los concursos que
/// existen: sirve para comprobar que la app ya lee la base de datos real.
/// Las pantallas de organizador, juez y resultados se agregan sobre esta.
class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  late Future<_DatosInicio> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<_DatosInicio> _cargar() async {
    final usuario = db.auth.currentUser;
    if (usuario == null) throw StateError('No hay sesión iniciada');

    // Cada usuario solo puede leer su propio perfil (regla de seguridad en la base).
    final perfil = await db.from('perfil').select().eq('id', usuario.id).single();

    final concursos = await db
        .from('concurso')
        .select()
        .eq('es_plantilla', false)
        .eq('activo', true)
        .order('creado', ascending: false);

    return _DatosInicio(
      perfil,
      List<Map<String, dynamic>>.from(concursos),
    );
  }

  Future<void> _recargar() async {
    final nuevo = _cargar();
    setState(() => _futuro = nuevo);
    try {
      await nuevo;
    } catch (_) {
      // El error se muestra en pantalla; aquí solo se evita que se propague.
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: FutureBuilder<_DatosInicio>(
        future: _futuro,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorCarga(
              detalle: '${snapshot.error}',
              alReintentar: _recargar,
            );
          }
          final datos = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _TarjetaPerfil(perfil: datos.perfil),
                const SizedBox(height: 24),
                Text(
                  'Concursos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (datos.perfil['activo'] == false)
                  const Text('Tu cuenta está desactivada. Habla con el organizador.')
                else if (datos.concursos.isEmpty)
                  const Text(
                    'Todavía no hay concursos. El organizador los creará pronto.',
                  )
                else
                  for (final concurso in datos.concursos)
                    _TarjetaConcurso(concurso: concurso),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TarjetaPerfil extends StatelessWidget {
  const _TarjetaPerfil({required this.perfil});
  final Map<String, dynamic> perfil;

  static String _nombreRol(String? rol) {
    switch (rol) {
      case 'ORGANIZADOR':
        return 'Organizador';
      case 'JUEZ':
        return 'Juez';
      default:
        return 'General';
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombre = '${perfil['nombre_completo'] ?? ''}';
    final usuario = '${perfil['usuario'] ?? ''}';
    final rol = _nombreRol(perfil['rol'] as String?);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(nombre.isEmpty ? '?' : nombre[0].toUpperCase()),
        ),
        title: Text(nombre),
        subtitle: Text('@$usuario'),
        trailing: Chip(label: Text(rol)),
      ),
    );
  }
}

class _TarjetaConcurso extends StatelessWidget {
  const _TarjetaConcurso({required this.concurso});
  final Map<String, dynamic> concurso;

  static String? _fecha(Object? iso) {
    if (iso == null) return null;
    final partes = '$iso'.split('-');
    if (partes.length != 3) return '$iso';
    return '${partes[2]}/${partes[1]}/${partes[0]}';
  }

  static String _nombreEstado(String? estado) {
    switch (estado) {
      case 'ABIERTO':
        return 'En vivo';
      case 'CERRADO':
        return 'Finalizado';
      default:
        return 'Próximamente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final detalles = <String>[
      if (_fecha(concurso['fecha_concurso']) != null)
        _fecha(concurso['fecha_concurso'])!,
      if ((concurso['sede'] ?? '').toString().isNotEmpty)
        concurso['sede'].toString(),
    ];

    return Card(
      child: ListTile(
        leading: const Icon(Icons.emoji_events_outlined),
        title: Text('${concurso['nombre'] ?? ''}'),
        subtitle: detalles.isEmpty ? null : Text(detalles.join(' · ')),
        trailing: Chip(label: Text(_nombreEstado(concurso['estado'] as String?))),
      ),
    );
  }
}

class _ErrorCarga extends StatelessWidget {
  const _ErrorCarga({required this.detalle, required this.alReintentar});
  final String detalle;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'No se pudieron cargar los datos.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(detalle, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: alReintentar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

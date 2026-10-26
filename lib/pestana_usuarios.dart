import 'package:flutter/material.dart';

import 'auth_servicio.dart';
import 'utiles.dart';

/// Solo para el organizador: ver a todos los usuarios, darles el rol de Juez
/// (o quitárselo) y desactivar cuentas.
class PestanaUsuarios extends StatefulWidget {
  const PestanaUsuarios({super.key});

  @override
  State<PestanaUsuarios> createState() => _PestanaUsuariosState();
}

class _PestanaUsuariosState extends State<PestanaUsuarios> {
  late Future<List<Map<String, dynamic>>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<List<Map<String, dynamic>>> _cargar() async {
    final filas = await db.from('perfil').select().order('creado');
    return List<Map<String, dynamic>>.from(filas);
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

  Future<void> _cambiar(Map<String, dynamic> usuario, Map<String, dynamic> cambios, String exito) async {
    final ok = await intentar(
      context,
      () async {
        await db.from('perfil').update(cambios).eq('id', usuario['id'] as String);
      },
      exito: exito,
    );
    if (ok && mounted) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final miId = db.auth.currentUser?.id;

    return CargaDatos<List<Map<String, dynamic>>>(
      futuro: _futuro,
      alReintentar: _recargar,
      construir: (context, usuarios) {
        return RefreshIndicator(
          onRefresh: _recargar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Todos se registran como General. Aquí puedes darle el rol de Juez a quien va a calificar.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (final u in usuarios) _tarjeta(u, esMio: u['id'] == miId),
            ],
          ),
        );
      },
    );
  }

  Widget _tarjeta(Map<String, dynamic> u, {required bool esMio}) {
    final rol = u['rol'] as String?;
    final activo = u['activo'] != false;
    final nombre = '${u['nombre_completo'] ?? ''}';
    final puedeEditar = rol != 'ORGANIZADOR' && !esMio;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(nombre.isEmpty ? '?' : nombre[0].toUpperCase()),
        ),
        title: Text(nombre),
        subtitle: Text(
          '@${u['usuario']} · ${nombreRol(rol)}${activo ? '' : ' · Desactivado'}',
        ),
        trailing: puedeEditar
            ? PopupMenuButton<String>(
                tooltip: 'Opciones',
                onSelected: (opcion) {
                  switch (opcion) {
                    case 'juez':
                      _cambiar(u, {'rol': 'JUEZ'}, 'Ahora es Juez');
                    case 'general':
                      _cambiar(u, {'rol': 'GENERAL'}, 'Ahora es General');
                    case 'desactivar':
                      _cambiar(u, {'activo': false}, 'Cuenta desactivada');
                    case 'activar':
                      _cambiar(u, {'activo': true}, 'Cuenta activada');
                  }
                },
                itemBuilder: (_) => [
                  if (rol != 'JUEZ')
                    const PopupMenuItem(value: 'juez', child: Text('Hacer Juez')),
                  if (rol != 'GENERAL')
                    const PopupMenuItem(value: 'general', child: Text('Hacer General')),
                  if (activo)
                    const PopupMenuItem(value: 'desactivar', child: Text('Desactivar cuenta'))
                  else
                    const PopupMenuItem(value: 'activar', child: Text('Activar cuenta')),
                ],
              )
            : null,
      ),
    );
  }
}

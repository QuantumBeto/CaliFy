import 'package:flutter/material.dart';

import 'auth_servicio.dart';
import 'formularios.dart';
import 'utiles.dart';

class _DatosBanda {
  _DatosBanda(this.banda, this.integrantes);
  final Map<String, dynamic> banda;
  final List<Map<String, dynamic>> integrantes;
}

/// Una banda: sus datos y sus integrantes. El organizador puede editarlos.
class PantallaBanda extends StatefulWidget {
  const PantallaBanda({
    super.key,
    required this.idBanda,
    required this.nombre,
    required this.esOrganizador,
  });
  final int idBanda;
  final String nombre;
  final bool esOrganizador;

  @override
  State<PantallaBanda> createState() => _PantallaBandaState();
}

class _PantallaBandaState extends State<PantallaBanda> {
  late Future<_DatosBanda> _futuro;
  _DatosBanda? _ultimo;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<_DatosBanda> _cargar() async {
    final banda = await db.from('banda').select().eq('id_banda', widget.idBanda).single();
    final integrantes = await db
        .from('integrante')
        .select()
        .eq('id_banda', widget.idBanda)
        .eq('activo', true)
        .order('id_integrante');
    final datos = _DatosBanda(banda, List<Map<String, dynamic>>.from(integrantes));
    if (mounted) setState(() => _ultimo = datos);
    return datos;
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

  Future<void> _editar(Map<String, dynamic> b) async {
    final datos = await pedirCampos(
      context,
      titulo: 'Editar banda',
      campos: camposBanda,
      inicial: {
        'nombre': '${b['nombre'] ?? ''}',
        'instructor': '${b['instructor'] ?? ''}',
        'procedencia': '${b['procedencia'] ?? ''}',
        'orden_participacion': b['orden_participacion'] == null ? '' : '${b['orden_participacion']}',
      },
    );
    if (datos == null || !mounted) return;
    final ok = await intentar(
      context,
      () async {
        await db.from('banda').update(valoresBanda(datos)).eq('id_banda', widget.idBanda);
      },
      exito: 'Cambios guardados',
    );
    if (ok && mounted) _recargar();
  }

  Future<void> _eliminar(Map<String, dynamic> b) async {
    final seguro = await confirmar(
      context,
      titulo: 'Eliminar banda',
      texto: 'Se borrarán "${b['nombre']}", sus integrantes y sus calificaciones.',
    );
    if (!seguro || !mounted) return;
    final ok = await intentar(
      context,
      () async {
        await db.from('banda').delete().eq('id_banda', widget.idBanda);
      },
      exito: 'Banda eliminada',
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _nuevoIntegrante() async {
    final datos = await pedirCampos(
      context,
      titulo: 'Nuevo integrante',
      campos: camposIntegrante,
      textoBoton: 'Agregar',
    );
    if (datos == null || !mounted) return;
    final ok = await intentar(
      context,
      () async {
        await db.from('integrante').insert({
          'id_banda': widget.idBanda,
          'nombre': datos['nombre'],
          'cargo': nulo(datos['cargo']),
        });
      },
      exito: 'Integrante agregado',
    );
    if (ok && mounted) _recargar();
  }

  Future<void> _quitarIntegrante(Map<String, dynamic> i) async {
    final seguro = await confirmar(
      context,
      titulo: 'Quitar integrante',
      texto: '¿Quitar a ${i['nombre']} de la banda?',
      boton: 'Quitar',
    );
    if (!seguro || !mounted) return;
    final ok = await intentar(
      context,
      () async {
        await db.from('integrante').delete().eq('id_integrante', i['id_integrante'] as int);
      },
    );
    if (ok && mounted) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final bandaActual = _ultimo?.banda;

    return Scaffold(
      appBar: AppBar(
        title: Text('${bandaActual?['nombre'] ?? widget.nombre}'),
        actions: [
          if (widget.esOrganizador && bandaActual != null)
            PopupMenuButton<String>(
              tooltip: 'Opciones',
              onSelected: (opcion) {
                if (opcion == 'editar') _editar(bandaActual);
                if (opcion == 'eliminar') _eliminar(bandaActual);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'editar', child: Text('Editar banda')),
                PopupMenuItem(value: 'eliminar', child: Text('Eliminar banda')),
              ],
            ),
        ],
      ),
      body: CargaDatos<_DatosBanda>(
        futuro: _futuro,
        alReintentar: _recargar,
        construir: (context, datos) {
          final b = datos.banda;
          final instructor = '${b['instructor'] ?? ''}';
          final procedencia = '${b['procedencia'] ?? ''}';

          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.tag),
                        title: Text(b['orden_participacion'] == null
                            ? 'Sin número de participación'
                            : 'Participación No. ${b['orden_participacion']}'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.school_outlined),
                        title: Text(instructor.isEmpty ? 'Sin instructor' : 'Instructor: $instructor'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(procedencia.isEmpty ? 'Sin procedencia' : procedencia),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text('Integrantes', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    if (widget.esOrganizador)
                      FilledButton.tonalIcon(
                        onPressed: _nuevoIntegrante,
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Agregar'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (datos.integrantes.isEmpty)
                  const Text('Aún no hay integrantes registrados.')
                else
                  for (final i in datos.integrantes)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text('${i['nombre']}'),
                        subtitle: (i['cargo'] ?? '').toString().isEmpty ? null : Text('${i['cargo']}'),
                        trailing: widget.esOrganizador
                            ? IconButton(
                                tooltip: 'Quitar',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _quitarIntegrante(i),
                              )
                            : null,
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

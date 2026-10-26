import 'package:flutter/material.dart';

import 'auth_servicio.dart';
import 'formularios.dart';
import 'pantalla_banda.dart';
import 'utiles.dart';

/// Resumen de una hoja de evaluación (un "rubro" como Revista u Orden cerrado).
class _Hoja {
  _Hoja(this.nombre, this.criterios, this.puntosMax, this.peso);
  final String nombre;
  final int criterios;
  final num puntosMax;
  final num peso;
}

class _DatosCategoria {
  _DatosCategoria(this.bandas, this.hojas);
  final List<Map<String, dynamic>> bandas;
  final List<_Hoja> hojas;
}

/// Una categoría: sus hojas de evaluación y sus bandas.
class PantallaCategoria extends StatefulWidget {
  const PantallaCategoria({
    super.key,
    required this.idCategoria,
    required this.nombre,
    required this.esOrganizador,
    required this.rol,
  });
  final int idCategoria;
  final String nombre;
  final bool esOrganizador;
  final String rol;

  @override
  State<PantallaCategoria> createState() => _PantallaCategoriaState();
}

class _PantallaCategoriaState extends State<PantallaCategoria> {
  late Future<_DatosCategoria> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<_DatosCategoria> _cargar() async {
    final bandas = await db
        .from('banda')
        .select()
        .eq('id_categoria', widget.idCategoria)
        .eq('activo', true)
        .order('orden_participacion', ascending: true)
        .order('id_banda');

    // Cada hoja trae sus criterios anidados (rubro(...) es la tabla de renglones).
    final aspectos = await db
        .from('aspecto')
        .select('id_aspecto, nombre, peso, activo, orden, rubro(puntaje_max, activo)')
        .eq('id_categoria', widget.idCategoria)
        .order('orden')
        .order('id_aspecto');

    final hojas = <_Hoja>[];
    for (final a in aspectos) {
      if (a['activo'] == false) continue;
      final renglones = ((a['rubro'] as List?) ?? const [])
          .where((r) => (r as Map)['activo'] != false)
          .toList();
      num maximo = 0;
      for (final r in renglones) {
        maximo += (r as Map)['puntaje_max'] as num;
      }
      hojas.add(_Hoja('${a['nombre']}', renglones.length, maximo, (a['peso'] as num?) ?? 1));
    }
    return _DatosCategoria(List<Map<String, dynamic>>.from(bandas), hojas);
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

  Future<void> _nuevaBanda(int siguiente) async {
    final datos = await pedirCampos(
      context,
      titulo: 'Nueva banda',
      campos: camposBanda,
      inicial: {'orden_participacion': '$siguiente'},
      textoBoton: 'Agregar',
    );
    if (datos == null || !mounted) return;
    final ok = await intentar(
      context,
      () async {
        await db.from('banda').insert({
          'id_categoria': widget.idCategoria,
          ...valoresBanda(datos),
        });
      },
      exito: 'Banda agregada',
    );
    if (ok && mounted) _recargar();
  }

  Future<void> _abrirBanda(Map<String, dynamic> banda) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PantallaBanda(
          idBanda: banda['id_banda'] as int,
          nombre: '${banda['nombre']}',
          esOrganizador: widget.esOrganizador,
        ),
      ),
    );
    if (mounted) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.nombre)),
      body: CargaDatos<_DatosCategoria>(
        futuro: _futuro,
        alReintentar: _recargar,
        construir: (context, datos) {
          num total = 0;
          for (final h in datos.hojas) {
            total += h.puntosMax * h.peso;
          }

          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text('Hojas de evaluación', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (datos.hojas.isEmpty)
                  const Text('Esta categoría todavía no tiene hojas de evaluación.')
                else ...[
                  for (final h in datos.hojas)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.fact_check_outlined),
                        title: Text(h.nombre),
                        subtitle: Text(
                          '${h.criterios} ${h.criterios == 1 ? 'criterio' : 'criterios'}'
                          '${h.peso == 1 ? '' : ' · peso ${formatoPuntos(h.peso)}'}',
                        ),
                        trailing: Text('${formatoPuntos(h.puntosMax)} pts'),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Total posible: ${formatoPuntos(total)} puntos',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text('Bandas', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    if (widget.esOrganizador)
                      FilledButton.tonalIcon(
                        onPressed: () => _nuevaBanda(datos.bandas.length + 1),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (datos.bandas.isEmpty)
                  Text(
                    widget.esOrganizador
                        ? 'Aún no hay bandas. Agrega la primera.'
                        : 'Aún no hay bandas registradas.',
                  )
                else
                  for (final b in datos.bandas) _TarjetaBanda(banda: b, alTocar: () => _abrirBanda(b)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TarjetaBanda extends StatelessWidget {
  const _TarjetaBanda({required this.banda, required this.alTocar});
  final Map<String, dynamic> banda;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final orden = banda['orden_participacion'];
    final procedencia = '${banda['procedencia'] ?? ''}';
    final instructor = '${banda['instructor'] ?? ''}';
    final detalles = <String>[
      if (procedencia.isNotEmpty) procedencia,
      if (instructor.isNotEmpty) 'Instructor: $instructor',
    ];

    return Card(
      child: ListTile(
        onTap: alTocar,
        leading: CircleAvatar(child: Text(orden == null ? '•' : '$orden')),
        title: Text('${banda['nombre']}'),
        subtitle: detalles.isEmpty ? null : Text(detalles.join(' · ')),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

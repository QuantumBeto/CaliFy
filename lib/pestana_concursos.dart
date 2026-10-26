import 'package:flutter/material.dart';

import 'auth_servicio.dart';
import 'formularios.dart';
import 'pantalla_concurso.dart';
import 'utiles.dart';

/// Lista de concursos. Todos la ven; el organizador además puede crear.
class PestanaConcursos extends StatefulWidget {
  const PestanaConcursos({
    super.key,
    required this.esOrganizador,
    required this.rol,
  });
  final bool esOrganizador;
  final String rol;

  @override
  State<PestanaConcursos> createState() => _PestanaConcursosState();
}

class _PestanaConcursosState extends State<PestanaConcursos> {
  late Future<List<Map<String, dynamic>>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<List<Map<String, dynamic>>> _cargar() async {
    final filas = await db
        .from('concurso')
        .select()
        .eq('es_plantilla', false)
        .eq('activo', true)
        .order('creado', ascending: false);
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

  Future<void> _nuevo() async {
    final datos = await pedirCampos(
      context,
      titulo: 'Nuevo concurso',
      campos: camposConcurso,
      textoBoton: 'Crear',
    );
    if (datos == null || !mounted) return;
    final ok = await intentar(context, () async {
      await db.from('concurso').insert(valoresConcurso(datos));
    }, exito: 'Concurso creado');
    if (ok && mounted) _recargar();
  }

  Future<void> _abrir(Map<String, dynamic> concurso) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PantallaConcurso(
          idConcurso: concurso['id_concurso'] as int,
          esOrganizador: widget.esOrganizador,
          rol: widget.rol,
        ),
      ),
    );
    if (mounted) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return CargaDatos<List<Map<String, dynamic>>>(
      futuro: _futuro,
      alReintentar: _recargar,
      construir: (context, concursos) {
        return RefreshIndicator(
          onRefresh: _recargar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.esOrganizador)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _nuevo,
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo concurso'),
                  ),
                ),
              if (widget.esOrganizador) const SizedBox(height: 12),
              if (concursos.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    widget.esOrganizador
                        ? 'Todavía no hay concursos. Crea el primero con el botón de arriba.'
                        : 'Todavía no hay concursos. El organizador los creará pronto.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final concurso in concursos)
                  _TarjetaConcurso(
                    concurso: concurso,
                    alTocar: () => _abrir(concurso),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _TarjetaConcurso extends StatelessWidget {
  const _TarjetaConcurso({required this.concurso, required this.alTocar});
  final Map<String, dynamic> concurso;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final fecha = fechaCorta(concurso['fecha_concurso']);
    final sede = '${concurso['sede'] ?? ''}';
    final detalles = <String>[?fecha, if (sede.isNotEmpty) sede];

    return Card(
      child: ListTile(
        onTap: alTocar,
        leading: _Miniatura(url: concurso['imagen_url'] as String?),
        title: Text('${concurso['nombre'] ?? ''}'),
        subtitle: detalles.isEmpty ? null : Text(detalles.join(' · ')),
        trailing: Chip(
          label: Text(nombreEstado(concurso['estado'] as String?)),
        ),
      ),
    );
  }
}

/// Cuadrito con la imagen del concurso (o un trofeo si no tiene).
class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    const icono = SizedBox(
      width: 48,
      height: 48,
      child: Icon(Icons.emoji_events_outlined),
    );
    if (url == null) return icono;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Image.network(
          url!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => icono,
        ),
      ),
    );
  }
}

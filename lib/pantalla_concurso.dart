import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'auth_servicio.dart';
import 'formularios.dart';
import 'pantalla_categoria.dart';
import 'storage_servicio.dart';
import 'utiles.dart';

class _DatosConcurso {
  _DatosConcurso(this.concurso, this.categorias);
  final Map<String, dynamic> concurso;
  final List<Map<String, dynamic>> categorias;
}

/// Un concurso: su imagen, su estado y sus categorías.
/// El organizador puede editarlo todo; los demás solo lo ven.
class PantallaConcurso extends StatefulWidget {
  const PantallaConcurso({
    super.key,
    required this.idConcurso,
    required this.esOrganizador,
    required this.rol,
  });
  final int idConcurso;
  final bool esOrganizador;
  final String rol;

  @override
  State<PantallaConcurso> createState() => _PantallaConcursoState();
}

class _PantallaConcursoState extends State<PantallaConcurso> {
  late Future<_DatosConcurso> _futuro;
  _DatosConcurso? _ultimo;
  bool _subiendo = false;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<_DatosConcurso> _cargar() async {
    final concurso = await db
        .from('concurso')
        .select()
        .eq('id_concurso', widget.idConcurso)
        .single();
    final categorias = await db
        .from('categoria')
        .select()
        .eq('id_concurso', widget.idConcurso)
        .order('orden')
        .order('id_categoria');
    final datos = _DatosConcurso(concurso, List<Map<String, dynamic>>.from(categorias));
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

  // ----------------------------------------------------------- concurso

  Future<void> _editar(Map<String, dynamic> c) async {
    final datos = await pedirCampos(
      context,
      titulo: 'Editar concurso',
      campos: camposConcurso,
      inicial: {
        'nombre': '${c['nombre'] ?? ''}',
        'descripcion': '${c['descripcion'] ?? ''}',
        'sede': '${c['sede'] ?? ''}',
        'fecha_concurso': '${c['fecha_concurso'] ?? ''}',
      },
    );
    if (datos == null || !mounted) return;
    final ok = await intentar(
      context,
      () async {
        await db
            .from('concurso')
            .update(valoresConcurso(datos))
            .eq('id_concurso', widget.idConcurso);
      },
      exito: 'Cambios guardados',
    );
    if (ok && mounted) _recargar();
  }

  Future<void> _eliminar(Map<String, dynamic> c) async {
    final seguro = await confirmar(
      context,
      titulo: 'Eliminar concurso',
      texto: 'Se borrarán "${c['nombre']}", sus categorías, bandas y calificaciones. '
          'Esto no se puede deshacer.',
    );
    if (!seguro || !mounted) return;
    final ruta = StorageServicio.rutaDesdeUrl(c['imagen_url'] as String?);
    final ok = await intentar(
      context,
      () async {
        await db.from('concurso').delete().eq('id_concurso', widget.idConcurso);
        if (ruta != null) {
          try {
            await StorageServicio.borrarImagen(ruta);
          } catch (_) {
            // Si la imagen no se puede borrar no pasa nada: el concurso ya se eliminó.
          }
        }
      },
      exito: 'Concurso eliminado',
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _cambiarEstado(String estado) async {
    final ok = await intentar(
      context,
      () async {
        await db
            .from('concurso')
            .update({'estado': estado})
            .eq('id_concurso', widget.idConcurso);
      },
      exito: 'Estado: ${nombreEstado(estado)}',
    );
    if (ok && mounted) _recargar();
  }

  // ------------------------------------------------------------- imagen

  Future<void> _cambiarImagen(Map<String, dynamic> c) async {
    final imagen = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (imagen == null || !mounted) return;
    final bytes = await imagen.readAsBytes();
    if (!mounted) return;
    final previa = StorageServicio.rutaDesdeUrl(c['imagen_url'] as String?);

    setState(() => _subiendo = true);
    final ok = await intentar(
      context,
      () async {
        final subida = await StorageServicio.subirImagen(
          idConcurso: widget.idConcurso,
          bytes: bytes,
          nombreArchivo: imagen.name,
        );
        await StorageServicio.guardarUrlEnConcurso(widget.idConcurso, subida.urlPublica);
        if (previa != null) {
          try {
            await StorageServicio.borrarImagen(previa);
          } catch (_) {
            // Si la imagen anterior no se puede borrar, solo queda ocupando espacio.
          }
        }
      },
      exito: 'Imagen actualizada',
    );
    if (!mounted) return;
    setState(() => _subiendo = false);
    if (ok) _recargar();
  }

  Future<void> _quitarImagen(Map<String, dynamic> c) async {
    final seguro = await confirmar(
      context,
      titulo: 'Quitar imagen',
      texto: '¿Quitar la imagen de este concurso?',
      boton: 'Quitar',
    );
    if (!seguro || !mounted) return;
    final ruta = StorageServicio.rutaDesdeUrl(c['imagen_url'] as String?);
    final ok = await intentar(
      context,
      () async {
        await StorageServicio.guardarUrlEnConcurso(widget.idConcurso, null);
        if (ruta != null) {
          try {
            await StorageServicio.borrarImagen(ruta);
          } catch (_) {
            // Si no se puede borrar del bucket, el concurso ya no la muestra.
          }
        }
      },
      exito: 'Imagen quitada',
    );
    if (ok && mounted) _recargar();
  }

  // --------------------------------------------------------- categorías

  Future<void> _nuevaCategoria() async {
    final datos = await pedirCampos(
      context,
      titulo: 'Nueva categoría',
      campos: const [
        CampoForm('nombre', 'Nombre (ej. Secundarias "B")', requerido: true, maxCaracteres: 60),
        CampoForm(
          'plantilla',
          'Usar las hojas de evaluación de Secundarias "A" (se pueden editar después)',
          tipo: TipoCampo.casilla,
        ),
      ],
      textoBoton: 'Crear',
    );
    if (datos == null || !mounted) return;
    final ok = await intentar(
      context,
      () async {
        await db.rpc('crear_categoria', params: {
          'p_id_concurso': widget.idConcurso,
          'p_nombre': datos['nombre'],
          'p_usar_plantilla': datos['plantilla'] == 'true',
        });
      },
      exito: 'Categoría creada',
    );
    if (ok && mounted) _recargar();
  }

  Future<void> _renombrarCategoria(Map<String, dynamic> cat) async {
    final datos = await pedirCampos(
      context,
      titulo: 'Renombrar categoría',
      campos: const [
        CampoForm('nombre', 'Nombre', requerido: true, maxCaracteres: 60),
      ],
      inicial: {'nombre': '${cat['nombre']}'},
    );
    if (datos == null || !mounted) return;
    final ok = await intentar(
      context,
      () async {
        await db
            .from('categoria')
            .update({'nombre': datos['nombre']})
            .eq('id_categoria', cat['id_categoria'] as int);
      },
      exito: 'Categoría renombrada',
    );
    if (ok && mounted) _recargar();
  }

  Future<void> _eliminarCategoria(Map<String, dynamic> cat) async {
    final seguro = await confirmar(
      context,
      titulo: 'Eliminar categoría',
      texto: 'Se borrarán "${cat['nombre']}", sus hojas de evaluación, bandas y calificaciones.',
    );
    if (!seguro || !mounted) return;
    final ok = await intentar(
      context,
      () async {
        await db.from('categoria').delete().eq('id_categoria', cat['id_categoria'] as int);
      },
      exito: 'Categoría eliminada',
    );
    if (ok && mounted) _recargar();
  }

  Future<void> _abrirCategoria(Map<String, dynamic> cat) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PantallaCategoria(
          idCategoria: cat['id_categoria'] as int,
          nombre: '${cat['nombre']}',
          esOrganizador: widget.esOrganizador,
          rol: widget.rol,
        ),
      ),
    );
  }

  // -------------------------------------------------------------- vista

  @override
  Widget build(BuildContext context) {
    final concursoActual = _ultimo?.concurso;

    return Scaffold(
      appBar: AppBar(
        title: Text('${concursoActual?['nombre'] ?? 'Concurso'}'),
        actions: [
          if (widget.esOrganizador && concursoActual != null)
            PopupMenuButton<String>(
              tooltip: 'Opciones',
              onSelected: (opcion) {
                if (opcion == 'editar') _editar(concursoActual);
                if (opcion == 'eliminar') _eliminar(concursoActual);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'editar', child: Text('Editar datos')),
                PopupMenuItem(value: 'eliminar', child: Text('Eliminar concurso')),
              ],
            ),
        ],
      ),
      body: CargaDatos<_DatosConcurso>(
        futuro: _futuro,
        alReintentar: _recargar,
        construir: (context, datos) {
          final c = datos.concurso;
          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _Imagen(url: c['imagen_url'] as String?),
                if (widget.esOrganizador) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _subiendo ? null : () => _cambiarImagen(c),
                        icon: _subiendo
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.image_outlined),
                        label: Text(c['imagen_url'] == null ? 'Agregar imagen' : 'Cambiar imagen'),
                      ),
                      if (c['imagen_url'] != null)
                        OutlinedButton.icon(
                          onPressed: _subiendo ? null : () => _quitarImagen(c),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Quitar'),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _DatosGenerales(concurso: c),
                const SizedBox(height: 12),
                if (widget.esOrganizador) ...[
                  Text('Estado del concurso', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      for (final e in estadosConcurso.entries)
                        ButtonSegment<String>(value: e.key, label: Text(e.value)),
                    ],
                    selected: {'${c['estado']}'},
                    onSelectionChanged: (s) => _cambiarEstado(s.first),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Los jueces solo pueden calificar cuando el concurso está "En vivo".',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(label: Text(nombreEstado(c['estado'] as String?))),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text('Categorías', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    if (widget.esOrganizador)
                      FilledButton.tonalIcon(
                        onPressed: _nuevaCategoria,
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (datos.categorias.isEmpty)
                  Text(
                    widget.esOrganizador
                        ? 'Aún no hay categorías. Agrega la primera (por ejemplo Secundarias "A").'
                        : 'Aún no hay categorías.',
                  )
                else
                  for (final cat in datos.categorias)
                    Card(
                      child: ListTile(
                        onTap: () => _abrirCategoria(cat),
                        leading: const Icon(Icons.groups_outlined),
                        title: Text('${cat['nombre']}'),
                        trailing: widget.esOrganizador
                            ? PopupMenuButton<String>(
                                tooltip: 'Opciones',
                                onSelected: (opcion) {
                                  if (opcion == 'renombrar') _renombrarCategoria(cat);
                                  if (opcion == 'eliminar') _eliminarCategoria(cat);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'renombrar', child: Text('Renombrar')),
                                  PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                                ],
                              )
                            : const Icon(Icons.chevron_right),
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

/// Imagen del concurso (o un espacio con un icono si todavía no tiene).
class _Imagen extends StatelessWidget {
  const _Imagen({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final vacio = Container(
      color: colores.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.emoji_events_outlined, size: 56, color: colores.onSurfaceVariant),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: url == null
            ? vacio
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => vacio,
                loadingBuilder: (context, child, progreso) =>
                    progreso == null ? child : const Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }
}

class _DatosGenerales extends StatelessWidget {
  const _DatosGenerales({required this.concurso});
  final Map<String, dynamic> concurso;

  @override
  Widget build(BuildContext context) {
    final descripcion = '${concurso['descripcion'] ?? ''}';
    final sede = '${concurso['sede'] ?? ''}';
    final fecha = fechaCorta(concurso['fecha_concurso']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (descripcion.isNotEmpty) Text(descripcion),
        if (fecha != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.event_outlined),
            title: Text(fecha),
          ),
        if (sede.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.place_outlined),
            title: Text(sede),
          ),
      ],
    );
  }
}

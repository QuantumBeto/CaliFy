import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_servicio.dart' show AuthFallo;

/// Texto vacío -> null (para guardar "sin dato" en la base de datos).
String? nulo(String? texto) {
  final t = texto?.trim() ?? '';
  return t.isEmpty ? null : t;
}

/// 10 -> "10", 9.5 -> "9.50"
String formatoPuntos(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);

/// Nombre del rol como lo ve la gente.
String nombreRol(String? rol) {
  switch (rol) {
    case 'ORGANIZADOR':
      return 'Organizador';
    case 'JUEZ':
      return 'Juez';
    default:
      return 'General';
  }
}

/// "2026-10-25" -> "25/10/2026"
String? fechaCorta(Object? iso) {
  if (iso == null) return null;
  final partes = '$iso'.split('-');
  if (partes.length != 3) return '$iso';
  return '${partes[2]}/${partes[1]}/${partes[0]}';
}

/// Nombres que ve la gente para el estado de un concurso.
const Map<String, String> estadosConcurso = {
  'BORRADOR': 'Próximamente',
  'ABIERTO': 'En vivo',
  'CERRADO': 'Finalizado',
};

String nombreEstado(String? estado) => estadosConcurso[estado] ?? 'Próximamente';

/// Convierte un error en un mensaje entendible.
String mensajeDeError(Object e) {
  if (e is AuthFallo) return e.mensaje;
  if (e is StorageException) {
    final m = e.message.toLowerCase();
    if (m.contains('row-level security') || m.contains('unauthorized') || e.statusCode == '403') {
      return 'No tienes permiso para subir o borrar imágenes.';
    }
    if (m.contains('bucket not found')) {
      return 'No existe el bucket "concurso-imagenes" en Supabase.';
    }
    if (m.contains('mime') || m.contains('not supported')) {
      return 'Ese tipo de archivo no está permitido. Usa JPG, PNG o WEBP.';
    }
    if (m.contains('size') || m.contains('too large') || e.statusCode == '413') {
      return 'La imagen es demasiado pesada.';
    }
    return 'No se pudo subir la imagen: ${e.message}';
  }
  if (e is PostgrestException) {
    switch (e.code) {
      case '42501':
        return 'No tienes permiso para hacer esto.';
      case '23503':
        return 'No se puede completar porque tiene datos relacionados.';
      case '23505':
        return 'Ya existe un registro igual.';
      default:
        return e.message;
    }
  }
  return 'No se pudo completar. Revisa tu internet e inténtalo de nuevo. ($e)';
}

/// Ejecuta una acción sobre la base de datos y avisa si algo sale mal.
/// Devuelve true si todo salió bien.
Future<bool> intentar(
  BuildContext context,
  Future<void> Function() accion, {
  String? exito,
}) async {
  final mensajes = ScaffoldMessenger.of(context);
  try {
    await accion();
    if (exito != null) {
      mensajes.showSnackBar(SnackBar(content: Text(exito)));
    }
    return true;
  } catch (e) {
    mensajes.showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    return false;
  }
}

/// Pregunta "¿Seguro?" antes de borrar algo.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String texto,
  String boton = 'Eliminar',
}) async {
  final respuesta = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(boton),
        ),
      ],
    ),
  );
  return respuesta ?? false;
}

/// Pantalla de error con botón para reintentar.
class ErrorCarga extends StatelessWidget {
  const ErrorCarga({super.key, required this.detalle, required this.alReintentar});
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

/// Muestra "cargando", el error o los datos, según lo que pase con el futuro.
class CargaDatos<T> extends StatelessWidget {
  const CargaDatos({
    super.key,
    required this.futuro,
    required this.construir,
    required this.alReintentar,
  });
  final Future<T> futuro;
  final Widget Function(BuildContext context, T datos) construir;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: futuro,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorCarga(
            detalle: mensajeDeError(snapshot.error!),
            alReintentar: alReintentar,
          );
        }
        return construir(context, snapshot.data as T);
      },
    );
  }
}

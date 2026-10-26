import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_servicio.dart' show AuthFallo, db;

/// Resultado al subir una imagen.
class SubidaImagen {
  const SubidaImagen({required this.urlPublica, required this.ruta});
  final String urlPublica; // lista para guardar en concurso.imagen_url
  final String ruta; // ruta dentro del bucket (sirve para borrarla después)
}

/// Sube y borra imágenes del bucket "concurso-imagenes" (Supabase Storage).
/// Solo el organizador tiene permiso (políticas de Storage en la base de datos).
class StorageServicio {
  static const String _bucket = 'concurso-imagenes';

  /// Tamaño máximo de una imagen (el bucket también lo limita en Supabase).
  static const int maxBytes = 5 * 1024 * 1024;

  static const Map<String, String> _tipos = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  static String? _extension(String nombreArchivo) {
    final i = nombreArchivo.lastIndexOf('.');
    if (i < 0) return null;
    final ext = nombreArchivo.substring(i + 1).toLowerCase();
    return _tipos.containsKey(ext) ? ext : null;
  }

  /// Sube [bytes] como imagen del concurso [idConcurso].
  ///
  /// [nombreArchivo] es el nombre que trae la imagen (ej. "foto.jpg"); de ahí se
  /// toma la extensión. Cada subida usa un nombre nuevo para que nadie vea la
  /// imagen vieja guardada en caché.
  static Future<SubidaImagen> subirImagen({
    required int idConcurso,
    required Uint8List bytes,
    required String nombreArchivo,
  }) async {
    final ext = _extension(nombreArchivo);
    if (ext == null) {
      throw AuthFallo('Elige una imagen JPG, PNG o WEBP.');
    }
    if (bytes.length > maxBytes) {
      throw AuthFallo('La imagen pesa más de 5 MB. Elige una más ligera.');
    }

    final ruta = 'concurso-$idConcurso/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await db.storage.from(_bucket).uploadBinary(
          ruta,
          bytes,
          fileOptions: FileOptions(contentType: _tipos[ext]),
        );
    final url = db.storage.from(_bucket).getPublicUrl(ruta);
    return SubidaImagen(urlPublica: url, ruta: ruta);
  }

  /// Saca la ruta del bucket a partir de la URL pública guardada en el concurso.
  static String? rutaDesdeUrl(String? url) {
    if (url == null) return null;
    const marca = '/$_bucket/';
    final i = url.indexOf(marca);
    if (i < 0) return null;
    final ruta = url.substring(i + marca.length).split('?').first;
    return ruta.isEmpty ? null : Uri.decodeComponent(ruta);
  }

  /// Borra una imagen del bucket.
  static Future<void> borrarImagen(String ruta) async {
    await db.storage.from(_bucket).remove([ruta]);
  }

  /// Guarda (o quita, con null) la URL de la imagen en la tabla concurso.
  static Future<void> guardarUrlEnConcurso(int idConcurso, String? url) async {
    await db.from('concurso').update({'imagen_url': url}).eq('id_concurso', idConcurso);
  }
}

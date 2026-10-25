import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

/// Acceso rápido al cliente de Supabase (ya inicializado en main.dart).
SupabaseClient get db => Supabase.instance.client;

/// Error con un mensaje listo para mostrarle al usuario.
class AuthFallo implements Exception {
  AuthFallo(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Registro, inicio y cierre de sesión.
class AuthServicio {
  // Letras minúsculas sin acentos y números; punto, guion y guion bajo solo
  // entre caracteres (no al inicio, al final ni repetidos).
  static final RegExp _formatoUsuario = RegExp(r'^[a-z0-9]+([._-][a-z0-9]+)*$');

  /// Valida el nombre de usuario al registrarse. Devuelve null si está bien.
  static String? validarUsuario(String? texto) {
    final u = (texto ?? '').trim().toLowerCase();
    if (u.isEmpty) return 'Escribe un usuario';
    if (u.length < 3 || u.length > 20) return 'Debe tener de 3 a 20 caracteres';
    if (!_formatoUsuario.hasMatch(u)) {
      return 'Solo letras sin acentos, números, punto, guion y guion bajo';
    }
    return null;
  }

  /// Valida la contraseña al registrarse. Devuelve null si está bien.
  static String? validarContrasena(String? texto) {
    final c = texto ?? '';
    if (c.isEmpty) return 'Escribe una contraseña';
    if (c.length < 6) return 'Mínimo 6 caracteres';
    return null;
  }

  /// "Juan" -> juan@gmail.com. Si ya trae @ (por ejemplo la cuenta del
  /// organizador, que se creó con un correo real) se respeta tal cual.
  static String usuarioACorreo(String entrada) {
    final t = entrada.trim().toLowerCase();
    return t.contains('@') ? t : '$t@${Config.dominioInterno}';
  }

  static Future<void> entrar(String usuarioOCorreo, String contrasena) async {
    try {
      await db.auth.signInWithPassword(
        email: usuarioACorreo(usuarioOCorreo),
        password: contrasena,
      );
    } on AuthException catch (e) {
      throw AuthFallo(_traducir(e.message));
    } catch (_) {
      throw AuthFallo(_sinConexion);
    }
  }

  /// Crea la cuenta. Todas nacen como GENERAL (la base de datos lo impone);
  /// solo el organizador puede subir a alguien a Juez.
  static Future<void> registrar({
    required String usuario,
    required String nombre,
    required String contrasena,
  }) async {
    try {
      final respuesta = await db.auth.signUp(
        email: usuarioACorreo(usuario),
        password: contrasena,
        data: {'nombre_completo': nombre.trim()},
      );
      if (respuesta.session == null) {
        throw AuthFallo(
          'La cuenta se creó, pero Supabase está pidiendo confirmar el correo. '
          'Desactiva "Confirm email" en Authentication → Sign In / Providers → Email.',
        );
      }
    } on AuthFallo {
      rethrow;
    } on AuthException catch (e) {
      throw AuthFallo(_traducir(e.message));
    } catch (_) {
      throw AuthFallo(_sinConexion);
    }
  }

  static Future<void> salir() => db.auth.signOut();

  static const String _sinConexion =
      'No se pudo conectar. Revisa tu internet e inténtalo de nuevo.';

  static String _traducir(String mensaje) {
    final t = mensaje.toLowerCase();
    if (t.contains('invalid login credentials')) {
      return 'Usuario o contraseña incorrectos.';
    }
    if (t.contains('already registered') || t.contains('already exists')) {
      return 'Ese usuario ya existe. Elige otro.';
    }
    if (t.contains('email not confirmed')) {
      return 'Esta cuenta necesita confirmar su correo. Pide al organizador que revise la configuración.';
    }
    if (t.contains('password') &&
        (t.contains('at least') || t.contains('weak') || t.contains('short'))) {
      return 'La contraseña es muy corta o débil (mínimo 6 caracteres).';
    }
    if (t.contains('rate limit') || t.contains('too many')) {
      return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
    }
    if (t.contains('signups not allowed') || t.contains('signup is disabled')) {
      return 'El registro de nuevas cuentas está desactivado en Supabase.';
    }
    if (t.contains('email') && t.contains('invalid')) {
      return 'Supabase rechazó el correo interno de este usuario. '
          'Prueba con otro usuario o cambia "dominioInterno" en config.dart.';
    }
    return 'No se pudo completar la operación: $mensaje';
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso rápido al cliente de Supabase (ya inicializado en main.dart).
SupabaseClient get db => Supabase.instance.client;

/// Error con un mensaje listo para mostrarle al usuario.
class AuthFallo implements Exception {
  AuthFallo(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Registro, inicio de sesión, recuperación de contraseña y cierre de sesión.
///
/// Cada persona tiene un USUARIO (para entrar y para que el organizador la
/// identifique) y un CORREO (para recuperar su contraseña). Funcionan por
/// separado: se puede entrar con cualquiera de los dos.
class AuthServicio {
  // Letras minúsculas sin acentos y números; punto, guion y guion bajo solo
  // entre caracteres (no al inicio, al final ni repetidos).
  static final RegExp _formatoUsuario = RegExp(r'^[a-z0-9]+([._-][a-z0-9]+)*$');
  static final RegExp _formatoCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Valida el usuario que se elige al registrarse. Devuelve null si está bien.
  static String? validarUsuario(String? texto) {
    final u = (texto ?? '').trim().toLowerCase();
    if (u.isEmpty) return 'Escribe un usuario';
    if (u.length < 3 || u.length > 20) return 'Debe tener de 3 a 20 caracteres';
    if (!_formatoUsuario.hasMatch(u)) {
      return 'Solo letras sin acentos, números, punto, guion y guion bajo';
    }
    return null;
  }

  /// Valida un correo. Devuelve null si está bien.
  static String? validarCorreo(String? texto) {
    final c = (texto ?? '').trim();
    if (c.isEmpty) return 'Escribe tu correo';
    if (!_formatoCorreo.hasMatch(c)) return 'Ese correo no es válido';
    return null;
  }

  /// Valida la contraseña al registrarse o cambiarla. Devuelve null si está bien.
  static String? validarContrasena(String? texto) {
    final c = texto ?? '';
    if (c.isEmpty) return 'Escribe una contraseña';
    if (c.length < 6) return 'Mínimo 6 caracteres';
    return null;
  }

  /// Valida lo que se escribe al ENTRAR (usuario o correo).
  static String? validarUsuarioOCorreoEntrada(String? texto) {
    final u = (texto ?? '').trim();
    if (u.isEmpty) return 'Escribe tu usuario o tu correo';
    if (u.contains(' ')) return 'No lleva espacios';
    return null;
  }

  /// Valida el código de 6 dígitos que llega por correo.
  static String? validarCodigo(String? texto) {
    final c = (texto ?? '').trim();
    if (c.isEmpty) return 'Escribe el código';
    if (!RegExp(r'^\d{6,10}$').hasMatch(c)) return 'Son 6 números';
    return null;
  }

  /// Entra con usuario o con correo.
  static Future<void> entrar(String usuarioOCorreo, String contrasena) async {
    try {
      final texto = usuarioOCorreo.trim();
      final correo = texto.contains('@')
          ? texto.toLowerCase()
          : await _correoDeUsuario(texto, contrasena);
      await db.auth.signInWithPassword(email: correo, password: contrasena);
    } on AuthFallo {
      rethrow;
    } on AuthException catch (e) {
      throw AuthFallo(_traducir(e.message));
    } catch (_) {
      throw AuthFallo(_sinConexion);
    }
  }

  /// Supabase entra con correo, así que se le pregunta a la base de datos cuál
  /// es el correo de ese usuario. La base solo lo entrega si la contraseña es
  /// correcta (así nadie puede juntar correos ajenos) y bloquea 15 minutos
  /// después de 5 intentos fallidos.
  static Future<String> _correoDeUsuario(String usuario, String contrasena) async {
    try {
      final respuesta = await db.rpc('correo_para_entrar', params: {
        'p_usuario': usuario.toLowerCase(),
        'p_contrasena': contrasena,
      });
      if (respuesta is String && respuesta.isNotEmpty) return respuesta;
    } on PostgrestException catch (e) {
      if (e.message.contains('DEMASIADOS_INTENTOS')) {
        throw AuthFallo(
          'Demasiados intentos fallidos con este usuario. '
          'Espera 15 minutos, o entra con tu correo.',
        );
      }
      throw AuthFallo('No se pudo comprobar el usuario: ${e.message}');
    }
    throw AuthFallo('Usuario o contraseña incorrectos.');
  }

  /// Crea la cuenta. Todas nacen como GENERAL (la base de datos lo impone);
  /// solo el organizador puede subir a alguien a Juez.
  static Future<void> registrar({
    required String usuario,
    required String correo,
    required String nombre,
    required String contrasena,
  }) async {
    try {
      final u = usuario.trim().toLowerCase();
      final libre = await db.rpc('usuario_disponible', params: {'p_usuario': u});
      if (libre != true) {
        throw AuthFallo('Ese usuario ya está ocupado. Elige otro.');
      }
      final respuesta = await db.auth.signUp(
        email: correo.trim().toLowerCase(),
        password: contrasena,
        data: {'usuario': u, 'nombre_completo': nombre.trim()},
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
    } on PostgrestException catch (e) {
      throw AuthFallo('No se pudo comprobar el usuario: ${e.message}');
    } catch (_) {
      throw AuthFallo(_sinConexion);
    }
  }

  /// Paso 1 de "Olvidé mi contraseña": envía un código de 6 dígitos al correo.
  static Future<void> pedirCodigoRecuperacion(String correo) async {
    try {
      await db.auth.resetPasswordForEmail(correo.trim().toLowerCase());
    } on AuthException catch (e) {
      throw AuthFallo(_traducir(e.message));
    } catch (_) {
      throw AuthFallo(_sinConexion);
    }
  }

  /// Paso 2: comprueba el código. Si es correcto, la sesión queda iniciada.
  static Future<void> verificarCodigoRecuperacion(String correo, String codigo) async {
    try {
      await db.auth.verifyOTP(
        email: correo.trim().toLowerCase(),
        token: codigo.trim(),
        type: OtpType.recovery,
      );
    } on AuthException catch (e) {
      throw AuthFallo(_traducir(e.message));
    } catch (_) {
      throw AuthFallo(_sinConexion);
    }
  }

  /// Paso 3: guarda la contraseña nueva (ya con el código verificado).
  static Future<void> cambiarContrasena(String nueva) async {
    try {
      await db.auth.updateUser(UserAttributes(password: nueva));
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
      return 'Ese correo ya tiene una cuenta. Si es tuyo, entra con tu usuario '
          'o usa "¿Olvidaste tu contraseña?".';
    }
    if (t.contains('database error saving new user')) {
      return 'No se pudo crear la cuenta. Puede que el usuario o el correo ya '
          'estén en uso; prueba con otros.';
    }
    if (t.contains('email not confirmed')) {
      return 'Esta cuenta necesita confirmar su correo. Avisa al organizador.';
    }
    if (t.contains('token') && (t.contains('expired') || t.contains('invalid'))) {
      return 'El código es incorrecto o ya venció. Pide uno nuevo.';
    }
    if (t.contains('different from the old')) {
      return 'La contraseña nueva debe ser distinta a la anterior.';
    }
    if (t.contains('security purposes') ||
        (t.contains('after') && t.contains('seconds'))) {
      return 'Espera un minuto antes de pedir otro código.';
    }
    if (t.contains('sending') && t.contains('email')) {
      return 'No se pudo enviar el correo. Avisa al organizador.';
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
      return 'Supabase rechazó ese correo. Revisa que esté bien escrito.';
    }
    return 'No se pudo completar la operación: $mensaje';
  }
}

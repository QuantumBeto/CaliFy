import 'package:flutter_test/flutter_test.dart';

import 'package:calify/auth_servicio.dart';

void main() {
  group('validar usuario (al registrarse)', () {
    test('acepta nombres válidos', () {
      for (final u in ['juan', 'Juan', 'maria.lopez', 'banda_01', 'a-b-c', 'abc']) {
        expect(AuthServicio.validarUsuario(u), isNull, reason: u);
      }
    });

    test('rechaza nombres inválidos', () {
      final malos = [
        '',
        'ab',
        'a' * 21,
        'juan perez',
        'ñandú',
        '.juan',
        'juan.',
        'ju..an',
        'juan@correo.com',
      ];
      for (final u in malos) {
        expect(AuthServicio.validarUsuario(u), isNotNull, reason: u);
      }
    });
  });

  group('validar correo', () {
    test('acepta correos válidos', () {
      for (final c in ['a@b.com', 'maria.lopez@gmail.com', ' juan@correo.mx ']) {
        expect(AuthServicio.validarCorreo(c), isNull, reason: c);
      }
    });

    test('rechaza correos inválidos', () {
      for (final c in ['', 'juan', 'juan@', '@correo.com', 'juan@correo', 'ju an@correo.com']) {
        expect(AuthServicio.validarCorreo(c), isNotNull, reason: c);
      }
    });
  });

  group('al entrar', () {
    test('acepta usuario o correo y rechaza vacío o espacios', () {
      expect(AuthServicio.validarUsuarioOCorreoEntrada('beto'), isNull);
      expect(AuthServicio.validarUsuarioOCorreoEntrada('beto@correo.com'), isNull);
      expect(AuthServicio.validarUsuarioOCorreoEntrada(''), isNotNull);
      expect(AuthServicio.validarUsuarioOCorreoEntrada('beto lopez'), isNotNull);
    });
  });

  group('contraseña y código', () {
    test('contraseña de mínimo 6 caracteres', () {
      expect(AuthServicio.validarContrasena('12345'), isNotNull);
      expect(AuthServicio.validarContrasena('123456'), isNull);
      expect(AuthServicio.validarContrasena(''), isNotNull);
    });

    test('código de 6 a 10 números', () {
      expect(AuthServicio.validarCodigo('123456'), isNull);
      expect(AuthServicio.validarCodigo('12345'), isNotNull);
      expect(AuthServicio.validarCodigo('12a456'), isNotNull);
      expect(AuthServicio.validarCodigo(''), isNotNull);
    });
  });
}

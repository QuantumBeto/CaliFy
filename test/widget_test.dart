import 'package:flutter_test/flutter_test.dart';

import 'package:calify/auth_servicio.dart';
import 'package:calify/config.dart';

void main() {
  group('usuario -> correo interno', () {
    test('agrega el dominio interno y pasa a minúsculas', () {
      expect(AuthServicio.usuarioACorreo('Juan'), 'juan@${Config.dominioInterno}');
      expect(AuthServicio.usuarioACorreo('  maria.lopez '),
          'maria.lopez@${Config.dominioInterno}');
    });

    test('si ya trae @ se respeta', () {
      expect(AuthServicio.usuarioACorreo('Beto@Hotmail.com'), 'beto@hotmail.com');
    });
  });

  group('validar usuario', () {
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

  group('validar contraseña', () {
    test('mínimo 6 caracteres', () {
      expect(AuthServicio.validarContrasena('12345'), isNotNull);
      expect(AuthServicio.validarContrasena('123456'), isNull);
      expect(AuthServicio.validarContrasena(''), isNotNull);
    });
  });
}

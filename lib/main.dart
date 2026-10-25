import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_servicio.dart';
import 'config.dart';
import 'pantalla_acceso.dart';
import 'pantalla_inicio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Config.configurado) {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabaseAnonKey,
    );
  }
  runApp(const CalifyApp());
}

class CalifyApp extends StatelessWidget {
  const CalifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CaliFy',
      debugShowCheckedModeBanner: false,
      theme: _tema(Brightness.light),
      darkTheme: _tema(Brightness.dark),
      themeMode: ThemeMode.system,
      home: Config.configurado
          ? const PuertaDeSesion()
          : const PantallaFaltaConfig(),
    );
  }
}

ThemeData _tema(Brightness brillo) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1F3F7A),
      brightness: brillo,
    ),
  );
}

/// Decide qué pantalla mostrar: si hay sesión iniciada va al inicio; si no, al
/// acceso. Escucha los cambios, así que al entrar o salir cambia sola. Supabase
/// guarda la sesión en el teléfono: no hay que volver a entrar cada vez.
class PuertaDeSesion extends StatelessWidget {
  const PuertaDeSesion({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final sesion = snapshot.data?.session ?? db.auth.currentSession;
        return sesion == null ? const PantallaAcceso() : const PantallaInicio();
      },
    );
  }
}

/// Se muestra mientras no se hayan pegado los datos de Supabase en config.dart.
class PantallaFaltaConfig extends StatelessWidget {
  const PantallaFaltaConfig({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CaliFy')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Falta conectar con Supabase.\n\n'
            'Abre el archivo lib/config.dart y pega ahí tu Project URL y tu '
            'clave pública (publishable/anon). Luego vuelve a ejecutar la app.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'auth_servicio.dart';

/// Entrar o crear cuenta. Al lograrlo, PuertaDeSesion cambia sola al inicio.
class PantallaAcceso extends StatefulWidget {
  const PantallaAcceso({super.key});

  @override
  State<PantallaAcceso> createState() => _PantallaAccesoState();
}

class _PantallaAccesoState extends State<PantallaAcceso> {
  final _formulario = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _nombre = TextEditingController();
  final _contrasena = TextEditingController();
  final _confirmar = TextEditingController();

  bool _registro = false;
  bool _cargando = false;
  bool _verContrasena = false;
  String? _error;

  @override
  void dispose() {
    _usuario.dispose();
    _nombre.dispose();
    _contrasena.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!(_formulario.currentState?.validate() ?? false)) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      if (_registro) {
        await AuthServicio.registrar(
          usuario: _usuario.text,
          nombre: _nombre.text,
          contrasena: _contrasena.text,
        );
      } else {
        await AuthServicio.entrar(_usuario.text, _contrasena.text);
      }
      // Si todo salió bien, PuertaDeSesion cambia sola a la pantalla de inicio.
    } on AuthFallo catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _cambiarModo(bool registro) {
    setState(() {
      _registro = registro;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formulario,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.emoji_events_outlined,
                        size: 64, color: colores.primary),
                    const SizedBox(height: 8),
                    Text(
                      'CaliFy',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Calificación de bandas de guerra en tiempo real',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(value: false, label: Text('Entrar')),
                        ButtonSegment<bool>(
                            value: true, label: Text('Crear cuenta')),
                      ],
                      selected: {_registro},
                      onSelectionChanged: _cargando
                          ? null
                          : (seleccion) => _cambiarModo(seleccion.first),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _usuario,
                      enabled: !_cargando,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: _registro ? 'Usuario' : 'Usuario o correo',
                        helperText: _registro
                            ? 'Letras, números, punto, guion o guion bajo'
                            : null,
                        prefixIcon: const Icon(Icons.person_outline),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (valor) => _registro
                          ? AuthServicio.validarUsuario(valor)
                          : ((valor ?? '').trim().isEmpty
                              ? 'Escribe tu usuario'
                              : null),
                    ),
                    if (_registro) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nombre,
                        enabled: !_cargando,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nombre completo',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (valor) {
                          final t = (valor ?? '').trim();
                          if (t.isEmpty) return 'Escribe tu nombre';
                          if (t.length > 60) return 'Máximo 60 caracteres';
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _contrasena,
                      enabled: !_cargando,
                      obscureText: !_verContrasena,
                      textInputAction: _registro
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_registro) _enviar();
                      },
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _verContrasena ? 'Ocultar' : 'Mostrar',
                          icon: Icon(_verContrasena
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () =>
                              setState(() => _verContrasena = !_verContrasena),
                        ),
                      ),
                      validator: (valor) => _registro
                          ? AuthServicio.validarContrasena(valor)
                          : ((valor ?? '').isEmpty
                              ? 'Escribe tu contraseña'
                              : null),
                    ),
                    if (_registro) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmar,
                        enabled: !_cargando,
                        obscureText: !_verContrasena,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _enviar(),
                        decoration: const InputDecoration(
                          labelText: 'Repite la contraseña',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (valor) => valor == _contrasena.text
                            ? null
                            : 'Las contraseñas no coinciden',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tu cuenta será de tipo General: puedes ver los resultados '
                        'de los concursos. El organizador puede darte el rol de Juez.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colores.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: colores.onErrorContainer),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _cargando ? null : _enviar,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _cargando
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_registro ? 'Crear cuenta' : 'Entrar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_servicio.dart';

/// "¿Olvidaste tu contraseña?": 1) se escribe el correo y llega un código de
/// 6 dígitos; 2) se escribe el código y la contraseña nueva.
class PantallaRecuperar extends StatefulWidget {
  const PantallaRecuperar({super.key});

  @override
  State<PantallaRecuperar> createState() => _PantallaRecuperarState();
}

class _PantallaRecuperarState extends State<PantallaRecuperar> {
  final _formulario = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _codigo = TextEditingController();
  final _nueva = TextEditingController();
  final _repite = TextEditingController();

  bool _codigoEnviado = false;
  bool _verificado = false; // el código ya se comprobó; solo falta guardar la contraseña
  bool _cargando = false;
  bool _verContrasena = false;
  String? _error;
  String? _aviso;

  @override
  void dispose() {
    _correo.dispose();
    _codigo.dispose();
    _nueva.dispose();
    _repite.dispose();
    super.dispose();
  }

  Future<void> _enviarCodigo() async {
    if (!(_formulario.currentState?.validate() ?? false)) return;
    setState(() {
      _cargando = true;
      _error = null;
      _aviso = null;
    });
    try {
      await AuthServicio.pedirCodigoRecuperacion(_correo.text);
      if (!mounted) return;
      setState(() {
        _codigoEnviado = true;
        _aviso = 'Si ese correo tiene una cuenta, te enviamos un código de '
            '6 números. Revisa también la carpeta de spam.';
      });
    } on AuthFallo catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambiar() async {
    if (!(_formulario.currentState?.validate() ?? false)) return;
    final mensajes = ScaffoldMessenger.of(context);
    final navegador = Navigator.of(context);
    setState(() {
      _cargando = true;
      _error = null;
      _aviso = null;
    });
    try {
      if (!_verificado) {
        await AuthServicio.verificarCodigoRecuperacion(_correo.text, _codigo.text);
        _verificado = true;
      }
      await AuthServicio.cambiarContrasena(_nueva.text);
      mensajes.showSnackBar(
        const SnackBar(content: Text('Contraseña cambiada. Ya entraste a tu cuenta.')),
      );
      navegador.pop();
    } on AuthFallo catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _cambiarCorreo() {
    setState(() {
      _codigoEnviado = false;
      _verificado = false;
      _codigo.clear();
      _error = null;
      _aviso = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
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
                    Text(
                      _codigoEnviado
                          ? 'Escribe el código que te llegó y elige tu contraseña nueva.'
                          : 'Escribe el correo con el que creaste tu cuenta. '
                              'Te enviaremos un código para cambiar tu contraseña.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    if (!_codigoEnviado)
                      TextFormField(
                        controller: _correo,
                        enabled: !_cargando,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _enviarCodigo(),
                        decoration: const InputDecoration(
                          labelText: 'Correo',
                          prefixIcon: Icon(Icons.mail_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: AuthServicio.validarCorreo,
                      )
                    else ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.mail_outline),
                        title: Text(_correo.text.trim()),
                        trailing: TextButton(
                          onPressed: _cargando ? null : _cambiarCorreo,
                          child: const Text('Cambiar'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _codigo,
                        enabled: !_cargando && !_verificado,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        maxLength: 10,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Código de 6 números',
                          prefixIcon: Icon(Icons.pin_outlined),
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        validator: (valor) =>
                            _verificado ? null : AuthServicio.validarCodigo(valor),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nueva,
                        enabled: !_cargando,
                        obscureText: !_verContrasena,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Contraseña nueva',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _verContrasena ? 'Ocultar' : 'Mostrar',
                            icon: Icon(_verContrasena
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () => setState(
                                () => _verContrasena = !_verContrasena),
                          ),
                        ),
                        validator: AuthServicio.validarContrasena,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _repite,
                        enabled: !_cargando,
                        obscureText: !_verContrasena,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _cambiar(),
                        decoration: const InputDecoration(
                          labelText: 'Repite la contraseña nueva',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (valor) => valor == _nueva.text
                            ? null
                            : 'Las contraseñas no coinciden',
                      ),
                    ],
                    if (_aviso != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colores.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _aviso!,
                          style: TextStyle(color: colores.onSecondaryContainer),
                        ),
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
                      onPressed: _cargando
                          ? null
                          : (_codigoEnviado ? _cambiar : _enviarCodigo),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _cargando
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_codigoEnviado
                                ? 'Cambiar contraseña'
                                : 'Enviar código'),
                      ),
                    ),
                    if (_codigoEnviado && !_verificado)
                      TextButton(
                        onPressed: _cargando ? null : _enviarCodigo,
                        child: const Text('Volver a enviar el código'),
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

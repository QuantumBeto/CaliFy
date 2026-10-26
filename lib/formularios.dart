import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'utiles.dart';

/// Tipos de campo que puede tener un formulario.
enum TipoCampo { texto, multilinea, numero, fecha, casilla }

/// Un campo de un formulario (clave = nombre de la columna en la base de datos).
class CampoForm {
  const CampoForm(
    this.clave,
    this.etiqueta, {
    this.tipo = TipoCampo.texto,
    this.requerido = false,
    this.maxCaracteres,
  });
  final String clave;
  final String etiqueta;
  final TipoCampo tipo;
  final bool requerido;
  final int? maxCaracteres;
}

/// Abre un formulario y devuelve lo que se escribió (o null si se canceló).
/// Los valores vuelven como texto; las casillas como 'true' o 'false'.
Future<Map<String, String>?> pedirCampos(
  BuildContext context, {
  required String titulo,
  required List<CampoForm> campos,
  Map<String, String> inicial = const {},
  String textoBoton = 'Guardar',
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _DialogoCampos(
      titulo: titulo,
      campos: campos,
      inicial: inicial,
      textoBoton: textoBoton,
    ),
  );
}

class _DialogoCampos extends StatefulWidget {
  const _DialogoCampos({
    required this.titulo,
    required this.campos,
    required this.inicial,
    required this.textoBoton,
  });
  final String titulo;
  final List<CampoForm> campos;
  final Map<String, String> inicial;
  final String textoBoton;

  @override
  State<_DialogoCampos> createState() => _DialogoCamposState();
}

class _DialogoCamposState extends State<_DialogoCampos> {
  final _formulario = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controladores = {};
  final Map<String, bool> _casillas = {};

  @override
  void initState() {
    super.initState();
    for (final campo in widget.campos) {
      if (campo.tipo == TipoCampo.casilla) {
        _casillas[campo.clave] = (widget.inicial[campo.clave] ?? 'true') == 'true';
      } else {
        _controladores[campo.clave] =
            TextEditingController(text: widget.inicial[campo.clave] ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controladores.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _elegirFecha(CampoForm campo) async {
    final controlador = _controladores[campo.clave]!;
    final actual = DateTime.tryParse(controlador.text);
    final fecha = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (fecha == null) return;
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');
    controlador.text = '${fecha.year.toString().padLeft(4, '0')}-$mes-$dia';
  }

  void _guardar() {
    if (!(_formulario.currentState?.validate() ?? false)) return;
    final resultado = <String, String>{};
    for (final campo in widget.campos) {
      if (campo.tipo == TipoCampo.casilla) {
        resultado[campo.clave] = (_casillas[campo.clave] ?? false) ? 'true' : 'false';
      } else {
        resultado[campo.clave] = _controladores[campo.clave]!.text.trim();
      }
    }
    Navigator.pop(context, resultado);
  }

  Widget _construirCampo(CampoForm campo) {
    switch (campo.tipo) {
      case TipoCampo.casilla:
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(campo.etiqueta),
          value: _casillas[campo.clave] ?? false,
          onChanged: (v) => setState(() => _casillas[campo.clave] = v ?? false),
        );
      case TipoCampo.fecha:
        final controlador = _controladores[campo.clave]!;
        return TextFormField(
          controller: controlador,
          readOnly: true,
          onTap: () => _elegirFecha(campo),
          decoration: InputDecoration(
            labelText: campo.etiqueta,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Quitar fecha',
              icon: const Icon(Icons.clear),
              onPressed: () => controlador.clear(),
            ),
          ),
        );
      case TipoCampo.numero:
        return TextFormField(
          controller: _controladores[campo.clave],
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: campo.etiqueta,
            border: const OutlineInputBorder(),
          ),
          validator: (v) =>
              campo.requerido && (v ?? '').trim().isEmpty ? 'Campo obligatorio' : null,
        );
      case TipoCampo.texto:
      case TipoCampo.multilinea:
        return TextFormField(
          controller: _controladores[campo.clave],
          maxLength: campo.maxCaracteres,
          maxLines: campo.tipo == TipoCampo.multilinea ? 3 : 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: campo.etiqueta,
            border: const OutlineInputBorder(),
          ),
          validator: (v) =>
              campo.requerido && (v ?? '').trim().isEmpty ? 'Campo obligatorio' : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SingleChildScrollView(
        child: Form(
          key: _formulario,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final campo in widget.campos)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: _construirCampo(campo),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: Text(widget.textoBoton)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Formularios de cada cosa que el organizador puede crear o editar
// ---------------------------------------------------------------------------

const List<CampoForm> camposConcurso = [
  CampoForm('nombre', 'Nombre del concurso', requerido: true, maxCaracteres: 80),
  CampoForm('descripcion', 'Descripción', tipo: TipoCampo.multilinea, maxCaracteres: 300),
  CampoForm('sede', 'Sede (lugar)', maxCaracteres: 80),
  CampoForm('fecha_concurso', 'Fecha', tipo: TipoCampo.fecha),
];

Map<String, dynamic> valoresConcurso(Map<String, String> d) => {
      'nombre': d['nombre'],
      'descripcion': nulo(d['descripcion']),
      'sede': nulo(d['sede']),
      'fecha_concurso': nulo(d['fecha_concurso']),
    };

const List<CampoForm> camposBanda = [
  CampoForm('nombre', 'Nombre de la banda', requerido: true, maxCaracteres: 80),
  CampoForm('instructor', 'Instructor', maxCaracteres: 80),
  CampoForm('procedencia', 'Procedencia (escuela o ciudad)', maxCaracteres: 80),
  CampoForm('orden_participacion', 'Número de participación', tipo: TipoCampo.numero),
];

Map<String, dynamic> valoresBanda(Map<String, String> d) => {
      'nombre': d['nombre'],
      'instructor': nulo(d['instructor']),
      'procedencia': nulo(d['procedencia']),
      'orden_participacion': int.tryParse(d['orden_participacion'] ?? ''),
    };

const List<CampoForm> camposIntegrante = [
  CampoForm('nombre', 'Nombre', requerido: true, maxCaracteres: 80),
  CampoForm('cargo', 'Cargo (ej. Comandante, Corneta)', maxCaracteres: 60),
];

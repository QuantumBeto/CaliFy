# CaliFy – Contexto del proyecto

Archivo para retomar el trabajo en cualquier conversación nueva con Claude.
Última actualización: 2026-10-25.

## Qué es
App móvil (Flutter, Android + iOS) para calificar bandas de guerra en tiempo real en concursos.
Repo: https://github.com/QuantumBeto/CaliFy (el proyecto Flutter está en la carpeta `calify/`).
Idioma de trabajo: español. El usuario trabaja en laptops con Windows y VS Code.

## Roles
- **Organizador** (solo uno): crea y edita todo (concurso, imagen, categorías, bandas con integrantes, instructor, procedencia, hojas y rubros con sus escalas) y sube usuarios a Juez.
- **Juez**: solo crea y modifica sus propias calificaciones (quedan guardadas por usuario). Solo califica las hojas que el organizador le asignó y solo mientras el concurso está ABIERTO.
- **General**: cualquiera se registra solo para ver resultados. No ve calificaciones individuales, solo promedios y ranking.
- Todos se registran como General. El Organizador inicial se asigna una sola vez desde el SQL Editor de Supabase con `select public.nombrar_organizador('correo_o_usuario');`.

## Tecnología
- Backend: **Supabase** (Postgres + Auth + Realtime + Storage). No hay API propia. OCI se descartó porque el usuario no pudo crear ni acceder a su cuenta.
- Cada persona tiene **usuario** (para entrar y para que el organizador la identifique) y **correo** (para recuperar su contraseña). Funcionan por separado: se entra con cualquiera de los dos.
- Entrar con usuario: la app llama a la función `correo_para_entrar(usuario, contraseña)`, que solo entrega el correo si la contraseña es correcta y bloquea 15 min tras 5 fallos. Así no se exponen correos.
- Recuperar contraseña: "¿Olvidaste tu contraseña?" → se pide el correo → llega un código de 6 dígitos (plantilla "Reset Password" de Supabase con `{{ .Token }}`) → código + contraseña nueva (`verifyOTP` tipo recovery + `updateUser`).
- Correos: Supabase solo envía a miembros del equipo con su SMTP de prueba (2 por hora), así que se usa SMTP propio con una cuenta de Gmail (contraseña de aplicación, host smtp.gmail.com, puerto 587; unos 500 correos al día). "Confirm email" está APAGADO para que registrarse no dependa del correo.
- Cuentas viejas con correo inventado: `select public.cambiar_correo('usuario', 'correo@real.com');` desde el SQL Editor.
- Plan gratuito de Supabase: el proyecto se pausa tras 1 semana sin actividad y no hay respaldos automáticos.
- Claves: a la app solo va el **Project URL** y la **anon/publishable key**. La `service_role` nunca se comparte ni se pone en la app.

## Base de datos (scripts SQL)
Ya ejecutados por el usuario en Supabase: `calify_supabase.sql`, `calify_parche_01.sql`, `calify_parche_02.sql`.
Entregado y pendiente de correr por el usuario: `calify_parche_03.sql` (usuario y correo por separado).
`calify_supabase.sql` es el script completo actualizado, solo para un proyecto nuevo.

Estructura: `concurso` → `categoria` (nivel, ej. Secundarias "A") → `aspecto` (hoja de evaluación: Revista, Orden cerrado, Toque de bandera, Toques reglamentarios) → `rubro` (renglón con `puntaje_min`, `puntaje_max`, `paso`, `grupo`).
Otras tablas: `perfil`, `banda`, `integrante`, `asignacion` (qué juez evalúa qué hoja), `calificacion` (con `comentario` opcional), `observacion` (áreas de oportunidad), `nivel_rubro` (descripción de cada calificación), `actualizacion` (contador para tiempo real).
Nota de vocabulario: el usuario llama "rubro" a lo que en la base es un `aspecto` (ej. "Revista"). Decidir los nombres de la interfaz al diseñarla.

Datos por defecto: plantilla con las 4 hojas de `SECUNDARIAS_A.pdf` (ASIBGEEM 2023–2024). 77 rubros y 156 puntos en total (Revista 10, Orden cerrado 36, Toque de bandera 20, Toques reglamentarios 90). El toque de bandera solo acepta 0, 0.25 y 0.5. Todo es editable por el organizador. `crear_categoria(id_concurso, nombre)` copia la plantilla.

## Cómo se calcula el ganador
- Cada rubro vale el promedio de lo que pusieron los jueces.
- Total de la banda = suma de sus rubros activos (cada hoja multiplicada por su `peso`, por defecto 1). Gana el mayor `puntaje_total`; los empates comparten posición.
- `calificacion_final` = puntos / máximo posible × 10. Es solo para mostrar.
- Si se agrega, quita, desactiva o edita un rubro u hoja, todo se recalcula solo (vistas `v_resultado_rubro`, `v_resultado_aspecto`, `v_ranking`).
- `completo` indica si la banda ya tiene todos sus rubros calificados.
- No se puede cambiar la escala de un rubro si deja fuera calificaciones ya capturadas.

## Seguridad (ya implementada con RLS)
- Sin sesión no se ve nada.
- Cada juez solo ve y edita sus calificaciones. El organizador ve todas y puede borrarlas.
- Un juez con calificaciones no se borra, se desactiva.
- Las cuentas desactivadas pierden el acceso.

## Tiempo real
La app se suscribe a cambios de la tabla `actualizacion` (por concurso) y, al detectarlos, vuelve a pedir `v_ranking` con una espera de ~1 s (debounce).

## Pruebas
Suite de 159 pruebas sobre PostgreSQL con Supabase simulado. Pasa en base nueva, actualizando con los parches 01, 02 y 03, y con el parche 03 corrido dos veces.

## Pendiente
1. Ya hecho: Correr `calify_parche_03.sql`, configurar el SMTP de Gmail y la plantilla "Reset Password" en Supabase, y cambiar el correo del organizador con `cambiar_correo`.
2. Ya hecho: identificadores de Android corregidos a `com.quantumbeto.calify`. Revisar los de iOS (`PRODUCT_BUNDLE_IDENTIFIER` en `ios/Runner.xcodeproj/project.pbxproj`) si algún día se publica en iOS.
3. Ya hecho: conexión Flutter–Supabase (login, registro, pantalla de inicio). La app vive en la raíz del repo (`lib/`). Archivos: `main.dart`, `config.dart`, `auth_servicio.dart`, `pantalla_acceso.dart`, `pantalla_recuperar.dart`, `pantalla_inicio.dart`. Falta: pantallas de organizador, juez y resultados en vivo.
4. Crear el bucket de Storage para las imágenes de los concursos.
5. Diseñar las pantallas: organizador (administración), juez (captura por hoja y banda) y general (resultados en vivo).
6. Decidir si cada hoja debe pesar igual (hoy pesan por sus puntos: Toques reglamentarios 90 de 156) y la regla de desempate.
7. Publicación: el usuario eligió distribuir gratis: APK para Android y versión web (también sirve en iPhone desde Safari). El APK necesita el permiso INTERNET en `AndroidManifest.xml` (ya agregado).
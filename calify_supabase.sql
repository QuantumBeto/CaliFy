-- =====================================================================
-- CALIFY - Base de datos para Supabase (PostgreSQL)
--
-- COMO EJECUTARLO:
--   Supabase > tu proyecto > SQL Editor > New query > pega TODO este
--   archivo > Run. Debe correr completo sin errores en un proyecto nuevo.
--   (No es repetible: si necesitas empezar de cero, usa el bloque
--   "REINICIAR" de abajo.)
--
-- VOCABULARIO (el mismo de las hojas de evaluacion):
--   concurso   -> el evento / circuito (nombre, imagen, sede, fecha)
--   categoria  -> nivel en el que compiten las bandas: Secundarias "A", ...
--   banda      -> "B de G" (banda de guerra) con su "No. de participacion"
--   aspecto    -> cada hoja: Revista, Orden cerrado, Toque de bandera...
--   rubro      -> cada renglon que se califica dentro de un aspecto
--
-- ROLES:
--   GENERAL      cualquiera que se registre: solo VE resultados.
--   JUEZ         califica SOLO lo que el organizador le asigno.
--   ORGANIZADOR  uno solo: administra todo y asigna roles.
--   Todos se registran solos como GENERAL. Solo el organizador puede
--   subir a alguien a JUEZ. El organizador inicial se asigna una vez
--   desde este SQL Editor (ver el final del archivo).
-- =====================================================================

/* ---------------------------------------------------------------------
-- REINICIAR (descomenta SOLO si quieres borrar todo y empezar de cero)
drop view  if exists public.v_ranking, public.v_resultado_aspecto, public.v_resultado_rubro;
drop table if exists public.actualizacion, public.observacion, public.calificacion,
                     public.nivel_rubro, public.intento_acceso, public.asignacion, public.rubro, public.aspecto, public.integrante,
                     public.banda, public.categoria, public.concurso, public.perfil cascade;
drop function if exists public.crear_perfil_al_registrarse() cascade;
drop function if exists public.crear_categoria(bigint, text, boolean);
drop function if exists public.nombrar_organizador(text);
drop function if exists public.copiar_estructura(bigint, bigint);
drop function if exists public.mi_rol(), public.es_organizador(), public.es_juez(),
                        public.es_usuario_activo(), public.proteger_perfil(),
                        public.validar_calificacion(), public.validar_observacion(),
                        public.anotar_actualizacion(), public.anotar_actualizacion_estructura(),
                        public.validar_nivel_rubro(), public.validar_cambio_escala(),
                        public.usuario_disponible(text), public.correo_para_entrar(text, text),
                        public.cambiar_correo(text, text) cascade;
--------------------------------------------------------------------- */


-- Necesaria para comprobar la contrasena al entrar con el usuario (en Supabase ya viene).
create extension if not exists pgcrypto with schema extensions;


-- =====================================================================
-- 1. PERFIL (datos y rol de cada usuario; el login lo maneja Supabase Auth)
-- =====================================================================
create table public.perfil (
  id              uuid primary key references auth.users (id) on delete cascade,
  usuario         text not null,
  nombre_completo text not null,
  rol             text not null default 'GENERAL'
                  check (rol in ('ORGANIZADOR', 'JUEZ', 'GENERAL')),
  activo          boolean not null default true,
  creado          timestamptz not null default now()
);

-- Nombre de usuario unico sin importar mayusculas
create unique index uq_perfil_usuario on public.perfil (lower(usuario));
-- Solo puede existir UN organizador
create unique index uq_un_organizador on public.perfil (rol) where rol = 'ORGANIZADOR';


-- ---------------------------------------------------------------------
-- Funciones de ayuda para las politicas de seguridad.
-- Devuelven el rol del usuario conectado (NULL si no hay sesion o si su
-- cuenta esta desactivada, asi una cuenta desactivada pierde todo acceso).
-- ---------------------------------------------------------------------
create or replace function public.mi_rol()
returns text language sql stable security definer set search_path = '' as $$
  select p.rol from public.perfil p where p.id = auth.uid() and p.activo
$$;

create or replace function public.es_organizador()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.mi_rol() = 'ORGANIZADOR', false)
$$;

create or replace function public.es_juez()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.mi_rol() = 'JUEZ', false)
$$;

create or replace function public.es_usuario_activo()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.mi_rol() is not null
$$;


-- ---------------------------------------------------------------------
-- Registro abierto: al crearse un usuario en Supabase Auth se crea su
-- perfil SIEMPRE como GENERAL. Nada que mande la app puede cambiar eso.
-- El "usuario" es el que la persona eligio al registrarse (independiente de su
-- correo). Si no manda uno valido (cuentas creadas a mano desde el panel de
-- Supabase), se usa lo que va antes de la @ del correo.
-- ---------------------------------------------------------------------
create or replace function public.crear_perfil_al_registrarse()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_pedido  text := lower(trim(coalesce(new.raw_user_meta_data ->> 'usuario', '')));
  v_base    text;
  v_usuario text;
begin
  if v_pedido ~ '^[a-z0-9]+([._-][a-z0-9]+)*$' and char_length(v_pedido) between 3 and 20 then
    if exists (select 1 from public.perfil where lower(usuario) = v_pedido) then
      raise exception 'USUARIO_EN_USO';
    end if;
    v_usuario := v_pedido;
  else
    v_base    := coalesce(nullif(split_part(new.email, '@', 1), ''), new.id::text);
    v_usuario := v_base;
    while exists (select 1 from public.perfil where lower(usuario) = lower(v_usuario)) loop
      v_usuario := v_base || (floor(random() * 9000) + 1000)::int;
    end loop;
  end if;

  insert into public.perfil (id, usuario, nombre_completo, rol)
  values (
    new.id,
    v_usuario,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'nombre_completo'), ''), v_usuario),
    'GENERAL'
  );
  return new;
end $$;

create trigger trg_auth_nuevo_usuario
  after insert on auth.users
  for each row execute function public.crear_perfil_al_registrarse();


-- ---------------------------------------------------------------------
-- Protecciones del perfil. Solo aplican a la app (roles authenticated y
-- anon). Quien entra como administrador (rol postgres o service_role: SQL
-- Editor, Table Editor, funciones de servidor) puede cambiar lo que quiera,
-- aunque la sesion del editor traiga la identidad de algun usuario.
-- ---------------------------------------------------------------------
create or replace function public.proteger_perfil()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user not in ('authenticated', 'anon') or auth.uid() is null then
    return new;
  end if;

  if new.id is distinct from old.id or new.usuario is distinct from old.usuario then
    raise exception 'No se puede cambiar el identificador ni el nombre de usuario.';
  end if;

  if old.id = auth.uid()
     and (new.rol is distinct from old.rol or new.activo is distinct from old.activo) then
    raise exception 'No puedes cambiar tu propio rol ni desactivar tu propia cuenta.';
  end if;

  if new.rol = 'ORGANIZADOR' and old.rol <> 'ORGANIZADOR' then
    raise exception 'El rol ORGANIZADOR solo se asigna desde el SQL Editor de Supabase.';
  end if;

  return new;
end $$;

create trigger trg_proteger_perfil
  before update on public.perfil
  for each row execute function public.proteger_perfil();


-- ---------------------------------------------------------------------
-- Nombrar al ORGANIZADOR (uso unico, desde el SQL Editor con el rol postgres):
--     select public.nombrar_organizador('tu_correo_o_usuario');
-- Solo la pueden ejecutar los administradores; la app no tiene permiso.
-- Para pasar el cargo a otra persona: primero cambia el rol del organizador
-- actual a GENERAL (update public.perfil set rol = 'GENERAL' where ...) y
-- despues usa esta funcion con la persona nueva.
-- ---------------------------------------------------------------------
create or replace function public.nombrar_organizador(p_usuario_o_correo text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_id      uuid;
  v_usuario text;
begin
  select p.id, p.usuario into v_id, v_usuario
    from public.perfil p
   where lower(p.usuario) = lower(trim(p_usuario_o_correo))
      or p.id in (select u.id from auth.users u where lower(u.email) = lower(trim(p_usuario_o_correo)))
   limit 1;

  if v_id is null then
    raise exception 'No encontre ningun usuario "%". Revisa que ya se haya registrado.', p_usuario_o_correo;
  end if;

  if exists (select 1 from public.perfil where rol = 'ORGANIZADOR' and id <> v_id) then
    raise exception 'Ya existe un organizador. Primero cambia su rol a GENERAL.';
  end if;

  alter table public.perfil disable trigger trg_proteger_perfil;
  update public.perfil set rol = 'ORGANIZADOR', activo = true where id = v_id;
  alter table public.perfil enable trigger trg_proteger_perfil;

  return 'Listo: ' || v_usuario || ' ahora es ORGANIZADOR.';
end $$;

revoke execute on function public.nombrar_organizador(text) from public, anon, authenticated;


-- =====================================================================
-- 2. ESTRUCTURA DEL CONCURSO (todo se puede agregar, editar y quitar)
--    "Quitar" = poner activo = false (no se pierden calificaciones por
--    error). Un DELETE real borra en cascada todo lo que cuelga de ese
--    registro.
-- =====================================================================
create table public.concurso (
  id_concurso    bigint generated by default as identity primary key,
  nombre         text not null,
  descripcion    text,
  imagen_url     text,                       -- la imagen vive en Storage; aqui solo su direccion
  fecha_concurso date,
  sede           text,
  -- BORRADOR: preparando | ABIERTO: los jueces pueden calificar | CERRADO: solo lectura
  estado         text not null default 'BORRADOR'
                 check (estado in ('BORRADOR', 'ABIERTO', 'CERRADO')),
  es_plantilla   boolean not null default false,   -- la plantilla guarda la estructura por defecto
  activo         boolean not null default true,
  creado         timestamptz not null default now()
);

create table public.categoria (
  id_categoria bigint generated by default as identity primary key,
  id_concurso  bigint not null references public.concurso (id_concurso) on delete cascade,
  nombre       text not null,                -- ej. Secundarias "A"
  orden        int  not null default 0,
  activo       boolean not null default true
);
create index ix_categoria_concurso on public.categoria (id_concurso);

create table public.banda (
  id_banda            bigint generated by default as identity primary key,
  id_categoria        bigint not null references public.categoria (id_categoria) on delete cascade,
  nombre              text not null,         -- "B de G" en la hoja
  instructor          text,
  procedencia         text,
  orden_participacion int,                   -- "No. de participacion" en la hoja
  activo              boolean not null default true
);
create index ix_banda_categoria on public.banda (id_categoria);

create table public.integrante (
  id_integrante bigint generated by default as identity primary key,
  id_banda      bigint not null references public.banda (id_banda) on delete cascade,
  nombre        text not null,
  cargo         text,
  activo        boolean not null default true
);
create index ix_integrante_banda on public.integrante (id_banda);

-- Cada ASPECTO es una hoja de evaluacion. "peso" multiplica su puntaje en
-- el ranking general (1 = suma normal; ponlo en 0 para que no cuente).
create table public.aspecto (
  id_aspecto   bigint generated by default as identity primary key,
  id_categoria bigint not null references public.categoria (id_categoria) on delete cascade,
  nombre       text not null,
  peso         numeric(6,2) not null default 1 check (peso >= 0),
  orden        int not null default 0,
  activo       boolean not null default true
);
create index ix_aspecto_categoria on public.aspecto (id_categoria);

-- Cada RUBRO es un renglon que se califica, con su propia escala:
--   puntaje_min / puntaje_max : rango permitido
--   paso                      : de cuanto en cuanto (NULL = cualquier valor del rango)
--   grupo                     : etiqueta para agrupar renglones en pantalla
create table public.rubro (
  id_rubro    bigint generated by default as identity primary key,
  id_aspecto  bigint not null references public.aspecto (id_aspecto) on delete cascade,
  grupo       text,
  nombre      text not null,
  puntaje_min numeric(8,2) not null default 0,
  puntaje_max numeric(8,2) not null,
  paso        numeric(8,3),
  orden       int not null default 0,
  activo      boolean not null default true,
  constraint ck_rubro_rango check (puntaje_max > puntaje_min),
  constraint ck_rubro_paso  check (paso is null or paso > 0)
);
create index ix_rubro_aspecto on public.rubro (id_aspecto);

-- Descripcion opcional de cada nivel de un rubro: el "por que" de cada
-- calificacion. Ej.: en un rubro de 1 a 5 -> 5 = "Excelente: ...", 4 = "Muy bien: ..."
create table public.nivel_rubro (
  id_nivel    bigint generated by default as identity primary key,
  id_rubro    bigint not null references public.rubro (id_rubro) on delete cascade,
  valor       numeric(8,2) not null,
  descripcion text not null,
  constraint uq_nivel_rubro unique (id_rubro, valor)
);

-- Que juez evalua que aspecto (el "observador" de cada hoja).
create table public.asignacion (
  id_asignacion bigint generated by default as identity primary key,
  id_juez       uuid   not null references public.perfil (id) on delete cascade,
  id_aspecto    bigint not null references public.aspecto (id_aspecto) on delete cascade,
  constraint uq_asignacion unique (id_juez, id_aspecto)
);
create index ix_asignacion_aspecto on public.asignacion (id_aspecto);


-- =====================================================================
-- 3. CALIFICACIONES
--    Una fila = lo que UN juez puso a UNA banda en UN rubro.
--    No hay ON DELETE CASCADE hacia el juez: un juez con calificaciones
--    no se puede borrar, se desactiva (perfil.activo = false).
-- =====================================================================
create table public.calificacion (
  id_calificacion bigint generated by default as identity primary key,
  id_juez         uuid   not null references public.perfil (id),
  id_banda        bigint not null references public.banda (id_banda) on delete cascade,
  id_rubro        bigint not null references public.rubro (id_rubro) on delete cascade,
  valor           numeric(8,2) not null,
  comentario      text,                    -- el "por que" de esta calificacion (opcional)
  creado          timestamptz not null default now(),
  modificado      timestamptz not null default now(),
  constraint uq_calificacion unique (id_juez, id_banda, id_rubro),
  constraint ck_calificacion_comentario check (comentario is null or char_length(comentario) <= 500)
);
create index ix_calificacion_banda on public.calificacion (id_banda);
create index ix_calificacion_rubro on public.calificacion (id_rubro);

-- "Areas de oportunidad": comentario de cada juez por banda y aspecto.
create table public.observacion (
  id_observacion bigint generated by default as identity primary key,
  id_juez        uuid   not null references public.perfil (id),
  id_banda       bigint not null references public.banda (id_banda) on delete cascade,
  id_aspecto     bigint not null references public.aspecto (id_aspecto) on delete cascade,
  texto          text not null default '',
  creado         timestamptz not null default now(),
  modificado     timestamptz not null default now(),
  constraint uq_observacion unique (id_juez, id_banda, id_aspecto)
);

-- Contador que sube cada vez que cambia una calificacion de un concurso.
-- La app se suscribe a esta tabla (tiempo real) y, al detectar un cambio,
-- vuelve a pedir el ranking. Asi los usuarios GENERAL se enteran de los
-- cambios sin poder ver las calificaciones individuales de cada juez.
create table public.actualizacion (
  id_concurso bigint primary key references public.concurso (id_concurso) on delete cascade,
  version     bigint not null default 0,
  actualizado timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- Validacion de calificaciones: la base de datos misma rechaza lo
-- invalido, aunque la app tenga un error.
-- ---------------------------------------------------------------------
create or replace function public.validar_calificacion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_rol          text;
  v_activo       boolean;
  r              record;
  v_cat_banda    bigint;
  v_banda_activa boolean;
begin
  select p.rol, p.activo into v_rol, v_activo from public.perfil p where p.id = new.id_juez;
  if v_rol is distinct from 'JUEZ' or not coalesce(v_activo, false) then
    raise exception 'Solo un usuario activo con rol JUEZ puede calificar.';
  end if;

  if tg_op = 'UPDATE'
     and (new.id_juez <> old.id_juez or new.id_banda <> old.id_banda or new.id_rubro <> old.id_rubro) then
    raise exception 'No se puede cambiar el juez, la banda ni el rubro de una calificación existente.';
  end if;

  select ru.puntaje_min, ru.puntaje_max, ru.paso, ru.activo as rubro_activo,
         a.id_aspecto, a.activo as aspecto_activo, a.id_categoria as cat_aspecto,
         ca.activo as cat_activa, c.estado
    into r
    from public.rubro ru
    join public.aspecto   a  on a.id_aspecto    = ru.id_aspecto
    join public.categoria ca on ca.id_categoria = a.id_categoria
    join public.concurso  c  on c.id_concurso   = ca.id_concurso
   where ru.id_rubro = new.id_rubro;

  select b.id_categoria, b.activo into v_cat_banda, v_banda_activa
    from public.banda b where b.id_banda = new.id_banda;

  if v_cat_banda is distinct from r.cat_aspecto then
    raise exception 'La banda y el rubro pertenecen a categorías distintas.';
  end if;

  if r.estado <> 'ABIERTO' then
    raise exception 'El concurso no está abierto para calificar (estado actual: %).', r.estado;
  end if;

  if not (r.rubro_activo and r.aspecto_activo and r.cat_activa and v_banda_activa) then
    raise exception 'Este rubro o esta banda ya no están activos.';
  end if;

  if not exists (select 1 from public.asignacion s
                  where s.id_juez = new.id_juez and s.id_aspecto = r.id_aspecto) then
    raise exception 'No tienes asignado este aspecto.';
  end if;

  if new.valor < r.puntaje_min or new.valor > r.puntaje_max then
    raise exception 'La calificación (%) debe estar entre % y %.', new.valor, r.puntaje_min, r.puntaje_max;
  end if;

  if r.paso is not null and mod(new.valor - r.puntaje_min, r.paso) <> 0 then
    raise exception 'La calificación (%) debe ir de % en % a partir de %.',
      new.valor, r.paso, r.paso, r.puntaje_min;
  end if;

  if tg_op = 'UPDATE' then
    new.modificado := now();
  end if;
  return new;
end $$;

create trigger trg_validar_calificacion
  before insert or update on public.calificacion
  for each row execute function public.validar_calificacion();


create or replace function public.validar_observacion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_rol       text;
  v_activo    boolean;
  v_estado    text;
  v_cat_asp   bigint;
  v_cat_banda bigint;
begin
  select p.rol, p.activo into v_rol, v_activo from public.perfil p where p.id = new.id_juez;
  if v_rol is distinct from 'JUEZ' or not coalesce(v_activo, false) then
    raise exception 'Solo un usuario activo con rol JUEZ puede escribir observaciones.';
  end if;

  select a.id_categoria, c.estado into v_cat_asp, v_estado
    from public.aspecto a
    join public.categoria ca on ca.id_categoria = a.id_categoria
    join public.concurso  c  on c.id_concurso   = ca.id_concurso
   where a.id_aspecto = new.id_aspecto;

  select b.id_categoria into v_cat_banda from public.banda b where b.id_banda = new.id_banda;

  if v_cat_banda is distinct from v_cat_asp then
    raise exception 'La banda y el aspecto pertenecen a categorías distintas.';
  end if;
  if v_estado <> 'ABIERTO' then
    raise exception 'El concurso no está abierto para calificar (estado actual: %).', v_estado;
  end if;
  if not exists (select 1 from public.asignacion s
                  where s.id_juez = new.id_juez and s.id_aspecto = new.id_aspecto) then
    raise exception 'No tienes asignado este aspecto.';
  end if;

  if tg_op = 'UPDATE' then
    new.modificado := now();
  end if;
  return new;
end $$;

create trigger trg_validar_observacion
  before insert or update on public.observacion
  for each row execute function public.validar_observacion();


-- Sube el contador de "actualizacion" cuando cambia una calificacion.
-- Nota para la app: un juez que guarda toda una hoja de golpe genera
-- muchos avisos seguidos; conviene esperar ~1 segundo antes de volver a
-- pedir el ranking (debounce).
create or replace function public.anotar_actualizacion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_concurso bigint;
begin
  select ca.id_concurso into v_concurso
    from public.banda b
    join public.categoria ca on ca.id_categoria = b.id_categoria
   where b.id_banda = coalesce(new.id_banda, old.id_banda);

  -- Si el concurso ya no existe (se esta borrando en cascada) no hay nada que avisar.
  if v_concurso is not null
     and exists (select 1 from public.concurso where id_concurso = v_concurso) then
    insert into public.actualizacion (id_concurso, version, actualizado)
    values (v_concurso, 1, now())
    on conflict (id_concurso)
    do update set version = public.actualizacion.version + 1, actualizado = now();
  end if;
  return null;
end $$;

create trigger trg_calificacion_actualiza
  after insert or update or delete on public.calificacion
  for each row execute function public.anotar_actualizacion();

-- ---------------------------------------------------------------------
-- Descripcion de niveles, proteccion de escala y avisos de cambios de estructura
-- ---------------------------------------------------------------------
-- El valor descrito debe existir en la escala del rubro.
create or replace function public.validar_nivel_rubro()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  r record;
begin
  select ru.puntaje_min, ru.puntaje_max, ru.paso into r
    from public.rubro ru where ru.id_rubro = new.id_rubro;

  if new.valor < r.puntaje_min or new.valor > r.puntaje_max then
    raise exception 'El valor % debe estar entre % y % (la escala del rubro).',
      new.valor, r.puntaje_min, r.puntaje_max;
  end if;
  if r.paso is not null and mod(new.valor - r.puntaje_min, r.paso) <> 0 then
    raise exception 'El valor % no existe en la escala del rubro (de % en %, desde %).',
      new.valor, r.paso, r.paso, r.puntaje_min;
  end if;
  return new;
end $$;

drop trigger if exists trg_validar_nivel_rubro on public.nivel_rubro;
create trigger trg_validar_nivel_rubro
  before insert or update on public.nivel_rubro
  for each row execute function public.validar_nivel_rubro();


-- 2. No se puede cambiar la escala de un rubro si dejaria fuera calificaciones
--    (o descripciones de nivel) que ya existen. Subir el maximo siempre se puede.
create or replace function public.validar_cambio_escala()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  n integer;
begin
  if new.puntaje_min is distinct from old.puntaje_min
     or new.puntaje_max is distinct from old.puntaje_max
     or new.paso is distinct from old.paso then

    select count(*) into n
      from public.calificacion c
     where c.id_rubro = new.id_rubro
       and (c.valor < new.puntaje_min or c.valor > new.puntaje_max
            or (new.paso is not null and mod(c.valor - new.puntaje_min, new.paso) <> 0));
    if n > 0 then
      raise exception 'La nueva escala deja fuera % calificacion(es) ya capturada(s) en este rubro. Ajusta la escala o borra primero esas calificaciones.', n;
    end if;

    select count(*) into n
      from public.nivel_rubro v
     where v.id_rubro = new.id_rubro
       and (v.valor < new.puntaje_min or v.valor > new.puntaje_max
            or (new.paso is not null and mod(v.valor - new.puntaje_min, new.paso) <> 0));
    if n > 0 then
      raise exception 'La nueva escala deja fuera % descripcion(es) de nivel de este rubro. Ajustalas o borralas primero.', n;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_validar_cambio_escala on public.rubro;
create trigger trg_validar_cambio_escala
  before update on public.rubro
  for each row execute function public.validar_cambio_escala();


-- 1. Aviso en tiempo real cuando cambia la ESTRUCTURA (rubros, hojas, bandas,
--    categorias): los resultados que ya se estan viendo se recalculan solos.
create or replace function public.anotar_actualizacion_estructura()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_fila     record;
  v_concurso bigint;
begin
  if tg_op = 'DELETE' then v_fila := old; else v_fila := new; end if;

  case tg_table_name
    when 'rubro' then
      select ca.id_concurso into v_concurso
        from public.aspecto a join public.categoria ca on ca.id_categoria = a.id_categoria
       where a.id_aspecto = v_fila.id_aspecto;
    when 'aspecto' then
      select ca.id_concurso into v_concurso
        from public.categoria ca where ca.id_categoria = v_fila.id_categoria;
    when 'banda' then
      select ca.id_concurso into v_concurso
        from public.categoria ca where ca.id_categoria = v_fila.id_categoria;
    when 'categoria' then
      v_concurso := v_fila.id_concurso;
  end case;

  -- Si el concurso ya no existe (se esta borrando en cascada), no hay nada que avisar.
  if v_concurso is not null
     and exists (select 1 from public.concurso where id_concurso = v_concurso) then
    insert into public.actualizacion (id_concurso, version, actualizado)
    values (v_concurso, 1, now())
    on conflict (id_concurso)
    do update set version = public.actualizacion.version + 1, actualizado = now();
  end if;
  return null;
end $$;

drop trigger if exists trg_rubro_actualiza     on public.rubro;
drop trigger if exists trg_aspecto_actualiza   on public.aspecto;
drop trigger if exists trg_banda_actualiza     on public.banda;
drop trigger if exists trg_categoria_actualiza on public.categoria;
create trigger trg_rubro_actualiza     after insert or update or delete on public.rubro
  for each row execute function public.anotar_actualizacion_estructura();
create trigger trg_aspecto_actualiza   after insert or update or delete on public.aspecto
  for each row execute function public.anotar_actualizacion_estructura();
create trigger trg_banda_actualiza     after insert or update or delete on public.banda
  for each row execute function public.anotar_actualizacion_estructura();
create trigger trg_categoria_actualiza after insert or update or delete on public.categoria
  for each row execute function public.anotar_actualizacion_estructura();

revoke execute on function public.validar_nivel_rubro(),
                          public.validar_cambio_escala(),
                          public.anotar_actualizacion_estructura()
  from public, anon;



-- Activa el tiempo real para esa tabla (solo existe en Supabase).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.actualizacion;
  end if;
exception when duplicate_object then
  null;
end $$;


-- =====================================================================
-- 4. FUNCIONES PARA EL ORGANIZADOR
-- =====================================================================

-- Copia los aspectos y rubros activos de una categoria a otra.
-- Sirve para reusar la estructura de otro nivel o de un concurso anterior.
create or replace function public.copiar_estructura(p_origen bigint, p_destino bigint)
returns integer language plpgsql set search_path = '' as $$
declare
  a        record;
  r        record;
  v_nuevo  bigint;
  v_rubro  bigint;
  v_rubros integer := 0;
begin
  if not public.es_organizador() then
    raise exception 'Solo el organizador puede copiar estructuras.';
  end if;
  if p_origen = p_destino then
    raise exception 'El origen y el destino son la misma categoría.';
  end if;

  for a in select * from public.aspecto
            where id_categoria = p_origen and activo
            order by orden, id_aspecto
  loop
    insert into public.aspecto (id_categoria, nombre, peso, orden)
    values (p_destino, a.nombre, a.peso, a.orden)
    returning id_aspecto into v_nuevo;

    for r in select * from public.rubro
              where id_aspecto = a.id_aspecto and activo
              order by orden, id_rubro
    loop
      insert into public.rubro (id_aspecto, grupo, nombre, puntaje_min, puntaje_max, paso, orden)
      values (v_nuevo, r.grupo, r.nombre, r.puntaje_min, r.puntaje_max, r.paso, r.orden)
      returning id_rubro into v_rubro;

      -- tambien se copia la descripcion de cada nivel de calificacion
      insert into public.nivel_rubro (id_rubro, valor, descripcion)
      select v_rubro, n.valor, n.descripcion
        from public.nivel_rubro n
       where n.id_rubro = r.id_rubro;

      v_rubros := v_rubros + 1;
    end loop;
  end loop;

  return v_rubros;
end $$;

-- Crea una categoria y, por defecto, le copia la estructura de la plantilla
-- (las 4 hojas de Secundarias "A"). Despues todo se puede editar.
create or replace function public.crear_categoria(
  p_id_concurso bigint, p_nombre text, p_usar_plantilla boolean default true)
returns bigint language plpgsql set search_path = '' as $$
declare
  v_id        bigint;
  v_plantilla bigint;
begin
  if not public.es_organizador() then
    raise exception 'Solo el organizador puede crear categorías.';
  end if;

  insert into public.categoria (id_concurso, nombre, orden)
  values (p_id_concurso, p_nombre,
          coalesce((select max(orden) + 1 from public.categoria where id_concurso = p_id_concurso), 1))
  returning id_categoria into v_id;

  if p_usar_plantilla then
    select ca.id_categoria into v_plantilla
      from public.categoria ca
      join public.concurso c on c.id_concurso = ca.id_concurso
     where c.es_plantilla and ca.id_categoria <> v_id
     order by ca.orden, ca.id_categoria
     limit 1;
    if v_plantilla is not null then
      perform public.copiar_estructura(v_plantilla, v_id);
    end if;
  end if;

  return v_id;
end $$;


-- =====================================================================
-- 4b. USUARIO Y CORREO POR SEPARADO
--    El usuario sirve para entrar y para que el organizador identifique a cada
--    persona. El correo sirve para recuperar la contrasena. Se puede entrar con
--    cualquiera de los dos.
-- =====================================================================
-- Antes de registrarse, la app pregunta si el usuario esta libre.
create or replace function public.usuario_disponible(p_usuario text)
returns boolean language sql stable security definer set search_path = '' as $$
  select nullif(trim(coalesce(p_usuario, '')), '') is not null
     and not exists (select 1 from public.perfil
                      where lower(usuario) = lower(trim(p_usuario)))
$$;


-- 3. Entrar con el usuario. Supabase Auth entra con correo, asi que la app
--    necesita saber el correo de ese usuario. Esta funcion lo entrega SOLO si
--    la contrasena es correcta (y asi nadie puede juntar correos ajenos).
--    5 fallos seguidos bloquean el acceso con usuario por 15 minutos (entrando
--    con el correo no hay bloqueo propio, eso lo limita Supabase).
create table if not exists public.intento_acceso (
  usuario         text primary key,
  fallos          integer not null default 0,
  bloqueado_hasta timestamptz
);
alter table public.intento_acceso enable row level security;   -- sin politicas: la app no lo toca
revoke all on public.intento_acceso from anon, authenticated;

create or replace function public.correo_para_entrar(p_usuario text, p_contrasena text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_usuario text := lower(trim(coalesce(p_usuario, '')));
  v_inten   record;
  v_correo  text;
  v_hash    text;
  v_fallos  integer;
  v_hay     boolean;
begin
  if v_usuario = '' or p_contrasena is null or p_contrasena = '' then
    return null;
  end if;

  select * into v_inten from public.intento_acceso where usuario = v_usuario;
  v_hay := found;
  if v_hay then
    if v_inten.bloqueado_hasta is not null and v_inten.bloqueado_hasta > now() then
      raise exception 'DEMASIADOS_INTENTOS';
    end if;
  end if;

  select u.email, u.encrypted_password into v_correo, v_hash
    from public.perfil p
    join auth.users u on u.id = p.id
   where lower(p.usuario) = v_usuario;

  if v_correo is not null and coalesce(v_hash, '') <> ''
     and extensions.crypt(p_contrasena, v_hash) = v_hash then
    delete from public.intento_acceso where usuario = v_usuario;
    return v_correo;
  end if;

  -- Contrasena incorrecta. Solo se cuentan los fallos de usuarios que existen
  -- (asi nadie puede llenar la tabla con nombres inventados).
  if v_correo is not null then
    if not v_hay then
      v_fallos := 1;
    elsif v_inten.bloqueado_hasta is not null then
      v_fallos := 1;                                   -- el bloqueo ya vencio: se empieza de cero
    else
      v_fallos := v_inten.fallos + 1;
    end if;
    insert into public.intento_acceso (usuario, fallos, bloqueado_hasta)
    values (v_usuario, v_fallos, case when v_fallos >= 5 then now() + interval '15 minutes' end)
    on conflict (usuario) do update
      set fallos = excluded.fallos, bloqueado_hasta = excluded.bloqueado_hasta;
  end if;
  return null;
end $$;


-- 4. Solo para el administrador (SQL Editor): cambia el correo de una cuenta.
--    Ejemplo:  select public.cambiar_correo('tu_usuario', 'tucorreo@gmail.com');
create or replace function public.cambiar_correo(p_usuario text, p_correo text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_id     uuid;
  v_correo text := lower(trim(coalesce(p_correo, '')));
begin
  if v_correo !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'El correo "%" no es valido.', p_correo;
  end if;

  select id into v_id from public.perfil where lower(usuario) = lower(trim(coalesce(p_usuario, '')));
  if v_id is null then
    raise exception 'No encontre el usuario "%".', p_usuario;
  end if;
  if exists (select 1 from auth.users where lower(email) = v_correo and id <> v_id) then
    raise exception 'Ese correo ya lo usa otra cuenta.';
  end if;

  update auth.users set email = v_correo, updated_at = now() where id = v_id;
  update auth.identities
     set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_correo)),
         updated_at = now()
   where user_id = v_id and provider = 'email';

  return 'Listo: el usuario ' || p_usuario || ' ahora usa el correo ' || v_correo;
end $$;




-- =====================================================================
-- 5. SEGURIDAD (Row Level Security): quien puede ver y modificar que
-- =====================================================================
alter table public.perfil        enable row level security;
alter table public.asignacion    enable row level security;
alter table public.calificacion  enable row level security;
alter table public.observacion   enable row level security;
alter table public.actualizacion enable row level security;

-- Perfil: cada quien ve y edita el suyo (rol y estado quedan protegidos por
-- el trigger); el organizador ve y edita todos (asi asigna roles).
create policy perfil_ver on public.perfil for select to authenticated
  using (id = auth.uid() or public.es_organizador());
create policy perfil_editar on public.perfil for update to authenticated
  using (id = auth.uid() or public.es_organizador())
  with check (id = auth.uid() or public.es_organizador());

-- Estructura del concurso: TODOS los usuarios con cuenta activa la ven;
-- solo el organizador la modifica.
do $$
declare
  t text;
begin
  foreach t in array array['concurso', 'categoria', 'banda', 'integrante', 'aspecto', 'rubro', 'nivel_rubro'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.es_usuario_activo())',
      t || '_ver', t);
    execute format(
      'create policy %I on public.%I for all to authenticated
         using (public.es_organizador()) with check (public.es_organizador())',
      t || '_organizador', t);
  end loop;
end $$;

-- Asignaciones: el organizador las administra; cada juez ve las suyas.
create policy asignacion_ver on public.asignacion for select to authenticated
  using (id_juez = auth.uid() or public.es_organizador());
create policy asignacion_organizador on public.asignacion for all to authenticated
  using (public.es_organizador()) with check (public.es_organizador());

-- Calificaciones: cada juez ve y modifica SOLO las suyas. El organizador
-- las ve todas (para saber quien califico que) y puede borrarlas.
-- Los usuarios GENERAL no las ven; ven los promedios en las vistas.
create policy calificacion_ver on public.calificacion for select to authenticated
  using (id_juez = auth.uid() or public.es_organizador());
create policy calificacion_insertar on public.calificacion for insert to authenticated
  with check (id_juez = auth.uid() and public.es_juez());
create policy calificacion_editar on public.calificacion for update to authenticated
  using (id_juez = auth.uid() and public.es_juez())
  with check (id_juez = auth.uid() and public.es_juez());
create policy calificacion_borrar on public.calificacion for delete to authenticated
  using (public.es_organizador());

-- Observaciones ("areas de oportunidad"): mismas reglas que las calificaciones.
create policy observacion_ver on public.observacion for select to authenticated
  using (id_juez = auth.uid() or public.es_organizador());
create policy observacion_insertar on public.observacion for insert to authenticated
  with check (id_juez = auth.uid() and public.es_juez());
create policy observacion_editar on public.observacion for update to authenticated
  using (id_juez = auth.uid() and public.es_juez())
  with check (id_juez = auth.uid() and public.es_juez());
create policy observacion_borrar on public.observacion for delete to authenticated
  using (public.es_organizador());

-- Contador de actualizaciones: solo lectura para cualquier usuario activo.
create policy actualizacion_ver on public.actualizacion for select to authenticated
  using (public.es_usuario_activo());


-- =====================================================================
-- 6. VISTAS DE RESULTADOS (lo que ven los usuarios GENERAL)
--    Por cada rubro se promedia lo que pusieron los jueces; cada aspecto
--    suma sus rubros; el ranking suma los aspectos (multiplicados por su
--    peso). Solo cuentan elementos activos y concursos que no son plantilla.
--    A proposito estas vistas se ejecutan con permisos del dueño (no del
--    usuario): asi los usuarios GENERAL ven los PROMEDIOS sin poder leer
--    la calificacion individual de cada juez.
-- =====================================================================
create or replace view public.v_resultado_rubro as
select ca.id_concurso,
       ca.id_categoria,
       b.id_banda,
       b.nombre                    as banda,
       b.orden_participacion,
       a.id_aspecto,
       a.nombre                    as aspecto,
       a.orden                     as orden_aspecto,
       a.peso,
       r.id_rubro,
       r.grupo,
       r.nombre                    as rubro,
       r.orden                     as orden_rubro,
       r.puntaje_max,
       count(cal.id_calificacion)  as num_jueces,
       round(avg(cal.valor), 2)    as promedio
  from public.banda b
  join public.categoria ca on ca.id_categoria = b.id_categoria and ca.activo
  join public.concurso  c  on c.id_concurso   = ca.id_concurso and c.activo and not c.es_plantilla
  join public.aspecto   a  on a.id_categoria  = ca.id_categoria and a.activo
  join public.rubro     r  on r.id_aspecto    = a.id_aspecto and r.activo
  left join public.calificacion cal
         on cal.id_banda = b.id_banda and cal.id_rubro = r.id_rubro
 where b.activo
 group by b.id_banda, ca.id_categoria, a.id_aspecto, r.id_rubro;

create or replace view public.v_resultado_aspecto as
select id_concurso, id_categoria, id_banda, banda, orden_participacion,
       id_aspecto, aspecto, orden_aspecto, peso,
       sum(coalesce(promedio, 0))              as puntaje,
       sum(puntaje_max)                        as puntaje_max,
       count(*)                                as rubros_total,
       count(*) filter (where num_jueces > 0)  as rubros_calificados,
       round(10 * sum(coalesce(promedio, 0)) / nullif(sum(puntaje_max), 0), 2) as calificacion_aspecto
  from public.v_resultado_rubro
 group by id_concurso, id_categoria, id_banda, banda, orden_participacion,
          id_aspecto, aspecto, orden_aspecto, peso;

-- Ranking por categoria (las bandas con el mismo puntaje comparten posicion).
--   puntaje_total / puntaje_maximo : puntos sumados de TODOS los rubros activos.
--       Cada rubro vale el promedio de sus jueces. Si agregas, quitas o
--       desactivas un rubro u hoja, el total y el maximo se ajustan solos.
--       El GANADOR es quien tiene mayor puntaje_total.
--   completo           : true cuando la banda ya tiene calificacion en todos sus rubros
--   calificacion_final : lo mismo expresado de 0 a 10 (puntos obtenidos / posibles x 10),
--       solo para mostrar. Cada rubro cuenta segun sus puntos (la hoja de Toques
--       reglamentarios, con 90 de 156, pesa mas que Revista). Con "peso" en cada
--       aspecto se puede ajustar.
create or replace view public.v_ranking as
select id_concurso, id_categoria, id_banda, banda, orden_participacion,
       round(sum(puntaje * peso), 2)      as puntaje_total,
       round(sum(puntaje_max * peso), 2)  as puntaje_maximo,
       rank() over (partition by id_categoria order by sum(puntaje * peso) desc) as posicion,
       sum(rubros_calificados)            as rubros_calificados,
       sum(rubros_total)                  as rubros_total,
       round(10 * sum(puntaje * peso) / nullif(sum(puntaje_max * peso), 0), 2) as calificacion_final,
       (sum(rubros_calificados) = sum(rubros_total)) as completo
  from public.v_resultado_aspecto
 group by id_concurso, id_categoria, id_banda, banda, orden_participacion;


-- =====================================================================
-- 7. PERMISOS
--    Sin sesion (anon) no se ve nada. Con sesion, la seguridad fina la
--    ponen las politicas de arriba.
-- =====================================================================
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Tabla interna del limite de intentos: la app no la toca (solo las funciones de la base).
revoke all on public.intento_acceso from anon, authenticated;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.mi_rol(), public.es_organizador(), public.es_juez(),
                          public.es_usuario_activo(),
                          public.copiar_estructura(bigint, bigint),
                          public.crear_categoria(bigint, text, boolean)
  to authenticated;

-- Permisos. Estas dos funciones se usan ANTES de iniciar sesion, por eso
-- se abren a "anon". Las demas quedan cerradas para la app.
revoke execute on function public.usuario_disponible(text),
                          public.correo_para_entrar(text, text),
                          public.cambiar_correo(text, text)
  from public, anon, authenticated;
grant execute on function public.usuario_disponible(text),
                          public.correo_para_entrar(text, text)
  to anon, authenticated;


-- =====================================================================
-- 8. DATOS POR DEFECTO: PLANTILLA "Secundarias A" (hojas ASIBGEEM)
--    Es un "concurso" marcado es_plantilla. Al crear una categoria con
--    crear_categoria() se copia su estructura. Todo se puede editar.
--
--    Puntaje maximo por hoja:  Revista 10 | Orden cerrado 36 |
--    Toque de bandera 20 | Toques reglamentarios 90   (total 156)
-- =====================================================================
do $$
declare
  v_conc bigint;
  v_cat  bigint;
  v_asp  bigint;
begin
  insert into public.concurso (nombre, descripcion, estado, es_plantilla)
  values ('PLANTILLA (estructura por defecto)',
          'No es un concurso real: guarda las hojas de evaluación que se copian al crear una categoría.',
          'BORRADOR', true)
  returning id_concurso into v_conc;

  insert into public.categoria (id_concurso, nombre, orden)
  values (v_conc, 'Secundarias "A"', 1)
  returning id_categoria into v_cat;

  ---------------------------------------------------------------- 1. REVISTA
  -- Un solo rubro; se elige un valor de la tabla: 10, 9.8, 9.6 ... 2.2
  insert into public.aspecto (id_categoria, nombre, orden)
  values (v_cat, 'Revista', 1) returning id_aspecto into v_asp;

  insert into public.rubro (id_aspecto, nombre, puntaje_min, puntaje_max, paso, orden)
  values (v_asp,
          'Peinado en mujeres y corte de cabello en varones, uniforme similar y acorde a su talla, '
          'guantes o manos limpias, pantalón o falda del mismo color o material, color de cabello '
          'natural, sin aretes, sin pulseras o collares',
          2.2, 10, 0.2, 1);

  ---------------------------------------------------------- 2. ORDEN CERRADO
  -- 18 renglones, cada uno de 0 a 2 (0, 1 o 2)
  insert into public.aspecto (id_categoria, nombre, orden)
  values (v_cat, 'Orden cerrado', 2) returning id_aspecto into v_asp;

  insert into public.rubro (id_aspecto, grupo, nombre, puntaje_min, puntaje_max, paso, orden)
  select v_asp, t.grupo, t.nombre, 0, 2, 1, t.n
    from (values
      ( 1, null,                                                   'Liderazgo y dominio del comandante'),
      ( 2, 'Voz de mando (se califica entrada y romper la formación)', 'Clara'),
      ( 3, 'Voz de mando (se califica entrada y romper la formación)', 'Fuerte'),
      ( 4, 'Voz de mando (se califica entrada y romper la formación)', 'Breve'),
      ( 5, 'Voz de mando (se califica entrada y romper la formación)', 'Advertencia'),
      ( 6, 'Voz de mando (se califica entrada y romper la formación)', 'Preventiva'),
      ( 7, 'Voz de mando (se califica entrada y romper la formación)', 'Ejecutiva'),
      ( 8, 'Apego al protocolo de la convocatoria',                'Alinearse por la derecha'),
      ( 9, 'Apego al protocolo de la convocatoria',                'Firmes'),
      (10, 'Apego al protocolo de la convocatoria',                '3 pasos al frente'),
      (11, 'Apego al protocolo de la convocatoria',                'Saludar'),
      (12, 'Apego al protocolo de la convocatoria',                'Flanco derecho'),
      (13, 'Apego al protocolo de la convocatoria',                'Paso redoblado'),
      (14, 'Apego al protocolo de la convocatoria',                'Alto'),
      (15, 'Apego al protocolo de la convocatoria',                'Flanco izquierdo'),
      (16, 'Apego al protocolo de la convocatoria',                'Presentar'),
      (17, 'Apego al protocolo de la convocatoria',                'Firmes'),
      (18, 'Apego al protocolo de la convocatoria',                'Romper la formación')
    ) as t(n, grupo, nombre);

  ----------------------------------------------- 3. TOQUE DE BANDERA (CMTE Y C.O.)
  -- Tabla de 4 filas x 10 columnas; cada celda vale 0, 0.25 o 0.5 (40 rubros).
  -- Cada Atencion / Punto ejecutivo se agrupo con el toque que lo acompana
  -- en la hoja (Paso redoblado, Bandera, Marinos).
  insert into public.aspecto (id_categoria, nombre, orden)
  values (v_cat, 'Toque de bandera (comandante y C.O.)', 3) returning id_aspecto into v_asp;

  insert into public.rubro (id_aspecto, grupo, nombre, puntaje_min, puntaje_max, paso, orden)
  select v_asp, f.grupo, f.fila || ' - ' || c.columna, 0, 0.5, 0.25, (f.n - 1) * 10 + c.n
    from (values
      (1, 'Comandante',         'Precisión de movimientos'),
      (2, 'Comandante',         'Correcta ejecución del ademán'),
      (3, 'Corneta de órdenes', 'Interpretación del ademán del comandante'),
      (4, 'Corneta de órdenes', 'Sincronía con el ademán del comandante')
    ) as f(n, grupo, fila)
    cross join (values
      ( 1, 'Paso redoblado: atención'),
      ( 2, 'Paso redoblado'),
      ( 3, 'Paso redoblado: punto ejecutivo (E.D.B.)'),
      ( 4, 'Bandera: atención'),
      ( 5, 'Bandera'),
      ( 6, 'Bandera: punto ejecutivo (E.D.B.)'),
      ( 7, 'Marinos: atención'),
      ( 8, 'Marinos'),
      ( 9, 'Marinos: punto ejecutivo (E.D.B.)'),
      (10, '2das. posiciones en la marcha reglamentaria')
    ) as c(n, columna);

  ------------------------------------------- 4. TOQUES REGLAMENTARIOS (BANDA)
  -- 3 toques x 6 renglones, cada uno de 1 a 5 (18 rubros).
  insert into public.aspecto (id_categoria, nombre, orden)
  values (v_cat, 'Toques reglamentarios (banda)', 4) returning id_aspecto into v_asp;

  insert into public.rubro (id_aspecto, grupo, nombre, puntaje_min, puntaje_max, paso, orden)
  select v_asp, g.grupo, i.nombre, 1, 5, 1, (g.n - 1) * 6 + i.n
    from (values (1, 'Bandera'), (2, 'Paso redoblado'), (3, 'Marinos')) as g(n, grupo)
    cross join (values
      (1, 'Correcta interpretación de la partitura en tambores (apego al material de guía)'),
      (2, 'Igualdad en baqueteo de tambores'),
      (3, 'Cadencia en los tambores'),
      (4, 'Correcta interpretación de la partitura en cornetas (apego al material de guía)'),
      (5, 'Cadencia en cornetas'),
      (6, 'Acoplamiento entre cornetas y tambores (inicio acorde al toque)')
    ) as i(n, nombre);
end $$;


-- =====================================================================
-- PRIMER ORGANIZADOR (hazlo UNA vez, despues de crear los demas objetos)
--   1. Registrate normalmente desde la app (o en Supabase > Authentication
--      > Users > Add user).
--   2. En este SQL Editor (con el rol postgres, sin elegir ningun usuario)
--      corre, con tu correo o tu nombre de usuario:
--
--        select public.nombrar_organizador('tu_correo_o_usuario');
--
--   A partir de ahi, el organizador sube a JUEZ a quien corresponda
--   directamente desde la app (editando el rol del perfil).
-- =====================================================================

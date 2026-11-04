-- =====================================================================
--  PLANILLAS PERÚ – Migración única (noviembre 2026)
--  Ejecútala UNA vez en: Supabase → SQL Editor → New query → Run,
--  después de supabase.sql. Se puede volver a ejecutar sin problema: no borra datos.
--
--  Incluye todo lo que necesita la versión actual de index.html:
--   1. Columnas de empresas (permiso, rubro, ubicación, origen y TIPO DE CUENTA: prueba / cliente / suscriptor).
--   2. Función emp_actualizar_datos (el rep. con permiso edita rubro y dirección).
--   3. Escritura de representantes: trabajadores (todo representante, incluye la carga masiva) y
--      periodos = cálculo de planilla (administrador y representantes con permiso "administrador").
--   4. Tipos de cuenta: registro de prueba con RUC y límite de 2 trabajadores solo en cuentas de prueba.
--   5. Recibos por honorarios (prestadores de 4ta categoría); en cuentas de prueba, máximo 2 prestadores
--      y 2 recibos por prestador.
--   6. Correo de los usuarios: recuperación de contraseña para todos, ingreso con RUC protegido.
--   Matriz de permisos por tipo de cuenta (bloque MATRIZ DE PERMISOS) y candados que impiden que
--   el perfil "usuario" modifique el cálculo de la planilla o que un representante cambie parámetros.
--   El tipo de cuenta se edita desde la lista de Empresas: solo el administrador puede guardarlo
--   (regla empresas_admin + trigger empresa_suscripcion).
--   Las sub-pestañas de Planilla (Principal / Dctos.) son solo navegación: no requieren cambios aquí.
--
--  No hacen falta tablas nuevas para la carga masiva: los trabajadores se guardan en
--  "trabajadores" y los datos del mes (por N° de documento) en "periodos".
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
--  1. COLUMNAS DE EMPRESAS
-- ---------------------------------------------------------------------
alter table public.empresas add column if not exists permiso      text not null default 'usuario';
alter table public.empresas add column if not exists rubro        text not null default '';
alter table public.empresas add column if not exists ciudad       text not null default '';
alter table public.empresas add column if not exists departamento text not null default '';
alter table public.empresas add column if not exists provincia    text not null default '';
alter table public.empresas add column if not exists distrito     text not null default '';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'empresas_permiso_check') then
    alter table public.empresas add constraint empresas_permiso_check check (permiso in ('usuario','administrador'));
  end if;
  -- Suscripción: las empresas que ya existían quedan activas (solo la primera vez que se crea la columna)
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'empresas' and column_name = 'suscripcion_activa') then
    alter table public.empresas add column suscripcion_activa boolean not null default false;
    update public.empresas set suscripcion_activa = true;
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'empresas' and column_name = 'origen') then
    alter table public.empresas add column origen text not null default 'admin' check (origen in ('admin','prueba'));
  end if;
  -- Es cliente de la asesoría: las empresas que ya existían quedan como clientes (conservan su permiso)
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'empresas' and column_name = 'es_cliente') then
    alter table public.empresas add column es_cliente boolean not null default true;
    -- solo la primera vez: las cuentas de prueba son suscriptoras (luego lo decide el administrador)
    execute 'update public.empresas set es_cliente = false where origen = ''prueba''';
  end if;
  -- TIPO DE CUENTA: cliente | suscriptor | prueba. Es el campo que manda; es_cliente y suscripcion_activa
  -- se mantienen sincronizados (trigger de la sección 4) solo por compatibilidad.
  -- La primera vez se toma de las casillas que ya existían: es cliente → cliente;
  -- no es cliente con suscripción → suscriptor; no es cliente sin suscripción → prueba.
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'empresas' and column_name = 'tipo_cuenta') then
    alter table public.empresas add column tipo_cuenta text not null default 'cliente'
      check (tipo_cuenta in ('cliente','suscriptor','prueba'));
    execute 'update public.empresas set tipo_cuenta = case when es_cliente then ''cliente''
                                                           when suscripcion_activa then ''suscriptor''
                                                           else ''prueba'' end';
  end if;
end $$;

-- ---------------------------------------------------------------------
--  MATRIZ DE PERMISOS (por tipo de cuenta)
--                                         Admin   PRUEBA   CLIENTE             SUSCRIPTOR
--                                                          usuario   admin.
--   Límite de trabajadores                  —     máx. 2   sin límite          sin límite
--   Agregar / editar trabajadores           sí      sí       sí        sí        sí
--   Eliminar trabajadores, datos empresa    sí      sí       no        sí        sí
--   Prestadores de 4ta (honorarios)         sí      sí       no        sí        sí
--   CÁLCULO DE PLANILLA (tabla periodos:    sí      sí       NO        sí        sí
--   Dctos., ajustes, carga masiva, generar)
--   Parámetros, empresas, tipo de cuenta,   sí      no       no        no        no
--   permisos
--
--   CLIENTE: vale el permiso que elige el administrador ("usuario" o "administrador").
--   SUSCRIPTOR y PRUEBA: siempre "administrador" (la prueba conserva los permisos de la demo).
-- ---------------------------------------------------------------------
create or replace function public.permiso_efectivo(p_empresa text)
returns text language sql stable security definer set search_path = public as $$
  select case when e.tipo_cuenta = 'cliente' then coalesce(e.permiso, 'usuario') else 'administrador' end
    from public.empresas e where e.id = p_empresa
$$;

-- ¿Puede gestionar la empresa? (eliminar trabajadores, datos de la empresa, honorarios 4ta)
-- Administrador, o representante cuyo permiso efectivo es "administrador"
create or replace function public.puede_gestionar(p_empresa text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin()
      or (p_empresa = public.mi_empresa() and public.permiso_efectivo(p_empresa) = 'administrador')
$$;

-- ¿Puede agregar y editar trabajadores? Administrador, o cualquier representante en su propia empresa
create or replace function public.puede_editar_trabajadores(p_empresa text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or (p_empresa is not null and p_empresa = public.mi_empresa())
$$;

-- ¿Puede procesar el cálculo de la planilla (tabla periodos)? Administrador, o representante con permiso
-- efectivo "administrador" (cliente con perfil Administrador, o suscriptor). El perfil "usuario", nunca.
create or replace function public.puede_procesar_planilla(p_empresa text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin()
      or (p_empresa = public.mi_empresa() and public.permiso_efectivo(p_empresa) = 'administrador')
$$;

-- ---------------------------------------------------------------------
--  2. EL REPRESENTANTE CON PERMISO ACTUALIZA RUBRO, DIRECCIÓN Y UBICACIÓN
--     (si tu base ya tiene esta función, se conserva la tuya)
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'emp_actualizar_datos') then
    execute $f$
      create function public.emp_actualizar_datos(p_rubro text, p_direccion text, p_departamento text,
                                                  p_provincia text, p_distrito text, p_ciudad text)
      returns void language plpgsql security definer set search_path = public as $b$
      begin
        if public.mi_empresa() is null or not public.puede_gestionar(public.mi_empresa()) then
          raise exception 'No autorizado';
        end if;
        update public.empresas
           set rubro = coalesce(p_rubro, ''), direccion = coalesce(p_direccion, ''), departamento = coalesce(p_departamento, ''),
               provincia = coalesce(p_provincia, ''), distrito = coalesce(p_distrito, ''), ciudad = coalesce(p_ciudad, '')
         where id = public.mi_empresa();
      end $b$;
    $f$;
    execute 'revoke execute on function public.emp_actualizar_datos(text,text,text,text,text,text) from public, anon';
    execute 'grant execute on function public.emp_actualizar_datos(text,text,text,text,text,text) to authenticated';
  end if;
end $$;

-- ---------------------------------------------------------------------
--  3. ESCRITURA DE REPRESENTANTES
--     Trabajadores: todo representante agrega y edita los de su empresa (también por carga masiva);
--                   eliminar requiere permiso efectivo "administrador".
--     Datos del mes / cálculo de planilla (periodos): administrador y representantes con permiso "administrador".
-- ---------------------------------------------------------------------
drop policy if exists trab_rep_insertar on public.trabajadores;
drop policy if exists trab_rep_editar   on public.trabajadores;
drop policy if exists trab_rep_borrar   on public.trabajadores;
create policy trab_rep_insertar on public.trabajadores for insert to authenticated with check (public.puede_editar_trabajadores(empresa_id));
create policy trab_rep_editar   on public.trabajadores for update to authenticated using (public.puede_editar_trabajadores(empresa_id)) with check (public.puede_editar_trabajadores(empresa_id));
create policy trab_rep_borrar   on public.trabajadores for delete to authenticated using (public.puede_gestionar(empresa_id));

drop policy if exists per_rep_insertar on public.periodos;
drop policy if exists per_rep_editar   on public.periodos;
drop policy if exists per_rep_borrar   on public.periodos;
create policy per_rep_insertar on public.periodos for insert to authenticated with check (public.puede_procesar_planilla(empresa_id));
create policy per_rep_editar   on public.periodos for update to authenticated using (public.puede_procesar_planilla(empresa_id)) with check (public.puede_procesar_planilla(empresa_id));
create policy per_rep_borrar   on public.periodos for delete to authenticated using (public.puede_procesar_planilla(empresa_id));

-- Candados (RESTRICTIVE): se cumplen SIEMPRE, aunque tu base tenga otras reglas más amplias creadas antes.
-- · Nadie escribe trabajadores de otra empresa.
-- · El perfil "usuario" no puede modificar el cálculo de la planilla por ninguna regla antigua.
drop policy if exists trab_candado_ins on public.trabajadores;
drop policy if exists trab_candado_upd on public.trabajadores;
drop policy if exists trab_candado_del on public.trabajadores;
create policy trab_candado_ins on public.trabajadores as restrictive for insert to authenticated with check (public.puede_editar_trabajadores(empresa_id));
create policy trab_candado_upd on public.trabajadores as restrictive for update to authenticated using (public.puede_editar_trabajadores(empresa_id)) with check (public.puede_editar_trabajadores(empresa_id));
create policy trab_candado_del on public.trabajadores as restrictive for delete to authenticated using (public.puede_gestionar(empresa_id));

drop policy if exists per_candado_ins on public.periodos;
drop policy if exists per_candado_upd on public.periodos;
drop policy if exists per_candado_del on public.periodos;
create policy per_candado_ins on public.periodos as restrictive for insert to authenticated with check (public.puede_procesar_planilla(empresa_id));
create policy per_candado_upd on public.periodos as restrictive for update to authenticated using (public.puede_procesar_planilla(empresa_id)) with check (public.puede_procesar_planilla(empresa_id));
create policy per_candado_del on public.periodos as restrictive for delete to authenticated using (public.puede_procesar_planilla(empresa_id));

-- Parámetros del sistema (RMV, UIT, EsSalud, ONP, AFP, regímenes, conceptos): solo el administrador general
drop policy if exists aj_candado_ins on public.ajustes;
drop policy if exists aj_candado_upd on public.ajustes;
drop policy if exists aj_candado_del on public.ajustes;
create policy aj_candado_ins on public.ajustes as restrictive for insert to authenticated with check (public.is_admin());
create policy aj_candado_upd on public.ajustes as restrictive for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy aj_candado_del on public.ajustes as restrictive for delete to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
--  4. TIPOS DE CUENTA: PRUEBA, CLIENTE, SUSCRIPTOR
-- ---------------------------------------------------------------------
-- Solo el administrador cambia el tipo de cuenta, el origen o el permiso de una empresa.
-- Además mantiene es_cliente y suscripcion_activa sincronizados con tipo_cuenta.
create or replace function public.tg_empresa_suscripcion()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Pasan: el administrador, y los cambios hechos directo en la base (SQL Editor), que no llegan por la API de la app.
  -- Las peticiones de la app (incluidas las funciones como registrar_prueba) llegan con session_user = 'authenticator'.
  if not (public.is_admin() or session_user <> 'authenticator') then
    if tg_op = 'INSERT' then
      new.tipo_cuenta := 'prueba';     -- un alta que no hace el administrador (registro propio) siempre es de prueba
    elsif new.tipo_cuenta is distinct from old.tipo_cuenta or new.origen is distinct from old.origen
       or new.permiso is distinct from old.permiso then
      raise exception 'Solo el administrador puede cambiar el tipo de cuenta o el permiso de una empresa';
    end if;
  end if;
  new.es_cliente := (new.tipo_cuenta = 'cliente');
  new.suscripcion_activa := (new.tipo_cuenta <> 'prueba');
  return new;
end $$;
drop trigger if exists empresa_suscripcion on public.empresas;
create trigger empresa_suscripcion before insert or update on public.empresas
  for each row execute function public.tg_empresa_suscripcion();

-- Cuenta de PRUEBA: máximo 2 trabajadores registrados (activos y cesados). Cliente y suscriptor: sin límite.
-- Editar uno existente no cuenta. También aplica a la carga masiva: el trigger se ejecuta fila por fila.
create or replace function public.tg_limite_trabajadores()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_admin() then return new; end if;
  if exists (select 1 from public.trabajadores where id = new.id) then return new; end if;
  if coalesce((select tipo_cuenta from public.empresas where id = new.empresa_id), 'prueba') <> 'prueba' then return new; end if;
  if (select count(*) from public.trabajadores where empresa_id = new.empresa_id) >= 2 then
    raise exception 'LIMITE_PRUEBA: tu cuenta de prueba permite registrar hasta 2 trabajadores. Para registrar más, contacta al administrador.';
  end if;
  return new;
end $$;
drop trigger if exists limite_trabajadores on public.trabajadores;
create trigger limite_trabajadores before insert on public.trabajadores
  for each row execute function public.tg_limite_trabajadores();

-- Dígito verificador del RUC (módulo 11, pesos 5-4-3-2-7-6-5-4-3-2)
create or replace function public.ruc_valido(p_ruc text)
returns boolean language plpgsql immutable as $$
declare
  w int[] := array[5,4,3,2,7,6,5,4,3,2];
  s int := 0; d int;
begin
  if p_ruc is null or p_ruc !~ '^(10|15|16|17|20)[0-9]{9}$' then return false; end if;
  for i in 1..10 loop s := s + substr(p_ruc, i, 1)::int * w[i]; end loop;
  d := 11 - (s % 11);
  if d = 10 then d := 0; elsif d = 11 then d := 1; end if;
  return d = substr(p_ruc, 11, 1)::int;
end $$;

-- Correo real de un usuario: minúsculas, formato válido y no el dominio interno de los RUC
create or replace function public.correo_valido(p_email text)
returns text language plpgsql immutable as $$
declare v text := lower(trim(coalesce(p_email, '')));
begin
  if v !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' or v like '%@empresa.planillas.pe' then
    raise exception 'Ingresa un correo electrónico válido.';
  end if;
  return v;
end $$;

-- Registro de cuentas de prueba (lo usa la pantalla de ingreso, sin iniciar sesión).
-- El correo que registra el usuario es el de su cuenta: lo usa para recuperar su contraseña.
-- Sigue ingresando con su RUC (ver login_ruc en la sección 6).
drop function if exists public.registrar_prueba(text, text, text, text);
create or replace function public.registrar_prueba(p_ruc text, p_razon text, p_regimen text, p_password text, p_email text)
returns void language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  v_ruc   text := trim(coalesce(p_ruc, ''));
  v_razon text := trim(coalesce(p_razon, ''));
  v_email text;
  v_id    text;
  v_uid   uuid;
begin
  if not public.ruc_valido(v_ruc) then
    raise exception 'El RUC no es válido. Revisa que tenga 11 dígitos y esté bien escrito.';
  end if;
  if length(v_razon) < 3 then raise exception 'Ingresa la razón social de tu empresa.'; end if;
  if p_password is null or length(p_password) < 8 then
    raise exception 'La contraseña debe tener al menos 8 caracteres.';
  end if;
  if p_regimen not in ('MICRO','PEQUENA','DL728')
     and not exists (select 1 from public.ajustes a, jsonb_array_elements(a.data->'regimenes') r
                      where a.clave = 'config' and r->>'id' = p_regimen) then
    raise exception 'Elige un régimen laboral válido.';
  end if;
  v_email := public.correo_valido(p_email);
  if exists (select 1 from public.empresas where ruc = v_ruc) or exists (select 1 from auth.users where email = public.rep_email(v_ruc)) then
    raise exception 'Este RUC ya tiene una cuenta. Si es tu empresa y no puedes ingresar, contacta al administrador.';
  end if;
  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'Ese correo ya está registrado en otra cuenta. Usa otro correo o recupera tu contraseña.';
  end if;

  v_id := 'p' || substr(md5(gen_random_uuid()::text), 1, 13);
  insert into public.empresas (id, ruc, razon, direccion, regimen_id, permiso, rubro, ciudad, departamento, provincia, distrito, origen, tipo_cuenta)
  values (v_id, v_ruc, v_razon, '', p_regimen, 'administrador', '', '', '', '', '', 'prueba', 'prueba');

  v_uid := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, email_change, email_change_token_new, recovery_token)
  values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_email,
          crypt(p_password, gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(),
          '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_uid, v_uid::text,
          jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true),
          'email', now(), now(), now());
  insert into public.profiles (id, role, empresa_id) values (v_uid, 'rep', v_id);
end $$;

revoke execute on function public.registrar_prueba(text, text, text, text, text) from public;
grant  execute on function public.registrar_prueba(text, text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
--  5. RECIBOS POR HONORARIOS (prestadores de 4ta categoría)
--     Una fila por empresa y prestador (RUC del emisor); en "data" van sus datos
--     para la PLAME y el historial de sus recibos.
-- ---------------------------------------------------------------------
create table if not exists public.prestadores4ta (
  id          text primary key,
  empresa_id  text not null references public.empresas(id) on delete cascade,
  ruc         text not null,
  data        jsonb not null,
  updated_at  timestamptz not null default now(),
  unique (empresa_id, ruc)
);
create index if not exists prestadores4ta_empresa on public.prestadores4ta(empresa_id);
alter table public.prestadores4ta enable row level security;

drop policy if exists ps4_leer     on public.prestadores4ta;
drop policy if exists ps4_insertar on public.prestadores4ta;
drop policy if exists ps4_editar   on public.prestadores4ta;
drop policy if exists ps4_borrar   on public.prestadores4ta;
create policy ps4_leer     on public.prestadores4ta for select to authenticated using (public.is_admin() or empresa_id = public.mi_empresa());
create policy ps4_insertar on public.prestadores4ta for insert to authenticated with check (public.puede_gestionar(empresa_id));
create policy ps4_editar   on public.prestadores4ta for update to authenticated using (public.puede_gestionar(empresa_id)) with check (public.puede_gestionar(empresa_id));
create policy ps4_borrar   on public.prestadores4ta for delete to authenticated using (public.puede_gestionar(empresa_id));

revoke all on public.prestadores4ta from anon;
grant select, insert, update, delete on public.prestadores4ta to authenticated;

-- Cuenta de PRUEBA: máximo 2 prestadores por empresa y 2 recibos por prestador. Cliente y suscriptor: sin límite.
-- Se valida fila por fila, así que también frena las cargas de .txt, .xml o .pdf hechas fuera de la app.
-- Al editar, solo se bloquea si AUMENTAN los recibos por encima de 2 (una empresa que pasa de cliente a
-- prueba con más recibos puede seguir corrigiendo los existentes).
create or replace function public.tg_limite_prestadores4ta()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_nuevos int := case when jsonb_typeof(new.data->'recibos') = 'array' then jsonb_array_length(new.data->'recibos') else 0 end;
  v_antes  int := 0;
begin
  if session_user <> 'authenticator' or public.is_admin() then return new; end if;
  if coalesce((select tipo_cuenta from public.empresas where id = new.empresa_id), 'prueba') <> 'prueba' then return new; end if;
  if tg_op = 'INSERT' then
    -- Un upsert de un prestador existente pasa primero por aquí: se compara con lo que ya tiene
    select case when jsonb_typeof(p.data->'recibos') = 'array' then jsonb_array_length(p.data->'recibos') else 0 end
      into v_antes from public.prestadores4ta p
     where p.id = new.id or (p.empresa_id = new.empresa_id and p.ruc = new.ruc) limit 1;
    if not found then
      v_antes := 0;
      if (select count(*) from public.prestadores4ta where empresa_id = new.empresa_id) >= 2 then
        raise exception 'LIMITE_PRUEBA: tu cuenta de prueba permite registrar hasta 2 prestadores de 4ta categoría. Para registrar más, contacta al administrador.';
      end if;
    end if;
  else
    v_antes := case when jsonb_typeof(old.data->'recibos') = 'array' then jsonb_array_length(old.data->'recibos') else 0 end;
  end if;
  if v_nuevos > 2 and v_nuevos > v_antes then
    raise exception 'LIMITE_PRUEBA: tu cuenta de prueba permite registrar hasta 2 recibos por honorarios por prestador. Para registrar más, contacta al administrador.';
  end if;
  return new;
end $$;
drop trigger if exists limite_prestadores4ta on public.prestadores4ta;
create trigger limite_prestadores4ta before insert or update on public.prestadores4ta
  for each row execute function public.tg_limite_prestadores4ta();

-- ---------------------------------------------------------------------
--  6. CORREO DE LOS USUARIOS Y RECUPERACIÓN DE CONTRASEÑA
--     El correo de la cuenta es el correo real del usuario, así Supabase le puede enviar
--     el enlace de "¿Olvidaste tu contraseña?". Los representantes siguen ingresando con su RUC.
--     Las cuentas antiguas sin correo conservan el usuario interno RUC@empresa.planillas.pe
--     hasta que el administrador o el propio usuario registren un correo.
-- ---------------------------------------------------------------------

-- Intentos fallidos de ingreso con RUC (máx. 10 cada 15 minutos por RUC)
create table if not exists public.intentos_login (
  ruc     text primary key,
  fallos  int not null default 0,
  desde   timestamptz not null default now()
);
alter table public.intentos_login enable row level security;   -- sin reglas: solo lo usan las funciones
revoke all on public.intentos_login from anon, authenticated;

-- Ingreso con RUC: comprueba la contraseña y, solo si es correcta, devuelve el correo de la cuenta
-- para que la app inicie la sesión. Así no se puede averiguar el correo de nadie con solo su RUC.
create or replace function public.login_ruc(p_ruc text, p_password text)
returns text language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  v_ruc   text := trim(coalesce(p_ruc, ''));
  v_email text;
  v_hash  text;
  v_i     public.intentos_login%rowtype;
begin
  select * into v_i from public.intentos_login where ruc = v_ruc;
  if found and v_i.fallos >= 10 and v_i.desde > now() - interval '15 minutes' then
    raise exception 'Demasiados intentos fallidos. Espera 15 minutos y vuelve a intentarlo.';
  end if;
  select u.email, u.encrypted_password into v_email, v_hash
    from public.profiles p
    join public.empresas e on e.id = p.empresa_id
    join auth.users u on u.id = p.id
   where p.role = 'rep' and e.ruc = v_ruc;
  if v_hash is null or p_password is null or extensions.crypt(p_password, v_hash) <> v_hash then
    insert into public.intentos_login as t (ruc, fallos, desde) values (v_ruc, 1, now())
    on conflict (ruc) do update
      set fallos = case when t.desde < now() - interval '15 minutes' then 1 else t.fallos + 1 end,
          desde  = case when t.desde < now() - interval '15 minutes' then now() else t.desde end;
    return null;
  end if;
  delete from public.intentos_login where ruc = v_ruc;
  return v_email;
end $$;
revoke execute on function public.login_ruc(text, text) from public;
grant  execute on function public.login_ruc(text, text) to anon, authenticated;

-- Cambia el correo de la cuenta del propio usuario (Mi cuenta)
create or replace function public.cambiar_mi_correo(p_email text)
returns void language plpgsql security definer set search_path = public, auth as $$
declare v text;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;
  v := public.correo_valido(p_email);
  if exists (select 1 from auth.users where lower(email) = v and id <> auth.uid()) then
    raise exception 'Ese correo ya está registrado en otra cuenta.';
  end if;
  update auth.users set email = v, updated_at = now() where id = auth.uid();
  update auth.identities set identity_data = identity_data || jsonb_build_object('email', v)
   where user_id = auth.uid() and provider = 'email';
end $$;
revoke execute on function public.cambiar_mi_correo(text) from public, anon;
grant  execute on function public.cambiar_mi_correo(text) to authenticated;

-- Correo registrado del representante de una empresa (solo administrador; vacío si no tiene)
create or replace function public.admin_correo_rep(p_empresa text)
returns text language plpgsql security definer set search_path = public, auth as $$
declare v text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select u.email into v from public.profiles p join auth.users u on u.id = p.id
   where p.empresa_id = p_empresa and p.role = 'rep';
  return case when v like '%@empresa.planillas.pe' then '' else coalesce(v, '') end;
end $$;
revoke execute on function public.admin_correo_rep(text) from public, anon;
grant  execute on function public.admin_correo_rep(text) to authenticated;

-- Crear acceso / cambiar contraseña del representante (solo administrador), ahora con correo opcional.
-- Reemplaza a la versión de supabase.sql: al cambiar la contraseña ya no se pisa un correo real.
drop function if exists public.admin_set_rep_password(text, text);
create or replace function public.admin_set_rep_password(p_empresa text, p_password text, p_email text default null)
returns void language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  v_ruc   text;
  v_email text;
  v_uid   uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_password is null or length(p_password) < 8 then
    raise exception 'La contraseña debe tener al menos 8 caracteres';
  end if;
  select ruc into v_ruc from public.empresas where id = p_empresa;
  if v_ruc is null then raise exception 'Empresa no encontrada'; end if;
  v_email := case when nullif(trim(coalesce(p_email, '')), '') is null then null else public.correo_valido(p_email) end;

  select id into v_uid from public.profiles where empresa_id = p_empresa and role = 'rep';
  if v_email is not null and exists (select 1 from auth.users where lower(email) = v_email and id is distinct from v_uid) then
    raise exception 'Ese correo ya está registrado en otra cuenta.';
  end if;

  if v_uid is null then
    v_email := coalesce(v_email, public.rep_email(v_ruc));
    if exists (select 1 from auth.users where email = public.rep_email(v_ruc)) then
      raise exception 'Ya existe un usuario con ese RUC';
    end if;
    v_uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, email_change, email_change_token_new, recovery_token)
    values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_email,
            crypt(p_password, gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(),
            '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_uid, v_uid::text,
            jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true),
            'email', now(), now(), now());
    insert into public.profiles (id, role, empresa_id) values (v_uid, 'rep', p_empresa);
  else
    update auth.users
       set encrypted_password = crypt(p_password, gen_salt('bf')),
           email = coalesce(v_email, email),
           updated_at = now()
     where id = v_uid;
    if v_email is not null then
      update auth.identities set identity_data = identity_data || jsonb_build_object('email', v_email)
       where user_id = v_uid and provider = 'email';
    end if;
  end if;
end $$;
revoke execute on function public.admin_set_rep_password(text, text, text) from public, anon;
grant  execute on function public.admin_set_rep_password(text, text, text) to authenticated;

-- Si cambia el RUC de una empresa, solo se actualiza el usuario interno (RUC@empresa.planillas.pe);
-- un correo real registrado se conserva. El ingreso con el RUC nuevo funciona igual (login_ruc).
create or replace function public.tg_empresa_ruc()
returns trigger language plpgsql security definer set search_path = public, auth as $$
begin
  if new.ruc <> old.ruc then
    update auth.users set email = public.rep_email(new.ruc), updated_at = now()
     where id in (select id from public.profiles where empresa_id = new.id and role = 'rep')
       and email like '%@empresa.planillas.pe';
    update auth.identities set identity_data = identity_data || jsonb_build_object('email', public.rep_email(new.ruc))
     where user_id in (select id from public.profiles where empresa_id = new.id and role = 'rep')
       and identity_data->>'email' like '%@empresa.planillas.pe';
  end if;
  return new;
end $$;

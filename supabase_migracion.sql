-- =====================================================================
--  PLANILLAS PERÚ – Migración única (noviembre 2026)
--  Ejecútala UNA vez en: Supabase → SQL Editor → New query → Run,
--  después de supabase.sql. Se puede volver a ejecutar sin problema: no borra datos.
--
--  Incluye todo lo que necesita la versión actual de index.html:
--   1. Columnas de empresas (permiso, rubro, ubicación, suscripción, origen).
--   2. Función emp_actualizar_datos (el rep. con permiso edita rubro y dirección).
--   3. Escritura de representantes: trabajadores (todo representante, incluye la carga masiva) y
--      periodos = cálculo de planilla (administrador y representantes con permiso "administrador").
--   4. Cuentas de prueba: registro con RUC y límite de 2 trabajadores sin suscripción.
--   5. Recibos por honorarios (prestadores de 4ta categoría).
--   Matriz de permisos con «Es cliente» (ver el bloque MATRIZ DE PERMISOS) y candados que impiden que
--   el perfil "usuario" modifique el cálculo de la planilla o que un representante cambie parámetros.
--   «Es cliente» y «Suscripción activa» se editan desde la lista de Empresas: solo el administrador
--   puede guardarlos (regla empresas_admin + trigger empresa_suscripcion).
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
  end if;
end $$;
update public.empresas set es_cliente = false where origen = 'prueba' and es_cliente;   -- cuentas de prueba = suscriptores (se ejecuta desde el SQL Editor)

-- ---------------------------------------------------------------------
--  MATRIZ DE PERMISOS
--                                         Admin   Rep. CLIENTE          Rep. SUSCRIPTOR
--                                                 usuario   admin.     (incluye prueba)
--   Agregar / editar trabajadores           sí      sí        sí         sí (prueba: máx. 2)
--   Eliminar trabajadores, datos empresa,   sí      no        sí         sí
--   honorarios 4ta
--   CÁLCULO DE PLANILLA (tabla periodos:    sí      NO        sí         sí
--   Dctos., ajustes, carga masiva, generar)
--   Parámetros, empresas, es_cliente,       sí      no        no         no
--   suscripción, permisos
--
--   En una empresa CLIENTE (es_cliente = true) vale el permiso que elige el administrador.
--   Una empresa SUSCRIPTORA (es_cliente = false) maneja su cuenta con permiso "administrador".
-- ---------------------------------------------------------------------
create or replace function public.permiso_efectivo(p_empresa text)
returns text language sql stable security definer set search_path = public as $$
  select case when not e.es_cliente then 'administrador' else coalesce(e.permiso, 'usuario') end
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
--  4. CUENTAS DE PRUEBA Y SUSCRIPCIÓN
-- ---------------------------------------------------------------------
-- Solo el administrador cambia la suscripción, el origen, «Es cliente» o el permiso de una empresa
create or replace function public.tg_empresa_suscripcion()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Pasan: el administrador, y los cambios hechos directo en la base (SQL Editor), que no llegan por la API de la app.
  -- Las peticiones de la app (incluidas las funciones como registrar_prueba) llegan con session_user = 'authenticator'.
  if public.is_admin() or session_user <> 'authenticator' then return new; end if;
  if tg_op = 'INSERT' then
    new.suscripcion_activa := false;   -- un alta que no hace el administrador (registro de prueba) nunca nace con suscripción
    new.es_cliente := false;           -- ni como cliente de la asesoría
  elsif new.suscripcion_activa is distinct from old.suscripcion_activa or new.origen is distinct from old.origen
     or new.es_cliente is distinct from old.es_cliente or new.permiso is distinct from old.permiso then
    raise exception 'Solo el administrador puede cambiar la suscripción, el permiso o la condición de cliente de una empresa';
  end if;
  return new;
end $$;
drop trigger if exists empresa_suscripcion on public.empresas;
create trigger empresa_suscripcion before insert or update on public.empresas
  for each row execute function public.tg_empresa_suscripcion();

-- Sin suscripción: máximo 2 trabajadores registrados (activos y cesados). Editar uno existente no cuenta.
-- También aplica a la carga masiva: el trigger se ejecuta fila por fila.
create or replace function public.tg_limite_trabajadores()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_admin() then return new; end if;
  if exists (select 1 from public.trabajadores where id = new.id) then return new; end if;
  if coalesce((select suscripcion_activa from public.empresas where id = new.empresa_id), false) then return new; end if;
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

-- Registro de cuentas de prueba (lo usa la pantalla de ingreso, sin iniciar sesión)
create or replace function public.registrar_prueba(p_ruc text, p_razon text, p_regimen text, p_password text)
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
  v_email := public.rep_email(v_ruc);
  if exists (select 1 from public.empresas where ruc = v_ruc) or exists (select 1 from auth.users where email = v_email) then
    raise exception 'Este RUC ya tiene una cuenta. Si es tu empresa y no puedes ingresar, contacta al administrador.';
  end if;

  v_id := 'p' || substr(md5(gen_random_uuid()::text), 1, 13);
  insert into public.empresas (id, ruc, razon, direccion, regimen_id, permiso, rubro, ciudad, departamento, provincia, distrito, suscripcion_activa, origen, es_cliente)
  values (v_id, v_ruc, v_razon, '', p_regimen, 'administrador', '', '', '', '', '', false, 'prueba', false);

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

revoke execute on function public.registrar_prueba(text, text, text, text) from public;
grant  execute on function public.registrar_prueba(text, text, text, text) to anon, authenticated;

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

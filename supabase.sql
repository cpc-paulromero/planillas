-- =====================================================================
--  PLANILLAS PERÚ – Script de base de datos para Supabase
--  Ejecútalo UNA vez en: Supabase → SQL Editor → New query → Run
--  Crea las tablas, las reglas de seguridad (RLS) y las funciones
--  para gestionar el acceso de los representantes legales.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- Dominio interno con el que se arma el usuario del representante legal:
--   RUC 20123456789  ->  20123456789@empresa.planillas.pe
-- (no se envían correos; es solo el identificador de inicio de sesión)
create or replace function public.rep_email(p_ruc text)
returns text language sql immutable as $$
  select p_ruc || '@empresa.planillas.pe'
$$;

-- ---------------------------------------------------------------------
--  TABLAS
-- ---------------------------------------------------------------------
create table if not exists public.empresas (
  id          text primary key,
  ruc         text not null unique check (ruc ~ '^(10|15|16|17|20)[0-9]{9}$'),
  razon       text not null,
  direccion   text not null default '',
  regimen_id  text not null,
  created_at  timestamptz not null default now()
);

create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        text not null check (role in ('admin','rep')),
  empresa_id  text references public.empresas(id) on delete cascade,
  created_at  timestamptz not null default now(),
  check ((role = 'admin' and empresa_id is null) or (role = 'rep' and empresa_id is not null))
);
create unique index if not exists profiles_un_rep_por_empresa on public.profiles(empresa_id) where role = 'rep';

create table if not exists public.trabajadores (
  id          text primary key,
  empresa_id  text not null references public.empresas(id) on delete restrict,
  data        jsonb not null,
  updated_at  timestamptz not null default now()
);
create index if not exists trabajadores_empresa on public.trabajadores(empresa_id);

create table if not exists public.periodos (
  empresa_id  text not null references public.empresas(id) on delete cascade,
  periodo     text not null check (periodo ~ '^[0-9]{4}-[0-9]{2}$'),
  data        jsonb not null default '{}'::jsonb,
  primary key (empresa_id, periodo)
);

-- Parámetros generales: config (RMV, UIT, regímenes…), afps, conceptos
create table if not exists public.ajustes (
  clave  text primary key check (clave in ('config','afps','conceptos')),
  data   jsonb not null
);

-- ---------------------------------------------------------------------
--  FUNCIONES DE APOYO PARA LAS REGLAS
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
$$;

create or replace function public.mi_empresa()
returns text language sql stable security definer set search_path = public as $$
  select empresa_id from public.profiles where id = auth.uid() and role = 'rep'
$$;

-- ---------------------------------------------------------------------
--  SEGURIDAD A NIVEL DE FILA (RLS)
--  Administrador: lee y modifica todo.
--  Representante legal: solo LEE los datos de su empresa.
-- ---------------------------------------------------------------------
alter table public.empresas     enable row level security;
alter table public.profiles     enable row level security;
alter table public.trabajadores enable row level security;
alter table public.periodos     enable row level security;
alter table public.ajustes      enable row level security;

drop policy if exists empresas_admin on public.empresas;
drop policy if exists empresas_rep   on public.empresas;
create policy empresas_admin on public.empresas for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy empresas_rep   on public.empresas for select to authenticated using (id = public.mi_empresa());

drop policy if exists trab_admin on public.trabajadores;
drop policy if exists trab_rep   on public.trabajadores;
create policy trab_admin on public.trabajadores for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy trab_rep   on public.trabajadores for select to authenticated using (empresa_id = public.mi_empresa());

drop policy if exists per_admin on public.periodos;
drop policy if exists per_rep   on public.periodos;
create policy per_admin on public.periodos for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy per_rep   on public.periodos for select to authenticated using (empresa_id = public.mi_empresa());

drop policy if exists aj_admin on public.ajustes;
drop policy if exists aj_leer  on public.ajustes;
create policy aj_admin on public.ajustes for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy aj_leer  on public.ajustes for select to authenticated using (true);

-- profiles: cada uno ve el suyo; el admin ve todos. Nadie escribe directo
-- (solo a través de las funciones de abajo).
drop policy if exists prof_leer on public.profiles;
create policy prof_leer on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());

revoke all on public.empresas, public.profiles, public.trabajadores, public.periodos, public.ajustes from anon;

-- ---------------------------------------------------------------------
--  GESTIÓN DE ACCESOS DE REPRESENTANTES LEGALES (solo administrador)
-- ---------------------------------------------------------------------

-- Crea el acceso del representante legal (usuario = RUC) o le asigna una nueva contraseña
create or replace function public.admin_set_rep_password(p_empresa text, p_password text)
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
  v_email := public.rep_email(v_ruc);

  select id into v_uid from public.profiles where empresa_id = p_empresa and role = 'rep';

  if v_uid is null then
    if exists (select 1 from auth.users where email = v_email) then
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
       set encrypted_password = crypt(p_password, gen_salt('bf')), email = v_email, updated_at = now()
     where id = v_uid;
  end if;
end $$;

-- Elimina el acceso del representante legal de una empresa
create or replace function public.admin_quitar_rep(p_empresa text)
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  delete from auth.users where id in (select id from public.profiles where empresa_id = p_empresa and role = 'rep');
end $$;

-- Si cambia el RUC de una empresa, su representante pasa a ingresar con el nuevo RUC
create or replace function public.tg_empresa_ruc()
returns trigger language plpgsql security definer set search_path = public, auth as $$
begin
  if new.ruc <> old.ruc then
    update auth.users set email = public.rep_email(new.ruc), updated_at = now()
     where id in (select id from public.profiles where empresa_id = new.id and role = 'rep');
    update auth.identities set identity_data = identity_data || jsonb_build_object('email', public.rep_email(new.ruc))
     where user_id in (select id from public.profiles where empresa_id = new.id and role = 'rep');
  end if;
  return new;
end $$;
drop trigger if exists empresa_ruc on public.empresas;
create trigger empresa_ruc after update of ruc on public.empresas for each row execute function public.tg_empresa_ruc();

-- Al eliminar una empresa se elimina también el usuario de su representante
create or replace function public.tg_empresa_borrar()
returns trigger language plpgsql security definer set search_path = public, auth as $$
begin
  delete from auth.users where id in (select id from public.profiles where empresa_id = old.id and role = 'rep');
  return old;
end $$;
drop trigger if exists empresa_borrar on public.empresas;
create trigger empresa_borrar before delete on public.empresas for each row execute function public.tg_empresa_borrar();

revoke execute on function public.admin_set_rep_password(text, text) from public, anon;
revoke execute on function public.admin_quitar_rep(text) from public, anon;
grant  execute on function public.admin_set_rep_password(text, text) to authenticated;
grant  execute on function public.admin_quitar_rep(text) to authenticated;

-- =====================================================================
--  PASO FINAL: conviértete en administrador
--  1) Supabase → Authentication → Users → "Add user" → "Create new user"
--     (tu correo + tu contraseña, marca "Auto Confirm User").
--  2) Cambia el correo de abajo por el tuyo y ejecuta SOLO esta línea:
--
--  insert into public.profiles (id, role) select id, 'admin' from auth.users where email = 'TU_CORREO@ejemplo.com';
-- =====================================================================

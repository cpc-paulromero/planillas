# Planillas Perú – Guía de instalación (GitHub Pages + Supabase)

La app tiene 3 archivos:

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La aplicación |
| `config.js` | Conexión con tu proyecto de Supabase (lo editas tú) |
| `supabase.sql` | Crea la base de datos y las reglas de seguridad (se ejecuta una sola vez en Supabase) |

Quién puede hacer qué:

- **Administrador (tú):** ingresa con su correo y contraseña. Ve y modifica todas las empresas, y crea o cambia las contraseñas de los representantes legales.
- **Representante legal:** ingresa con el **RUC** de su empresa y la contraseña que le diste. Solo **ve** su empresa (trabajadores, planilla y beneficios), **descarga boletas en PDF** y la planilla en Excel, y puede cambiar su contraseña. No puede modificar nada. Esto lo controla el servidor, no solo la pantalla.

---

## Paso 1 – Crear el proyecto en Supabase

1. Entra a <https://supabase.com>, crea una cuenta y luego **New project**. Elige la región más cercana (por ejemplo *South America (São Paulo)*) y guarda la contraseña de la base de datos.
2. Cuando el proyecto esté listo, abre **SQL Editor**, pulsa **New query**, pega **todo** el contenido de `supabase.sql` y pulsa **Run**. Debe terminar con *Success*.
3. Crea tu usuario de administrador:
   - Ve a **Authentication → Users → Add user → Create new user**.
   - Escribe tu correo y una contraseña segura, y marca **Auto Confirm User**.
4. Vuelve a **SQL Editor** y ejecuta esta línea, cambiando el correo por el tuyo:

   ```sql
   insert into public.profiles (id, role) select id, 'admin' from auth.users where email = 'TU_CORREO@ejemplo.com';
   ```

5. Recomendado: en **Authentication → Sign In / Providers**, desactiva **Allow new users to sign up**. Así nadie puede registrarse solo. Aunque alguien se registrara, no vería ningún dato porque no tiene perfil asignado.

## Paso 2 – Configurar `config.js`

En Supabase ve a **Project Settings → API** (o **Data API**) y copia:

- **Project URL**, por ejemplo `https://abcdxyz.supabase.co`
- **anon public key**: es una clave larga que empieza con `eyJ…` (en proyectos nuevos puede llamarse *publishable key*)

Pégalas en `config.js`:

```js
window.PLANILLAS_CONFIG = {
  SUPABASE_URL: "https://abcdxyz.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOi..."
};
```

> La clave *anon/publishable* puede ser pública: la seguridad la dan las reglas del `supabase.sql`.
> **Nunca** pongas la clave `service_role` / *secret* en este archivo.

## Paso 3 – Publicar en GitHub Pages

1. Entra a <https://github.com>, crea una cuenta y luego **New repository**. Ponle un nombre como `planillas` y créalo.
2. En el repositorio pulsa **Add file → Upload files**, arrastra `index.html`, `config.js` y `README.md`, y pulsa **Commit changes**.
   - `supabase.sql` no necesita subirse, pero puedes hacerlo para tenerlo guardado.
3. Ve a **Settings → Pages**. En **Source** elige *Deploy from a branch*, luego la rama `main` y la carpeta `/ (root)`, y pulsa **Save**.
4. En 1 o 2 minutos tu app estará en `https://TU-USUARIO.github.io/planillas/`.

> Si el repositorio es **público**, cualquiera puede ver el código, pero **no los datos**: esos están en Supabase y protegidos por contraseña.
> GitHub Pages con repositorio privado requiere un plan de pago de GitHub.

## Paso 4 – Primer uso

1. Abre la dirección de tu app e ingresa con tu **correo** de administrador.
2. **Si tenías datos en la versión anterior:** en la versión anterior ve a *Parámetros → Descargar respaldo*. Luego, en la nueva, ve a *Parámetros → Restaurar / importar respaldo*. Si alguna empresa no tenía RUC, la app te lo pedirá antes de importar.
3. Ve a **Empresas** y, en la empresa que quieras, pulsa **Crear acceso**. Escribe o genera una contraseña y pulsa **Crear acceso**. La app muestra los datos para enviárselos al representante legal (RUC + contraseña + dirección web).
4. El representante entra con su **RUC** y esa contraseña. Desde **Mi cuenta** puede cambiarla.

## Gestión de accesos

- **Olvidó su contraseña:** ve a *Empresas → Cambiar contraseña* y asígnale una nueva.
- **Quitar el acceso:** ve a *Empresas → Cambiar contraseña → Quitar acceso*.
- **Si cambias el RUC de una empresa**, su representante pasa a ingresar con el RUC nuevo, con la misma contraseña.
- **Si eliminas una empresa**, se elimina también el acceso de su representante.
- Tú también puedes cambiar tu contraseña de administrador en **Mi cuenta**.

## Actualizar la app

Cuando recibas una nueva versión de `index.html`, súbela de nuevo al repositorio con **Add file → Upload files** y reemplaza el archivo anterior. Tus datos no se pierden porque están en Supabase.

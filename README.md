# PlanillaPRo – Planillas Perú

Aplicación web para llevar la planilla de empresas peruanas. Calcula sueldos, descuentos de AFP u ONP, aportes a EsSalud, boletas de pago, CTS, gratificaciones, vacaciones e indemnizaciones según el régimen laboral de cada empresa.

Se publica gratis en **GitHub Pages** y guarda los datos en **Supabase**.

## Archivos del proyecto

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La aplicación completa: pantallas, diseño y fórmulas de cálculo |
| `config.js` | Conexión con tu proyecto de Supabase (lo editas tú) |
| `supabase.sql` | Crea la base de datos, las reglas de seguridad y las funciones (se ejecuta una vez en Supabase) |
| `README.md` | Esta guía |

---

## Cómo funciona

No hay un servidor propio. La app corre en el navegador de quien la usa y Supabase hace de backend.

```
GitHub Pages ──entrega index.html y config.js──▶ Navegador (la app)
                                                   │  calcula planillas, boletas y beneficios
                                                   │  genera PDF (jsPDF) y CSV
                                                   ▼
                                       Supabase (backend en la nube)
                                       ├─ Auth: usuarios y contraseñas cifradas
                                       ├─ API de datos: lecturas y escrituras
                                       ├─ Reglas RLS: cada usuario solo ve lo que le corresponde
                                       ├─ Funciones: gestión de accesos
                                       └─ Postgres: las tablas
```

- **Frontend (`index.html`):** todas las pantallas y cálculos. Usa `supabase-js` (desde jsDelivr) para conectarse a la base de datos, y `jsPDF` y `jspdf-autotable` (desde cdnjs) para las boletas en PDF.
- **Guardado:** los cambios se envían en una cola, uno por uno y en orden. Arriba se ve "Guardando…" y luego "✓ Guardado". Si cierras la pestaña con cambios pendientes, la app te avisa.
- **Backend (Supabase):** Auth verifica las contraseñas. Las reglas RLS (seguridad a nivel de fila) deciden en el servidor qué filas puede leer o modificar cada usuario, así que no basta con ocultar botones en la pantalla.
- **PDF y Excel:** se generan en el navegador y se descargan directamente, sin pasar por Supabase.

## Usuarios y permisos

Todos entran por la misma pantalla. Un **correo** identifica al administrador y un **RUC de 11 dígitos** identifica al representante legal de una empresa. Por dentro, la app convierte el RUC en el usuario `RUC@empresa.planillas.pe`; no se envían correos a esa dirección.

| Puede… | Administrador | Rep. legal con permiso "administrador" | Rep. legal ("usuario") |
|---|:-:|:-:|:-:|
| Ver todas las empresas | ✅ | – | – |
| Ver su propia empresa | ✅ | ✅ | ✅ |
| Crear, editar y eliminar empresas | ✅ | – | – |
| Editar rubro, dirección y ubicación de su empresa | ✅ | ✅ | – |
| Crear y editar trabajadores | ✅ | ✅ | ✅ |
| Eliminar trabajadores | ✅ | ✅ | – |
| Registrar faltas y descuentos (pestaña Dcto.) | ✅ | ✅ | – |
| Generar, ajustar y anular cálculos de planilla | ✅ | ✅ | – |
| Ver la planilla y los beneficios sociales | ✅ | ✅ | ✅ |
| Descargar boletas en PDF y la planilla en Excel | ✅ | ✅ | ✅ |
| Editar conceptos, AFP, regímenes y parámetros | ✅ | – | – |
| Crear, cambiar o quitar accesos de representantes | ✅ | – | – |
| Cambiar su propia contraseña | ✅ | ✅ | ✅ |

El permiso de cada representante ("usuario" o "administrador") se elige al editar su empresa.

## Pantallas

| Pestaña | Quién la ve | Qué hace |
|---|---|---|
| **Ingreso** | Todos | Inicio de sesión con correo o RUC. Muestra mensajes claros si la contraseña es incorrecta o falla la conexión. |
| **Empresas** | Administrador | Lista de empresas (RUC, razón social, régimen laboral). Crear, editar, eliminar, seleccionar la empresa activa y gestionar el acceso del representante legal. |
| **Trabajadores** | Todos | Ficha de cada trabajador: DNI, nombres, puesto, pensión (ONP o AFP), salud, remuneración, banco y cuenta. Historial de aumentos con el mes desde el que rigen. Avisa si el sueldo es menor a la RMV vigente, salvo en contratos a tiempo parcial. |
| **Planilla mensual** | Todos | Cálculo del mes por trabajador: ingresos, ONP o AFP (aporte, prima y comisión), renta de 5ta categoría, faltas, otros descuentos, neto y aportes del empleador (EsSalud, SIS, SCTR, Vida Ley, provisiones de gratificación, CTS y vacaciones). Boletas en PDF, exportación a Excel (CSV) y archivo de pagos para el banco. |
| **Dcto.** | Administrador y rep. con permiso | Hoja del mes para registrar días de vacaciones, faltas, tardanzas, adelantos y retenciones judiciales. Por cada falta sugiere descontar el día más 1/6 del descanso semanal. Se descarga en PDF. |
| **Beneficios sociales** | Todos | Por trabajador y año: gratificaciones de julio y diciembre con bonificación extraordinaria, CTS de mayo y noviembre, vacaciones y vacaciones truncas, e indemnización por despido arbitrario con su tope. Si hay fecha de cese, calcula los montos truncos. |
| **Conceptos** | Administrador | Catálogo de ingresos y descuentos adicionales. Para cada uno se indica si está afecto a EsSalud y a pensión, y si es computable para beneficios. |
| **AFP / ONP** | Administrador | Comisión sobre flujo, comisión sobre saldo, prima de seguros y aporte de cada AFP, y tasa de la ONP. |
| **Regímenes** | Administrador | Reglas de Microempresa, Pequeña empresa y D.L. 728: vacaciones, gratificación, CTS, indemnización y seguro de salud. Se pueden crear regímenes nuevos. |
| **Parámetros** | Administrador | Historial de la RMV, UIT, EsSalud, ONP, SIS, RMA, bonificación extraordinaria, Vida Ley y SCTR. Descarga y restauración de respaldos. |
| **Mi cuenta** | Todos | Cambio de contraseña. El rep. con permiso también puede editar los datos de su empresa desde aquí. |

### Valores que trae la app por defecto

Todos se pueden cambiar desde la app.

| Parámetro | Valor |
|---|---|
| RMV | S/ 1,130 desde 01/01/2025 · S/ 1,230 desde 01/10/2026 |
| UIT | S/ 5,500 |
| EsSalud | 9% |
| ONP | 13% |
| SIS (microempresa) | S/ 15 mensuales |
| RMA (tope de la prima de seguros AFP) | S/ 12,234.33 |
| Bonificación extraordinaria (Ley 30334) | 9% |
| Asignación familiar | 10% de la RMV |

| AFP | Comisión flujo | Comisión saldo | Prima de seguros | Aporte |
|---|--:|--:|--:|--:|
| AFP Habitat | 1.47% | 1.25% | 1.37% | 10% |
| AFP Integra | 1.55% | 0.78% | 1.37% | 10% |
| Prima AFP | 1.60% | 1.25% | 1.37% | 10% |
| Profuturo AFP | 1.69% | 0.68% | 1.37% | 10% |

| Régimen | Vacaciones | Gratificación | CTS | Indemnización | Salud |
|---|---|---|---|---|---|
| Microempresa (ventas ≤ 150 UIT) | 15 días | No | No | 10 RD por año, tope 90 | SIS o EsSalud |
| Pequeña empresa (ventas ≤ 1700 UIT) | 15 días | ½ sueldo | ½ | 20 RD por año, tope 120 | EsSalud |
| D.L. 728 – Mediana y gran empresa | 30 días | 1 sueldo | 1 | 45 RD por año (con fracciones), tope 360 | EsSalud |

## Base de datos

| Tabla | Qué guarda | Administrador | Representante legal |
|---|---|---|---|
| `empresas` | Una fila por empresa: RUC (único, empieza por 10, 15, 16, 17 o 20), razón social, dirección y régimen laboral | Lee y modifica todas | Solo lee la suya |
| `profiles` | Une cada usuario de Auth con su rol (`admin` o `rep`) y, si es representante, con su empresa. Cada empresa tiene como máximo un representante. | Lee todos | Solo lee el suyo |
| `trabajadores` | Una fila por trabajador. La ficha completa va en el campo `data` (JSON). | Lee y modifica todos | Lee los de su empresa |
| `periodos` | Una fila por empresa y mes (`AAAA-MM`). En `data` (JSON) guarda los datos del mes de cada trabajador: días, faltas, tardanzas, adelantos, ajustes y si el cálculo ya se generó. | Lee y modifica todos | Lee los de su empresa |
| `ajustes` | Tres filas: `config` (RMV, UIT, tasas, regímenes), `afps` y `conceptos`. Valen para todas las empresas. | Lee y modifica | Solo lee |
| `auth.users` | Tabla interna de Supabase con los usuarios y las contraseñas cifradas | Solo mediante funciones | No la ve |

Funciones y triggers:

| Nombre | Qué hace |
|---|---|
| `admin_set_rep_password(empresa, contraseña)` | Crea el acceso del representante legal o le asigna una contraseña nueva (mínimo 8 caracteres). Solo el administrador. |
| `admin_quitar_rep(empresa)` | Elimina el acceso del representante legal. Solo el administrador. |
| `is_admin()` · `mi_empresa()` | Las usan las reglas RLS para saber si el usuario es administrador y de qué empresa es representante. |
| `rep_email(ruc)` | Convierte un RUC en el usuario interno `RUC@empresa.planillas.pe`. |
| Trigger al cambiar el RUC | El representante pasa a entrar con el RUC nuevo, con la misma contraseña. |
| Trigger al eliminar una empresa | Elimina también el usuario de su representante. |

## ⚠️ Pendiente: `supabase.sql` no cubre todo lo que usa la app

La versión actual de `index.html` usa cosas que el script **no crea**. Si instalas desde cero solo con `supabase.sql`, estas funciones darán error hasta que se agreguen:

1. **Columnas de `empresas`:** `permiso` (`usuario` o `administrador`), `rubro`, `ciudad`, `departamento`, `provincia` y `distrito`. Sin ellas, guardar una empresa falla.
2. **Función `emp_actualizar_datos`:** el rep. con permiso la usa para actualizar el rubro, la dirección y la ubicación de su empresa.
3. **Reglas RLS de escritura para representantes:** el script solo deja escribir al administrador. La app espera que:
   - cualquier representante pueda crear y editar trabajadores de su empresa;
   - el rep. con permiso pueda eliminar trabajadores de su empresa y guardar sus periodos.

Si tu base de datos en Supabase ya tiene estos cambios, falta pasarlos a `supabase.sql` para que el repositorio quede completo.

---

## Instalación

### Paso 1 – Crear el proyecto en Supabase

1. Entra a <https://supabase.com>, crea una cuenta y luego **New project**. Elige la región más cercana (por ejemplo *South America (São Paulo)*) y guarda la contraseña de la base de datos.
2. Cuando el proyecto esté listo, abre **SQL Editor**, pulsa **New query**, pega **todo** el contenido de `supabase.sql` y pulsa **Run**. Debe terminar con *Success*. Revisa también la sección [Pendiente](#️-pendiente-supabasesql-no-cubre-todo-lo-que-usa-la-app).
3. Crea tu usuario de administrador:
   - Ve a **Authentication → Users → Add user → Create new user**.
   - Escribe tu correo y una contraseña segura, y marca **Auto Confirm User**.
4. Vuelve a **SQL Editor** y ejecuta esta línea, cambiando el correo por el tuyo:

   ```sql
   insert into public.profiles (id, role) select id, 'admin' from auth.users where email = 'TU_CORREO@ejemplo.com';
   ```

5. Recomendado: en **Authentication → Sign In / Providers**, desactiva **Allow new users to sign up**. Así nadie puede registrarse por su cuenta. Aunque alguien se registrara, no vería ningún dato porque no tendría perfil asignado.

### Paso 2 – Configurar `config.js`

En Supabase ve a **Project Settings → API** (o **Data API**) y copia:

- **Project URL**, por ejemplo `https://abcdxyz.supabase.co`
- **anon public key** (en proyectos nuevos se llama *publishable key* y empieza con `sb_publishable_`; en proyectos antiguos empieza con `eyJ…`)

Pégalas en `config.js`:

```js
window.PLANILLAS_CONFIG = {
  SUPABASE_URL: "https://abcdxyz.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_..."
};
```

> La clave *anon/publishable* puede ser pública: la seguridad la dan las reglas de `supabase.sql`.
> **Nunca** pongas la clave `service_role` / *secret* en este archivo.

### Paso 3 – Publicar en GitHub Pages

1. Crea un repositorio en <https://github.com>, por ejemplo `planillas`.
2. Sube `index.html`, `config.js` y `README.md`. Puedes usar **Add file → Upload files** o, si tienes Git instalado:

   ```bash
   git add index.html config.js README.md
   git commit -m "Actualizar app"
   git push
   ```

   `supabase.sql` no necesita subirse, pero conviene tenerlo guardado en el repositorio.
3. Ve a **Settings → Pages**. En **Source** elige *Deploy from a branch*, luego la rama `main` y la carpeta `/ (root)`, y pulsa **Save**.
4. En 1 o 2 minutos la app estará en `https://TU-USUARIO.github.io/planillas/`.

> Si el repositorio es **público**, cualquiera puede ver el código, pero **no los datos**: esos están en Supabase y protegidos por contraseña.
> GitHub Pages con repositorio privado requiere un plan de pago de GitHub.

### Paso 4 – Primer uso

1. Abre la dirección de tu app e ingresa con tu **correo** de administrador.
2. **Si tenías datos en una versión anterior:** en esa versión ve a *Parámetros → Descargar respaldo*. Luego, en la nueva, ve a *Parámetros → Restaurar / importar respaldo*. Si alguna empresa no tenía RUC, la app te lo pedirá antes de importar.
3. Ve a **Empresas** y, en la empresa que quieras, pulsa **Crear acceso**. Escribe o genera una contraseña y pulsa **Crear acceso**. La app muestra los datos para enviárselos al representante legal (RUC, contraseña y dirección web).
4. Si quieres que el representante también registre faltas y genere cálculos, edita la empresa y cambia su permiso a **administrador**.
5. El representante entra con su **RUC** y esa contraseña. Desde **Mi cuenta** puede cambiarla.

## Gestión de accesos

- **Olvidó su contraseña:** ve a *Empresas → Cambiar contraseña* y asígnale una nueva.
- **Quitar el acceso:** ve a *Empresas → Cambiar contraseña → Quitar acceso*.
- **Si cambias el RUC de una empresa**, su representante pasa a ingresar con el RUC nuevo y la misma contraseña.
- **Si eliminas una empresa**, se elimina también el acceso de su representante.
- Tú también puedes cambiar tu contraseña de administrador en **Mi cuenta**.

## Actualizar la app

Cuando tengas una nueva versión de `index.html`, súbela al repositorio y reemplaza el archivo anterior. Tus datos no se pierden porque están en Supabase. Si la versión nueva necesita cambios en la base de datos, ejecuta en Supabase el SQL correspondiente antes de usarla.

> Los cálculos son referenciales. Valida los casos especiales (licencias sin goce, remuneraciones variables, régimen agrario, etc.) con la normativa vigente.

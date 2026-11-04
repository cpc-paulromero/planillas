# PlanillaPRo - Perú

Aplicación web para llevar la planilla de empresas peruanas. Calcula sueldos, descuentos de AFP u ONP, aportes a EsSalud, boletas de pago, CTS, gratificaciones, vacaciones e indemnizaciones según el régimen laboral de cada empresa.

Se publica gratis en **GitHub Pages** y guarda los datos en **Supabase**.

## Archivos del proyecto

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La aplicación completa: pantallas, diseño y fórmulas de cálculo |
| `config.js` | Conexión con tu proyecto de Supabase (lo editas tú) |
| `supabase.sql` | Crea la base de datos, las reglas de seguridad y las funciones (se ejecuta una vez en Supabase) |
| `supabase_migracion.sql` | Migración única, después de `supabase.sql`: columnas de empresas, escritura de representantes, cuentas de prueba y suscripción, y recibos por honorarios. Se puede ejecutar más de una vez. |
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

| Puede… | Administrador general | Rep. legal con permiso "administrador" | Rep. legal ("usuario") |
|---|:-:|:-:|:-:|
| Ver todas las empresas | ✅ | – | – |
| Ver su propia empresa, sus trabajadores, planilla y beneficios | ✅ | ✅ | ✅ |
| Descargar boletas, planilla, AFPnet y PLAME | ✅ | ✅ | ✅ |
| Crear, editar y eliminar empresas; elegir su **tipo de cuenta** | ✅ | – | – |
| Editar rubro, dirección y ubicación de su empresa | ✅ | ✅ | – |
| Agregar y editar trabajadores (incluida la carga masiva) | ✅ | ✅ | ✅ |
| Eliminar trabajadores | ✅ | ✅ | – |
| **Cálculo de planilla:** Dctos., ajustes, carga masiva de planilla, generar y anular | ✅ | ✅ | – |
| Recibos por honorarios (Honorarios 4ta) | ✅ | ✅ | – |
| Editar conceptos, AFP, regímenes y parámetros (RMV, UIT, EsSalud, ONP…) | ✅ | – | – |
| Crear, cambiar o quitar accesos de representantes | ✅ | – | – |
| Cambiar su propia contraseña | ✅ | ✅ | ✅ |

**Permiso efectivo del representante:**
Cada empresa tiene un **tipo de cuenta**, que el administrador general elige en *Empresas*:

| Tipo de cuenta | Permiso del representante | Límite de trabajadores | Límite en Honorarios 4ta |
|---|---|---|---|
| **Cliente** (de la asesoría) | El que elige el administrador: "usuario" o "administrador" | Sin límite | Sin límite |
| **Suscriptor** | Siempre "administrador": maneja su propia cuenta, incluido el cálculo de su planilla | Sin límite | Sin límite |
| **Prueba** (quien se registra solo) | Siempre "administrador", como en la demo | **Máximo 2** (activos y cesados) | **Máximo 2 prestadores** y **2 recibos por prestador** |

Los límites de la cuenta de prueba se validan en la app y en la base de datos (triggers), así que tampoco se pueden superar con cargas masivas de .xlsx, .txt, .xml o .pdf.

Los prestadores de 4ta categoría (Honorarios 4ta) los editan el administrador general, el cliente con perfil "administrador", el suscriptor y la cuenta de prueba.

La base de datos aplica la misma matriz (`supabase_migracion.sql`). Además tiene candados que impiden que un representante "usuario" modifique el cálculo de la planilla, o que cualquier representante cambie los parámetros del sistema, aunque existan reglas antiguas más amplias.

### Cuentas de prueba y suscripción

- En la pantalla de ingreso, **Crear cuenta de prueba** permite que cualquier persona se registre con el RUC de su empresa (se valida el dígito verificador), su razón social, su régimen laboral y una contraseña.
- La cuenta queda con tipo **Prueba**: tiene los mismos accesos que un representante con permiso "administrador", pero su empresa **puede registrar como máximo 2 trabajadores** (activos y cesados). Al intentar registrar un tercero, la app muestra los datos de contacto.
- En **Empresas**, el administrador cambia el **tipo de cuenta** directamente en la lista. Al pasarla a *Cliente* o *Suscriptor* desaparece el límite. Las cuentas creadas por registro muestran la nota "Se registró solo".
- El límite y la suscripción los controla la base de datos (`supabase_migracion.sql`): un representante no puede saltarse el límite ni activarse la suscripción. Las empresas que existían antes de ejecutar el script quedan con suscripción activa.

### Recuperar contraseña

- **¿Olvidaste tu contraseña?** funciona para **todos los usuarios**. Cada uno escribe su correo registrado y recibe un enlace; al abrirlo, la app pide la nueva contraseña.
- Los representantes **siguen ingresando con su RUC**. Su correo registrado es el de su cuenta, y la base de datos solo lo usa para iniciar la sesión cuando la contraseña es correcta. Así nadie puede averiguar el correo de un cliente con su RUC. Además, tras 10 intentos fallidos el RUC queda bloqueado 15 minutos.
- **Dónde se registra el correo:**
  - Cuentas de prueba: es obligatorio al registrarse.
  - Representantes que ya existían: el administrador lo agrega en *Empresas → Crear acceso / Cambiar contraseña*, o el propio usuario lo registra en *Mi cuenta → Correo para recuperar tu contraseña*.
  - Quien aún no tiene correo sigue ingresando normalmente con su RUC; para recuperar su contraseña debe pedírsela al administrador.
- Configuración necesaria en Supabase:
  1. **Authentication → URL Configuration:** en *Site URL* y en *Redirect URLs* agrega la dirección de la app (por ejemplo `https://TU-USUARIO.github.io/planillas/`).
  2. **Authentication → Emails → SMTP Settings:** configura un servidor SMTP propio (Gmail con contraseña de aplicación, Brevo, Resend, etc.). El servicio de correo incluido en Supabase solo envía a los miembros del equipo del proyecto y tiene un límite muy bajo.

### Uso en celular

La app se adapta a pantallas de hasta 760 px de ancho sin cambiar la vista de PC:
- el menú principal se pliega en un botón **Menú** (hamburguesa);
- las sub-pestañas Principal / Dctos. ocupan el ancho;
- las tablas anchas se desplazan horizontalmente dentro de su recuadro, con la primera columna fija;
- los formularios pasan a una columna;
- las ventanas (carga masiva, fichas, PLAME, AFPnet) ocupan toda la pantalla, con los botones siempre visibles abajo.

## Pantallas

| Pestaña | Quién la ve | Qué hace |
|---|---|---|
| **Ingreso** | Todos | Inicio de sesión con correo o RUC. Muestra mensajes claros si la contraseña es incorrecta o falla la conexión. |
| **Empresas** | Administrador | Lista de empresas (RUC, razón social, régimen laboral). Crear, editar, eliminar, seleccionar la empresa activa y gestionar el acceso del representante legal. El **tipo de cuenta** (Cliente, Suscriptor o Prueba) se elige directamente en la lista. |
| **Trabajadores** | Todos | Ficha de cada trabajador: DNI, nombres, puesto, pensión (ONP o AFP), salud, remuneración, banco y cuenta. Historial de aumentos con el mes desde el que rigen. Avisa si el sueldo es menor a la RMV vigente, salvo en contratos a tiempo parcial. **Carga masiva** desde Excel con su formato descargable: agrega trabajadores nuevos sin tocar a los registrados (opcionalmente los actualiza) y entrega un .txt con las filas observadas. |
| **Planilla mensual › Principal** | Todos | Cálculo del mes por trabajador: ingresos, ONP o AFP (aporte, prima y comisión), renta de 5ta categoría, faltas, otros descuentos, neto y aportes del empleador (EsSalud, SIS, SCTR, Vida Ley, provisiones de gratificación, CTS y vacaciones). Boletas en PDF, exportación a Excel (CSV) y archivo de pagos para el banco. **Carga masiva de planilla** desde Excel, vinculada por N° de documento: carga días, vacaciones, tardanzas, horas extras, bonificaciones, movilidad y descuentos; nunca EsSalud, AFP, ONP ni 5ta, que siempre calcula la app. Entrega un .txt con los trabajadores no registrados. |
| **Planilla mensual › Dctos.** (sub-pestaña) | Administrador y rep. con permiso | Hoja del mes para registrar días de vacaciones, faltas, tardanzas, adelantos y retenciones judiciales. Por cada falta sugiere descontar el día más 1/6 del descanso semanal. Se descarga en PDF. |
| **Beneficios sociales** | Todos | Por trabajador y año: gratificaciones de julio y diciembre con bonificación extraordinaria, CTS de mayo y noviembre, vacaciones y vacaciones truncas, e indemnización por despido arbitrario con su tope. Si hay fecha de cese, calcula los montos truncos. |
| **Honorarios 4ta** | Administrador y rep. con permiso | Importa recibos por honorarios desde el reporte `.txt` de SUNAT o los `.xml` / `.pdf` de cada recibo (los dos formatos de PDF de SUNAT), los agrupa por prestador y no los duplica. Permite ajustar la fecha de pago y la retención pensionaria, y genera los archivos `.ps4` y `.4ta` de la PLAME. |
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

## Base de datos: dos scripts

1. `supabase.sql` crea la base inicial (tablas, reglas y accesos de representantes).
2. `supabase_migracion.sql` agrega todo lo que usa la versión actual de la app:
   - las columnas de `empresas` (`permiso`, `rubro`, ubicación, `suscripcion_activa`, `origen`);
   - la función `emp_actualizar_datos`;
   - las reglas para que los representantes escriban trabajadores y datos del mes;
   - las cuentas de prueba (`registrar_prueba`, límite de 2 trabajadores y de 2 prestadores de 4ta con 2 recibos cada uno);
   - la tabla `prestadores4ta` de recibos por honorarios.

   No borra datos y se puede ejecutar más de una vez. Si tu base ya tenía alguna de estas piezas, se conserva.

La carga masiva de trabajadores y de planilla no necesita tablas nuevas: usa `trabajadores` y `periodos`.

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

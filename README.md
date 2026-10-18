<div align="center">

# DefenderTray

### El control de Windows Defender que cabe en la bandeja del sistema.

**Activa, desactiva, diagnostica y repara Microsoft Defender desde un icono — sin abrir cinco ventanas ni pelear con GPOs.**

🌐 **Español** · [English](#english)

[![Versión](https://img.shields.io/badge/versi%C3%B3n-8.1%20ULTIMATE-4f46e5?style=flat-square)](versiones/8/DefenderTray_8.1_Pro.ps1)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-012456?style=flat-square&logo=powershell&logoColor=white)](#-requisitos)
[![Plataforma](https://img.shields.io/badge/Windows-10%20%C2%B7%2011%20%C2%B7%20Server-0078D4?style=flat-square&logo=windows&logoColor=white)](#-requisitos)
[![Un solo archivo](https://img.shields.io/badge/un%20solo%20archivo-4%20747%20l%C3%ADneas-059669?style=flat-square)](versiones/8/DefenderTray_8.1_Pro.ps1)
[![API local](https://img.shields.io/badge/API%20local-REST%20%C2%B7%20GraphQL%20%C2%B7%20SSE%20%C2%B7%20PWA-1e1b4b?style=flat-square)](#-api-local)
[![Licencia](https://img.shields.io/badge/licencia-propietaria-475569?style=flat-square)](LICENSE)
[![Seguridad](https://img.shields.io/badge/seguridad-pol%C3%ADtica%20publicada-FF3366?style=flat-square)](SECURITY.md)

[Requisitos](#-requisitos) · [Inicio rápido](#-inicio-rápido) · [Qué hace](#-qué-hace-cada-acción) · [Argumentos](#-argumentos-de-línea-de-comandos) · [API local](#-api-local) · [Configuración](#-configuración-y-datos) · [Solución de problemas](#-solución-de-problemas) · [FAQ](#-preguntas-frecuentes) · [Seguridad](#-seguridad) · [Licencia](#-licencia) · [Historial](CHANGELOG.md)

</div>

> [!WARNING]
> **DefenderTray desactiva la protección antivirus de tu equipo.** Es una herramienta de administración pensada para que uses **en máquinas propias o sobre las que tienes autorización explícita**. Desactivar Defender deja el sistema expuesto: hazlo el tiempo justo, avisa al responsable del equipo y vuelve a activarlo al terminar. Usarlo en equipos ajenos, en una red corporativa sin permiso o para facilitar una intrusión es responsabilidad exclusiva de quien lo hace — y en muchas jurisdicciones, un delito. Ver [LICENSE](LICENSE) (cláusula 5) y [SECURITY.md](SECURITY.md).

> [!IMPORTANT]
> **Software propietario, código visible.** Que el repositorio sea público no lo convierte en libre: copiarlo, modificarlo, redistribuirlo o usarlo en una organización requiere autorización del titular. Condiciones completas en [LICENSE](LICENSE).

## 💡 ¿Qué es DefenderTray?

**DefenderTray** es un **único script de PowerShell** (sin instalador, sin dependencias obligatorias, sin servicios de terceros) que pone el control de Microsoft Defender en la bandeja del sistema: un icono que cambia de color según el estado real del motor, un panel con botones grandes y un historial de cada acción.

Lo que hace difícil a mano —detener `WinDefend`, dejar los servicios en `Start=4`, limpiar las claves de `Real-Time Protection`, aguantar que Windows 11 los reviva desde el kernel, acordarse de exportar el registro antes y poder revertirlo todo después— aquí son **un clic con verificación posterior y respaldo del registro incluido**.

A partir de la rama 8.x el proyecto dejó de ser un simple *toggle* y añade una capa de **operaciones**: API REST/GraphQL local, panel web en tiempo real (SSE), PWA instalable, firma de reportes, exportación a Excel/CSV y PDF, alertas por Telegram, Firebase, SMTP y webhooks, modo auditoría, modo forense, agente residente por WMI y detección de anomalías.

> 🧯 **Piensa en él como un interruptor con registro de auditoría, no como un escudo.** Todo lo que quita la protección es, por definición, lo que un atacante querría usar. Si tu amenaza incluye usuarios locales con privilegios o malware ya activo, la protección real viene de cuentas estándar, UAC, BitLocker y unas buenas directivas de grupo (GPO) — no la contraseña del modo kiosco (léelo en [límites de seguridad](SECURITY.md#-límites-conocidos-y-mitigaciones)).

## 🧩 Qué incluye

| Pieza | Para qué sirve |
|---|---|
| 🟢 **Icono en la bandeja** | Estado en un color (verde *activo*, rojo *desactivado*, ámbar *parcial*), menú con las acciones frecuentes y notificaciones al terminar cada operación. |
| 🎛️ **Panel principal** | Diagnóstico, Activar, Desactivar, Reparación profunda, **EMERGENCIA** (reactivación de un clic), Event Log, Historial, Config, Ayuda y Salir. Tema oscuro/claro automático, paleta personalizable y apertura en el monitor activo. |
| 🧬 **Motor de activación/desactivación** | Secuencia de 10 pasos ordenada por dependencias, bucle de reintento (hasta 5) y verificación final; respaldo `.reg` de las políticas antes de tocar nada. |
| 🩺 **Diagnóstico y reparación** | Informe por capítulos (servicios, drivers, políticas, firmas, red, AV de terceros, Event Log), reparación de firmas corruptas (errores 31/12/1969), `sfc /scannow`, `DISM /RestoreHealth`, `gpupdate` y limpieza de políticas huérfanas. |
| 🗄️ **Historial y datos** | SQLite cifrado cuando el proveedor está disponible y JSON como respaldo: cada acción queda registrada con resultado y duración; exportación a CSV/Excel y estadísticas. |
| 🌐 **API local** | `HttpListener` en `127.0.0.1:9182` con REST, un subconjunto GraphQL, `SSE` para el panel en vivo, consola Fleet y PWA instalable. HTTP o HTTPS con certificado autofirmado. |
| 🔔 **Notificaciones** | Telegram Bot, Firebase Cloud Messaging (FCM v1), correo SMTP, webhooks JSON propios y alerta umbral («Defender lleva X horas desactivado»). |
| 🏢 **Capa empresarial** | Inventario de Active Directory, firma Authenticode de reportes y guía de certificado EV, generador de instalador MSI (WiX), `Dockerfile`/`docker-compose` para la consola, modo auditoría, modo forense y autoactualización desde GitHub Releases con verificación SHA256. |
| 📚 **Histórico de versiones** | 37 scripts PowerShell desde la v1 hasta la v8.1, indexados uno a uno en [`versiones/README.md`](versiones/README.md) y narrados en el [registro de cambios](CHANGELOG.md). |

## ✨ Funciones destacadas

- ⚡ **Un clic, resultado verificable.** Cada acción termina con una comprobación real (`Get-MpComputerStatus`, estado del servicio, proceso `MsMpEng`, modo de arranque) y un diálogo de resultado con el log paso a paso y el tiempo empleado.
- 💾 **Reversible por diseño.** Antes de modificar el registro se exporta un `.reg` a `Backups\Registro`; **Configuración** ofrece el botón *Restaurar Registro* con el último respaldo disponible y la Reparación profunda permite reconstruir el estado limpio sin reiniciar.
- 🚨 **Botón de emergencia.** Reactiva Defender y sus servicios en la máquina afectada aunque el panel esté cerrado; notifica a los canales configurados y queda en el historial.
- 👁️ **Modo auditoría (`-audit`).** Evalúa y registra lo que *haría*, sin escribir una sola tecla de registro. Es la forma recomendada de probar la herramienta antes de usarla en serio.
- 🕵️ **Modo forense.** Guarda una captura de pantalla y una instantánea (servicios, procesos, edad de las firmas) antes de cada cambio, para poder reconstruir qué pasó.
- 🧍 **Modo kiosco.** Pide contraseña (SHA-256) o verificación biométrica de Windows Hello para abrir el panel. Útil para evitar al usuario accidental; inútil contra un administrador — léelo en [límites de seguridad](SECURITY.md#-límites-conocidos-y-mitigaciones).
- 🧠 **Detección de anomalías.** Mantiene una línea base de métricas y avisa cuando una desviación supera el umbral Z configurado (por defecto 3,0).
- 🌍 **Interfaz bilingüe ES/EN** y textos en español por defecto, con ayuda integrada (`F1`) y atajos `F5` / `Esc`.
- 🔌 **Sin instalación, sin registro de producto, sin telemetría.** Ningún dato sale del equipo a menos que actives explícitamente Telegram, Firebase, SMTP, webhooks o la comprobación de actualizaciones.

## 📋 Requisitos

| Requisito | Mínimo | Notas |
|---|---|---|
| **Sistema operativo** | Windows 10 1607 / Windows 11 | Windows Server 2016+ funciona (detecta `ProductType`). Windows 7/8/8.1: la UI arranca, pero las API de políticas modernas y la protección frente a manipulaciones se comportan distinto: pruébalo antes de confiar en ellas. |
| **PowerShell** | Windows PowerShell **5.1** | Está incluido en Windows. PowerShell 7 también carga, pero los ensamblados WPF/Speech/WinForms se apoyan en .NET Framework: si algo del panel no aparece, usa 5.1. |
| **.NET Framework** | 4.5+ | Necesario para `System.Windows.Forms` y `System.Drawing`. |
| **Permisos** | Administrador, con UAC elevada | Sin administración la herramienta se limita a leer y avisar. |
| **Privilegios especiales** | `SeDebugPrivilege` no requerido | Algunas acciones usan `taskkill`, `sc.exe`, `reg.exe` y `netsh http`. |
| **Módulos opcionales** | `ActiveDirectory` (RSAT), `ImportExcel` | Sin ellos, el inventario de AD y la exportación `.xlsx` degradan con elegancia a «no disponible» o a COM de Excel. |
| **SQLite (opcional)** | `System.Data.SQLite` | Si falta, el script intenta bajar el paquete NuGet `System.Data.SQLite.Core` 1.0.118.1 a `lib\` y, si no puede, usa JSON. Para equipos sin salida a Internet, copia antes `System.Data.SQLite.dll` y `SQLite.Interop.dll` en `lib\` — y verifica el hash, como se explica en [SECURITY.md](SECURITY.md#-límites-conocidos-y-mitigaciones). |
| **Huella** | ~230 KB el script | Más `Logs`, `Backups`, `Auditoria`, `Forense` y `Perfiles` en la carpeta de datos. |

## 🚀 Inicio rápido

Copia [`DefenderTray_8.1_Pro.ps1`](versiones/8/DefenderTray_8.1_Pro.ps1) a una carpeta dedicada y con permisos cerrados (`C:\DefenderTray` es la opción razonable): si lo dejas en *Escritorio* o *Descargas*, quien pueda escribir sobre ese archivo puede acabar ejecutándolo como `SYSTEM` si además usas el programador — ver [SECURITY.md](SECURITY.md#-límites-conocidos-y-mitigaciones) (L-2 y L-4):

```powershell
# 0) Comprueba que el archivo es el que esperas
Get-FileHash .\DefenderTray_8.1_Pro.ps1 -Algorithm SHA256

# 1) Abre PowerShell como Administrador y mira qué haría, sin tocar nada
powershell -NoProfile -ExecutionPolicy Bypass -File .\DefenderTray_8.1_Pro.ps1 -audit

# 2) Panel interactivo (icono en la bandeja + ventana de control)
powershell -NoProfile -ExecutionPolicy Bypass -File .\DefenderTray_8.1_Pro.ps1

# 3) Modo sin consola, para tareas programadas o despliegue por GPO
powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File .\DefenderTray_8.1_Pro.ps1 -silent -norest
```

**Antes de desactivar en Windows 11:** abre *Seguridad de Windows → Protección contra virus y amenazas → Configuración → Protección frente a manipulaciones* y desactívala; si está activa, DefenderTray se detendrá y lo dirá en el log (`ERROR: Tamper Protection ACTIVA`). Después puede exigir un **reinicio** para que el estado quede consistente: la herramienta te lo indica explícitamente.

Para arrancarlo con doble clic, crea un acceso directo con este destino:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\DefenderTray\DefenderTray_8.1_Pro.ps1" -silent
```

## 🧰 Qué hace cada acción

### Desactivar (`Disable-Defender`)

| Paso | Acción |
|---|---|
| 0/10 | Exporta las claves de políticas a un `.reg` en `Backups\Registro` (y snapshot forense si el modo está activo). |
| 1/10 | `Set-MpPreference` con 15+ conmutadores `Disable*` a `$true`; `MAPSReporting Disabled`, `SubmitSamplesConsent NeverSend`, `PUAProtection Disabled`, `EnableNetworkProtection Disabled`. |
| 2/10 | Elimina claves de políticas heredadas (`HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`, `...\CurrentVersion\Policies`, `WOW6432Node`, `HKCU\...\Policies`). |
| 3/10 | Fija las políticas de bloqueo: `DisableAntiSpyware`/`DisableAntiVirus`, ocho claves en `Real-Time Protection`, `SpynetReporting 0` y `SubmitSamplesConsent 2`. |
| 4/10 | Deshabilita las *FailureActions* (reinicios automáticos) de los ocho servicios implicados. |
| 5/10 | Bucle de hasta 5 intentos: mata procesos (`MsMpEng`, `NisSrv`, `SecurityHealthService`…), detiene servicios, deja `Start=4`, `sc config … start= disabled`, espera y comprueba. |
| 9/10 | Verificación final: servicio detenido, proceso fuera, `Start=4` en `WinDefend`/`WdNisSvc`/`Sense` y tiempo total. |

### Activar (`Enable-Defender`)

`Start` de cada servicio según su orden de arranque (1) → borrado de políticas de bloqueo (2) → limpieza de claves de `Real-Time Protection` (3) → arranque por dependencias (4) → reinicio de `WinDefend` (5) → reintento de servicios fallidos (6) → reactivación de todas las protecciones (7) → **Tamper Protection** (8) → restaurar el icono del área de notificación y `gpupdate /force` (9) → verificación final con `Get-MpComputerStatus` (10).

### Reparación profunda

Consola con acciones numeradas: **1. Borrar políticas**, **2. Servicios**, **3. `gpupdate`**, **4. `sfc /scannow`**, **5. `DISM /RestoreHealth`**, **Matar `MsMpEng`**, **Reparar firmas**, **Reparar todo**, **AD Inventory** y **Guía de certificados**. Cada comando se ejecuta a la vista en la propia consola, para que puedas leer la salida en lugar de confiar en un «hecho».

### Programador y «servicio»

*Programador* crea tareas `DefenderTray_<nombre>` diarias (activar o desactivar a una hora) e *Instalar como servicio* registra `DefenderTray_Service` al arrancar el equipo. Ambas se ejecutan como **`SYSTEM`** con nivel máximo: por eso la ruta del script debe quedar inaccesible para usuarios no administradores — obligatorio antes de usar esta función, ver [SECURITY.md](SECURITY.md#-límites-conocidos-y-mitigaciones).

## 💻 Argumentos de línea de comandos

| Argumento | Efecto |
|---|---|
| `-silent` | Sin diálogos ni confirmaciones: para tareas programadas y despliegue. |
| `-portable` | Todos los datos en `.\DefenderTrayData\`, junto al script, en vez de `%LOCALAPPDATA%\DefenderTray`. |
| `-audit` | Modo auditoría: registra lo que haría y **no aplica ningún cambio**. |
| `-norest` | No levanta la API local (recomendado en servidores y equipos compartidos). |
| `-https` | Sirve la API por HTTPS con certificado autofirmado (`CN=DefenderTray Localhost`, 5 años) en `LocalMachine\My`. |
| `-action enable` / `-action disable` | Ejecuta la acción por consola y sale con código `0`. |
| `-autoupdate` | Comprueba si hay una versión nueva en GitHub Releases y lo deja en el log. |

## 🌐 API local

Escucha **solo en `127.0.0.1`** (puerto `9182`, configurable en el diálogo de configuración). Sin `-https` el tráfico es HTTP en claro por el bucle local; con `-https` se autoemite un certificado que tu sistema no conoce: úsalo solo en tu equipo.

| Método y ruta | Descripción |
|---|---|
| `GET /` | Panel de estado en tiempo real (HTML + SSE). |
| `GET /status` | `estado`, `servicio`, `motor`, `tiempoReal`, `fecha`, `host` en JSON. |
| `GET /enable` · `GET /disable` | Devuelven **la línea de comando** para activar/desactivar (no la ejecutan). |
| `GET /emergency` | **Ejecuta** la reactivación de Defender en un proceso oculto. |
| `GET /diagnostic` | Versión, autor, contacto y capacidades activas. |
| `GET /fleet` · `GET /fleet/computers` | Consola Fleet (HTML) y equipos registrados en la base local. |
| `POST /fleet/command` | `{ "host": "...", "action": "enable" }` lanza esa acción en **este** equipo. |
| `POST /fleet/broadcast` | `{ "action": "..." }` — difunde a la lista local (esqueleto multi-equipo). |
| `POST /graphql` | Subconjunto: `{ status { estado servicio motor tiempoReal } }`, `equipos`, `config`. |
| `GET /sse/stream` | Un evento `status` por conexión, para el panel y la PWA. |
| `GET /pwa/` · `/pwa/manifest.json` · `/pwa/sw.js` · `/pwa/icon-192.png` · `/pwa/icon-512.png` | PWA instalable desde el navegador del equipo o del móvil en la misma red. |

```bash
curl -s http://127.0.0.1:9182/status
curl -s http://127.0.0.1:9182/diagnostic
curl -s http://127.0.0.1:9182/graphql -d '{"query":"{ status { estado motor } }"}'
```

> [!CAUTION]
> **La API no tiene autenticación.** Cualquier proceso de tu usuario —y cualquier usuario con perfil local— puede llamar a `/emergency` o a `POST /fleet/command`. En equipos compartidos, servidores o estaciones con software de terceros, arranca con `-norest` o desactiva «API REST local» en Configuración. Detalles y mitigaciones en [SECURITY.md](SECURITY.md#-límites-conocidos-y-mitigaciones).

## 🔧 Configuración y datos

Rutas por defecto (`-portable` las mueve a `.\DefenderTrayData\`):

| Ruta | Contenido |
|---|---|
| `%LOCALAPPDATA%\DefenderTray\config.dat` | Configuración completa, JSON cifrado con **DPAPI** (ámbito usuario). Contiene la huella del kiosco y los identificadores de Telegram/Firebase/SMTP/webhooks. |
| `…\Logs\DefenderTray_AAAA-MM-DD.log` | Log diario; se auto-limpia a los 30 días si tienes activada esa opción. |
| `…\Auditoria\audit_AAAA-MM-DD.log` | Trazas de auditoría (modo `-audit` y acciones sensibles). |
| `…\Backups\Registro\*.reg` | Respaldos del registro previos a cada cambio. |
| `…\Forense\<marca>\` | `screenshot.png` + `snapshot.json` del modo forense. **No está cifrado.** |
| `…\Perfiles\profiles.json` | Perfiles multiusuario (respaldo JSON). |
| `…\historial.json` · `…\defendertray.db` | Historial: JSON siempre, SQLite cuando el proveedor está disponible. |
| `…\lib\` | `System.Data.SQLite.dll` y `SQLite.Interop.dll` autodescargados. |
| `…\updates\` | Descargas de la autoactualización y `*.v<versión>.bak` del script. |

Opciones del diálogo **Configuración**: auto-reparar firmas al iniciar (si superan 30 días), limpiar logs viejos, seguir el tema del sistema, alerta umbral con horas configurables, agente residente WMI, API REST y puerto, HTTPS, modo kiosco (+ biométrico), firmar reportes con Authenticode, SMTP completo, Telegram (token y *chat id*), Firebase (project id, JSON de cuenta de servicio y token), detección de anomalías y umbral Z, modo forense, apertura en monitor activo, modo tutela, copia a una carpeta de red/nube sincronizada, repo de GitHub para actualizaciones y paleta de colores personalizada.

> [!NOTE]
> Los campos de terceros (`CfgGitHubRepo`) vienen por defecto con el marcador `usuario/DefenderTray`, que **desactiva** la comprobación de actualizaciones hasta que pongas un repositorio real. A cambio, todo lo demás funciona sin configurar nada.

## 🧭 Versiones

El código vive en [`versiones/`](versiones/), una carpeta por hito. Esta es la línea temporal (y el motivo de nombres tan poco pulidos):

| Versión | Archivo | Qué aportó |
|---|---|---|
| **8.1 ULTIMATE** ⭐ | [`versiones/8/DefenderTray_8.1_Pro.ps1`](versiones/8/DefenderTray_8.1_Pro.ps1) | Actual **y recomendada**. SQLite cifrado, firma Authenticode + guía EV, MSI con WiX, FCM v1, consola Fleet, anomalías por Z-score, Active Directory, GraphQL, PWA, kiosco biométrico, webhooks, Excel/CSV, panel SSE, autoactualización con SHA256 y empaquetado Docker. *Nota honesta:* v8.1 es **el mismo código que v8.0** con las cadenas de versión actualizadas (142 líneas, todas de texto): la novedad real es la de v8.0. |
| 8.0 ULTIMATE | [`versiones/8/DefenderTray_8.0_Pro.ps1`](versiones/8/DefenderTray_8.0_Pro.ps1) | Salto a «Enterprise Security Control»: las 15 funciones anteriores. |
| 7.0 ULTIMATE | [`versiones/7/DefenderTray_7.0_Pro.ps1`](versiones/7/DefenderTray_7.0_Pro.ps1) | Panel web servido por la API, perfiles, Telegram, auto-reparación heurística, voz, PDF firmado, botón de pánico, Event Log, nube, multi-monitor, tema editable, tutela, modo forense. |
| 6.0 ULTIMATE | [`versiones/6/DefenderTray_6.0_Pro.ps1`](versiones/6/DefenderTray_6.0_Pro.ps1) | Agente WMI, auto-update, tema automático, Windows Terminal, PowerShell 7, SMTP, **API REST en `127.0.0.1:9182`**, Hello, asistente de firma, MSI, alertas por umbral, reglas de firewall, `-audit`, config cifrada con DPAPI, Windows Server. |
| 5.0 Pro | [`versiones/5/DefenderTray_5.0_Pro.ps1`](versiones/5/DefenderTray_5.0_Pro.ps1) | Programador, servicio, backup/restore, AV de terceros, red, ES/EN, SHA256, estadísticas, contraseña de desinstalación. |
| 4.x Pro | [`versiones/4/`](versiones/4/) | Edición futurista: 4.0–4.3.x y 4.5, con el arranque ordenado por dependencias (corrección del doble clic) y reparación de la base de datos de firmas corruptas (errores 31/12/1969). Incluye `Reparar-DefenderTray.ps1`, un parcheador automático del 4.1. |
| 3.x | [`versiones/3/`](versiones/3/) | Ayuda contextual, tooltips, asistente de primera ejecución, autoinicio, atajos, tema y colores. |
| 1 – 2 | [`versiones/1/`](versiones/1/) · [`versiones/2/`](versiones/2/) | El tray original con menú y modal de colores. |

⭐ = usa esta. Las demás se conservan como referencia histórica y para entornos antiguos; **no reciben correcciones** (ver [SECURITY.md](SECURITY.md#-versiones-con-soporte)). El índice archivo por archivo —líneas, bytes, estado y qué declara cada cabecera— está en [`versiones/README.md`](versiones/README.md), y el detalle completo, en [CHANGELOG.md](CHANGELOG.md).

## 📚 Documentación del repositorio

| Documento | Qué contiene |
|---|---|
| [README.md](README.md) | Lo que estás leyendo: uso, argumentos, API, configuración y diagnóstico. |
| [CHANGELOG.md](CHANGELOG.md) | Historial reconstruido de las cabeceras de cada script, más la lista de limpieza pendiente. |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Entorno, banco de pruebas en VM, estilo del proyecto, reglas de versionado y revisión sensible. |
| [SECURITY.md](SECURITY.md) | Reporte privado, alcance, modelo de amenazas, 14 límites conocidos con su mitigación y endurecimiento. |
| [LICENSE](LICENSE) | Licencia propietaria bilingüe (español prevalece), con la cláusula de uso responsable. |
| [`versiones/README.md`](versiones/README.md) | Índice del histórico: 37 `.ps1` con tamaño, estado y una línea de contexto. |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | Comprobaciones: sintaxis (bloqueante en la v8), codificación y CRLF, PSScriptAnalyzer y enlaces de la documentación. |
| [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/) · [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md) | Plantillas de informe de error, propuesta de mejora y pull request. |
| [`.gitignore`](.gitignore) · [`.gitattributes`](.gitattributes) | Qué queda fuera del repositorio y por qué los `.ps1` viajan con CRLF. |

## 🩺 Solución de problemas

| Síntoma | Causa habitual | Qué hacer |
|---|---|---|
| `ERROR: Tamper Protection ACTIVA.` | La protección frente a manipulaciones bloquea los cambios. | Desactívala en *Seguridad de Windows* (o con `Set-MpPreference -DisableTamperProtection $true` cuando el SO lo permita) y repite. |
| `[!] DESACTIVACION INCOMPLETA. Windows 11 22H2+ reinicia WinDefend desde el kernel.` | El registro ya está cambiado, pero el subsistema de arranque revive el servicio. | **Reinicia** el equipo y vuelve a abrir el diagnóstico. Si no puedes reiniciar, asume que sigue protegido. |
| Doble clic y se cierra al instante | Política de ejecución o falta de administración. | Ejecuta con `-ExecutionPolicy Bypass` desde una PowerShell elevada y revisa `Logs\`. |
| `Start=4: PARCIAL` | GPO de dominio o una tarea de remediación revierte el valor. | Con `-audit` verás las claves en juego; en dominio, se resuelve con la GPO, no con este script. |
| «Reparación de firmas» no termina (errores 31 / 12 / 1969) | Base de firmas corrupta o `WinDefend` detenido. | Usa **REPARAR FIRMAS** y después **REPARAR TODO**; si persiste, `MpCmdRun.exe -RemovalEntries` y actualizar desde *Seguridad de Windows*. |
| `REST no arranco` o el puerto está ocupado | Otro proceso escucha en 9182 o falta la reserva `urlacl`. | Cambia el puerto en Configuración, arranca con `-norest`, o revisa las reservas con `netsh http show urlacl` y libera la antigua con `netsh http delete urlacl`.  |
| No se ven los gráficos / el tema sale raro en PowerShell 7 | Ensamblados dependientes de .NET Framework. | Ejecuta con `powershell.exe` (5.1) en lugar de `pwsh`. |
| «No se pudo cargar SQLite» | Sin salida a Internet o sin permisos en `lib\`. | Copia manualmente las dos DLL, o ignóralo: el historial pasa a JSON sin perder funciones. |
| SmartScreen avisa del script | Es normal en un `.ps1` no firmado descargado de Internet. | Verifica el SHA256 contra esta página y, si lo vas a desplegar, fírmalo con tu propio certificado. |
| Acentos o `ñ` mal mostrados en un diálogo | Archivo leído como ANSI. | Guarda los `.ps1` en UTF-8 sin BOM y CRLF (como los de este repo) y evita caracteres fuera del ASCII en las cadenas: ver [CONTRIBUTING.md](CONTRIBUTING.md#-estilo-y-convenciones). |

## 🔐 Seguridad

- **Por defecto, nada sale del equipo.** Sin Telegram, Firebase, SMTP, webhooks ni repositorio de actualizaciones configurados, la herramienta no hace ninguna petición de red — salvo la descarga opcional de SQLite.
- **Solo bucle invertido.** La API escucha en `127.0.0.1` y no se expone a la red; no la abras con reenvíos de puerto ni la publiques.
- **Credenciales cifradas con DPAPI** (ámbito usuario) en `config.dat`; el `TelegramToken` y el JSON de cuenta de servicio quedan dentro de ese blob: quien pueda iniciar sesión como tú, puede leerlos.
- **Auditoría local.** Cada acción, su resultado y su duración quedan en el historial (SQLite/JSON) y en los logs; en modo `-audit` se escribe además `Auditoria\`, para poder explicar después qué se tocó.
- **Antes de tocar el registro, respaldo `.reg`.** Y el modo `-audit` permite leer sin escribir.

¿Encontraste una vulnerabilidad? **No abras un issue público**: usa el reporte privado de GitHub siguiendo [SECURITY.md](SECURITY.md). Riesgos conocidos, límites reales de cada protección y recomendaciones de endurecimiento están ahí, escritos sin eufemismos.

## 📁 Estructura del repositorio

```text
versiones/
  1/  DefenderTray_1.ps1                       El tray original
  2/  DefenderTray_2.ps1, WiFi_1126H2_2.1.ps1  Modal de colores (+ un auxiliar de red)
  3/  DefenderTray_3.0 … 3.12.ps1              Ayuda, tema, asistente y autoinicio
  4/  DefenderTray_4.0 … 4.5_Pro.ps1,
      Reparar-DefenderTray.ps1                 Edición futurista y parcheador del 4.1
  5/  DefenderTray_5.0_Pro.ps1                 Programador, servicio, backup/restore
  6/  DefenderTray_6.0_Pro.ps1                 API REST, DPAPI, Windows Server, -audit
  7/  DefenderTray_7.0_Pro.ps1                 Panel web, Telegram, modo forense y tutela
  8/  DefenderTray_8.0_Pro.ps1, 8.1_Pro.ps1    Capa «enterprise» (la recomendada)
  README.md                                    Índice del histórico y reglas de la carpeta

CHANGELOG.md · README.md · CONTRIBUTING.md · LICENSE · SECURITY.md
.github/
  workflows/ci.yml                             Sintaxis, codificación, análisis y enlaces
  ISSUE_TEMPLATE/bug_report.yml · feature_request.yml · config.yml
  PULL_REQUEST_TEMPLATE.md · dependabot.yml
  check_markdown_links.py                      El comprobador que usa el job «docs»
.gitattributes · .gitignore
```

Es un repositorio de **un solo archivo ejecutable por versión**: no hay árbol `src/`, ni compilación, ni gestores de paquetes. Cada `.ps1` es autónomo y autocontenido (65 secciones y 134 funciones en la v8.1), lo que facilita copiarlo a un equipo aislado y lo que hace que el tamaño llame la atención. Los archivos con sufijos `.backup_*`, `- copia - copia` y el marcador `revisar` son residuos del desarrollo histórico: no los uses como referencia, toma siempre la v8.1. Se listan y explican en [CHANGELOG.md](CHANGELOG.md#-pendientes-de-limpieza-registrados), y [`.gitignore`](.gitignore) ya impide que se generen otros nuevos.

## ❓ Preguntas frecuentes

<details>
<summary><b>¿Por qué desactivaría yo el antivirus?</b></summary>

<br />

Por trabajo real: instalar software antiguo que Defender marca como *PUA* y necesitas descartar un falso positivo, montar un entorno de pruebas, auditar una máquina, aislar una muestra, o recuperar una estación de trabajo de un laboratorio. La herramienta está pensada para hacerlo **de forma temporal, verificable y reversible**, con registro de lo que se tocó — no para dejar una máquina desprotegida. Al terminar, un clic en **Activar** (o `GET /emergency` desde tu propio equipo) devuelve el estado sano.

</details>

<details>
<summary><b>¿Windows va a deshacer mis cambios?</b></summary>

<br />

Sí, y es útil saberlo: en Windows 11 22H2+ el subsistema de arranque puede relanzar `WinDefend` aunque el registro diga lo contrario. Por eso la secuencia desactiva las *FailureActions*, deja `Start=4` y avisa explícitamente cuando la desactivación quedó **INCOMPLETA** hasta reiniciar. Si el diagnóstico después muestra `PARCIAL`, el equipo sigue protegido: confía en `Get-MpComputerStatus`, no en la sensación.

</details>

<details>
<summary><b>¿Sirve en un dominio con GPOs?</b></summary>

<br />

Para diagnosticar y para inventario de AD, sí. Para desactivar de forma persistente, **no**: una GPO que fije las políticas de Defender volverá a aplicarlas en el siguiente `gpupdate`, y el script no puede (ni debe) ganar esa discusión. Toca la GPO en el controlador de dominio o trabaja en un grupo de pruebas sin enlace.

</details>

<details>
<summary><b>¿Y si quiero el control sin interfaz gráfica?</b></summary>

<br />

`-silent -norest -action disable` (o `enable`) desde una tarea programada o un despliegue por GPO/Intune, sin bandeja ni diálogos y con salida a los logs. Combínalo con `-audit` en tu primera pasada sobre cada modelo de equipo.

</details>

<details>
<summary><b>¿Qué datos personales toca?</b></summary>

<br />

Nombre de equipo y dirección IPv4 local (para la consola Fleet), estado de servicios y firmas, y lo que tú escribas en Configuración. Las capturas del modo forense sí contienen **lo que haya en pantalla**: actívalo solo en máquinas propias y limpia `Forense\` antes de entregar el equipo. No hay analíticas, ni publicidad, ni servidores propios: si activas Telegram, Firebase o webhooks, el mensaje viaja a esos proveedores con el nombre de tu equipo.

</details>

<details>
<summary><b>¿Puedo usarlo en mi empresa?</b></summary>

<br />

Para uso interno de tu equipo de sistemas, con autorización escrita y sin redistribuir copias, la cláusula 3 de [LICENSE](LICENSE) lo permite. Cualquier otra cosa (empaquetarlo en una imagen, ofrecerlo a clientes, incluirlo en un producto, modificarlo y distribuirlo) requiere autorización del titular. Y antes de desplegar nada que pueda desactivar el antivirus en 500 equipos, apruébalo con tu responsable de seguridad.

</details>

<details>
<summary><b>¿Por qué un script gigante en vez de un módulo con funciones?</b></summary>

<br />

Porque el requisito de diseño es «cópialo en una USB y arráncalo en una máquina sin acceso a nada». Un único `.ps1` no necesita instalación, no depende de la ruta de un módulo y funciona en un equipo recién formateado. El coste es la legibilidad: de ahí las 65 secciones numeradas y el orden estricto de dependencias que se documenta en [CONTRIBUTING.md](CONTRIBUTING.md#-anatomía-de-un-script).

</details>

<details>
<summary><b>¿Por qué mi antivirus detecta el script?</b></summary>

<br />

No asumas que sí: un script que manipula las claves de políticas de Defender es un patrón típico de *tamperware* y varios antivirus lo detectan genéricamente. Si necesitas que pase un control, firma Authenticode tu copia, documenta el hash y explica el uso — y recuerda que el código está abierto a lectura para que un revisor pueda auditarlo sin ejecutarlo.

</details>

## 📝 Registro de cambios

El historial completo, versión a versión y con las mejoras que declara cada script, está en [CHANGELOG.md](CHANGELOG.md); ahí se explica también por qué la 8.1 es una revisión de texto de la 8.0 y qué queda pendiente de limpieza en `versiones/`. Cuando existan etiquetas y releases, cada entrada ganará su fecha.

## 🤝 Contribuir

Informes de error, propuestas de mejora, correcciones de documentación y pull requests son bienvenidos, con las plantillas de `.github/`. La guía está en [CONTRIBUTING.md](CONTRIBUTING.md): cómo montar el entorno, **cómo probar sin tumbar tu Windows** (máquina virtual + `-audit`), el estilo de PowerShell del proyecto, el esquema de versiones y las reglas para los cambios que tocan la desactivación de la protección, que reciben una revisión extra por ser duales.

## 📄 Licencia

**Software propietario — todos los derechos reservados.** © 2026 Yosvany Hernández Quintero.

El repositorio es público y el código legible, pero eso no concede derechos de uso. Ver, bifurcar en GitHub y usarlo en equipos propios sin fines comerciales está permitido; distribuirlo, modificarlo para terceros, integrarlo en otros productos u ofrecerlo como servicio requiere autorización previa por escrito. Texto completo (español e inglés) en [LICENSE](LICENSE); los términos de contribución están en la cláusula 6 y en [CONTRIBUTING.md](CONTRIBUTING.md).

## 👤 Autor y contacto

**Ing. Yosvany Hernández Quintero** · [@yhquintero](https://github.com/yhquintero)

- Dudas de uso y errores: [issues del repositorio](https://github.com/yhquintero/DefenderTray/issues)
- Vulnerabilidades: **canal privado**, nunca un issue — [SECURITY.md](SECURITY.md#-cómo-reportar-una-vulnerabilidad)
- Móviles (referidos en los encabezados de los scripts): +53 5 2160801 · +53 5 9860911

---

<a id="english"></a>

## 🇬🇧 English

**DefenderTray** is a single, dependency-free PowerShell script that puts Microsoft Defender control in the system tray: one click to enable, disable, diagnose or deep-repair protection, with registry backups, verification of every result, an audit trail and — since v6/v8 — a local REST/GraphQL API, a live web dashboard, a PWA, an anomaly detector, enterprise integrations (Active Directory, Authenticode signing, MSI packaging, Docker) and multi-channel alerting.

> ⚠️ **It turns antivirus protection off.** Use it only on machines you own or are explicitly authorised to touch, keep the window short, and re-enable when you are done. Using it to weaken security on someone else's system is the operator's responsibility alone — see [LICENSE](LICENSE) clause 5.

**Requirements.** Windows 10/11 or Windows Server 2016+ (Windows 7/8/8.1 run with caveats), **Windows PowerShell 5.1** and .NET Framework 4.5+, an elevated administrator session, and optionally the `ActiveDirectory`/`ImportExcel` modules plus a local SQLite provider.

**Quick start.**

```powershell
Get-FileHash .\DefenderTray_8.1_Pro.ps1 -Algorithm SHA256                      # verify what you downloaded
powershell -NoProfile -ExecutionPolicy Bypass -File .\DefenderTray_8.1_Pro.ps1 -audit    # read-only dry run
powershell -NoProfile -ExecutionPolicy Bypass -File .\DefenderTray_8.1_Pro.ps1           # interactive panel
```

On Windows 11, turn **Tamper Protection** off first: while it is on, the disable sequence stops and says so; an incomplete disable needs a reboot to settle.

**Switches.** `-silent` (no dialogs), `-portable` (data next to the script), `-audit` (log only, apply nothing), `-norest` (no local API), `-https` (self-signed TLS), `-action enable|disable`, `-autoupdate`.

**Local API.** Serves on `127.0.0.1:9182` only: `/` (SSE dashboard), `/status`, `/enable`, `/disable`, `/emergency` (executes re-activation), `/diagnostic`, `/fleet`, `/fleet/computers`, `POST /fleet/command`, `POST /fleet/broadcast`, `POST /graphql`, `/sse/stream`, `/pwa/*`. **There is no authentication**, so run with `-norest` on shared or server machines.

**Privacy.** Nothing leaves the machine unless you configure Telegram, Firebase Cloud Messaging, SMTP, webhooks or the GitHub update check. Settings are stored DPAPI-encrypted (current user) in `%LOCALAPPDATA%\DefenderTray\config.dat`; forensic screenshots are **not** encrypted.

**Status of features.** v8.1 is the reference build. Note that v8.1 differs from v8.0 only in version strings, that multi-machine fleet support is a local skeleton rather than a central server, and that voice control is a stub. Read [SECURITY.md](SECURITY.md) for the honest list of known limits and mitigations, [CONTRIBUTING.md](CONTRIBUTING.md) for conventions and safe testing, [CHANGELOG.md](CHANGELOG.md) for the version history, and [LICENSE](LICENSE) for terms. Continuous integration (`.github/workflows/ci.yml`) checks PowerShell syntax, file encoding and documentation links without ever running the tool.

---

<div align="center">

<sub><b>DefenderTray</b> · El control de Windows Defender que cabe en la bandeja del sistema · © 2026 yhquintero · <a href="#defendertray">Volver arriba ⬆</a></sub>

</div>

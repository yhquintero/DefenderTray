# Política de seguridad · Security policy

🌐 **Español** · [English](#english)

DefenderTray es una herramienta **dual**: existe para quitar la protección antivirus de un equipo y para volver a ponerla. Ese poder está en el propio diseño, no en un fallo, y por eso este documento no es un formulario legal: es la descripción honesta de lo que el script hace con tus derechos de administrador, de lo que **no** te protege y de cómo cerrar cada hueco mientras no esté corregido en el código.

Gracias por ayudarnos a mantenerla segura. Si ves algo que aquí no esté, dinóslo por el canal privado.

> [!IMPORTANT]
> **Auditoría de la que parte este documento:** revisión del código de [`versiones/8/DefenderTray_8.1_Pro.ps1`](versiones/8/DefenderTray_8.1_Pro.ps1) (4 747 líneas, 65 secciones). v8.1 es idéntico funcionalmente a v8.0; todo lo que sigue aplica a ambas. Los límites están **abiertos y sin corregir** a la fecha de este documento: trátalos como condiciones de uso, no como parches en camino.

## 📦 Versiones con soporte

| Versión | Soporte |
|---|---|
| **8.1 ULTIMATE** (rama `main`) | ✅ Recibe correcciones de seguridad y de funcionamiento. |
| 8.0 ULTIMATE | 🟡 Solo mientras no exista 8.2: recibe el parche, sin versión propia. |
| 7.0 y 6.0 ULTIMATE | ❌ Sin soporte. Contienen la API REST sin las protecciones posteriores y menos verificaciones: actualiza. |
| 5.0 Pro y anteriores (4.x, 3.x, 1–2) | ❌ Sin soporte. Diseñadas antes del modo auditoría, del cifrado de configuración y del respaldo del registro. |

Para reportes, indica siempre **versión exacta y SHA256** del `.ps1` que usas (`Get-FileHash .\DefenderTray_8.1_Pro.ps1`), porque entre la 4.x y la 8.x cambiaron por completo las rutas de datos, la API local y el manejo de credenciales.

## 📣 Cómo reportar una vulnerabilidad

> [!CAUTION]
> **No abras un issue, una discusión ni un pull request público** para una vulnerabilidad, ni menciones la palabra «exploit» en el título: cualquier lectura del repositorio daría a un atacante un mapa del hueco antes de que exista corrección. Tampoco subas capturas del diálogo de Configuración: contienen tokens.

1. Usa el **reporte privado de GitHub**: pestaña **Security** → **Report a vulnerability**, o directamente [este formulario](https://github.com/yhquintero/DefenderTray/security/advisories/new). Solo el titular del repositorio ve tu informe y puedes proponer un plazo de divulgación.
2. Si el formulario no está disponible, abre un issue titulado **«Solicitud de contacto de seguridad» sin ningún detalle técnico** y te responderemos con un canal privado.
3. Si el problema afecta a una **instalación concreta de una organización**, avisa también a su responsable de seguridad: el riesgo no es solo del código, sino del despliegue (ver [recomendaciones](#-recomendaciones-de-uso-seguro)).

**Qué incluir**

- Versión/SHA256 del script, SO y build (p. ej. Windows 11 23H2), PowerShell 5.1 o 7, y si se ejecuta elevado.
- Modo de arranque y argumentos (`-silent`, `-portable`, `-norest`, `-https`) y qué funciones están activas en Configuración (API REST, kiosco, forense, nube, notificaciones).
- El paso a paso mínimo para reproducirlo y, si puedes, una prueba de concepto que **no** desactive Defender en una máquina productiva: usa una máquina virtual con instantánea.
- Impacto estimado (¿qué gana un atacante y con qué privilegios previos?) y, si lo tienes, el parche propuesto: los arreglos pequeños de este archivo se aceptan con gusto.

**No incluyas** rutas reales de equipos de terceros, tokens de Telegram/Firebase, contenido de `config.dat`, archivos `.reg` de producción, ni logs con nombres de usuario ajenos. Sustitúyelos por valores inventados.

**Qué pasa después**

- Confirmamos recepción y evaluación con el objetivo de **3 días laborables**, y respuesta con el objetivo de **30 días**: es un proyecto mantenido por una sola persona y esto es una voluntad, no un SLA.
- Coordinamos contigo la divulgación; te pedimos no publicar detalles hasta que exista corrección o hasta los **90 días** desde el primer contacto.
- Con tu permiso, te reconocemos en el aviso de seguridad (GitHub Security Advisory). No hay programa de recompensas económicas.
- Publicamos el arreglo en la nueva versión del script y, si hay aviso de GitHub, se enlaza desde la pestaña Security.

## 🎯 Alcance

**Dentro del alcance**

- El script en sí: secuencias de `Disable-Defender` y `Enable-Defender`, reparación profunda y de firmas, respaldo/restauración del registro, modo auditoría y modo forense.
- La **API local**: HTTP/HTTPS, REST, GraphQL, SSE, Fleet y PWA (autenticación, métodos, enlazado de puerto, CORS, inyección de argumentos).
- Manejo de secretos: `config.dat` (DPAPI), huella del kiosco, contraseña de desinstalación, clave de la base SQLite, tokens de Telegram/FCM, credenciales SMTP y URL de webhooks.
- Distribución y actualización: descarga automática del proveedor SQLite, autoactualización desde GitHub Releases, verificación SHA256, firma Authenticode, MSI de WiX y `Dockerfile`/`docker-compose`.
- Persistencia: tareas programadas (`DefenderTray_*`, `DefenderTray_Service`), exclusión de Defender añadida al directorio del script y reglas de firewall.
- Interfaz: diálogos, atajos, validación de entradas, control de biométricos (`UserConsentVerifier`).

**Fuera del alcance**

- **Que Windows reviva Defender** (Servicio de protección, arranque seguro, VBS/HVCI, *Boot Critical* de `WdBoot`/`Wdfilter`) y en general el diseño de la seguridad de Windows o de Microsoft Defender: repórtalo al [Microsoft Security Response Center](https://msrc.microsoft.com/report/vulnerability/new?produccategoryid=37).
- El estado de una máquina **ya comprometida**: si un atacante ya es `SYSTEM`, cualquier control de esta herramienta es irrelevante (ver [límites](#-límites-conocidos-y-mitigaciones)).
- Ataques que requieren acceso físico sin BitLocker, ingeniería social, denegación de servicio volumétrica y el uso deliberado de la herramienta contra equipos ajenos.
- Vulnerabilidades de proveedores con los que te integras (NuGet, `api.telegram.org`, Google/Firebase, tu relay SMTP, tu receptor de webhooks) sin impacto demostrable sobre DefenderTray.
- Versiones antiguas del script y copias modificadas o renombradas por terceros: reproduce primero contra la v8.1 publicada.
- Detecciones de antivirus sobre el script: no son un fallo nuestro sino una consecuencia esperada del propósito. Aporta contexto y trabajamos la documentación; no «ofuscamos para pasar».

## 🧨 Modelo de amenazas: qué protege y qué no

| Escenario | ¿DefenderTray te ayuda? |
|---|---|
| Un usuario sin permisos desactiva Defender desde *Ajustes*. | 🟡 Parcialmente: el **modo kiosco** y la contraseña de desinstalación frenan al curioso, **solo** si el atacante no es administrador. |
| Tú necesitas una ventana de 10 minutos sin protección para instalar algo antiguo, dejando rastro. | ✅ Para esto está: `-audit`, respaldo del registro, verificación y **botón de emergencia**. |
| Malware ya en ejecución, con el token del usuario administrador. | ❌ Puede llamar a tu API local, escribir sobre el script y borrase el log. Usa cuentas estándar + UAC. |
| Un atacante **sin** privilegios en el equipo, pero con navegación web. | ⚠️ Depende de tu configuración: con la API local encendida hay superficie real ([L-1](#-los-límites-detallados)). Léela y decide. |
| Quieres que tu flota no pueda desactivar Defender. | ❌ Herramienta equivocada: se resuelve con GPO/Intune (política de *Tamper Protection* y `DisableAntiSpyware` bloqueado por administración de TI). |
| Auditoría posterior: «¿quién apagó el antivirus y cuándo?». | 🟡 Deja rastro local en `Logs\`, `Auditoria\` e historial; pero el log es un archivo plano sin integridad firmada. |

## 🔐 Cómo protege DefenderTray tus datos

- **Sin servidores propios.** No hay analíticas, publicidad, actualización forzada ni telemetría. La única petición que puede ocurrir sin configurar nada es la descarga opcional del proveedor SQLite (ver [L-6](#-los-límites-detallados)).
- **Todo local por defecto.** Configuración, logs, historial, respaldos y snapshots en `%LOCALAPPDATA%\DefenderTray` (o en `.\DefenderTrayData\` con `-portable`).
- **`config.dat` cifrado con DPAPI** en ámbito `CurrentUser`: el blob no sirve en otro usuario ni en otro equipo, y la contraseña SMTP viaja además protegida individualmente.
- **Solo bucle invertido.** La API se enlaza a `127.0.0.1` (no a `+` ni a `*`), y `HttpListener` rechaza peticiones cuyo encabezado `Host` no corresponda al prefijo registrado, lo que corta el *DNS rebinding* clásico.
- **Respaldo antes de romper.** `Backup-DefenderRegistry` exporta `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender` a un `.reg` con marca de tiempo antes de la desactivación.
- **Verificación en vez de confianza.** Cada secuencia acaba comprobando servicio, proceso, `Get-MpComputerStatus` y modo de arranque, y cada actualización puede comprobarse contra SHA256.

**Qué sale del equipo y cuándo**

| Canales (desactivados por defecto) | Destino | Contenido que viaja |
|---|---|---|
| Telegram Bot | `api.telegram.org` | Tu mensaje de alerta con el prefijo `[DefenderTray]`. |
| Firebase Cloud Messaging | `oauth2.googleapis.com` y `fcm.googleapis.com` | Título, cuerpo y datos del evento, más el intercambio del token de tu cuenta de servicio. |
| Webhooks | Las URL que tú configures | `{event, timestamp, host, payload}` → **incluye el nombre del equipo**. |
| Correo SMTP | Tu relay | El cuerpo del reporte que generes. |
| Comprobación de actualizaciones | `api.github.com` | Solo el `owner/repos` configurado (por defecto el marcador `usuario/DefenderTray`, que la desactiva). |
| Proveedor SQLite | `www.nuget.org` | Nada tuyo: descarga un paquete público. |

El modo **forense** y la consola **Fleet** trabajan solo con datos del propio equipo (nombre, IPv4 local, servicios, procesos, edad de firmas) y no los envían a ningún sitio.

## 🚧 Límites conocidos y mitigaciones

Se enumeran con su estado real en v8.1. Ninguno tiene parche publicado; la columna de mitigación es lo que puedes hacer **hoy**.

| ID | Límite | Gravedad | Mitigación inmediata |
|---|---|---|---|
| L-1 | API local **sin autenticación** y sin comprobación de origen; `GET /emergency` muta el estado | **Alta** | Arranca con `-norest` o desactiva «API REST local». |
| L-2 | Exclusión de Defender sobre la carpeta del script, añadida **al arrancar y nunca retirada** | **Alta** | Ejecuta desde una carpeta propia vacía (`C:\DefenderTray`), nunca desde *Escritorio* ni *Descargas*; borra la exclusión al terminar. |
| L-3 | `reg delete` sobre claves `CurrentVersion\Policies` de HKLM, WOW6432Node y HKCU, **sin respaldo previo** de esas tres | **Alta** | Exporta manualmente las claves antes de desactivar (comando abajo). |
| L-4 | Tarea programada / «servicio» ejecuta el script **como `SYSTEM`** desde una ruta que puede ser escribible por usuarios | **Alta** | ACL estrictas en la carpeta (comando abajo) y desplegar solo en equipos de un solo administrador. |
| L-5 | Autoactualización sin verificación de firma: el SHA256 solo se comprueba **si el release tiene** un asset `*.sha256`/checksums | Media | No lo uses sin publicar el hash; o deja `CfgGitHubRepo` en blanco y actualiza a mano. |
| L-6 | Descarga automática del proveedor SQLite desde NuGet **sin comprobar hash** | Media | Preinstala las dos DLL en `lib\` o bloquea la salida a `www.nuget.org` del proceso. |
| L-7 | Clave de cifrado de la base SQLite derivada del **nombre del equipo** (`DTv8_MasterKey_<EQUIPO>`) | Media | No guardes nada sensible en `defendertray.db`; la protección real es la ACL del archivo. |
| L-8 | Contraseña de kiosco/desinstalación: SHA-256 **truncado a 16 hex**, sin sal, sin bloqueo por intentos, sin retardo | Media | Frase larga y única, o directamente no la actives en equipos compartidos. No la reutilices. |
| L-9 | Tokens (Telegram, JSON de cuenta de servicio FCM) accesibles para cualquier proceso que corra como tú | Media | Bot con permisos mínimos, rotación periódica, y limpiar el portapapeles/capturas de Configuración. |
| L-10 | Modo forense: capturas de pantalla completas **sin cifrar**, y la purga de 30 días no es recursiva (no borra los `Forense\<marca>\screenshot.png`) | Media | Actívalo solo en equipos propios; limpia `Forense\` a mano antes de vender o entregar la máquina. |
| L-11 | `-https` autoemite un certificado válido 5 años y lo deja en `LocalMachine\My` con clave privada | Baja | Bórralo al terminar (`Get-ChildItem Cert:\LocalMachine\My \| Where-Object FriendlyName -eq 'DefenderTray Localhost' \| Remove-Item`). |
| L-12 | Webhooks a la URL que tú escribas, sin forzar TLS ni validar destino (SSRF interno posible) | Baja | Configura solo `https://` a un receptor propio y filtra por red. |
| L-13 | `/diagnostic` expone versión, capacidades, autor y teléfonos de contacto | Baja | Consideralo información pública; desactiva la API si no te da la gana. |
| L-14 | Logs e historial sin integridad: quien escriba en `%LOCALAPPDATA%\DefenderTray` puede borrar su rastro | Baja | Exporta `Logs\` y `Auditoria\` a un destino de solo escritura (rutas de auditoría corporativas). |

### 🔎 Los límites detallados

**L-1 — cualquier página web puede hablar con tu API.** Con la API encendida (**por defecto lo está**), un `fetch` desde una pestaña del navegador llega a `http://127.0.0.1:9182`. `POST /fleet/command` toma el campo `action` del cuerpo y lo interpola en una línea de `Start-Process`, así que una petición como `{"action":"disable"}` puede acabar lanzando `-silent -action disable`. No hay token, no hay encabezado anti-CSRF y los métodos no están restringidos (`/emergency` funciona por `GET`). Los navegadores modernos añaden mitigaciones (Private Network Access, bloqueo de contenido mixto) que reducen el escenario pero **no lo cierran**, y la protección de red privada se desactiva con extensiones o con navegadores antiguos. Si vas a dejar la API activa, hazlo en tu equipo personal, con el navegador que uses solo para eso, y revisa `netstat -ano | findstr :9182` al terminar.

**L-2 — la exclusión es el riesgo más silencioso.** En cada arranque con privilegios, el script hace `Add-MpPreference -ExclusionPath $script:ScriptDir`. La carpeta que contiene el script deja de analizarse, y **no se quita al salir ni al reactivar Defender**. Si lo copiaste a `C:\Users\tu\Downloads`, todo lo que bajes ahí queda fuera del escaneo. Corrige el rumbo: crea una carpeta exclusiva, pon ahí el `.ps1` con `icacls . /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F"`, y revisa `Get-MpPreference | Select-Object -ExpandProperty ExclusionPath` periódicamente.

**L-3 — el borrado de políticas es más ancho que el respaldo.** `Disable-Defender` elimina cuatro claves, pero `Backup-DefenderRegistry` exporta **solo** `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`. Las otras tres (`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies`, su gemela en `WOW6432Node` y `HKCU\Software\Microsoft\Windows\CurrentVersion\Policies`) se borran sin copia previa y guardan políticas de muchas otras funciones del sistema, no solo de Defender. Respáldalas tú antes:

```powershell
foreach ($k in "HKLM\SOFTWARE\Microsoft\Windows Defender","HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
               "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies","HKCU\Software\Microsoft\Windows\CurrentVersion\Policies") {
  reg export "$k" "$env:USERPROFILE\Desktop\pre-$($k.Split('\')[-3]).reg" /y
}
```

**L-4 — persistencia con privilegios máximos.** `Register-TrayTask` e `Install-AsService` crean tareas con `-UserId "SYSTEM" -RunLevel Highest` que ejecutan `powershell.exe -ExecutionPolicy Bypass -File "<ruta del script>"`. Eso es un primitivo de escalada local si la ruta es escribible (o si el ejecutable del planificador se sustituye). Además `-ExecutionPolicy Bypass` en la línea de comandos hace que lo que importe sea **el contenido del archivo**, no la política del sistema. Mitigación real:

```powershell
icacls "C:\DefenderTray" /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)RX"
Get-ScheduledTask -TaskName "DefenderTray_*" | ForEach-Object { $_.TaskName; $_.Actions.Execute; $_.Actions.Arguments }
```

y desinstalar (`Unregister-ScheduledTask -TaskName "DefenderTray_Service" -Confirm:$false`) en cuanto no la necesites.

**L-5 / L-6 — cadena de suministro.** La actualización copia el asset `.ps1`/`.zip` de un release sobre el script en ejecución (creando `*.v<versión>.bak`) y **solo** rechaza el cambio si existía un asset con el hash. La descarga de `System.Data.SQLite.Core` 1.0.118.1 desde NuGet tampoco se contrasta. Mientras no estén firmadas ambas rutas, haz la actualización a mano y con diff: `git diff --no-index viejo.ps1 nuevo.ps1`, y conserva los hashes que publicas.

**L-7 / L-8 — crypto honesta: esto no es un sistema de secretos.** La contraseña del modo kiosco se compara contra `SHA256(texto)` truncado a 64 bits sin sal y con intentos ilimitados; la base de datos usa como contraseña `DTv8_MasterKey_<NOMBRE_DEL_EQUIPO>`: el nombre del equipo es público en un dominio y se lee sin permisos. Ninguno de los dos controles está pensado contra un atacante con tiempo y acceso al archivo, sino contra el uso accidental. Lo mismo para el **modo tutela** y para la contraseña de desinstalación: son un aviso, no una barrera.

## 🧰 Recomendaciones de uso seguro

1. **Arranca con `-audit` la primera vez** en cada equipo y cada versión: confirma que lo que registra coincide con lo que esperas cambiar.
2. **Carpeta dedicada y ACL cerradas** para el script (L-2 y L-4), mejor `-portable` con `DefenderTrayData\` dentro de esa carpeta que una `%LOCALAPPDATA%` con permisos heredados del perfil.
3. **Sin API donde no la necesites**: `-norest` en servidores, equipos compartidos y cualquier máquina que navegue por Internet.
4. **Corta el tiempo desprotegido**: desactiva, trabaja, **Activar** y verifica con `Get-MpComputerStatus` en una consola elevada; revisa que `RealTimeProtectionEnabled`, `TamperProtection` y el estado de `WinDefend` sean los correctos.
5. **Copia el `.reg` de `Backups\Registro`** fuera del equipo antes de tocar un servidor, y comprueba que importa en una VM antes de necesitarlo.
6. **No reutilices la contraseña del kiosco** en ningún otro sitio; considera la biométrica de Windows Hello como factor adicional, recordando que su negativa de consentimiento es reemplazable por la contraseña truncada.
7. **Restringe los canales salientes**: bot de Telegram solo para un chat propio, cuenta de servicio de Firebase con el rol mínimo de `roles/firebase.sdkAdminServiceAgent` y un proyecto aislado, webhooks a un destino TLS tuyo, y relay SMTP sin credenciales compartidas.
8. **No dejes `-https` en reposo**: genera un certificado en el almacén del equipo (L-11); bórralo.
9. **Limpia lo sensible**: `Forense\`, `Logs\`, `Auditoria\`, `updates\` y `Perfiles\` antes de entregar o reinstalar la máquina; y revisa `Get-MpPreference | Select-Object -ExpandProperty ExclusionPath`.
10. **Actualiza con verificación**: publica `SHA256SUMS` con el release y confirma siempre `Get-FileHash` antes de ejecutar nada descargado.
11. **Documenta el uso en tu organización**: si la política de tu empresa exige aprobación para tocar `DisableAntiSpyware`, la herramienta no te exime de tramitarla.
12. **Asume que el `.ps1` es legible**: no hay ofuscación ni protección anticopia, y cualquiera con el archivo puede auditar lo que hace con sus privilegios.

## 🩺 Hacia dónde va el arreglo (para quien quiera parchear)

Orden de prioridad que el mantenimiento acepta como base de trabajo, con el ancla de código correspondiente de la v8.1:

1. **API local:** rechazar peticiones cuyo `Origin`/`Referer` no sea `http(s)://127.0.0.1:<puerto>`, aceptar solo `POST` en `/emergency` y `/fleet/command`, y validar `action` contra una lista blanca (`enable|disable`) antes de armar la línea de comandos. Añadir un token de sesión aleatorio en cabecera para todo lo que escriba ([`Initialize-RESTApi`](versiones/8/DefenderTray_8.1_Pro.ps1)).
2. **Exclusión:** escribirla sobre la carpeta de datos propia y **quitarla** en la salida y en `Enable-Defender`, o hacerla opt-in explícito en Configuración ([`SECCION 62`](versiones/8/DefenderTray_8.1_Pro.ps1)).
3. **Respaldos:** exportar todas las claves que se borran y acompañarlas de un manifiesto con hash y hora.
4. **Kiosco y desinstalación:** PBKDF2-SHA256 con sal aleatoria, longitud completa del digest y umbral de intentos con retardo creciente.
5. **Actualizaciones:** exigir asset de checksum o firma Authenticode válida y comprobar el `signtool`/`Get-AuthenticodeSignature` del release antes de copiar sobre el script.
6. **SQLite:** clave aleatoria de 32 bytes guardada con DPAPI en lugar de derivarla del nombre del equipo, y verificación de hash para el paquete descargado.

Manda el parche siguiendo [CONTRIBUTING.md](CONTRIBUTING.md#-cambios-sensibles-tienen-revisión-extra) y entra en la revisión de seguridad.

## 📚 Referencias

- [Descripción general de la protección frente a manipulaciones (tamper protection)](https://learn.microsoft.com/en-us/defender-endpoint/prevent-changes-to-security-settings-with-tamper-protection)
- [Preferencias de análisis y exclusiones de Microsoft Defender](https://learn.microsoft.com/en-us/defender-endpoint/preferences-run-antimalware-configuration) · [Configuración de Defender con directivas de grupo](https://learn.microsoft.com/en-us/defender-endpoint/use-group-policy-microsoft-defender-antivirus) · [Modo de solución de problemas de la protección frente a manipulaciones](https://learn.microsoft.com/en-us/defender-endpoint/troubleshoot-problems-with-tamper-protection)
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) · [Cryptographic Storage](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html) · [Transport Layer Security](https://cheatsheetseries.owasp.org/cheatsheets/Transport_Layer_Security_Cheat_Sheet.html)
- [Privilege Escalation en tareas programadas — MITRE ATT&CK T1053.005](https://attack.mitre.org/techniques/T1053/005/) · [Defender Tamper Protection: T1562.001](https://attack.mitre.org/techniques/T1562/001/)
- [RFC 9116 `security.txt`](https://www.rfc-editor.org/rfc/rfc9116) para que cada organización publique su propio contacto.

---

<a id="english"></a>

## 🇬🇧 English

DefenderTray is a **dual-use** tool: its purpose is to switch Microsoft Defender off and back on. That power is by design, not a bug. This page states what the script does with your administrator rights, what it does **not** protect you from, and how to close each gap until it is fixed in code.

### 📦 Supported versions

**8.1 ULTIMATE** (branch `main`) receives security fixes; 8.0 gets the same patch while no 8.2 exists; 7.0, 6.0 and everything ≤ 5.0 Pro are unsupported. Always report the exact version **and SHA256** of the `.ps1` you run (`Get-FileHash`).

### 📣 Reporting a vulnerability

> [!CAUTION]
> **Do not open a public issue, discussion or pull request** for a vulnerability, and never put the word "exploit" in a title.

1. Use **GitHub private vulnerability reporting**: **Security** tab → **Report a vulnerability**, or [this form](https://github.com/yhquintero/DefenderTray/security/advisories/new).
2. If the form is unavailable, open an issue titled **"Security contact request"** with **no technical details** and we will give you a private channel.
3. If a specific organisation's deployment is affected, notify its security owner too.

Include: script version/SHA256, Windows build, PowerShell version, elevation, the arguments and Configuration toggles in play, minimal reproduction steps (on a VM with a snapshot — never on a production box), impact and, if you have one, the patch. Do **not** include third-party hostnames, Telegram/Firebase tokens, `config.dat` contents, production `.reg` files, or logs naming other users.

We aim to acknowledge within **3 business days** and respond within **30 days** — a stated intention, not an SLA, since the project is maintained by one person. Please hold disclosure until a fix exists or **90 days** after first contact. With your permission we will credit you in the GitHub Security Advisory. There is no paid bug bounty.

**Out of scope:** Windows/Defender itself (report to [MSRC](https://msrc.microsoft.com/report/vulnerability)), machines already compromised by an attacker holding `SYSTEM`, physical attacks without BitLocker, social engineering, volumetric DoS, third-party provider issues without demonstrable impact on DefenderTray, older versions, modified third-party copies, and antivirus detections of the script (expected for its purpose).

### 🚧 Known limitations (open in v8.1)

| ID | Limitation | Severity | Mitigate now |
|---|---|---|---|
| L-1 | Local API has **no authentication** and no origin check; `GET /emergency` changes state, and `POST /fleet/command` interpolates a caller-supplied `action` into a `Start-Process` command line | **High** | Start with `-norest` or turn off "API REST local". |
| L-2 | `Add-MpPreference -ExclusionPath <script folder>` runs at every elevated start and is **never removed** — anything in that folder escapes scanning (Downloads/Desktop are common choices) | **High** | Run from a dedicated, access-controlled folder; check `Get-MpPreference \| Select-Object -ExpandProperty ExclusionPath` and delete the exclusion afterwards. |
| L-3 | `reg delete` removes four `Policies` keys but only `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender` is backed up first | **High** | Export the other three yourself before disabling. |
| L-4 | Scheduled tasks / "service" run the script as **`SYSTEM`** with `-ExecutionPolicy Bypass` from a possibly user-writable path → local privilege escalation primitive | **High** | `icacls "C:\DefenderTray" /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)RX"`; unregister when done. |
| L-5 | Auto-update verifies SHA256 **only if** the release ships a checksum asset, and does not check code signatures | Medium | Publish `SHA256SUMS`, or keep `CfgGitHubRepo` at its placeholder and update manually. |
| L-6 | SQLite provider is auto-downloaded from NuGet **without hash verification** | Medium | Pre-place both DLLs in `lib\`, or block `www.nuget.org` for the process. |
| L-7 | SQLite database password derives from the **computer name** (`DTv8_MasterKey_<HOST>`) | Medium | Store nothing sensitive in the DB; file ACLs are the actual control. |
| L-8 | Kiosk/uninstall password is an **unsalted SHA-256 truncated to 16 hex chars**, no lockout or delay | Medium | Use a long unique passphrase and treat it as a speed bump, never a boundary; don't reuse it. |
| L-9 | Telegram token and FCM service-account JSON are readable by any process running as you (DPAPI is per-user, not per-application) | Medium | Least-privilege bot, isolated Firebase project, rotate often, no screenshots of the Settings dialog. |
| L-10 | Forensic mode writes **unencrypted full-screen screenshots**, and the 30-day purge is not recursive, so `Forense\<stamp>\screenshot.png` stays forever | Medium | Enable only on your own machines; wipe `Forense\` before handing a machine over. |
| L-11 | `-https` creates a 5-year self-signed certificate with private key in `LocalMachine\My` | Low | Delete it after use. |
| L-12 | Webhooks POST to any URL you configure (hostname + timestamp), TLS not enforced → internal SSRF possible | Low | `https://` to your own endpoint only. |
| L-13 | `/diagnostic` reveals version, feature flags, author and phone numbers | Low | Disable the API if that bothers you. |
| L-14 | Logs and history are plain files with no integrity protection: whoever can write `%LOCALAPPDATA%\DefenderTray` can erase the trail | Low | Ship `Logs\` and `Auditoria\` to append-only storage. |

### 🧰 Safe-use checklist

Dry-run with `-audit` first; use a dedicated folder with strict ACLs; keep the API off where it is not needed; keep the unprotected window as short as possible and re-verify with `Get-MpComputerStatus`; copy the `.reg` backups off-box and test that they import; never reuse the kiosk password; lock down notification channels; remove the HTTPS certificate afterwards; wipe forensic/log/profile folders before decommissioning; verify hashes before running any update; follow your organisation's approval process — the tool does not replace it.

Fix priorities the maintainer will review as a working base: origin checks plus a session token and `action` allow-list on the API; removing the Defender exclusion on exit; backing up every key that is deleted; PBKDF2 with salt and lockout for passwords; mandatory checksum/signature on updates; random DPAPI-protected SQLite key with verified NuGet download. Send patches per [CONTRIBUTING.md](CONTRIBUTING.md) and they enter the security review track.

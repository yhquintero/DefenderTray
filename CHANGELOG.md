# Registro de cambios · Changelog

🌐 **Español** · [English](#english)

Historial de DefenderTray reconstruido **a partir de lo que declaran los propios scripts**: los bloques `<# … #>` de cada archivo (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES`, «Novedades vX» y «Fixes»). No se añade ninguna mejora que no esté escrita en el código.

> [!NOTE]
> **Sin fechas deliberadamente.** El repositorio tiene un único commit, **ni tags ni GitHub Releases**, así que poner fechas aquí sería inventar. En cuanto existan etiquetas `v8.1`, `v8.0`…, cada encabezado debería llevar la fecha del tag correspondiente (ver [cómo publicar](#-cómo-mantener-este-archivo)).
>
> El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/) (`Añadido`, `Cambiado`, `Corregido`, `Obsoleto`) y la numeración del proyecto es *ad-hoc*: la rama 4.x usó sufijos `+`, `Pro`, `_Final` en lugar de números.

## [Sin publicar] — conservación de firmas y botones (2026-10-18)

### Corregido

- La versión mantenida **8.2** pausa únicamente la protección en tiempo real. Ya no mata `MsMpEng`, `MpCmdRun` ni otros procesos, deshabilita servicios/controladores, cambia Tamper Protection o borra políticas al desactivar. Windows puede reactivar automáticamente la pausa.
- Activar no detiene ni reinicia el motor. La recuperación de bloqueos antiguos elimina valores concretos, con respaldo previo, sin borrar ramas completas ni `Signature Updates`. No recupera políticas que una versión anterior ya haya eliminado.
- **Reparar Firmas** y la reparación automática actualizan sin eliminar definiciones. Se quitan `-RemoveDefinitions -All` y el parámetro inválido `-UpdateInterval 0`. Se comprueban versión y fecha; un fallo de descarga no se etiqueta como éxito.
- Los botones **Activar / Desactivar** recuperan las posiciones de 8.1, uno junto al otro. Se modifica realmente `Enabled`, no solo el color. Al finalizar una operación se recalculan: ACTIVO permite desactivar, una pausa permite activar y PARCIAL prioriza recuperar protección; ocupado bloquea ambos.
- El estado consulta `Get-MpComputerStatus`: ni un proceso activo ni políticas pendientes bastan para anunciar éxito. `Set-MpPrefValue` usa `ErrorAction=Stop` para detectar errores no terminantes.
- Reparación profunda ya no ofrece matar el motor ni borrar ramas completas de políticas.

### Añadido

- [Pruebas y protocolo manual](tests/README.md): contratos estáticos Python y suite PowerShell con Defender/registro/descargas simulados, integrada en CI de Windows. La validación real en una VM Windows sigue siendo necesaria.

Las notas históricas que siguen describen el comportamiento anterior, no el control de protección corregido.

## [Sin publicar] — infraestructura del repositorio

No cambia el comportamiento del script: es todo lo que hay a su alrededor.

### Añadido

- Documentación de proyecto completa: [README.md](README.md) reescrito, [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) con los límites auditados de la v8.1 y [LICENSE](LICENSE) propietaria bilingüe.
- Este registro de cambios y el índice del histórico en [`versiones/README.md`](versiones/README.md).
- Integración continua (`.github/workflows/ci.yml`): parseo de los `.ps1` de la versión soportada (bloqueante), comprobación de BOM y CRLF (bloqueante), aviso de literales no ASCII, `PSScriptAnalyzer` y verificación de enlaces y anclas con `.github/check_markdown_links.py`.
- Plantillas de issue (error y propuesta), plantilla de pull request y `dependabot.yml` para las acciones.
- [`.gitignore`](.gitignore) para el estado local que genera la herramienta y [`.gitattributes`](.gitattributes) para fijar CRLF en los `.ps1`.

## [Sin publicar] — administrador siempre, MSI que compila

### Anadido

- **Auto-elevacion a Administrador** en las tres versiones de la v8 (`8.0`, `8.1`, `8.2`): nueva seccion 2b que comprueba los privilegios al arrancar y, si no los tiene, se relanza con UAC como Administrador conservando motor, argumentos y codigo de salida. Sin privilegios, el script deja de avisar «ejecuta como Administrador» y hace lo que puede hacer. Con `-noelevate` se desactiva (pruebas, auditoria, equipos sin UAC).
- `versiones/8/Add-WiXToPath.ps1`: anade `C:\Program Files (x86)\WiX Toolset v3.11\bin` al PATH de Windows (`-Scope User` o `-Scope Machine`, `-SessionOnly` para no tocar el registro, `-Remove` para quitarlo).
- `versiones/8/build-msi.ps1`: compila el MSI de una vez (candle + light), copia el script con el nombre que espera el `.wxs`, adapta la plantilla a la version pedida y comprueba el resultado.

### Corregido

- **El `.wxs` ya compila sin errores ICE.** `ICE80` (`This 32BitComponent ... uses 64BitDirectory INSTALLFOLDER`): el paquete es x64 (`Platform="x64"`) y los componentes son de 64 bits (`Win64="yes"`), ademas de `-arch x64` al compilar. `ICE64` (`The directory ProgramMenuDir is in the user profile but is not listed in the RemoveFile table`): el componente del acceso directo pasa a vivir dentro de `ProgramMenuDir` con `RemoveFolder` sobre esa misma carpeta y su clave de registro pasa de `HKCU` a `HKLM`, con lo que el acceso directo es por maquina. Las plantillas embebidas en los tres scripts y la del repositorio quedan iguales.
- `New-WixInstallerPackage` (el generador de MSI del panel) ya no exige que WiX este en el PATH: localiza `candle.exe`/`light.exe` en las instalaciones habituales de WiX v3 y anade la carpeta al PATH de la sesion antes de compilar.

## [8.2 ULTIMATE] ⭐ actual

📄 [`versiones/8/DefenderTray_8.2_Pro.ps1`](versiones/8/DefenderTray_8.2_Pro.ps1) · 5 119 líneas · 66 secciones · 144 funciones

### Corregido

- **Bug crítico de `Set-MpPreference` que causaba activaciones y desactivaciones parciales.** Las llamadas de las secciones de activar/desactivar hacían `Set-MpPreference @{ $p = $true } -Force`: PowerShell intenta enlazar el hashtable como parámetro *posicional* (falla siempre) y `-Force` **no existe** en `Set-MpPreference`, así que **todas** las llamadas —las 13 preferencias con hashtable y las nominales con `-Force`— fallaban en silencio (`catch { }`) y las 15+ protecciones nunca se aplicaban. Ahora cada preferencia se aplica por su nombre real mediante *splatting* (`Set-MpPrefValue`).
- Mismo `-Force` inválido eliminado de `Add-MpPreference` (exclusiones) y de `Set-MpPreference -DisableRealtimeMonitoring` del Deep Repair.

### Cambiado

- **Desactivación TOTAL en una sola pasada**: preferencias reales → políticas ampliadas (AntiSpyware, RTP, Spynet, Exploit Guard/Network Protection, PUA, SmartScreen) → FailureActions → muerte de procesos + `Start=4` con reintentos → intento de bajar Tamper Protection por registro → verificación granular.
- **Activación TOTAL en una sola pasada**: servicios restaurados → políticas eliminadas (incluidas ExploitGuard/PUA/SmartScreen) → claves RTP limpiadas → 13 preferencias reactivadas con reintentos hasta confirmar Protección en tiempo real → Tamper Protection → verificación.
- **Un solo clic, sin dobles clics**: eliminado el diálogo de confirmación «Desactivar Windows Defender?» y el diálogo modal de resultado de la acción rápida; el resultado se avisa por globo. El sentido del interruptor se decide solo: ACTIVO → desactiva; DESACTIVADO → activa; PARCIAL → termina lo que esté a medias.
- **Tamper Protection ya no aborta** la desactivación: se aplica todo lo posible (lo persistente se conserva) y, si Windows bloquea el resto, se guía con un botón para abrir Seguridad de Windows (`windowsdefender://threatsettings`).
- **Estado `DESACTIVADO` real**: con políticas + servicios deshabilitados se reporta `DESACTIVADO` (con el detalle «reinicio pendiente» cuando Windows 11 22H2+ aún no ha soltado `WinDefend`), no `PARCIAL`. `PARCIAL` queda reservado a estados a medio hacer.
- En `PARCIAL`, el panel indica que **ACTIVAR** restaura la protección y que el interruptor contextual sigue la acción pendiente; ya no hay que depender del menú `Acciones` para encontrar la activación.

### Añadido

- Interruptor contextual **«UN CLIC»** en el panel (botón grande que cambia de texto y color según la acción), además de `Activar` y `Desactivar` directos en los menús.
- Botón verde **ACTIVAR PROTECCIÓN** siempre visible en el panel, también en estado `PARCIAL`; ejecuta `Enable-Defender`, actualiza la interfaz y registra el resultado.
- CLI: `-action toggle` además de `enable`/`disable`.
- Helpers `Set-MpPrefValue`, `Test-TamperProtectionActive`, `Disable-TamperProtectionBestEffort`, `Show-TamperProtectionGuide`, `Test-DefenderServicesDisabled`, `Get-ToggleAction`, `Invoke-ToggleProtection`, `Invoke-EnableProtection` y `Set-ToggleButtonLook`.

## [8.1 ULTIMATE]

📄 [`versiones/8/DefenderTray_8.1_Pro.ps1`](versiones/8/DefenderTray_8.1_Pro.ps1) · 4 747 líneas · 65 secciones · 134 funciones

### Corregido

- Cadenas de versión en el título de la ventana (ES/EN), en la Ayuda, en el diálogo de Configuración, en `/diagnostic` y en las plantillas embebidas de MSI/WiX.

> [!IMPORTANT]
> **v8.1 no contiene cambios funcionales respecto a v8.0.** La comparación línea a línea de ambos archivos da 142 líneas distintas y **todas** son cadenas de versión. Todo lo que se atribuye a la 8.1 es obra de la 8.0. Si publicas releases, evita el patrón «renombrar y subir»: usa `v8.0` para esas quince funciones y deja la 8.1 como revisión de texto.

## [8.0 ULTIMATE]

📄 [`versiones/8/DefenderTray_8.0_Pro.ps1`](versiones/8/DefenderTray_8.0_Pro.ps1) · salto de 166 734 → 236 088 bytes sobre la 7.0

### Añadido

1. Base de datos **SQLite real con cifrado** (AES-256 vía proveedor, contraseña derivada con DPAPI) y respaldo automático a JSON si el proveedor no está disponible.
2. **Firma digital Authenticode** de reportes + guía de certificado EV (con `Get-CodeSigningCert`, `Sign-FileAuthenticode` y `Show-CertificateGuide`).
3. **Instalador MSI generado con WiX Toolset**, con el `.wxs` embebido en el script.
4. Notificaciones **push por Firebase Cloud Messaging (FCM v1)** con token OAuth2 de cuenta de servicio.
5. **Panel de administración multi-equipo** (consola Fleet servida por la API local).
6. **Detección de anomalías** con estadística Z-score sobre una línea base de métricas del sistema.
7. **Integración con Active Directory**: equipos, usuarios e inventario.
8. **API GraphQL** (subconjunto) además de REST.
9. **PWA instalable** (manifiesto, *service worker* e iconos servidos por la API local).
10. **Kiosco biométrico** con Windows Hello (`UserConsentVerifier`), con alternativa de contraseña.
11. **Webhooks** de eventos (POST JSON configurable, filtros por tipo de evento).
12. **Exportación a Excel** (`.xlsx` vía módulo `ImportExcel` o COM de Excel) **y CSV**.
13. **Dashboard en tiempo real** por Server-Sent Events.
14. **Autoactualización desde GitHub Releases** con verificación SHA256 cuando el release incluye el asset de `SHA256SUMS`.
15. **`Dockerfile` y `docker-compose`** generados desde el propio script para despliegue de la consola.

### Cambiado

- Reorganización del arranque en secciones numeradas (`§62 ARRANQUE v8.1`), con inicialización de SQLite, migración del historial, registro en Fleet, hash del script y exclusión de Defender del directorio del script.

## [7.0 ULTIMATE]

📄 [`versiones/7/DefenderTray_7.0_Pro.ps1`](versiones/7/DefenderTray_7.0_Pro.ps1)

### Añadido

1. Panel web HTML5 servido por la API REST · 2. Multiusuario con perfiles (SQLite simulado con JSON) · 3. Notificaciones móviles por **Telegram Bot** · 4. Autorreparación inteligente con heurística · 5. Control por voz (Windows Speech Recognition) · 6. Exportación a PDF firmado digitalmente · 7. **Modo de emergencia (botón de pánico)** · 8. Historial del **Event Log de Windows Defender** · 9. Integración con captura de tráfico · 10. Copia de seguridad a la nube (OneDrive/Google Drive) · 11. Soporte multi-monitor (diálogos en el monitor activo) · 12. Tema personalizable con editor de colores · 13. Modo tutela (bloqueo parental) · 14. API para móvil (endpoints JSON) · 15. **Modo forense** (captura de pantalla + logs antes de cada cambio).

### Corregido

- Saltos de línea `\r\n` (CRLF) en los diálogos.
- API REST con reserva `urlacl` y HTTPS opcional.
- Certificado autofirmado para HTTPS.

## [6.0 ULTIMATE]

📄 [`versiones/6/DefenderTray_6.0_Pro.ps1`](versiones/6/DefenderTray_6.0_Pro.ps1)

### Añadido

1. **Agente residente** (watcher WMI de cambios en Defender) · 2. Autocomprobación de versión remota · 3. Tema claro/oscuro automático según el sistema · 4. Integración con Windows Terminal · 5. Soporte de **PowerShell 7+** (paralelización de servicios) · 6. Reportes por **correo SMTP** · 7. **API REST local** (`HttpListener` en `127.0.0.1:9182`) · 8. Autenticación **Windows Hello** con alternativa de contraseña · 9. Asistente de firma Authenticode · 10. Asistente de empaquetado MSI · 11. **Alertas por umbral** (aviso si está desactivado más de X horas) · 12. Reglas de firewall (`netsh advfirewall`) · 13. **Modo auditoría** (registra sin aplicar) · 14. **Cifrado de la configuración con DPAPI** · 15. Soporte de **Windows Server**.

## [5.0 Pro]

📄 [`versiones/5/DefenderTray_5.0_Pro.ps1`](versiones/5/DefenderTray_5.0_Pro.ps1)

### Añadido

Logs con ajuste de línea automático (scroll solo vertical) · quince mejoras continuas integradas · autorreparación de firmas al iniciar · **programador de tareas** · instalación como servicio (tarea programada) · respaldo y restauración del registro de políticas · detección de antivirus de terceros · diagnóstico de red y conectividad · multi-idioma ES/EN (parcial) · limpieza automática de logs de más de 30 días · verificación SHA256 del script · estadísticas históricas · **contraseña de desinstalación**.

## [4.5 Pro]

📄 [`versiones/4/DefenderTray_4.5_Pro.ps1`](versiones/4/DefenderTray_4.5_Pro.ps1)

### Corregido

- Diálogo de resultado con scroll **solo vertical**.
- Activación con arranque ordenado por dependencias (corrige el doble clic necesario en 4.3.x).
- Reparación de la base de datos de firmas corruptas (errores 31 / 12 / 1969).
- Mensajes claros sobre Windows 11 y reinicio requerido.

### Añadido

- Botón extra **«Reparar Firmas»** dentro de la Reparación Profunda.

## [4.4 Pro]

📄 declarado en la cabecera de [`DefenderTray_4.3.3_Pro.ps1`](versiones/4/DefenderTray_4.3.3_Pro.ps1) — ⚠️ **el nombre del archivo dice 4.3.3 y la cabecera dice v4.4**; no hay un archivo `4.4`.

### Añadido

Diálogo de resultados con barra vertical · botones deshabilitados durante las operaciones · *Deep Repair* y Configuración 100 % en español · bucle de reintentos de `Set-MpPreference`.

### Corregido

- Ya no requiere doble clic para activar.
- Barra de estado con texto completo.

## [4.3.1 Pro]

📄 [`DefenderTray_4.3.1_Pro.ps1`](versiones/4/DefenderTray_4.3.1_Pro.ps1) (existe una copia gemela `… - copia - copia.ps1`, bytes idénticos)

### Añadido

- Desactivación con **bucle de verificación de 5 intentos**.
- Deshabilitación de *FailureActions* (evita la autorrecuperación de Windows).
- Muerte de `MsMpEng` **antes** de detener `WinDefend` (desestabiliza el servicio).
- El diagnóstico indica qué drivers requieren reinicio.

### Corregido

- *Timer* con ticks (evita `op_Subtraction`).
- `return` dentro de `switch` → `if`/`elseif`.

## [4.3 Pro] y sus variantes `+`, `++`

📄 [`DefenderTray_4.3_Pro.ps1`](versiones/4/DefenderTray_4.3_Pro.ps1) · [`+DefenderTray_4.3_Pro.ps1`](versiones/4/+DefenderTray_4.3_Pro.ps1) · [`DefenderTray_4.3_Pro+.ps1`](versiones/4/DefenderTray_4.3_Pro+.ps1) · [`DefenderTray_4.3_Pro++.ps1`](versiones/4/DefenderTray_4.3_Pro++.ps1)

### Añadido

- Iconos dinámicos verde/rojo/naranja según estado, y **icono oficial de Microsoft** en las variantes `+`.
- Activación completa de las **15+ protecciones**; desactivación total de los **8 servicios y 6 procesos**.
- Diagnóstico detallado por servicio, proceso, módulo y registro.
- Reparación profunda con consola en vivo (`reg delete`, `sc`, `sfc`, `DISM`).
- Modo kiosco con contraseña hasheada (SHA-256), barra de estado contextual y atajos de teclado.

## [4.3] y [4.3+]

📄 [`DefenderTray_4.3.ps1`](versiones/4/DefenderTray_4.3.ps1) · [`DefenderTray_4.3+.ps1`](versiones/4/DefenderTray_4.3+.ps1)

- Desactivación total agresiva (mata `MsMpEng.exe`), barra de menú restaurada, **modo kiosco funcional con contraseña** y bordes ajustados.

## [4.2] y [4.2 Final]

📄 [`DefenderTray_4.2.ps1`](versiones/4/DefenderTray_4.2.ps1) · [`DefenderTray_4.2_Final.ps1`](versiones/4/DefenderTray_4.2_Final.ps1)

### Añadido

- Módulo de **Reparación Profunda** con consola de registro en vivo (ejecuta `reg delete`, `sc config`, `gpupdate`, `sfc`, `DISM`).

### Corregido

- Todas las asignaciones a `AppConfig` con notación de índice en vez de punto (motivo por el que nació [`Reparar-DefenderTray.ps1`](versiones/4/Reparar-DefenderTray.ps1)).
- En la *Final*: sin hashtable en el ámbito del script, sin `AccentTeal`, sin funciones anidadas, configuración en variables individuales.

## [4.1] y [4.0]

📄 [`DefenderTray_4.1.ps1`](versiones/4/DefenderTray_4.1.ps1) · [`DefenderTray_4.0.ps1`](versiones/4/DefenderTray_4.0.ps1)

- **4.1** — «Completa y corregida», *Futuristic Edition*; el archivo más grande de la rama 4 hasta la 4.5 y el único con respaldo `.backup_*` en el repositorio.
- **4.0** — Edición futurista con todas las mejoras profesionales previas integradas: programador, perfiles, respaldo y restauración, gráfico, eventos, kiosco, autodiagnóstico, **modo portable**, notificaciones *toast*, integridad y multi-idioma.

## [3.12] → [3.0]

La rama 3.x es donde el proyecto pasó de «script con menú» a aplicación de administración. Cada archivo declara su propia `.DESCRIPTION`:

| Versión | Cambios declarados en la cabecera |
|---|---|
| **3.12** | Sistema de ayuda en tiempo real: tooltips en todos los controles, barra de estado con ayuda contextual, ayuda `F1` con pestañas temáticas, asistente de primera ejecución, autoinicio con Windows y atajos (`F1`, `F5`, `Ctrl+R`, `Esc`). |
| **3.11** | Desactivación agresiva completa (`reg delete` + `sc config` + `Start=4`), historial de las últimas 20 operaciones, notificaciones *toast*, exportación del log a CSV y `Ctrl+R`. |
| **3.10** | Ámbitos corregidos: sin funciones anidadas en los manejadores de eventos; verificación de 18 módulos; panel único; diálogo de opciones avanzadas al activar; *timer* a 5 s con consultas ligeras; **log en `%LOCALAPPDATA%\DefenderTray\Logs\`**. |
| **3.8.1** | Panel único (singleton) con controles en `$script:`; *timer* y eventos fiables en cualquier momento. |
| **3.8.0** | Verificación completa de los 18 módulos de Defender, botón «Verificar estado completo», salida integrada en la columna de botones, panel *singleton* que se trae al frente y **intento honesto de activar Tamper Protection con verificación**. |
| **3.7** | Optimizada (sin congelamiento del sistema) y diálogo de opciones avanzadas al activar: **MAPS/nube, envío de muestras y protección contra alteraciones**. |
| **3.6** | Versión optimizada para no congelar el sistema: *timer* a 5 s con consultas ligeras (sin WMI), caché de 30 s, `DoEvents` para no bloquear la UI y se retira `Update-MpSignature` (provocaba esperas de descarga). |
| **3.5** | *Timer* en tiempo real con segundos transcurridos por operación, refresco automático cada 2 s, botón de salida anclado al fondo, textos sin truncar y **desactivación reforzada con verificación y reintento**. |
| **3.4** | Criterio estricto del estado ACTIVADO: `WinDefend` corriendo **y** `RealTimeProtectionEnabled` **y** sin políticas `DisableAntiSpyware`/`DisableAntiVirus`. |
| **3.3** | El estado se calcula con `AMServiceEnabled`, no con `AntivirusEnabled`, porque este último no cambia al detener el servicio. |
| **3.2** | Quinto botón «Ver Registro» en el panel. |
| **3.1.1** | Verificación inicial obligatoria del estado al arrancar, con mensaje claro; cuatro botones siempre visibles; color por acción disponible. |
| **3.1** | Ajustes del panel compacto y del menú en texto plano. |
| **3.0** | Exclusión de Defender para que el script no sea detenido, ventana «Acerca de…», detección del sistema operativo y botones habilitados/deshabilitados según estado. |

## [2] y [1]

| Versión | Cambios declarados en la cabecera |
|---|---|
| **2** | Icono en la bandeja con menú contextual **en texto plano** (sin caracteres especiales), modal visual compacto y colorido con Activar / Desactivar / Salir y verificación del estado tras cada acción. |
| **1** | Utilidad de bandeja para activar y desactivar Defender (servicio, tiempo real y registro), con verificación posterior y notificación. Compatible declarada con Windows 7, 8, 8.1, 10 y 11 (24H2, 25H2, 26H2). |

## Herramientas auxiliares

| Herramienta | Qué hace |
|---|---|
| [`versiones/4/Reparar-DefenderTray.ps1`](versiones/4/Reparar-DefenderTray.ps1) | Parcheador automático de `DefenderTray_4.1.ps1`: sustituye la notación de punto por índice en las asignaciones a `$script:AppConfig`, **valida la sintaxis final con el parser de PowerShell**, crea un `.bak` con marca de tiempo y emite un informe de los cambios. Antecedente directo de la comprobación de sintaxis de la [integración continua](.github/workflows/ci.yml). |
| [`versiones/2/WiFi_1126H2_2.1.ps1`](versiones/2/WiFi_1126H2_2.1.ps1) | **No es de DefenderTray:** gestor de hotspot WiFi v2.1 (activa el punto de acceso aunque no haya Internet), con autoelevación. Está depositado aquí por error; ver [pendientes de limpieza](#-pendientes-de-limpieza-registrados). |

## 🧹 Pendientes de limpieza registrados

Detectados al redactar este historial; cada uno merece su propio pull request:

1. `versiones/4/DefenderTray_4.1.ps1.backup_2026-10-15_211129.bak` — respaldo en el repositorio (ahora lo impide [`.gitignore`](.gitignore)).
2. `versiones/4/DefenderTray_4.3.1_Pro - copia - copia.ps1` — duplicado idéntico (mismos 101 700 bytes) del archivo vecino.
3. `versiones/revisar` — archivo vacío (un solo salto de línea): una nota personal «revisar» que no describe nada.
4. Cuatro variantes de la 4.3 Pro (`+`, `++`, prefijo `+` y la base) con la misma cabecera: hay que decidir cuál es la buena y mover el resto a un histórico.
5. `DefenderTray_4.3.3_Pro.ps1` se autodenomina **v4.4** en su cabecera: renombrar el archivo o corregir la cabecera.
6. `WiFi_1126H2_2.1.ps1` fuera de lugar; y su propia cabecera recomienda «UTF-8 con BOM» mientras el archivo está guardado **sin BOM**.
7. Sin `v` inicial ni tags: publicar `v8.1` como GitHub Release con el `.ps1` y su `SHA256SUMS` permitiría usar la autoactualización y fechar este archivo.
8. La cabecera de la v8.1 mantiene el contacto telefónico del autor en claro; si eso no es lo que quieres publicar, conviene moverlo a la documentación y dejar en el script solo el enlace al repositorio.

## 📦 Cómo mantener este archivo

- **Una línea por cambio**, en la sección `Añadido`/`Corregido` de la versión en curso, con el imperativo en pasado («Añadido modo X», «Corregido el caso Y»).
- Cambia **a la vez** el bloque `<# Novedades vX sobre vY #>` de la cabecera del script: es la fuente de este registro y de la Ayuda (`F1`).
- Al publicar una versión: `git tag v8.2 && git push origin v8.2`, crea el release con el `.ps1` y un asset `SHA256SUMS`, y añade la fecha real a la entrada de arriba.
- Antes de abrir el pull request: `python .github/check_markdown_links.py`, que es lo que corta la integración continua si dejas un enlace o una ancla rotos.
- Los cambios de comportamiento sensibles (desactivación, API, cifrado, red, persistencia) merecen también una línea en [SECURITY.md](SECURITY.md), no solo aquí.

---

<a id="english"></a>

## 🇬🇧 English

This is the project's historical changelog, reconstructed from what the scripts themselves declare in their header comment blocks (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES`, «Novedades» and «Fixes» lists) — nothing here is invented or attributed to a release that does not document it.

Dates are deliberately absent: the repository has a single commit and **no tags and no GitHub Releases**, so dating these entries would be guesswork. Once tags exist, each entry should carry the tag date.

Highlights, newest first: **8.1** is a version-string-only revision of **8.0** (142 differing lines, all text), which added the fifteen enterprise features (encrypted SQLite, Authenticode signing and EV guide, WiX MSI packaging, FCM v1 push, Fleet console, Z-score anomaly detection, Active Directory, GraphQL, PWA, Windows Hello kiosk, webhooks, Excel/CSV export, SSE dashboard, GitHub auto-update with SHA256, Docker packaging); **7.0** added the web panel, Telegram, voice, signed PDFs, panic button, forensic and parental modes; **6.0** added the resident WMI agent, the local REST API on `127.0.0.1:9182`, DPAPI-encrypted settings, audit mode, SMTP, Windows Hello, threshold alerts, firewall rules and Windows Server support; **5.0** added the task scheduler, service installation, registry backup/restore and SHA256 self-verification; **4.x** grew the tray app into a professional control panel (deep repair console, kiosk password, dynamic icons, 8-service/6-process disable sequence) and **3.x/2.x/1** built the tray fundamentals and the "verify, don't guess" status logic.

The [clean-up list](#-pendientes-de-limpieza-registrados) records the repository hygiene issues found while writing this file: a `.bak` and an identical duplicate in `versiones/4/`, an empty `versiones/revisar`, four competing 4.3 Pro variants, a file named 4.3.3 whose header says v4.4, and a WiFi hotspot script that does not belong to this project.

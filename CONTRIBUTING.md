# Cómo contribuir · Contributing

🌐 **Español** · [English](#english)

¡Gracias por tu interés en mejorar DefenderTray! Esta guía explica cómo informar de errores, proponer mejoras, probar sin tumbar tu Windows y enviar cambios que se puedan revisar rápido.

> [!IMPORTANT]
> DefenderTray es **software propietario** ([LICENSE](LICENSE)). Al enviar una contribución aceptas la cláusula 6 de la licencia: el titular puede usar tu aportación como parte del producto. Contribuir no concede ningún derecho de uso sobre DefenderTray.

> [!WARNING]
> Estás tocando el código que **apaga el antivirus**. Los cambios en `Disable-Defender`, `Enable-Defender`, la API local, el cifrado, la autoactualización o la persistencia pasan por la [revisión sensible](#-cambios-sensibles-tienen-revisión-extra) y deben justificarse con un caso de uso legítimo y una forma de revertirlos.

## 🧭 Formas de contribuir

- 🐞 **Informar de un error** — usa la plantilla [Informe de error](https://github.com/yhquintero/DefenderTray/issues/new?template=bug_report.yml): pide versión, SHA256 del `.ps1`, build de Windows, línea de comandos y el fragmento de log. Varios campos son obligatorios a propósito, porque sin ellos no se reproduce nada.
- ✨ **Proponer una mejora** — con la plantilla [Propuesta de mejora](https://github.com/yhquintero/DefenderTray/issues/new?template=feature_request.yml), que empieza por el **problema** y sigue por el riesgo y la reversión; una propuesta sin problema descrito no se puede valorar.
- 🩺 **Casos de reparación** — los errores de firmas, servicios que reviven o `Start=4` que no se sostiene son el mejor regalo: describe el build, qué hiciste antes y qué dijo el diagnóstico.
- 📚 **Documentación** — [README.md](README.md), [CHANGELOG.md](CHANGELOG.md), esta guía y [SECURITY.md](SECURITY.md) se aceptan encantados; corregir una afirmación técnica equivocada de las que evitan un susto, mejor aún.
- 🌍 **Idiomas** — añadir o pulir claves de la tabla ES/EN del script.
- 🔒 **Vulnerabilidades** — **nunca** en público: usa el reporte privado descrito en [SECURITY.md](SECURITY.md#-cómo-reportar-una-vulnerabilidad).

## ✅ Antes de empezar

- Busca si ya existe un issue o un pull request sobre lo mismo.
- Para cambios grandes (una sección nueva, otro proveedor de datos, otra forma de persistencia, tocar la secuencia de 10 pasos), abre antes un issue y acordemos el enfoque: aquí el coste de equivocarse es una máquina sin protección.
- **Un pull request = un cambio.** «Arreglo del puerto + refactor de colores + i18n» se cierra y se pide separar.
- Si añades, renombras o quitas un archivo de `versiones/`, actualiza la tabla de índice de [`versiones/README.md`](versiones/README.md) y el [CHANGELOG.md](CHANGELOG.md): ese par es lo primero que lee quien llega sin contexto.
- Cambia **la versión actual** (`versiones/8/DefenderTray_8.1_Pro.ps1`), no las carpetas históricas: 1.x–7.x son archivo, no destino.
- No toques `versiones/4/DefenderTray_4.1.ps1.backup_*.bak`, `DefenderTray_4.3.1_Pro - copia - copia.ps1` ni `versiones/revisar`: son residuos catalogados en [CHANGELOG.md](CHANGELOG.md#-pendientes-de-limpieza-registrados). Si quieres proponer limpiarlos, hazlo en un pull request propio y sin tocar nada más.

## 🔨 Preparar el entorno

No hay compilación ni gestores de paquetes: es un archivo `.ps1` y se ejecuta tal cual.

| Requisito | Para qué |
|---|---|
| **Windows 10/11** en una **máquina virtual con instantánea** | No hay entorno de pruebas que no pueda romper el equipo: la herramienta cambia servicios y registro. |
| **Windows PowerShell 5.1** | Es el intérprete objetivo (los ensamblados WPF/Speech de la interfaz dependen de .NET Framework). |
| **Visual Studio Code** + extensión *PowerShell* | Navegación por las 65 secciones, análisis de sintaxis y formato. |
| `PSScriptAnalyzer` (opcional) | `Install-Module PSScriptAnalyzer -Scope CurrentUser` |
| Módulo `ActiveDirectory` (opcional) | Solo para probar la sección de inventario de AD; sin él debe degradar, no fallar. |

```powershell
git clone https://github.com/yhquintero/DefenderTray.git
cd DefenderTray
code .\versiones\8\DefenderTray_8.1_Pro.ps1

# Comprobación de sintaxis sin ejecutar nada: si $errs queda vacío, el archivo parsea
$errs = $null; $toks = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .\versiones\8\DefenderTray_8.1_Pro.ps1), [ref]$toks, [ref]$errs)
$errs | ForEach-Object { "{0}: {1}" -f $_.Extent.StartLineNumber, $_.Message }

# Análisis estático (recomendado, no bloqueante)
Invoke-ScriptAnalyzer -Path .\versiones\8\DefenderTray_8.1_Pro.ps1 -Severity Warning,Error
```

## 🧪 Banco de pruebas: cómo probar sin quedarte desprotegido

Sigue este orden en la máquina virtual y toma la instantánea **antes** del paso 2:

1. **Instantánea limpia** de la VM (con Defender en estado sano).
2. **Exporta el registro** que la herramienta puede borrar (los comandos están en [SECURITY.md](SECURITY.md#-los-límites-detallados), L-3) y guarda la salida en el escritorio de la VM.
3. **Modo auditoría**: `powershell -NoProfile -ExecutionPolicy Bypass -File .\DefenderTray_8.1_Pro.ps1 -audit`. Revisa `%LOCALAPPDATA%\DefenderTray\Logs\` y `Auditoria\`: no debe haber **ninguna** escritura aplicada.
4. **Desactivación controlada**: `-silent -action disable`, comprueba `Get-MpComputerStatus`, **reinicia** y vuelve a comprobar (así se ve si el estado queda o Windows lo revive).
5. **Reactivación**: abre el panel y pulsa *Activar*, o `-silent -action enable`. Verifica que Tamper Protection, `WinDefend` en ejecución y `RealTimeProtectionEnabled` quedan en `True`.
6. **Reparación profunda**: ejecuta *1. Borrar políticas* y *2. Servicios* en un equipo estropeado a propósito (p. ej. `sc config WinDefend start= disabled`) y confirma que lo devuelve a un estado saneable.
7. **Limpieza**: quita la exclusión de Defender creada al arrancar, `Unregister-ScheduledTask -TaskName "DefenderTray_*"` si creaste tareas, borra el certificado autofirmado si probaste `-https` y revierte la instantánea.

### Matriz de comprobaciones manuales

Ejecuta las filas relacionadas con tu cambio y pégalas en la descripción del pull request con ✅/❌:

| Área | Cómo se comprueba | Resultado esperado |
|---|---|---|
| Arranque | `powershell -File … .ps1` sin argumentos | Icono en la bandeja, color coherente con `Get-QuickStatus`, sin ventanas de error. |
| Colores/tema | Cambia el tema de Windows (claro/oscuro) y vuelve a abrir | La paleta sigue la del sistema si «Seguir tema del sistema» está activo. |
| Diálogos | `F1`, `F5`, `Esc`, cada botón del panel y del menú de la bandeja | Todos abren, muestran texto legible y cierran sin dejar procesos huérfanos. |
| i18n | Alterna `ES`/`EN` en Configuración y reabre | Ninguna cadena visible se queda en el idioma anterior ni aparece vacía. |
| Auditoría | `-audit` + una acción de desactivación | Log sin cambios reales; el estado de Defender no se mueve. |
| API local | `Invoke-RestMethod http://127.0.0.1:9182/status` y `/`, `/pwa/`, `POST /graphql` | JSON coherente, panel HTML, manifiesto PWA y datos GraphQL. Con `-norest`, el puerto debe estar cerrado. |
| Datos | Ejecuta con `-portable`, luego sin él | `.\DefenderTrayData\` frente a `%LOCALAPPDATA%\DefenderTray`, sin mezclar. |
| Historial | Varias acciones, abrir el diálogo **Historial** y exportar CSV/Excel | Entradas con fecha, acción, resultado y segundos; el archivo exportado se abre. |
| Respaldo | Desactivar y mirar `Backups\Registro\` | Existe un `.reg` con marca de tiempo que importa sin error en una VM. |
| Degradación | Renombra `lib\System.Data.SQLite.dll` y arranca | Aviso en el log y funcionamiento sobre JSON: **nada de cierres**. |
| Sin permisos | Ejecuta como usuario estándar | Diagnóstico disponible; las acciones explican por qué no aplican. |

## ✅ Comprobaciones automáticas

Estas son las mismas que ejecuta la [integración continua](.github/workflows/ci.yml); conviene correrlas antes de abrir el pull request:

| Comprobación | Cómo se ejecuta | Corte |
|---|---|:--:|
| Sintaxis de la versión actual | `Parser::ParseFile` sobre `versiones/8/*.ps1` (bloque del [entorno](#-preparar-el-entorno)) | ✅ bloquea |
| Sintaxis del histórico | lo mismo sobre el resto de `versiones/` | ⚠️ informativo: hay archivos antiguos sin soporte que no parsean |
| Codificación | sin BOM y sin líneas LF sueltas en todos los `.ps1` | ✅ bloquea |
| Literales ASCII | avisa de caracteres fuera del ASCII, que PowerShell 5.1 lee como ANSI | ⚠️ informativo |
| Análisis estático | `Invoke-ScriptAnalyzer -Path versiones\8 -Recurse -Severity Warning,Error` | ⚠️ informativo |
| Enlaces y anclas | `python .github/check_markdown_links.py` | ✅ bloquea |

El comprobador de documentación es de propósito general: si mueves o renombras un archivo y dejas un enlace roto, te dice la ruta y la línea.

## 📐 Estilo y convenciones

- **Un solo archivo, y que lo siga siendo.** No dividas en módulos ni en `lib/`: el requisito que sostiene el proyecto es «cópialo en una USB y arráncalo en un equipo recién formateado».
- **Estructura por secciones.** Respeta los banners `# SECCION N - TÍTULO` y su orden de dependencias (utilidades antes que UI, UI antes que el arranque, el arranque antes que la bandeja). Añade el código nuevo en la sección que le corresponda, y una sección nueva al final con numeración contigua.
- **`$script:` es el estado global.** Variables de configuración como `$script:CfgAlgo`, en PascalCase y agrupadas bajo su `# --- vN.N ---`.
- **Nombres de función** `Verbo-Sustantivo` en inglés (`Get-`, `Set-`, `Test-`, `Show-`, `Invoke-`, `New-`, `Add-`, `Start-`, `Stop-`, `Initialize-`); los diálogos siempre `Show-*Dialog`. El contenido de los diálogos y los comentarios van en español, sin acentos.
- **Nada de cadenas visibles hardcoded**: usa `T "Clave"` y añade la clave a **las dos** tablas (`ES` y `EN`). Los caracteres fuera del ASCII se componen con código (`"Contrase" + [char]0x00F1 + "a"`), como hace el archivo actual.
- **Multilínea en diálogos:** pasa el texto por `Normalize-LineEndings` (los `@'...'@` llegan con CRLF/LF mezclados y se ve torcido en pantalla).
- **Reglas de seguridad obligatorias en el código:**
  - Toda función que escriba registro, detenga servicios o borre claves **empieza** con la salida de auditoría, igual que `Disable-Defender`: `if ($script:AuditMode) { … return }`.
  - Antes del primer cambio destructivo, `Backup-DefenderRegistry` (y añade la clave nueva al respaldo si amplías el borrado).
  - Cada paso se registra con `Write-AppLog "…" "INFO|WARN|ERROR"` y cada acción acaba en `Add-HistoryDB`.
  - Los fallos se degradan con `-ErrorAction SilentlyContinue` + aviso, **nunca** con un `throw` que deje el equipo a medias.
- **Sin dependencias nuevas obligatorias.** Detecta y degrada: `if (Get-Command X -ErrorAction SilentlyContinue) { … } else { … }` (así funcionan `ImportExcel`, `ActiveDirectory` y SQLite).
- **Sin llamadas de red nuevas** ni canales de salida sin acordarlo antes en un issue: son superficie de fuga y entran en la revisión sensible.
- **Codificación y finales de línea resueltos por [`.gitattributes`](.gitattributes)**: los `.ps1` se checkean con CRLF y los documentos con LF, así que no toques `core.autocrlf` ni conviertas archivos «para que se vean bien»; la comprobación de formato lo vigila.
- **Codificación y finales de línea:** guarda los `.ps1` en **UTF-8 sin BOM** y **CRLF** (igual que los del repositorio). PowerShell 5.1 lee sin BOM como ANSI, así que la combinación segura es: BOM ausente + literal ASCII. Compruébalo antes de commitear:

  ```powershell
  $b = [IO.File]::ReadAllBytes("ruta\al\script.ps1")
  "BOM: {0}" -f (($b[0] -eq 0xEF) -and ($b[1] -eq 0xBB) -and ($b[2] -eq 0xBF))
  ([regex]::Matches([Text.Encoding]::UTF8.GetString($b), "`r`n").Count, [regex]::Matches([Text.Encoding]::UTF8.GetString($b), "`n").Count -join " / ")
  ($b | Where-Object { $_ -gt 127 }).Count    # debe ser 0 salvo en la cabecera de bloque
  ```

## 🧬 Anatomía de un script

Sesenta y cinco secciones numeradas; las que importan cuando empiezas:

```text
§2   Argumentos y rutas        →$script:SilentMode, -portable, todas las rutas de datos
§7   i18n                      →$script:Strings.ES / .EN + function T
§8   Configuración con DPAPI   →defaults, Load-AppConfig, Save-AppConfig, Protect/Unprotect-String
§12  SHA256 y hash             →Get-ScriptHash, Get-StringHash
§13  Iconos                    →New-ShieldBitmap, Update-TrayIcon (el color del estado)
§15  Estado rápido             →Get-QuickStatus  ← la fuente de verdad de la UI
§16  SQLite                    →Initialize-Sqlite, Open-SqliteDB, Invoke-Sqlite (con respaldo JSON)
§45/§46 Desactivar / Activar   →Disable-Defender, Enable-Defender  ← el corazón, y lo más delicado
§47/§50 Historial              →Add-HistoryDB, Show-HistoryDialog, exportación CSV/Excel
§48/§51 Diagnóstico / Reparación→Get-DiagnosticReport, Show-DeepRepairDialog, Invoke-ConsoleCmd
§52/§53 Programador / servicio →Register-TrayTask, Install-AsService  ← persistencia: revisar con lupa
§54/§55 Kiosco / Configuración →Test-KioskAuth, Show-SettingsDialog
§56  Ayuda                    →Show-HelpDialog (la lista de funciones y endpoints, mantenla al día)
§58  Panel principal          →Show-DefenderPanel, New-NeonButton, paletas
§59  API REST                 →Initialize-RESTApi (HttpListener en un Start-Job) + GraphQL + SSE + PWA
§62  Arranque                 →secuencia inicial: hash, log, SQLite, exclusión, tareas, `-action`
§63/§65 Bandeja y bucle       →NotifyIcon, menú, ShowDialog y bucle principal
```

### Añadir una opción de configuración (receta)

Una opción nueva vive en cuatro sitios; si falta uno, la opción «no se guarda» o «no aparece»:

1. **Valor por defecto** en §8, con nombre `$script:CfgAlgo`.
2. **`Load-AppConfig`**: una rama en el `switch` (`"Algo" { $script:CfgAlgo = [bool]$prop.Value }`).
3. **`Save-AppConfig`**: la clave en la hashtable que se cifra con DPAPI.
4. **`Show-SettingsDialog`**: su control (`New-CheckBox` o `New-FormField`) y su asignación al guardar.

Y además: documentar la opción en la Ayuda (§56) y en [README.md](README.md#-configuración-y-datos). Si guarda un secreto, avísalo en [SECURITY.md](SECURITY.md#-cómo-protege-defendertray-tus-datos) con qué puede leer quien tenga tu sesión.

### Subir de versión

El número de versión está escrito en varios sitios (el proyecto los mantiene a mano). Al subir una versión, actualízalos **todos** y anótalo en el pull request:

- bloque `<# … #>` de la cabecera (título y lista numerada «Novedades vX sobre vY»);
- `Title` de las tablas `ES` y `EN` en §7;
- `$script:CurrentVersion` (usada por la comprobación de actualizaciones);
- textos de §56 (Ayuda) y del diálogo de configuración;
- `version` en `/diagnostic` y en las plantillas embebidas de MSI/WiX (`Version=` y `Product`).

💡 Si haces un cambio de versión, propón en el mismo pull request reemplazar esas literales por `"$($script:CurrentVersion)"`: así se evita la deriva que dejó la 8.1 como un simple renombrado de la 8.0. Y evita el patrón `v8.1.1`, `4.3+`, `4.3_Pro++` que heredamos del desarrollo histórico: **una rama, un número, un archivo**.

## 🔏 Secretos y datos personales

Nunca subas al repositorio:

- `config.dat` (es DPAPI, pero lleva huellas y tokens), `defendertray.db`, `historial.json`, `profiles.json`;
- `Logs\`, `Auditoria\`, `Forense\`, `Backups\Registro\*.reg` de un equipo real (los `.reg` exponen nombres de host y rutas internas);
- tokens de bot de Telegram, JSON de cuenta de servicio de Firebase, credenciales SMTP, URLs de webhooks, `CfgGitHubRepo` de una organización;
- capturas del diálogo de Configuración o del panel en equipos productivos: oscurece nombres de equipo y usuario.

Para pruebas usa datos inventados (`DEFENDER-TEST`, `127.0.0.1`, `bot123:AAAA-demo`). Si necesitas adjuntar un log, recorta las líneas con rutas de usuario. El [`.gitignore`](.gitignore) ya deja fuera `config.dat`, la base de datos, `Logs/`, `Auditoria/`, `Forense/`, `Backups/`, `DefenderTrayData/`, los `*.reg`, los `*.bak` y los `* - copia*`; si tu herramienta genera otro artefacto local, añade el patrón en el mismo pull request.

## 📝 Commits y pull requests

1. Crea una rama desde `main` con nombre descriptivo: `fix/puerto-en-uso`, `feat/exportar-fleet-csv`.
2. Mensajes en español con [Conventional Commits](https://www.conventionalcommits.org/es/v1.0.0/) y ámbito: `fix(defender):`, `feat(api):`, `docs(security):`, `test:`, `refactor(sqlite):`, `chore:`. Ejemplo: `fix(api): validar action en /fleet/command antes de armar la línea de comandos`.
3. Un commit lógico por cambio; nada de «copia», «final v2», «backup» ni «ahora sí». Los archivos `.bak` y `- copia` del repo vienen del desarrollo histórico, no son un precedente.
4. Añade tu línea al bloque `<# Novedades vX #>` de la cabecera **y** al [CHANGELOG.md](CHANGELOG.md), que se construye a partir de él; si tu cambio todavía no pertenece a una versión publicada, va en `[Sin publicar]`.
5. Actualiza la documentación afectada en el mismo pull request: [README.md](README.md) (funciones, argumentos, API, tabla de versiones), [SECURITY.md](SECURITY.md) (límites y mitigaciones si cambias el modelo de amenazas) y la Ayuda del script. Un pull request que añade una opción sin documentarla se devuelve.
6. Pega la matriz de [comprobaciones manuales](#matriz-de-comprobaciones-manuales) con los ✅, y adjunta capturas si cambia la interfaz.
7. Sin errores del parser; `Invoke-ScriptAnalyzer` sin avisos nuevos atribuibles a tu cambio.

Al abrir el pull request se rellena sola la [plantilla](.github/PULL_REQUEST_TEMPLATE.md); si lo abres sin ella, copia estas secciones a mano:

```markdown
### Qué cambia y por qué
### Cómo se probó (matriz + build de Windows + PowerShell)
### Riesgo de seguridad (¿toca desactivación, API, secretos, persistencia o red?)
### Reversión (cómo volver al estado anterior de un equipo ya tocado)
### Documentación actualizada (README / SECURITY / Ayuda)
```

## 🚨 Cambios sensibles tienen revisión extra

Todo lo que toque una de estas áreas se revisa línea a línea y puede pedirse un issue previo con justificación:

| Área | Por qué es delicada |
|---|---|
| `Disable-Defender` / `Enable-Defender` / `Invoke-EmergencyActivation` | Es la capacidad que un atacante querría; cada paso nuevo debe quedar auditado y reversible. |
| `Show-DeepRepairDialog`, `reg delete`, `sc config`, `FailureActions` | Borra claves y cambia el arranque de servicios críticos del SO. |
| `Initialize-RESTApi` y sus rutas | Autenticación, enlazado de puerto, métodos que mutan estado e interpolación de entradas. |
| `Protect-String`, huella del kiosco, clave de SQLite | Cualquier abaratamiento del cifrado o del hash se documenta como límite en SECURITY.md. |
| `Invoke-AutoUpdate`, `Get-LatestGitHubRelease`, `Initialize-Sqlite` | Descarga y ejecuta código: exige verificación de hash o firma. |
| `Register-TrayTask`, `Install-AsService`, `Add-MpPreference` | Persistencia con privilegios máximos y carpetas fuera del escaneo. |
| Notificaciones (Telegram/FCM/SMTP/webhooks) y `Backup-ToCloud` | Sacan datos del equipo: hay que decir cuáles, dónde y cómo se apagan. |

**No se aceptan** cambios cuyo objetivo sea: ocultar la ejecución a los antivirus (ofuscar, renombrar, dividir para evadir detección), alargar la desprotección «silenciosamente», persistir sin aviso en el log, saltarse el modo auditoría, o quitar verificaciones de hash o de firma. Tampoco funciones que actúen sobre equipos sin consentimiento del responsable: el límite no es técnico, es legal y ético ([LICENSE](LICENSE), cláusula 5).

## 🤝 Convivencia

Trata a todas las personas con respeto y cordialidad. Las críticas, siempre sobre el código y nunca sobre quien lo escribe. Se eliminarán los comentarios ofensivos, discriminatorios o de acoso — y también los que pidan ayuda para usar la herramienta contra equipos ajenos, que se reportan.

---

<a id="english"></a>

## 🇬🇧 English

Thank you for your interest in improving DefenderTray! This guide covers how to report bugs, propose improvements, test without leaving yourself unprotected, and send reviewable changes.

> DefenderTray is **proprietary software** ([LICENSE](LICENSE)). By submitting a contribution you accept clause 6: the owner may use it as part of the product. Contributing grants no right to use DefenderTray. And remember what the code does: changes to the disable/enable sequences, the local API, cryptography, auto-update or persistence go through the sensitive review track.

### 🧭 Ways to contribute

🐞 Bug reports through the "Informe de error" issue form (version, script SHA256, Windows build, command line, log excerpt) · ✨ improvement proposals that state the problem they solve and how long protection must stay off · 🩺 real-world repair cases (signature errors, services revived by Windows, `Start=4` not holding) · 📚 documentation · 🌍 ES/EN string tables · 🔒 vulnerabilities **only** via private reporting.

### ✅ Before you start

Search issues and pull requests first. Agree on a plan in an issue for anything large (a new section, another data provider, another persistence mechanism, changes to the 10-step sequences). One change per pull request. Patch the **current** version (`versiones/8/DefenderTray_8.1_Pro.ps1`); folders 1.x–7.x are an archive. Leave `*.bak`, `*- copia*` and `versiones/revisar` alone.

### 🔨 Development setup

No build step and no package manager — one `.ps1`. You need: a **Windows 10/11 VM with a snapshot** (the tool edits services and the registry), **Windows PowerShell 5.1**, and optionally VS Code with the PowerShell extension, `PSScriptAnalyzer`, and the `ActiveDirectory` module. Check syntax without executing:

```powershell
$errs = $null; $toks = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\versiones\8\DefenderTray_8.1_Pro.ps1), [ref]$toks, [ref]$errs)
$errs | ForEach-Object { "{0}: {1}" -f $_.Extent.StartLineNumber, $_.Message }
```

### ✅ Automated checks

The same ones [continuous integration](.github/workflows/ci.yml) runs: `Parser::ParseFile` on `versiones/8/*.ps1` (blocking), the same parse for the historical folder (advisory, since unsupported legacy files may not parse), an encoding check for no BOM and no bare LF in every `.ps1` (blocking), non-ASCII literal warnings, `Invoke-ScriptAnalyzer -Path versiones\8 -Recurse -Severity Warning,Error` (advisory) and `python .github/check_markdown_links.py` for broken links and anchors (blocking).

### 🧪 Testing protocol

Snapshot → export the registry keys the tool may delete → run `-audit` and confirm nothing was applied → `disable`, check `Get-MpComputerStatus`, reboot, check again → `enable` and verify Tamper Protection and `RealTimeProtectionEnabled` → break something on purpose and run Deep Repair → remove the Defender exclusion, unregister `DefenderTray_*` tasks, delete the self-signed HTTPS certificate, revert the snapshot. Paste the manual matrix (with ✅/❌) from the Spanish section into your pull request, covering only the rows your change touches: tray colour, dialogs and shortcuts, i18n toggle, audit mode, local API endpoints, portable vs. per-user data paths, history export, `.reg` backups, graceful SQLite degradation, and non-admin behaviour.

### 📐 Style and conventions

- **Keep it one file** — no modules; "copy it to a USB stick and run it on a bare machine" is the requirement that holds the project together.
- Respect the `# SECCION N - TITLE` banners and their dependency order (utilities → UI → startup → tray); append new numbered sections, don't renumber released ones.
- Global state lives in `$script:` variables (`$script:CfgSetting`, PascalCase, grouped under `# --- vN.N ---`).
- Functions are `Verb-Noun` in English; dialogs are `Show-*Dialog`; comments and dialog copy in Spanish **without accents**.
- No hardcoded user-visible strings: `T "Key"` with entries in **both** ES and EN tables; non-ASCII characters built from codes (`[char]0x00F1`); run multiline text through `Normalize-LineEndings`.
- Security rules that are mandatory in code: every mutating function starts with the `if ($script:AuditMode) { … return }` guard; back up the registry before the first destructive step; log every step with `Write-AppLog` and record it with `Add-HistoryDB`; degrade with `-ErrorAction SilentlyContinue` plus a warning instead of throwing mid-change.
- No new mandatory dependencies (`Get-Command` probe, then fall back), no new outbound network calls without an issue first.
- Save `.ps1` files as **UTF-8 without BOM, CRLF** and keep literals ASCII (PowerShell 5.1 decodes non-BOM as ANSI); [`.gitattributes`](.gitattributes) already pins the line endings on checkout, so do not re-convert files or tweak `core.autocrlf`. Verify with the encoding check before committing.

### 🚀 Bumping a version

The version is a literal in several places: the header `<# Novedades #>` block, the `Title` entries in the ES/EN tables, `$script:CurrentVersion`, the Help text, the Settings title, `/diagnostic` and the embedded WiX template. Update them all and list them in your pull request — better still, replace them with `"$($script:CurrentVersion)"` so the project stops shipping renames like 8.1 over 8.0. Use one number per file: no `4.3_Pro++`, `3.8.0`/`3.8.1`, `+DefenderTray_4.3_Pro` patterns in new work.

### 🔏 Secrets and personal data

Never commit `config.dat`, `defendertray.db`, `historial.json`, `profiles.json`, `Logs\`, `Auditoria\`, `Forense\`, production `.reg` exports, Telegram/Firebase tokens, SMTP credentials, webhook URLs, screenshots of the Settings dialog, or real hostnames. Use invented values in tests, issues and captures.

### 📝 Commits and pull requests

Branch from `main` (`fix/port-in-use`), Spanish [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) with a scope (`fix(api):`, `feat(defender):`, `docs(security):`, `refactor(sqlite):`), one logical change per commit, no "copia/final v2/backup" filenames, your line added to both the header `Novedades` block and [CHANGELOG.md](CHANGELOG.md), documentation updated in the same pull request, the manual matrix pasted with ✅, and a clean parser run. The [pull request template](.github/PULL_REQUEST_TEMPLATE.md) is applied automatically; without it, write these sections by hand: what changed and why · how it was tested · security risk · how to revert on an already-touched machine · docs updated.

### 🚫 What will not be accepted

Nothing whose purpose is evading antivirus detection or hiding execution, extending the unprotected window silently, persisting without a log entry, bypassing audit mode, or removing hash/signature verification; nothing aimed at machines whose operator has not consented (LICENSE clause 5). Treat those as reportable, not as features.

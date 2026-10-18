# Histórico de versiones

📦 Esta carpeta es el **archivo** del proyecto: 37 scripts `.ps1`, uno por versión publicada en su momento. No se corrigen ni se mantienen salvo la recomendada.

**Si vas a usar DefenderTray, no empieces por aquí:** el índice, los requisitos y el inicio rápido están en el [README de la raíz](../README.md).

- ✅ = la que hay que usar · 📦 = histórica (funciona en su momento, sin soporte) · 🧹 = residuo de desarrollo, no lo uses como referencia.
- Las columnas *Líneas* y *Bytes* son del archivo tal y como está commiteado (UTF-8 **sin BOM**, CRLF).
- Todas las notas de cada fila proceden de la cabecera `<# … #>` del propio script; el detalle completo, en el [registro de cambios](../CHANGELOG.md).

## 8 — Capa «enterprise» ⭐

| Archivo | Líneas | Bytes | Estado | Qué aporta |
|---|---:|---:|:--:|---|
| [`DefenderTray_8.1_Pro.ps1`](8/DefenderTray_8.1_Pro.ps1) | 4 747 | 236 088 | ✅ | **Versión de referencia.** 65 secciones, 134 funciones. Mismo código que la 8.0 con las cadenas de versión actualizadas. |
| [`DefenderTray_8.0_Pro.ps1`](8/DefenderTray_8.0_Pro.ps1) | 4 747 | 236 088 | 📦 | SQLite cifrado, firma Authenticode + guía EV, MSI con WiX, FCM v1, consola Fleet, anomalías Z-score, Active Directory, GraphQL, PWA, kiosco biométrico, webhooks, Excel/CSV, panel SSE, autoactualización con SHA256 y empaquetado Docker. |

## 7 — Web, voz y modo forense

| Archivo | Líneas | Bytes | Estado | Qué aporta |
|---|---:|---:|:--:|---|
| [`DefenderTray_7.0_Pro.ps1`](7/DefenderTray_7.0_Pro.ps1) | 3 469 | 166 734 | 📦 | Panel web HTML5 sobre la API, perfiles multiusuario, Telegram, autorreparación heurística, control por voz, PDF firmado, botón de pánico, Event Log de Defender, copia a la nube, multi-monitor, editor de colores, modo tutela y modo forense. |

## 6 — API local y servidor

| Archivo | Líneas | Bytes | Estado | Qué aporta |
|---|---:|---:|:--:|---|
| [`DefenderTray_6.0_Pro.ps1`](6/DefenderTray_6.0_Pro.ps1) | 3 115 | 149 237 | 📦 | Agente residente WMI, autoactualización, tema automático, Windows Terminal, PowerShell 7+, SMTP, **API REST en `127.0.0.1:9182`**, Windows Hello, asistente de firma y de MSI, alertas por umbral, reglas de firewall, **`-audit`**, configuración cifrada con DPAPI y Windows Server. |

## 5 — Programación e historial

| Archivo | Líneas | Bytes | Estado | Qué aporta |
|---|---:|---:|:--:|---|
| [`DefenderTray_5.0_Pro.ps1`](5/DefenderTray_5.0_Pro.ps1) | 2 877 | 132 703 | 📦 | Programador de tareas, instalación como servicio, respaldo/restauración del registro, detección de AV de terceros, diagnóstico de red, ES/EN parcial, verificación SHA256, estadísticas, limpieza de logs y contraseña de desinstalación. |

## 4 — El laboratorio de la interfaz futurista

Quince `.ps1` y un respaldo: la rama donde más se experimentó y donde más desorden quedó.

| Archivo | Líneas | Bytes | Estado | Qué aporta |
|---|---:|---:|:--:|---|
| [`DefenderTray_4.5_Pro.ps1`](4/DefenderTray_4.5_Pro.ps1) | 2 499 | 113 387 | 📦 | **La mejor de la rama 4.** Resultado con scroll solo vertical, activación ordenada por dependencias, reparación de firmas corruptas (31/12/1969) y botón «Reparar Firmas». |
| [`DefenderTray_4.3.3_Pro.ps1`](4/DefenderTray_4.3.3_Pro.ps1) | 2 328 | 104 707 | 📦 | Su cabecera se autodenomina **v4.4**: botones deshabilitados durante operaciones, Deep Repair y Configuración en español, reintentos de `Set-MpPreference`. |
| [`DefenderTray_4.3.1_Pro.ps1`](4/DefenderTray_4.3.1_Pro.ps1) | 2 280 | 101 700 | 📦 | Bucle de verificación de 5 intentos, *FailureActions* deshabilitadas, `MsMpEng` muerta antes de detener `WinDefend`, correcciones del *timer*. |
| `DefenderTray_4.3.1_Pro - copia - copia.ps1` | 2 280 | 101 700 | 🧹 | **Duplicado idéntico** del anterior (mismo tamaño y contenido). No lo uses. |
| [`DefenderTray_4.3_Pro+.ps1`](4/DefenderTray_4.3_Pro+.ps1) | 2 286 | 102 249 | 📦 | Variante del lote 4.3 Pro con icono oficial de Microsoft y las 15+ protecciones. |
| [`+DefenderTray_4.3_Pro.ps1`](4/+DefenderTray_4.3_Pro.ps1) | 2 172 | 96 296 | 🧹 | Otra variante de la misma cabecera (el `+` va aquí como prefijo del nombre). |
| [`DefenderTray_4.3_Pro++.ps1`](4/DefenderTray_4.3_Pro++.ps1) | 2 271 | 99 577 | 🧹 | Cuarta variante del lote 4.3 Pro: decide cuál es la buena antes de tocar nada de esto. |
| [`DefenderTray_4.3_Pro.ps1`](4/DefenderTray_4.3_Pro.ps1) | 1 857 | 82 149 | 📦 | Base del lote: iconos dinámicos, desactivación de 8 servicios, diagnóstico detallado, reparación profunda con consola, kiosco con contraseña. |
| [`DefenderTray_4.2.ps1`](4/DefenderTray_4.2.ps1) | 2 613 | 143 337 | 📦 | El archivo más grande de la rama: módulo de Reparación Profunda con consola en vivo (`reg delete`, `sc config`, `gpupdate`, `sfc`, `DISM`). |
| [`DefenderTray_4.2_Final.ps1`](4/DefenderTray_4.2_Final.ps1) | 1 609 | 85 834 | 📦 | Reescritura «sin hashtable en el ámbito, sin funciones anidadas, config en variables individuales». |
| [`DefenderTray_4.1.ps1`](4/DefenderTray_4.1.ps1) | 2 416 | 131 999 | 📦 | «Completa y corregida». Es el archivo que parcheaba `Reparar-DefenderTray.ps1`. |
| `DefenderTray_4.1.ps1.backup_2026-10-15_211129.bak` | — | 131 999 | 🧹 | Respaldo en el repositorio. Ahora [`.gitignore`](../.gitignore) impide que se repita. |
| [`DefenderTray_4.3+.ps1`](4/DefenderTray_4.3+.ps1) | 1 605 | 72 067 | 📦 | Iconos por estado, desactivación total con muerte de `MsMpEng`, barra de estado y kiosco con contraseña. |
| [`DefenderTray_4.3.ps1`](4/DefenderTray_4.3.ps1) | 1 448 | 66 493 | 📦 | Desactivación total agresiva, barra de menú restaurada y **modo kiosco funcional**. |
| [`DefenderTray_4.0.ps1`](4/DefenderTray_4.0.ps1) | 2 366 | 134 300 | 📦 | Edición futurista con todo lo previo integrado: programador, perfiles, respaldo, gráfico, eventos, kiosco, autodiagnóstico, portable, *toast*, integridad e idiomas. |
| [`Reparar-DefenderTray.ps1`](4/Reparar-DefenderTray.ps1) | 235 | 9 736 | 📦 | **Herramienta, no aplicación:** parchea el 4.1 (punto → índice en `$script:AppConfig`), valida con el parser de PowerShell, crea `.bak` e informa. Antecedente de la [integración continua](../.github/workflows/ci.yml). |

## 3 — De menú a aplicación

Catorce versiones en un salto numerado con hueco: **no existe la 3.9** (se pasa de 3.8.1 a 3.10, y el orden real de crecimiento es el de la columna *Líneas*).

| Archivo | Líneas | Bytes | Estado | Qué aporta |
|---|---:|---:|:--:|---|
| [`DefenderTray_3.12.ps1`](3/DefenderTray_3.12.ps1) | 2 159 | 108 927 | 📦 | Ayuda en tiempo real: tooltips, barra de estado contextual, ayuda `F1` por pestañas, asistente de primera ejecución, autoinicio y atajos. |
| [`DefenderTray_3.11.ps1`](3/DefenderTray_3.11.ps1) | 1 963 | 91 795 | 📦 | Desactivación agresiva (`reg delete` + `sc config` + `Start=4`), historial de 20 operaciones, *toast*, exportación CSV, `Ctrl+R`. |
| [`DefenderTray_3.10.ps1`](3/DefenderTray_3.10.ps1) | 1 582 | 73 147 | 📦 | Ámbitos corregidos (sin funciones anidadas en eventos), 18 módulos verificados, **log en `%LOCALAPPDATA%\DefenderTray\Logs\`**. |
| [`DefenderTray_3.8.1.ps1`](3/DefenderTray_3.8.1.ps1) | 1 532 | 70 828 | 📦 | Panel *singleton* con controles en `$script:`; *timer* y eventos fiables. |
| [`DefenderTray_3.8.0.ps1`](3/DefenderTray_3.8.0.ps1) | 1 593 | 71 715 | 📦 | Verificación de los 18 módulos, «Verificar estado completo» e **intento honesto** de activar Tamper Protection con verificación. |
| [`DefenderTray_3.7.ps1`](3/DefenderTray_3.7.ps1) | 1 326 | 58 055 | 📦 | Diálogo de opciones avanzadas al activar: MAPS/nube, envío de muestras y protección contra alteraciones. |
| [`DefenderTray_3.6.ps1`](3/DefenderTray_3.6.ps1) | 1 057 | 45 650 | 📦 | Anti-congelamiento: *timer* ligero sin WMI, caché de 30 s, `DoEvents` y se retira `Update-MpSignature`. |
| [`DefenderTray_3.5.ps1`](3/DefenderTray_3.5.ps1) | 1 047 | 46 576 | 📦 | *Timer* con segundos por operación, refresco cada 2 s, salida anclada al fondo y desactivación con reintento. |
| [`DefenderTray_3.4.ps1`](3/DefenderTray_3.4.ps1) | 953 | 41 936 | 📦 | Criterio estricto del estado ACTIVADO (servicio + tiempo real + sin políticas de bloqueo). |
| [`DefenderTray_3.3.ps1`](3/DefenderTray_3.3.ps1) | 995 | 43 584 | 📦 | Estado calculado con `AMServiceEnabled` en lugar de `AntivirusEnabled`. |
| [`DefenderTray_3.2.ps1`](3/DefenderTray_3.2.ps1) | 930 | 39 855 | 📦 | Quinto botón «Ver Registro». Primer archivo de la rama sin caracteres fuera del ASCII. |
| [`DefenderTray_3.1.1.ps1`](3/DefenderTray_3.1.1.ps1) | 775 | 38 158 | 📦 | Verificación inicial obligatoria con mensaje claro y botones por acción disponible. |
| [`DefenderTray_3.1.ps1`](3/DefenderTray_3.1.ps1) | 672 | 33 919 | 📦 | Ajustes del panel compacto y del menú en texto plano. |
| [`DefenderTray_3.0.ps1`](3/DefenderTray_3.0.ps1) | 609 | 30 630 | 📦 | Exclusión de Defender para que el script no se detenga, «Acerca de…», detección del SO y botones según estado. |

## 1 y 2 — El origen

| Archivo | Líneas | Bytes | Estado | Qué aporta |
|---|---:|---:|:--:|---|
| [`DefenderTray_2.ps1`](2/DefenderTray_2.ps1) | 399 | 19 696 | 📦 | Menú en **texto plano** (sin caracteres especiales), modal compacto y colorido con Activar / Desactivar / Salir. |
| [`DefenderTray_1.ps1`](1/DefenderTray_1.ps1) | 221 | 11 450 | 📦 | El original: icono en la bandeja, activar/desactivar (servicio, tiempo real y registro), verificación y notificación. Compatible declarada con Windows 7 → 11 (24H2, 25H2, 26H2). |
| [`WiFi_1126H2_2.1.ps1`](2/WiFi_1126H2_2.1.ps1) | 522 | 24 849 | 🧹 | **No pertenece a este proyecto:** gestor de hotspot WiFi (activa el punto de acceso sin Internet), con autoelevación. Está aquí por error. |

## Raíz de la carpeta

| Archivo | Estado | Nota |
|---|:--:|---|
| `revisar` | 🧹 | Vacío (un solo salto de línea): un apunte personal «revisar» que no describe nada. Candidato a borrar. |

## Cómo se lee este archivo de cada versión

```powershell
# 1) Ver qué declara (sin abrir 4 000 líneas)
Get-Content .\versiones\8\DefenderTray_8.1_Pro.ps1 -TotalCount 22

# 2) Ayuda de comment-based de PowerShell, si el archivo la tiene
Get-Help .\versiones\3\DefenderTray_3.12.ps1 -Full

# 3) Comparar dos versiones (el histórico real son los diffs)
git diff --no-index .\versiones\8\DefenderTray_8.0_Pro.ps1 .\versiones\8\DefenderTray_8.1_Pro.ps1
```

## Reglas para esta carpeta

1. **Una versión, un archivo, un nombre**: `DefenderTray_<MAJOR>.<MINOR>[_Pro].ps1` en `versiones/<MAJOR>/`. Sin `+`, `++`, `_Final`, `copia` ni fechas en el nombre.
2. Al abrir una rama mayor nueva, carpeta nueva; **nunca** se editan las carpetas antiguas.
3. Los respaldos y las copias se quedan fuera del repositorio (ver [`.gitignore`](../.gitignore)).
4. Si una versión se publica, se etiqueta: `git tag v8.2 && git push origin v8.2`, con release y `SHA256SUMS` (así funciona la autoactualización y se fecha el [CHANGELOG](../CHANGELOG.md)).

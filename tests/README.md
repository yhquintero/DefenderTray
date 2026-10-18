# Regresiones de protección

## Comprobaciones sin Defender

```bash
python -m unittest discover -s tests -p 'test_*.py' -v
```

Contratos estáticos: ausencia de borrado de firmas y cierres forzados, distribución de botones, guardas de auditoría, conservación de ramas de políticas y formato de archivos. `test_update_contract.py` cubre además el fix del ParserError, la validación del auto-updater y el recuperador independiente sin hacer llamadas de red.

En **Windows PowerShell 5.1**:

```powershell
powershell -NoProfile -File .\tests\Protection.Tests.ps1
```

La suite extrae del AST únicamente las funciones que prueba. **No ejecuta DefenderTray**, no eleva permisos, no consulta Defender, no toca el registro ni descarga firmas: sustituye esas operaciones por funciones simuladas. En Windows también crea botones WinForms sin mostrar una ventana para comprobar `Enabled` y la salida del estado ocupado. CI ejecuta esta suite en `windows-latest`.

## Verificación manual pendiente en Windows

Usar una **VM propia con instantánea**, sin políticas corporativas ni otro antivirus. No hacer pruebas de desactivación en un equipo de producción.

1. Anotar `AntivirusSignatureVersion`, `AntivirusSignatureLastUpdated`, `RealTimeProtectionEnabled`, `AntivirusEnabled` y `IsTamperProtected` con `Get-MpComputerStatus`.
2. Abrir la versión 8.4.1. Confirmar botones adyacentes. Con estado ACTIVO: Activar deshabilitado y Desactivar habilitado.
3. Pulsar Desactivar. Durante la operación deben bloquearse ambos. Según `CfgToggleMode`, cambia RTP (y, en modo Full, nube/muestras); `WinDefend`/`MsMpEng` y las firmas deben seguir disponibles. Activar queda habilitado y Desactivar deshabilitado. Versión/fecha de firmas deben conservarse, salvo una actualización legítima simultánea.
4. Pulsar Activar y repetir el ciclo. Verificar que siempre se puede volver a desactivar y que las firmas siguen disponibles.
5. Con Tamper Protection activa, comprobar que un cambio rechazado no se anuncia como exitoso y que los botones reflejan el estado real posterior.
6. En otra instantánea con el fallo anterior (`0.0.0.0`), pulsar Activar para recuperar los bloqueos antiguos y después **Reparar Firmas**. Requiere acceso a la fuente de actualizaciones configurada. Confirmar versión distinta de cero y fecha válida. Si Windows rechaza recuperar servicios/controladores, revisar el log y reiniciar; no forzar el cierre del motor.
7. Simular falta de red en la VM al reparar firmas. Debe informar fallo sin borrar la base instalada. Restaurar la red y volver a actualizar.
8. Comparar políticas `Signature Updates`, exclusiones y políticas ajenas antes/después de la recuperación selectiva. La migración elimina solo nombres de bloqueos usados por versiones antiguas, pero no puede distinguir su autor: **no usar esta migración en equipos administrados sin autorización**.

La corrección del código no repara por sí sola un Windows ya dañado. Las políticas que una versión anterior haya borrado solo pueden recuperarse desde un respaldo válido o desde su administrador. Las acciones independientes de reparación profunda (`sfc`, DISM, servicios, `gpupdate`) siguen siendo operaciones administrativas: no forman parte del ciclo Activar/Desactivar.

## Recuperar un script que no parsea

Un `ParserError` ocurre antes de ejecutar la primera línea de la aplicación, así que el auto-update integrado tampoco puede arrancar. Descarga `versiones/8/Reparar-DefenderTray.ps1` desde GitHub y ejecútalo desde una PowerShell elevada (ajusta `-TargetPath` si instalaste el `.ps1` en otra ruta):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparar-DefenderTray.ps1 -TargetPath "C:\DefenderTray_8.4_Pro.ps1"
```

El recuperador usa GitHub Contents API sobre `main`, verifica el SHA del blob y el parser, escribe un temporal en la carpeta destino y conserva una copia `.bak` antes de reemplazar. No ejecuta el script descargado. Una vez reparada y reiniciada la aplicación, **Buscar Actualización** usa ese mismo origen de GitHub; no hace falta publicar un Release.

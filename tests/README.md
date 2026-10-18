# Regresiones de protección

## Comprobaciones sin Defender

```bash
python -m unittest discover -s tests -p 'test_*.py' -v
```

Contratos estáticos: ausencia de borrado de firmas y cierres forzados, distribución de botones, guardas de auditoría, conservación de ramas de políticas y formato de archivos.

En **Windows PowerShell 5.1**:

```powershell
powershell -NoProfile -File .\tests\Protection.Tests.ps1
```

La suite extrae del AST únicamente las funciones que prueba. **No ejecuta DefenderTray**, no eleva permisos, no consulta Defender, no toca el registro ni descarga firmas: sustituye esas operaciones por funciones simuladas. En Windows también crea botones WinForms sin mostrar una ventana para comprobar `Enabled` y la salida del estado ocupado. CI ejecuta esta suite en `windows-latest`.

## Verificación manual pendiente en Windows

Usar una **VM propia con instantánea**, sin políticas corporativas ni otro antivirus. No hacer pruebas de desactivación en un equipo de producción.

1. Anotar `AntivirusSignatureVersion`, `AntivirusSignatureLastUpdated`, `RealTimeProtectionEnabled`, `AntivirusEnabled` y `IsTamperProtected` con `Get-MpComputerStatus`.
2. Abrir la versión 8.2 corregida. Confirmar botones adyacentes. Con estado ACTIVO: Activar deshabilitado y Desactivar habilitado.
3. Pulsar Desactivar. Durante la operación deben bloquearse ambos. Si Windows permite la pausa, tiempo real debe quedar desactivado pero `WinDefend`/`MsMpEng` deben continuar funcionando; Activar habilitado y Desactivar deshabilitado. Versión/fecha de firmas deben conservarse, salvo una actualización legítima simultánea.
4. Pulsar Activar y repetir el ciclo. Verificar que siempre se puede volver a desactivar y que las firmas siguen disponibles.
5. Con Tamper Protection activa, comprobar que un cambio rechazado no se anuncia como exitoso y que los botones reflejan el estado real posterior.
6. En otra instantánea con el fallo anterior (`0.0.0.0`), pulsar Activar para recuperar los bloqueos antiguos y después **Reparar Firmas**. Requiere acceso a la fuente de actualizaciones configurada. Confirmar versión distinta de cero y fecha válida. Si Windows rechaza recuperar servicios/controladores, revisar el log y reiniciar; no forzar el cierre del motor.
7. Simular falta de red en la VM al reparar firmas. Debe informar fallo sin borrar la base instalada. Restaurar la red y volver a actualizar.
8. Comparar políticas `Signature Updates`, exclusiones y políticas ajenas antes/después de la recuperación selectiva. La migración elimina solo nombres de bloqueos usados por versiones antiguas, pero no puede distinguir su autor: **no usar esta migración en equipos administrados sin autorización**.

La corrección del código no repara por sí sola un Windows ya dañado. Las políticas que una versión anterior haya borrado solo pueden recuperarse desde un respaldo válido o desde su administrador. Las acciones independientes de reparación profunda (`sfc`, DISM, servicios, `gpupdate`) siguen siendo operaciones administrativas: no forman parte del ciclo Activar/Desactivar.

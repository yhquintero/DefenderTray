## Qué cambia y por qué

Describe el cambio en dos o tres frases y enlaza el issue que resuelve (`Closes #…`).
Si es un cambio de comportamiento en la activación o la desactivación, empieza por el caso de uso.

## Cómo se probó

- [ ] VM Windows 10/11 con instantánea previa y exportación de las claves de políticas
- [ ] `Parser::ParseFile` sin errores en los `.ps1` tocados
- [ ] Ejecutado primero con `-audit`: ningún cambio aplicado en modo auditoría
- [ ] Activar y Desactivar verificados con `Get-MpComputerStatus` (antes y después, y tras reinicio si aplica)
- [ ] Matriz de [comprobaciones manuales](https://github.com/yhquintero/DefenderTray/blob/main/CONTRIBUTING.md#matriz-de-comprobaciones-manuales) pegada con ✅/❌ para las filas que tocan este cambio
- [ ] `PSScriptAnalyzer` sin avisos nuevos atribuibles a este PR

Build de Windows y PowerShell usados:

## Riesgo de seguridad

¿Toca desactivación de protecciones, API local, secretos/criptografía, red o persistencia (tareas, exclusión de Defender)?
- [ ] No
- [ ] Sí → explica el riesgo, cómo se mitiga y qué hay que añadir a [SECURITY.md](https://github.com/yhquintero/DefenderTray/blob/main/SECURITY.md).

## Reversión

Cómo vuelve un equipo ya tocado a su estado anterior (paso a paso corto, o «no aplica»).

## Documentación

- [ ] [README.md](https://github.com/yhquintero/DefenderTray/blob/main/README.md) actualizado (funciones, argumentos, API, tabla de versiones)
- [ ] [CHANGELOG.md](https://github.com/yhquintero/DefenderTray/blob/main/CHANGELOG.md) con una línea y cabecera `<# Novedades #>` del script
- [ ] [SECURITY.md](https://github.com/yhquintero/DefenderTray/blob/main/SECURITY.md) si cambia el modelo de amenazas
- [ ] [CONTRIBUTING.md](https://github.com/yhquintero/DefenderTray/blob/main/CONTRIBUTING.md) si cambia una convención
- [ ] Ayuda `F1` del script (§56) si cambia comportamiento visible

## Capturas

Si cambia la interfaz, pega una captura por estado (activo, desactivado, parcial, error).
**Oscurece nombre de equipo, usuario y cualquier token visible en Configuración.**

---

<sub>Un pull request = un cambio. Los mensajes de commit en español con
[Conventional Commits](https://www.conventionalcommits.org/es/v1.0.0/) y ámbito
(`fix(api): …`). Los cambios sensibles pasan por la revisión extra descrita en
CONTRIBUTING.md; si nadie responde en una semana, pon `@yhquintero` en un comentario.</sub>

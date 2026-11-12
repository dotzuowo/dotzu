# WinBoost 0.9 — PowerShell

Herramienta independiente para Windows 11 x64. El archivo unico despliega sus componentes y abre la interfaz.

## Modulos de Windows
Pulsa **Modulos de Windows**. Busca una funcion, elige una opcion y, si se pide, escribe el argumento exacto en la columna correspondiente. Todas empiezan en **Sin cambios**. Usa **Revisar plan** antes de **Ejecutar seleccion**. El informe distingue verificacion, ejecucion nativa y accion asistida.

89 acciones programadas y 32 flujos asistidos. Consulta COBERTURA.md: algunas familias tienen alcance parcial y no todas las variantes estan automatizadas. El inventario de componentes exporta nombres validos de caracteristicas, capacidades y paquetes.

Puedes guardar un plan JSON y ejecutarlo desde consola con el archivo unico:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WinBoost.ps1 -Mode ActionsPreview -PresetPath C:\Planes\MiPlan.json -OpenReport
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WinBoost.ps1 -Mode ActionsApply -PresetPath C:\Planes\MiPlan.json -OpenReport
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WinBoost.ps1 -Mode ActionsRestore -OpenReport
```

Acciones asistidas abren controles de Windows, requieren intervencion y no se verifican como ajustes aplicados. Los perfiles Rapido/Gaming/Mantenimiento siguen disponibles en Resumen y con `-Mode Apply -Profile Gaming`. Los planes de acciones avanzadas usan otro esquema y no se importan como perfiles base.

## Recuperacion
**Restaurar ultima sesion de modulos** o ActionsRestore recupera Registro (usuario y equipo), preferencias de Defender, DiagTrack y plan de energia. La recuperacion base se hace desde la pantalla Recuperacion o con -Mode Restore. No se sobrescriben cambios externos. El historial comun muestra sesiones base y avanzadas, incluso interrumpidas. Selecciona una y pulsa **Restaurar seleccion**, o usa `-RestoreSessionId <GUID>` con Restore/ActionsRestore. Sin ese parametro se conserva el comportamiento de ultima sesion del motor elegido. Los diarios ilegibles se conservan y muestran; no impiden restaurar otra sesion valida, pero bloquean aplicaciones nuevas. Si se lee una copia anterior del diario, se informa con un aviso y se exige restaurar antes de seguir aplicando.

Un fallo o una detencion solicita restauracion de las acciones avanzadas reversibles. Las instalaciones, desinstalaciones, componentes, hibernacion, almacenamiento reservado, actualizaciones, limpiezas y acciones manuales necesitan revision manual. No hay deshacer universal. El diario de operaciones sin reversion se guarda antes de iniciar cada una. No hay reinicio automatico.

Las opciones de seguridad indican su efecto en la descripcion; ninguna se cambia por defecto. Los planes son datos JSON, no scripts. Los argumentos de componentes y paquetes deben ser nombres exactos, sin comodines. Se valida el plan antes de realizar la primera mutacion.

## Pruebas
Pruebas de sintaxis, extraccion, motor base y motor de acciones con adaptadores simulados, incluidos reinicio, cancelacion, historial mixto, recuperacion por ID y corrupcion de diarios. Ya existen comprobaciones Windows PowerShell 5.1 y WPF exitosas del commit base; la CI ampliada las repite con los cambios actuales. UAC real y todos los efectos de los cmdlets nativos siguen requiriendo pruebas especificas. No se garantizan incrementos de FPS. Las politicas pueden depender de la edicion, compilacion y administracion del equipo.

El perfil Gaming, la preferencia de GPU por juego y las fuentes están en [GAMING.md](GAMING.md).

## Contrato de salida

Ambos motores incluyen ExitCode, RestartRequired y RestoredSession en summary.json. 0 = completado, 1 = fallo, 2 = avisos/conflictos, 3 = cancelado. RestartRequired se comunica tambien en el informe y la interfaz, sin reiniciar automaticamente. El paquete propaga el codigo en ejecucion por archivo; con iex lo deja en $LASTEXITCODE sin cerrar la consola.

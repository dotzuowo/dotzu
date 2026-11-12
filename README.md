# WinBoost 0.9

Herramienta independiente en PowerShell para Windows 11 x64. Interfaz WinBoost, perfiles automaticos, respaldo e informes. Version de prueba.

## Descargar y abrir
```powershell
iwr https://raw.githubusercontent.com/dotzuowo/dotzu/main/WinBoost.ps1 -useb | iex
```

El script despliega sus propios componentes y abre la interfaz. Pulsa **Modulos de Windows** para acceder a 121 familias: **89 acciones programadas y 32 flujos asistidos**. Todo empieza en Sin cambios. Elige tus opciones, revisa el plan y ejecuta. Algunas familias tienen alcance parcial: no todas las variantes del modelo de referencia estan automatizadas.

Incluye ajustes de privacidad, Explorador, Inicio, barra, juegos, energia, actualizaciones, seguridad, componentes y aplicaciones. Conserva los 45 ajustes del motor base; hay solapamientos y no se suman como funciones distintas.

[Alcance de cada funcion](src/v0.9/COBERTURA.md) · [Uso y recuperacion](src/v0.9/LEEME.md) · [Validacion](src/v0.9/VALIDACION.txt) · [Codigo fuente](src/v0.9/)

## Automatizar un plan guardado
Guarda el plan desde Modulos de Windows y ejecuta:
```powershell
& ([scriptblock]::Create((iwr https://raw.githubusercontent.com/dotzuowo/dotzu/main/WinBoost.ps1 -useb).Content)) -Mode ActionsApply -PresetPath 'C:\Planes\MiPlan.json' -OpenReport
```
Usa ActionsPreview para comprobar sin aplicar. ActionsRestore recupera la ultima sesion de modulos. Para recuperar una sesion concreta usa `-RestoreSessionId <GUID>` con `-Mode Restore` o `-Mode ActionsRestore`, o elige **Restaurar seleccion** desde Recuperacion. El historial incluye sesiones base y avanzadas; conserva y muestra diarios ilegibles. Los perfiles Rapido/Gaming/Mantenimiento usan el motor base y `-Mode Apply -Profile Gaming`.

El archivo unico contiene sus fuentes empaquetadas y comprueba el hash del paquete antes de extraer. El hash detecta corrupcion, no es una firma digital.

## Resultados y automatizacion

Los dos motores escriben `summary.json` con `ExitCode`, `RestartRequired` y `RestoredSession`. Codigos de salida: **0** completado, **1** fallo, **2** avisos/conflictos, **3** cancelacion. Un reinicio requerido no es un fallo ni provoca reinicio automatico. En uso con `iex`, el paquete conserva el codigo en `$LASTEXITCODE` y deja abierta la consola; con `powershell.exe -File`, lo devuelve al proceso invocador.

## Estado de validacion

Hay comprobaciones exitosas en Windows para el commit base: [Gaming](https://github.com/dotzuowo/dotzu/actions/runs/42530801889) y [presentacion WPF](https://github.com/dotzuowo/dotzu/actions/runs/42530801769). Cubren preferencias HKCU, repeticion/restauracion, navegacion y renderizado; no prueban mejoras de FPS ni todos los cmdlets nativos.

El workflow `WinBoost validation` valida ambos motores y sus contratos simulados, entrada/elevacion simulada, recuperacion por sesion, avisos de reinicio, integridad del paquete, sintaxis PowerShell 5.1 y presentacion WPF. Se ejecuta en push y pull requests. UAC real, Defender, servicios, DISM, WinGet y energia en hardware requieren validacion adicional en entornos desechables. Las acciones asistidas solo abren controles y no se registran como aplicadas.

Restaurar cubre los estados documentados; no deshace universalmente instalaciones, eliminaciones, limpiezas ni acciones manuales. Un diario ilegible o recuperado desde copia anterior bloquea nuevas aplicaciones hasta revisar/restaurar la sesion; no se borra automaticamente.

Para regenerar el archivo unico y su copia `install.ps1`: `python tools/build_package.py`. Para verificar el hash integrado y que los bytes del paquete coincidan con todas las fuentes: `python tools/build_package.py --check`. El hash detecta corrupcion, no sustituye la firma del editor.

[Perfil Gaming y fuentes en GitHub](src/v0.9/GAMING.md)

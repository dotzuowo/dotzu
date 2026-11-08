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
Usa ActionsPreview para comprobar sin aplicar. ActionsRestore recupera la ultima sesion de modulos. Los perfiles Rapido/Gaming/Mantenimiento usan el motor base y `-Mode Apply -Profile Gaming`.

El archivo unico contiene sus fuentes empaquetadas y comprueba el hash del paquete antes de extraer. El hash detecta corrupcion, no es una firma digital.

## Estado de validacion
Pruebas simuladas completadas: 154 variantes reversibles, 7 escenarios de acciones y 11 escenarios de motor base, entre otras comprobaciones. Pendiente probar Windows PowerShell 5.1, WPF, UAC y efectos reales en Windows 11. Las acciones asistidas solo abren controles y no se registran como aplicadas. No se garantizan mejoras de FPS.

Restaurar cubre los estados documentados; no deshace universalmente instalaciones, eliminaciones, limpiezas ni acciones manuales.

[Perfil Gaming y fuentes en GitHub](src/v0.9/GAMING.md)

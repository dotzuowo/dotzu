# WinBoost 0.8

Herramienta independiente de PowerShell para Windows 11 x64. Interfaz azul y gris, 44 preferencias, perfiles automaticos, respaldo y recuperacion. Version de prueba.

## Abrir WinBoost
Pega en Windows PowerShell, desde cualquier carpeta:
```powershell
iwr https://raw.githubusercontent.com/dotzuowo/dotzu/main/WinBoost.ps1 -useb | iex
```
El script despliega sus propios archivos y abre la interfaz. Solicita permisos administrativos con la misma cuenta cuando hacen falta. No requiere descargar un ZIP manualmente.

## Ejecutar un perfil automaticamente
```powershell
& ([scriptblock]::Create((iwr https://raw.githubusercontent.com/dotzuowo/dotzu/main/WinBoost.ps1 -useb).Content)) -Mode Apply -Profile Gaming -OpenReport
```
Usa `-Mode Preview` para revisar el plan sin aplicar cambios. Rápido cambia privacidad e interfaz. Gaming añade desactivar capturas Xbox y energia con corriente. No activa las 18 preferencias opcionales: se eligen en el catalogo y se pueden guardar en un perfil JSON.

## Codigo y validacion
[Codigo fuente](src/v0.8/) · [Uso y alcance](src/v0.8/LEEME.md) · [Pruebas](src/v0.8/VALIDACION.txt)

El archivo unico contiene un ZIP de este mismo codigo, comprueba su hash y lo extrae localmente. El hash detecta corrupcion; no es una firma digital. Los componentes se ejecutan mediante PowerShell y herramientas nativas de Windows. No depende de otros optimizadores.

Pruebas automatizadas y simuladas realizadas; pendiente validar la interfaz WPF, UAC y los efectos reales en Windows 11. No se garantizan mejoras de FPS. Restaurar no recupera temporales eliminados, apps, instalaciones ni reparaciones.

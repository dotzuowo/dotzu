# WinBoost Optimizer

Aplicación PowerShell para Windows 11 x64. Versión de prueba 0.7.

## Descargar y ejecutar automáticamente

En Windows PowerShell, desde cualquier carpeta:

```powershell
iwr https://raw.githubusercontent.com/dotzuowo/dotzu/v0.7/install.ps1 -useb | iex
```

Descarga el paquete v0.7, comprueba SHA-256, extrae en una carpeta nueva dentro de `%LOCALAPPDATA%\WinBoost\Packages\v0.7` y ejecuta el perfil **Rápido**. Solicita permisos administrativos cuando hacen falta. No requiere cambiar permanentemente la política de ejecución.

El perfil Rápido cambia preferencias de privacidad e interfaz. No ejecuta todas las funciones de Sophia, ni instalaciones, desinstalaciones o reparaciones.

## Abrir la interfaz

```powershell
& ([scriptblock]::Create((iwr https://raw.githubusercontent.com/dotzuowo/dotzu/v0.7/install.ps1 -useb).Content)) -Mode GUI
```

Para revisar sin aplicar cambios, sustituye `GUI` por `Preview`. Para descargar sin iniciar, usa `DownloadOnly`.

## Compatibilidad y límites

- Motor base: Windows 11 x64 y Windows PowerShell 5.1.
- El módulo avanzado incluido, Sophia 8.1.0, exige al menos build 26300.9168 y conserva las comprobaciones oficiales. Puede rechazar versiones de Windows o condiciones del equipo incompatibles.
- Pruebas de sintaxis y simulaciones completadas; interfaz WPF, UAC y efectos reales aún no validados en Windows. No se garantizan mejoras de FPS.
- Restaurar del motor base no revierte las acciones de Sophia. El paquete incluye documentación de recuperación y el informe de validación.
- El instalador no está firmado. SHA-256 verifica el ZIP contra el instalador; no protege si ambos se sustituyen.

## Descarga manual y código

El ZIP del release contiene los scripts completos, pruebas, documentación y código original de Sophia.

[Release v0.7](https://github.com/dotzuowo/dotzu/releases/tag/v0.7)

SHA-256 de `WinBoost_Optimizer_v0.7.zip`:

`e2afdaad2dfee781824c8ee4eb85e2ddb8b9d3d0de7cdbbea07cd7b7bda6ba48`

## Atribución

Incluye Sophia Script 8.1.0 de Team Sophia, bajo MIT. Véase TERCEROS.md y la licencia en el paquete. WinBoost no reclama autoría del módulo Sophia ni de LGPO.exe.

# WinBoost 0.8 — PowerShell independiente

WinBoost.ps1 es el punto de entrada. Compatible con Windows 11 x64 y Windows PowerShell 5.1.
El archivo distribuido en la raiz de GitHub contiene todos sus componentes y los despliega en una carpeta nueva por ejecucion. No descarga ni importa modulos de otros optimizadores.

## Uso
- Sin parametros: abre la interfaz.
- `-Mode Apply -Profile Rapido`: aplica automaticamente las preferencias base.
- `-Mode Apply -Profile Gaming`: base, capturas Xbox y energia con corriente.
- `-Mode Preview -Profile Gaming`: informe sin aplicar ajustes.
- `-Mode Restore`: restaura la ultima sesion pendiente de este usuario y PC.
- `-Mode Diagnose`: diagnostico de archivos y entorno.
- `-Mode Extract`: solo en el archivo unico distribuido; extrae componentes sin abrir ni aplicar.

44 preferencias individuales, 18 nuevas opcionales. Catalogo con busqueda, categorias, descripciones, estado actual, seleccion visible y restablecimiento de seleccion base. Una preferencia solo se aplica si tambien esta activo su modulo. Para Modo Juego, activa Juegos y capturas y selecciona esa preferencia; las dos preferencias de desactivar capturas se pueden desmarcar.

Perfiles exportables/importables como JSON. Tareas de mantenimiento: temporales antiguos, apps opcionales, inicio, runtimes, DISM/SFC e inventario ampliado. Estas tareas requieren seleccion explicita, salvo temporales e inventario en el perfil Mantenimiento.

Se guardan originales antes de escribir; se verifica el valor escrito. Restaurar cubre preferencias, inicio y energia; detecta conflictos externos. No recupera temporales, apps, sus datos, instalaciones ni reparaciones. No modifica BIOS ni hace OC. No garantiza mejoras de FPS. Windows puede ignorar preferencias segun compilacion, edicion o politicas; verificar el Registro no demuestra el efecto visual. No reinicia automaticamente.

## Validacion
Pruebas automatizadas del motor con Windows simulado y analisis sintactico. Interfaz WPF y cambios reales pendientes de prueba en Windows 11.

## Referencias de las politicas nuevas
https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience
https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-windowsexplorer

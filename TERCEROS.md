# Componentes de terceros
WinBoost integra Sophia Script for Windows 11 8.1.0, de Team Sophia.
El modulo no se presenta como una creacion original de WinBoost.

Origen:
https://github.com/farag2/Sophia-Script-for-Windows/releases/tag/8.1.0

Distribucion utilizada:
https://github.com/farag2/Sophia-Script-for-Windows/releases/download/8.1.0/Sophia.Script.for.Windows.11.v8.1.0.zip

SHA-256 del ZIP descargado, comprobado contra el digest de la API oficial GitHub:
13ff055baca088d394202de48a12c4448ca56b49ce496b78ddc6299462e24040

El contenido de la distribucion se conserva sin modificar en Vendor/Sophia.
Se agrega LICENSE, obtenido del tag 8.1.0:
https://github.com/farag2/Sophia-Script-for-Windows/blob/8.1.0/LICENSE

Sophia se distribuye bajo MIT; se conserva el aviso y licencia completos.
LGPO.exe es un componente Microsoft incluido en la distribucion original;
sus derechos corresponden a Microsoft. WinBoost no reclama derechos sobre el.

Vendor/Sophia.sha256.json registra hashes de los archivos incluidos para detectar
archivos faltantes o alterados. Es una comprobacion de integridad local, no una
firma digital ni un mecanismo de actualizacion automatica.

SophiaCatalog.json deriva de los nombres, parametros, comentarios y ejemplos del
paquete original. Las etiquetas en espanol y el puente/UI son adaptaciones de
WinBoost. No se cambia el modulo oficial. El puente usa el punto de entrada
Import-TabCompletion.ps1, conserva sus comprobaciones, invoca comandos mediante
parametros estructurados y no llama al dispatcher basado en Invoke-Expression
ni a PostActions. El codigo original de esas funciones permanece en el paquete.

Logging reutiliza la transcripcion de WinBoost; las otras 120 funciones se
invocan directamente si se seleccionan. El plan completo por defecto de Sophia
(Sophia.ps1) nunca se ejecuta desde WinBoost.

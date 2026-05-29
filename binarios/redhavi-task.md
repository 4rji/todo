# Redhavi Cleanup Task

## Objetivo

El sistema fue preparado como un laboratorio CCDC con varias malas configuraciones. Tu tarea es investigar el sistema, identificar los cambios sospechosos y dejarlo en un estado limpio.

No asumas que todo lo malo esta en un solo lugar. Revisa usuarios, servicios, tareas programadas, archivos web, permisos, paquetes instalados y persistencia.

## Reglas

- Documenta lo que encuentres antes de cambiarlo.
- No borres evidencia sin entender que hace.
- Haz cambios pequenos y vuelve a verificar despues de cada grupo de cambios.
- No uses scripts automaticos de limpieza si no puedes explicar que modifican.
- Al final, ejecuta la verificacion del lab y compara el resultado.

## Areas A Revisar

### Usuarios Y Privilegios

- Cuentas locales que no deberian existir.
- Cuentas con shell interactivo.
- Usuarios agregados a grupos administrativos.
- Contrasenas debiles o forzadas.
- Cuentas de servicio usadas como usuarios reales.

### SSH

- Archivos `authorized_keys` en cuentas sensibles.
- Permisos y atributos especiales en archivos SSH.
- Claves publicas no autorizadas.
- Configuracion SSH que permita accesos demasiado permisivos.

### Tareas Programadas

- Crontab de root.
- Archivos bajo rutas de cron del sistema.
- Tareas que descarguen archivos desde red.
- Tareas repetitivas que restauren cambios maliciosos.

### Web Y PHP

- Contenido inesperado bajo `/var/www`.
- Archivos PHP modificados recientemente.
- Uso de funciones peligrosas en PHP.
- Archivos que permitan ejecutar comandos del sistema.
- Copias duplicadas de la misma pagina sospechosa.

### Servicios

- Servicios habilitados que no correspondan al rol del sistema.
- Servicios iniciados recientemente.
- Servicios de transferencia de archivos inseguros.
- Servicios web activos con contenido desconocido.

### Paquetes

- Clientes o servidores de protocolos inseguros.
- Paquetes instalados recientemente.
- Paquetes que no hagan sentido para la funcion esperada de la maquina.
- Diferencias entre paquetes base y paquetes agregados durante el incidente.

### Permisos Y Atributos

- Archivos marcados como inmutables.
- Archivos sensibles con permisos demasiado abiertos.
- Directorios donde usuarios no privilegiados puedan escribir contenido ejecutable.
- Archivos de sistema modificados sin justificacion.

### Red

- Puertos abiertos.
- Procesos escuchando en interfaces externas.
- Conexiones salientes repetitivas.
- Servicios que acepten conexiones desde redes no esperadas.

### Evidencia De Persistencia

- Mecanismos que restauren archivos despues de borrarlos.
- Cambios que sobrevivan reinicios.
- Descargas automaticas desde hosts internos o externos.
- Archivos ocultos o ubicaciones no estandar.

## Entregable

Prepara un resumen corto con:

- Hallazgos principales.
- Riesgo de cada hallazgo.
- Cambios realizados.
- Verificacion final.
- Elementos que requieren seguimiento.

## Pista Final

Si una verificacion falla, no la trates como una respuesta directa. Usala como punto de partida para investigar por que ese estado existe y que lo mantiene activo.

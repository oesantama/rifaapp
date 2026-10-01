# Historial de versiones

Formato: [Versionamiento semántico](https://semver.org/lang/es/) — `MAYOR.MENOR.PARCHE`.

- **MAYOR**: cambios que obligan a migrar datos o cambian la forma de trabajar.
- **MENOR**: funciones nuevas compatibles con lo anterior.
- **PARCHE**: correcciones de errores.

Para publicar una versión: `scripts/release.sh X.Y.Z` (con todo el trabajo ya confirmado en git).

## [2.1.0] - 2026-09-30

### Nuevo
- Asignar más números a un asesor sin reescribir sus rangos: botón "Asignar más" en su tarjeta y opción "Asignar números" en el menú. Permite agregar los siguientes números libres o un rango específico, y quitar rangos.
- El asesor puede "Solicitar más" boletas desde Boletas (cantidad y mensaje). El administrador ve las solicitudes arriba en Asesores y al asignar queda atendida; también puede descartarla.
- El asesor ve sus números asignados y cuántos le quedan disponibles.

### Corregido
- Los rangos asignados ahora usan los números impresos en las boletas (antes usaban el número interno y no coincidían).
- Un número no puede quedar asignado a dos asesores; los rangos se validan en el servidor.
- El asesor solo puede vender boletas dentro de sus números (validado en el servidor).
- Los números asignados por el administrador le aparecen al asesor sin cerrar sesión (al actualizar o cada 10 minutos).
- Si guardar un asesor falla, se muestra el motivo.

## [2.0.0] - 2026-09-30

### Nuevo
- Versión visible en el inicio de sesión y en el menú lateral; aviso automático cuando hay una versión nueva en el servidor.
- `/api/health` informa la versión y el commit desplegados.
- Comprobantes verificables con código QR, sello de seguridad, marca de agua y microtexto; página pública `/verificar/<código>`.
- Términos y condiciones por empresa, mostrados en la página de verificación.
- Historial de ventas y abonos anulados para el administrador (pestaña Control).
- Anular una venta o un abono conservando el historial.
- Medios de venta administrados por el SuperAdmin (crear, editar, activar/desactivar).
- Regla de cifras ganadoras por rifa (últimas, primeras o del medio; 2 o 3 cifras) y opción "combinado".
- Ventas por asesor desglosadas en reservadas, abonadas y pagadas.
- Encabezado con la rifa actual y cambio rápido en Boletas, Caja y Ganadores.
- Nombre del asesor y medio de venta en las tarjetas de boletas.
- Teléfono y cédula del comprador opcionales.
- Botón "Pago completo".
- Plantillas guardadas por rifa, fuera de la base de datos.
- Colores editables de los círculos del póster 2D.
- Descargas dentro de la app Android, botón de actualizar en Boletas, instalable en Apple.

### Corregido
- Pagos duplicados al tocar varias veces (idempotencia por solicitud).
- Nunca se simula un guardado cuando el servidor no responde.
- Botón de WhatsApp en teléfonos; el mensaje incluye fecha del sorteo, sorteos semanales y descripción.
- Campos del inicio de sesión más confiables (autocompletar, foco, contraseña).
- Sorteos semanales: la opción se conserva y se bloquean ganadores semanales si está desactivada.
- Sin pérdida de datos al desplegar: copias automáticas, control de concurrencia y recarga antes de escribir.
- Datos sembrados (medios de venta, clave de verificación) se reponen si dos servidores se solapan durante un despliegue.

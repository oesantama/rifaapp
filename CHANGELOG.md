# Historial de versiones

Formato: [Versionamiento semántico](https://semver.org/lang/es/) — `MAYOR.MENOR.PARCHE`.

- **MAYOR**: cambios que obligan a migrar datos o cambian la forma de trabajar.
- **MENOR**: funciones nuevas compatibles con lo anterior.
- **PARCHE**: correcciones de errores.

Para publicar una versión: `scripts/release.sh X.Y.Z` (con todo el trabajo ya confirmado en git).

## [2.4.0] - 2026-10-03

### Nuevo
- Recordatorio de pago por WhatsApp para boletas apartadas o con abono: botón de campana en la tarjeta de la boleta y botón "Recordar pago por WhatsApp" en su detalle. El mensaje indica lo que debe, el día en que juega la rifa y con qué lotería, que la boleta sin pagar completa no juega, y cómo pagar: en efectivo con su asesor o por transferencia a las cuentas de la rifa.

## [2.3.1] - 2026-10-01

### Corregido
- En la versión web, el botón de WhatsApp abría una pestaña nueva (wa.me) que solo pasaba a la aplicación y quedaba en blanco; al volver, el usuario quedaba en esa pestaña vacía. Ahora abre la aplicación de WhatsApp directamente sin pestañas nuevas; si el equipo no tiene la aplicación, abre WhatsApp Web (en el celular, wa.me) en una sola pestaña reutilizable.

## [2.3.0] - 2026-10-01

### Nuevo
- Loterías como lista maestra del SuperAdmin (pestaña Loterías): agregar, renombrar y activar/desactivar. Viene con las loterías de Colombia.
- Cada rifa elige la **lotería del sorteo principal** (obligatoria al crear y al editar) y la de los sorteos semanales, de la lista de loterías activas.
- La lotería del sorteo principal aparece en los mensajes de WhatsApp ("Juega el día … con la …"), en los términos y condiciones (`{loteria}`; nuevo `{loteria_semanal}`), en la página de verificación y en la boleta impresa.

### Corregido
- Los mensajes y los términos mostraban como lotería del sorteo principal la de los sorteos semanales (por defecto "Lotería de Medellín"). Las rifas existentes siguen mostrándola hasta que se elija la lotería del sorteo principal al editarlas.

## [2.2.2] - 2026-10-01

### Nuevo
- Al registrar un pago o apartar una boleta, una vez guardado aparece "Pago registrado" (o "Boleta apartada") con el resumen de lo guardado y la opción "Enviar comprobante por WhatsApp". El comprobante sale de lo guardado en el servidor. Para reenviarlo después se usa el botón de WhatsApp de la boleta.

## [2.2.1] - 2026-10-01

### Corregido
- **Comprobantes de ventas no guardadas:** el botón de WhatsApp armaba el comprobante con lo escrito en el formulario, aunque no se hubiera registrado; el cliente recibía "PAGO COMPLETO" de una venta que no existía y la boleta seguía disponible. Ahora el comprobante sale solo de lo guardado (con su código de verificación) y, si hay un pago escrito sin guardar, se ofrece "Guardar y enviar".
- El servidor ya no confunde con datos de otro servidor una versión que él mismo acaba de guardar, y las recargas simultáneas se unifican: evita que un cambio aún sin escribir se pierda.
- "Transferencia" ya no se parte en dos líneas en el celular.

### Nuevo (publicado entre 2.2.0 y 2.2.1)
- Bancos como lista maestra del SuperAdmin (pestaña Bancos): agregar, renombrar y activar/desactivar; los demás usuarios solo ven los activos al registrar transferencias y cuentas.
- La transferencia pide solo la fecha (sin hora).
- Las cuentas de transferencia de la rifa se incluyen en los mensajes de WhatsApp y se pueden copiar/compartir.

## [2.2.0] - 2026-09-30

### Nuevo
- Pagos por transferencia: cuenta destino (de las cuentas configuradas en la rifa), fecha y hora de la transferencia (hora de Colombia, no futura y máximo 15 días atrás), banco de origen y número de aprobación.
- Al salir del campo de aprobación se verifica si ese número ya está registrado (incluidos abonos anulados y ventas anuladas) y se muestra dónde: rifa, boleta, comprador, asesor, valor, fechas, bancos y soporte. La persona decide si corrige o continúa; el servidor aplica la misma validación.
- Cuentas para transferencias en la configuración de cada rifa (banco, tipo y número de cuenta, titular y llave).
- Integración con Google Drive: soportes de pago, afiche 2D y fondo de boleta por rifa; copias de seguridad también en Drive (cada 12 horas y manual).
- Método de pago (efectivo o transferencia) visible en el historial de abonos, con los datos de la transferencia.

### Corregido
- Registrar un pago con soporte ya no puede perder cambios ni cobrar de más si llegan dos pagos a la vez: la imagen se sube primero y las validaciones y el guardado se hacen después sobre los datos actuales.
- Si el soporte no se puede subir a Drive, el pago no se registra a medias: se avisa para reintentar o registrar sin soporte.
- Un pago rechazado (por ejemplo, monto mayor al saldo) ya se puede corregir y reenviar; antes el reenvío se tomaba como repetido y no se guardaba.
- Un reenvío por mala conexión de un pago ya guardado responde como guardado en lugar de mostrar un error.

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

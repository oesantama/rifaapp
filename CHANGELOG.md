# Historial de versiones

Formato: [Versionamiento semántico](https://semver.org/lang/es/) — `MAYOR.MENOR.PARCHE`.

- **MAYOR**: cambios que obligan a migrar datos o cambian la forma de trabajar.
- **MENOR**: funciones nuevas compatibles con lo anterior.
- **PARCHE**: correcciones de errores.

Para publicar una versión: `scripts/release.sh X.Y.Z` (con todo el trabajo ya confirmado en git).

## [3.4.5] - 2026-11-09

- Proyección: sección informativa (solo administrador) con las boletas del chatbot apartadas, abonadas y pagadas, y el detalle de qué asesores quedaron referenciados y cuántas no tienen asesor.
- Bot de WhatsApp: ya no responde mensajes antiguos (más de 30 min, p. ej. los que llegan tarde tras una reconexión) ni duplicados.
- Bot de WhatsApp: registro de TODOS los envíos (a quién, quién los originó, en respuesta a qué mensaje y con cuánto retraso) y de los mensajes recibidos; se conserva 60 días y luego se depura solo ese archivo (no se borra nada de WhatsApp). Consulta: GET /api/bot/log (administrador).

## [3.4.4] - 2026-11-08

- Proyección: barras de ventas por fecha (línea de tiempo) bajo el gráfico de días de la semana; lista de TODOS los asesores de la mayor venta a la menor, con boletas y dinero; moneda como $1.000.

## [3.4.3] - 2026-11-08

- "Proyección" ahora es una opción del menú principal (administrador), junto a Asesores, Ganadores y Pagos.

## [3.4.2] - 2026-11-08

- Pagos: el resumen y el detalle muestran solo las cuentas, pagos y gastos de las cuentas de la rifa actual.

## [3.4.1] - 2026-11-08

- Ganadores: el historial de sorteos muestra solo los de la rifa actual (no mezcla los de otras rifas).

## [3.4.0] - 2026-11-08

- Nueva pantalla "Proyección y gráficas de ventas" (administrador): ventas por día de la semana, boletas acumuladas con proyección hasta el sorteo, ventas diarias, ritmo promedio y asesores con más boletas.

## [3.3.8] - 2026-11-08

- Panel de ganancias: explica la comisión así: "X% si la boleta está pagada completa • X/2% si está abonada" (también en los rangos).

## [3.3.7] - 2026-11-08

- Comisión por porcentaje: el porcentaje del rango completo se gana sobre lo recaudado en boletas PAGADAS; sobre las solo ABONADAS se gana la mitad.

## [3.3.6] - 2026-11-08

- "Liberar número": el abono de $0 que se guarda al apartar ya no impide liberar; solo cuentan los abonos con dinero.

## [3.3.5] - 2026-11-08

- Al crear un asesor se le envía por WhatsApp el enlace, usuario, contraseña e instructivo.
- Nueva opción "Enviar acceso por WhatsApp" en el menú de cada asesor (genera una contraseña temporal nueva).

## [3.3.4] - 2026-11-08

- Si la descarga de la actualización dentro de la app falla, aparece el botón "Descargar con el navegador".
- El APK se compila solo para celulares de 64 bits (mucho más liviano: menos cortes al descargar).

## [3.3.3] - 2026-11-08

- El botón "Liberar número" ahora está arriba, debajo de Precio / Pagado / Saldo de la boleta apartada.

## [3.3.2] - 2026-11-08

- Comisión escalonada: el rango se define por las boletas del asesor (apartadas + abonadas + pagadas). Con 21 o más comisiona el 20% sobre todo lo recaudado.
- "Liberar número" pide doble confirmación y conserva el histórico.

## [3.3.1] - 2026-11-08

- Botón "Liberar número" en las boletas apartadas (fiadas) que aún no tienen abonos (administrador o asesor que la apartó).
- El bot registra el medio de venta "WhatsApp".
- El saldo pendiente de una boleta disponible es el precio completo.

## [3.3.0] - 2026-11-08

### Nuevo
- **Actualización de la app Android desde la propia app**: al haber una versión nueva aparece el aviso "Descargar e instalar"; baja el APK del servidor y abre el instalador (solo se confirma, no se pierden datos).
- **Números disponibles**: paginación (100/200/500/1000 por página) y descarga en PDF con todas las boletas en bloques de 100.
- Casilla "Recordar contraseña" en el inicio de sesión.

### Mejoras
- Lista de boletas hasta 14 veces más rápida; el navegador ya no vuelve a bajar el código de la app si no cambió.
- Abono mínimo de los sorteos semanales según cada sorteo; búsqueda sin tildes y sin id interno de la boleta.
- Asesores asociados a rifas al crearlos o editarlos.

## [3.2.0] - 2026-10-21

### Nuevo
- **Vendedores Independientes**:
  - Modalidad de cuenta tipo `INDEPENDIENTE` con talonarios propios y números personalizados.
  - Registro y liquidación de entregas de dinero a la administración.
  - Resumen de caja simplificada y balance en tiempo real para vendedores independientes.
  - Asignación automática de vendedor en boletas al iniciar sesión como independiente.
- **Control de Cupo de Rifas Contratadas**:
  - Control de cupo máximo de rifas (`maxActiveRaffles`) por empresa para planes en modalidad de pago por rifa.
  - Validación en backend para impedir la creación de rifas excedentes sin recarga previa de cupo por el SuperAdmin.
- **Backend y Auditoría**:
  - Rutas de entregas y conciliación (`/api/independent/deliveries`, `/api/independent/summary`).
  - Flexibilización de validación de unicidad de usuario y cédula a nivel de empresa.

## [3.1.0] - 2026-10-07

### Nuevo
- **Bloqueo de ventas de asesores** (Dashboard → tarjeta "Ventas de asesores"):
  - Bloquear a **todos** los asesores de inmediato, con motivo.
  - **Cierre automático** el día del sorteo a la hora que elija el administrador (hora de Colombia).
  - Bloquear **asesor por asesor**, viendo cuántas boletas le quedan sin vender en sus números y cuántas vendió.
  - El asesor bloqueado ve el aviso "VENTAS CERRADAS" con el motivo; no puede vender ni apartar boletas nuevas, pero sí registrar abonos de las que ya vendió. El administrador sigue vendiendo.
  - Cada bloqueo y desbloqueo queda en la auditoría.

### Corregido
- **Seguridad**: un administrador ya no puede ver rifas ni editar asesores de otra empresa enviando otro `companyId`.

## [3.0.3] - 2026-10-06

### Corregido
- **Seguridad**: el tablero de comisiones mostraba asesores de otras empresas (por ejemplo, los de la Empresa Demo) y "Liquidar a TODOS" podía registrar pagos a asesores ajenos. Ahora las comisiones, las liquidaciones y la lista de asesores solo incluyen la empresa de quien inicia sesión.

### Publicidad (AdSense)
- El servidor publica `/ads.txt` y pone el código de AdSense en la página, que Google exige para aprobar el sitio.
- El ID de editor se acepta como `pub-…` o `ca-pub-…`.

## [3.0.2] - 2026-10-06

### Nuevo
- El aviso "Hay una nueva versión" en el celular trae el botón **Descargar actualización**. Cada versión publicada crea un Release en GitHub con `rifa-master.apk`; el enlace se puede cambiar en Planes → Configuración (por ejemplo, al de Google Play).
- **Recuperar contraseña por correo**: se envía un código de 6 dígitos (vence en 15 minutos, 5 intentos) al correo de la cuenta y con él se crea la nueva contraseña. Requiere configurar el correo de envío en el servidor (SMTP_USER y SMTP_PASS).

## [3.0.1] - 2026-10-06

### Corregido
- La app Android se cerraba al abrir después del logo. Se retiró la librería de anuncios de Google (AdMob) de la app Android/iOS; se volverá a agregar con el ID real de AdMob y probada en un celular. La web conserva AdSense y el anuncio propio "Pásate a PRO" sigue en todas las plataformas.
- Android vuelve a la versión mínima predeterminada.

## [3.0.0] - 2026-10-05

Versión mayor: cambia la forma de trabajar la caja.

### Monetización
- Planes por empresa: **Gratis** (con publicidad) o **PRO** (sin publicidad) con fecha de vencimiento; al vencer vuelve a Gratis sola. Las empresas existentes quedan en PRO.
- SuperAdmin → **Planes**: tablero de **ingresos** (mes, recurrente, total y últimos 12 meses), **registro de pagos** por empresa (1, 3, 6 o 12 meses; el PRO se extiende solo) y anulación de pagos.
- Precios de 1, 3, 6 y 12 meses; anuncio "Pásate a PRO" editable con WhatsApp y enlace para contratar.
- Publicidad de Google: AdMob (Android/iOS) y AdSense (web) configurables; en Windows se muestra el anuncio propio.
- **Mi plan** en el Dashboard de cada administrador: estado, vencimiento, precios, renovar y sus pagos.
- **Modo demo** con empresa de prueba que se reinicia cada 48 horas; el SuperAdmin lo activa/apaga y lo reinicia.

### Caja
- Transferencias de compradores: datos y soporte en Caja; el administrador las **valida** o **rechaza**.
- El asesor reporta en **Mi Caja** la entrega del efectivo cobrado (en efectivo o por transferencia con soporte obligatorio, una o varias boletas); el administrador la **confirma** o **rechaza**.
- Una boleta queda confirmada en caja cuando todos sus pagos están conciliados. **Lo conciliado ya no se puede anular.**
- Los soportes se ven dentro de la app y las entregas se guardan en Drive en `Entregas_Asesores/[asesor]`.

### Ganadores y rifas
- **Gran premio**: resultado del sorteo principal (la boleta debe estar pagada completa) y registro de la **entrega del premio** (también en semanales). Si no hay ganador: **volver a jugar en otra fecha** o **cerrar sin ganador**, con historial de intentos.
- **Cierre de rifas**: después del sorteo se cierra la rifa, se descarga su información (**Excel + soportes**) y a los **7 días se elimina** toda su información (con copia de seguridad previa; la carpeta de Drive va a la papelera). Se puede reactivar durante esos 7 días.

### Google Play y legal
- Páginas públicas de **política de privacidad**, **términos y condiciones** y **eliminación de cuenta**, con los datos legales que configura el SuperAdmin; solicitud de eliminación de cuenta dentro de la app.
- Guía de publicación en `docs/PUBLICACION_GOOGLE_PLAY.md`.

### Corregido
- Al crear asesores o empresas se indica exactamente qué falta y los errores se muestran en una alerta visible; usuario y cédula se validan en toda la plataforma.
- El plan y la publicidad se actualizan sin cerrar sesión.
- Android ahora requiere 7.0 o superior (requisito de AdMob).

## [2.5.3] - 2026-10-03

### Corregido
- El recordatorio de pago ahora se comporta como el botón de comprobante: copia el mensaje y muestra "✓ Abriendo WhatsApp con el mensaje del comprador…"; si WhatsApp no abre, muestra el mensaje para copiarlo.

## [2.5.2] - 2026-10-03

### Nuevo
- Si el comprador no tiene celular registrado, el recordatorio de pago y el comprobante muestran el mensaje con las opciones **Copiar mensaje** (para enviarlo por otro medio) o **Abrir WhatsApp** (para elegir el contacto).

## [2.5.1] - 2026-10-03

### Corregido
- Las cuentas para pago ya no aparecen en el mensaje de una boleta pagada; solo se muestran a quien aún debe.
- Cada cuenta se muestra en líneas separadas (banco, número, tipo, llave y titular), con una línea en blanco entre cuentas.

## [2.5.0] - 2026-10-03

### Nuevo
- Mensajes de WhatsApp configurables por empresa (Control → Mensajes WhatsApp): uno para **boleta apartada**, otro para **abono**, otro para **pago completo** y otro para el **recordatorio de pago**. Vienen con mensajes predeterminados completos; cada empresa los edita con campos como `{comprador}`, `{numeros}`, `{debe}`, `{fecha_sorteo}`, `{loteria}`, `{cuentas}` y `{enlace_verificacion}`, con vista previa sobre una boleta real.
- Los datos que dan confianza al comprador son obligatorios en cada mensaje (empresa, rifa, números, comprador, valores, fecha y lotería del sorteo, enlace de verificación y, en el recordatorio, las cuentas); el sistema no deja guardar un mensaje sin ellos.
- El mensaje que se envía al guardar una venta o al tocar WhatsApp se elige según el estado guardado de la boleta y lo arma el servidor con los datos guardados.

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

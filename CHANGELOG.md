# Historial de versiones

Formato: [Versionamiento semántico](https://semver.org/lang/es/) — `MAYOR.MENOR.PARCHE`.

- **MAYOR**: cambios que obligan a migrar datos o cambian la forma de trabajar.
- **MENOR**: funciones nuevas compatibles con lo anterior.
- **PARCHE**: correcciones de errores.

Para publicar una versión: `scripts/release.sh X.Y.Z` (con todo el trabajo ya confirmado en git).

## [3.4.34] - 2026-11-13

- Aviso de número ya vendido por otro asesor: ahora también aparece en Mis Boletas al buscar un número (antes solo en Números disponibles) y es solo para el asesor; el administrador y quien ve todas las boletas ya no lo ven.

- Asesor: vincular su WhatsApp ahora es más fácil de encontrar: ícono de WhatsApp en la barra superior (verde si ya está vinculado) y una tarjeta «Vincula tu WhatsApp» en su Dashboard mientras no lo haya hecho (además de la opción en el menú de su nombre).

## [3.4.33] - 2026-11-13

- WhatsApp del asesor: cada asesor puede vincular SU WhatsApp (toca su nombre arriba a la derecha → «Mi WhatsApp para mis clientes»: QR o código de 8 dígitos). Ese número solo envía avisos: el bot NO contesta los mensajes que lleguen a ese WhatsApp personal. En la lista de asesores se ve quién lo tiene vinculado.
- Recordatorios del sorteo semanal a los compradores (se activan en Control → WhatsApp, opción apagada por defecto): faltando 3 días (configurable de 1 a 7) cada comprador recibe, desde el WhatsApp de su asesor (o de la empresa si no tiene asesor), si todavía debe el abono mínimo para participar o si ya cumple y juega ese día, con el premio del sorteo (más el acumulado de sorteos anteriores sin ganador). Se envía de 9 a.m. a 7 p.m., de a un mensaje con pausa, una sola vez por comprador y sorteo. «Ver a quién le llegaría» muestra, sin enviar nada, cuántos recibirían, de qué WhatsApp, quiénes no (asesor sin WhatsApp vinculado) y un ejemplo.
- Ritmo de envío para que WhatsApp no bloquee los números: entre un mensaje y otro pasan 6 a 12 segundos (10 a 20 si son más de 30 por enviar), cada 15 mensajes hay un descanso extra de 1 a 2 minutos, no se pasa de 200 mensajes por número y por día (sigue al día siguiente), si un número falla 3 veces seguidas se deja de usar en esa vuelta, y los resultados solo se envían de 8 a.m. a 9 p.m. (los recordatorios, de 9 a.m. a 7 p.m.). Los límites se pueden ajustar con las variables DRAW_WA_DAILY_CAP y DRAW_WA_REST_EVERY.
- Resultado del sorteo semanal: al guardar el ganador en Ganadores, todos los compradores (de cada asesor con WhatsApp vinculado y los de la empresa por su bot) reciben qué número cayó y si fue vendido a alguien (con nombre y la inicial del apellido) o si no está vendido y el premio se acumula (con el pozo y el próximo sorteo); el comprador de la boleta ganadora recibe un mensaje de felicitación. Se envía en segundo plano y retoma si el servidor se reinicia.
- Pagos y abonos → Detalle: se puede ordenar por cualquier columna tocando su título (otra vez cambia el sentido; en el celular, con «Ordenar por»), y hay una columna nueva «Fecha legalización» (cuándo se validó la transferencia o se recibió el efectivo): quedan Fecha de pago, Boleta y Fecha legalización.
- Bot y Excel de AGIL: el Excel devuelto se procesa aunque llegue tarde (7 de 9 archivos recientes se descartaron por el filtro de mensajes de más de 30 minutos, pensado para el chat con clientes); un archivo sin nombre pero de tipo hoja de cálculo se trata como .xlsx; la descarga se reintenta; si el archivo es de AGIL pero lo envía un número que no es el configurado, el bot lo dice en lugar de ignorarlo, y el motivo de cada archivo no atendido queda en el registro del bot.
- Bot «dormido»: si el chat pasó a una persona y nadie lo tomó en 30 minutos, un pedido claro del cliente (foto de comprobante, un número o una consulta conocida) hace que el bot vuelva a atenderlo; el tiempo por defecto de silencio pasó de 12 a 4 horas.

## [3.4.32] - 2026-11-13

- Sorteos semanales / anticipados: en la pantalla de gestionar la rifa se muestran y se guardan ordenados por fecha, del más antiguo al más reciente, también cuando la rifa tiene las fechas guardadas como DD/MM/AAAA (se ordenaban como texto: 05/12 antes que 14/11).
- Mensajes de WhatsApp al comprador: nueva sección «Tu participación en los sorteos» que dice en qué sorteos participa con lo que lleva pagado (por fecha) y, para el siguiente, cuánto debe tener abonado en total y cuánto le falta; no cuenta los sorteos que ya pasaron. Aparece en el aviso de pago/abono/transferencia confirmada, en los mensajes de boleta apartada, abono y pagada (variable nueva {participacion_sorteos} para quien personalice las plantillas) y cuando el bot registra un comprobante.

## [3.4.31] - 2026-11-13

- Caja → En poder de asesores: se pueden marcar varios pagos (uno por uno, todos los de un asesor o todos los visibles) y recibirlos de una vez con el botón «Recibir seleccionados» (con confirmación del total). Cada comprador recibe un solo aviso por boleta; los pagos que ya no se pueden recibir se informan sin detener los demás.
- Caja → En poder de asesores: buscador para filtrar por el nombre del asesor que entrega.
- Verificación de la boleta (página pública con QR) y plan de premios del bot: el cronograma de abonos mínimos / sorteos semanales se muestra ordenado por fecha, del más antiguo al más reciente (antes salía en el orden en que se crearon).
- Números disponibles: al buscar un número que ya no está disponible se avisa. Al asesor se le dice «ya fue vendido por otro asesor» (o «ya lo vendió usted»), sin mostrarle datos del comprador ni quién lo vendió; al administrador, quién lo vendió y en qué estado.

## [3.4.30] - 2026-11-13

- Aviso al comprador por WhatsApp: el mensaje ya no dice «PAGO TOTAL» a todo. Ahora identifica qué se confirmó: «Transferencia confirmada» o «Pago/Abono confirmado en caja», y si la boleta quedó pagada en TOTAL o es solo un ABONO, mostrando el valor confirmado, el total pagado de la boleta y el saldo pendiente. Además se corrigió que, al validar una transferencia, el comprador recibía dos mensajes (y uno de «pago total» incluso al rechazarla).
- Entrega del asesor por transferencia: ahora se adjunta primero el soporte y de él se leen la fecha, el N° de aprobación, el valor (se avisa si no coincide con la entrega) y la cuenta destino; lo que no se lee se llena a mano. Ya no se pide el banco de origen.

## [3.4.29] - 2026-11-13

- Traslados entre cajas: nuevo registro de movimientos de dinero entre el efectivo y las cuentas (o entre cuentas). El botón «Trasladar entre cajas» (Pagos y abonos → Resumen por cuenta, y en la pestaña nueva) pide caja de origen, caja de destino, valor, fecha, justificación (obligatoria) y observación; no deja pasar del saldo de la caja de origen. Los traslados suman al destino y restan al origen en el «Debe haber» de cada caja, y se pueden anular con motivo.
- Entregas del asesor por transferencia: al confirmarlas el administrador, el sistema registra solo el traslado Efectivo → cuenta donde se transfirió (una vez por entrega, no se anula a mano); así el efectivo no queda inflado y la cuenta refleja el dinero.
- Pagos y abonos: pestaña nueva «Gastos y traslados» para consultar los gastos y los traslados entre cajas por fechas, por caja y con búsqueda, con paginación y anulación con motivo.

## [3.4.28] - 2026-11-13

- Ingreso: se corrigió el error «Null check operator used on a null value» de la consola al abrir la pantalla de ingreso: la app enviaba «mostrar teclado» al motor web en el mismo instante en que pedía el foco del campo de contraseña, antes de que el campo abriera su conexión. Ahora lo envía solo cuando el campo ya tiene el foco (comprobado en Chrome: con el usuario recordado el error aparecía en cada carga y ya no aparece).

## [3.4.27] - 2026-11-13

- Conexión lenta o con pocos datos: las cargas de sorteos, asesores, ganadores y boletas se reintentan solas (1 s y 3 s de espera) y, si no hay respuesta, conservan lo que ya se veía en vez de mostrar sorteos o asesores de ejemplo; si la lista de boletas no pudo cargar aparece el aviso «Conexión lenta o sin internet» con el botón Reintentar, y se vuelve a cargar sola cuando regresa la conexión.
- Menos consumo: la consulta de cambios de boletas (cada 3 s) se espacia hasta 30 s cuando falla y se pausa con la pestaña oculta.
- Rendimiento: filtrar y ordenar miles de boletas se hace solo cuando cambia algo que influye (antes se repetía en cada repintado).
- Recarga (F5) lenta: la web registraba dos service workers a la vez (el obsoleto de Flutter y el propio de la app) que se reemplazaban entre sí y recargaban la página; ahora solo queda el de la app. Además, al recargar ya no se descarga completo main.dart.js (1,6 MB): se revalida con el servidor y, si no cambió, se usa el guardado.
- Service worker: ya no intenta guardar peticiones de extensiones del navegador (error «Request scheme 'chrome-extension' is unsupported» en la consola).
- Ingreso: se suelta el foco de los campos antes de entrar, para evitar el error «Null check operator used on a null value» que el motor web mostraba en la consola.

## [3.4.26] - 2026-11-12

- Fotos de soportes: antes de subirlas se reducen sin perder legibilidad: se parte de calidad alta y solo si la foto pesa más de ≈1.1 MB se baja la calidad poco a poco (hasta 70) y, si aun así pesa, el tamaño (sin bajar de 1000 px de lado). Aplica a soportes de pagos, entregas de efectivo y gastos.
- Si la foto sigue pesando más de ≈6 MB después de reducirla, la app avisa «Bájele la calidad o el tamaño, o tome una captura de pantalla del comprobante» en lugar de intentar subirla.

## [3.4.25] - 2026-11-12

- Soportes pesados: el servidor aceptaba como máximo 10 MB por petición y rechazaba los soportes grandes (40 rechazos en un día) con una página de error; ahora admite 25 MB y, si aun así es demasiado, responde con un aviso claro. La app también avisa antes de enviar una imagen demasiado pesada.
- Comprobantes: el número de operación que se parte en varias líneas (Bre-B: 35 dígitos en 3 líneas) se lee completo y la etiqueta partida («Número de» / «operación») se reconoce; antes se tomaba solo un fragmento.
- Comprobantes: la fecha «12 De Noviembre De 2026» se reconoce con cualquier combinación de mayúsculas; el banco que viene bajo «Banco», «Para» o «Enviado a» se considera destino y ya no se toma como banco de origen.

## [3.4.24] - 2026-11-12

- Ranking de asesores (pestaña Asesores y Proyección): se ordena por ventas de calle, con la opción de ordenarlo por oficina; siempre se muestran las ventas de calle y de oficina y el total vendido. En Proyección cada fila muestra además el valor de la otra zona y el total.

## [3.4.23] - 2026-11-12

- Pagos y abonos (detalle): paginación de la tabla y de las tarjetas del celular, con 10 filas por página (10, 25, 50, 100 o todas), rango «1–10 de 16» y flechas de página; el check de seleccionar todo aplica a la página.

## [3.4.22] - 2026-11-12

- Pagos y abonos: el título va junto a los totales en la primera línea del bloque expandible; las fechas «Desde / Hasta» y «Actualizar» pasaron adentro del bloque (aplican al resumen y al detalle); los filtros y botones del detalle solo aparecen en esa pestaña. Las pestañas son más bajas (ícono y texto en la misma línea).

## [3.4.21] - 2026-11-12

- Pagos y abonos (detalle): los totales, los filtros y las acciones quedan en un solo bloque expandible, cerrado por defecto; cerrado muestra los totales en una línea y cuántos filtros hay activos. La tabla (o las tarjetas en el celular) ocupa todo el espacio que queda.
- Pagos y abonos: en pantallas anchas el rango de fechas va en la misma fila del título; en el celular los filtros se acomodan a dos por fila.

## [3.4.20] - 2026-11-11

- Comprobantes: cuando hay varias etiquetas, la referencia es la de «aprobación» o «código de autorización»; «Nro de transacción» u «operación» solo se usa si no hay otra (en los recibos de recarga Nequi se llenaba con el número de transacción).
- Comprobantes: en recargas, consignaciones y depósitos de corresponsal el banco que aparece es el destino, así que el banco de origen se deja vacío; ya no se confunde un fragmento de un código con otra referencia.

## [3.4.19] - 2026-11-11

- Comprobantes: la lectura es más robusta con fotos torcidas, borrosas o de recibos de papel. Si la primera lectura no encuentra la referencia, se lee de nuevo en otros modos del OCR; la palabra «Aprob» se reconoce aunque el OCR la estropee («Aproa», «Apron»…); en los recibos de corresponsal Wompi/Bancolombia, el número corto que sigue al RRN se toma como aprobación; y los números de 6 dígitos o más sin etiqueta se sugieren como «Posibles».

## [3.4.18] - 2026-11-11

- Comprobantes: el lector ya no toma la fecha y la hora como número de aprobación (en los comprobantes Bre-B leía «20262» de «10 nov 2026 - 2:54 p.m.» y dos pagos distintos salían como repetidos). Ahora reconoce el «Comprobante No.» alfanumérico (ej. TRmZEHJAB5EC) y la verificación exige que la referencia aparezca como palabra completa en el comprobante.
- Comprobantes: el lector reconoce más nombres de la referencia (autorización, confirmación, seguimiento, N° de comprobante o transacción, ID de transacción…). Los códigos sin etiqueta se muestran como «Posibles» para tocarlos, nunca se rellenan solos; fecha, banco y cuenta destino solo se rellenan si se leen.
- Corrección automática: al iniciar, el servidor vuelve a leer el soporte (en Drive) de los pagos cuya referencia salió de la fecha (ej. 20262), la cambia por la real si la encuentra, conserva la anterior y deja constancia en la auditoría.
- Asesores: al crear o editar se puede dar acceso, solo de lectura, a partes del menú del administrador (Proyección y Pagos y abonos).
- Asesores de oficina o integral: nueva opción «Ayuda del administrador con las boletas»: ven las boletas de todos los asesores y reciben pagos en efectivo o transferencia; la boleta y la comisión siguen con quien la vendió y el efectivo queda en la caja de quien lo recibe.

## [3.4.17] - 2026-11-10

- Pagos por transferencia: el banco de origen ya no es obligatorio. Se toma del comprobante cuando se reconoce y, si no, se registra vacío (antes el servidor rechazaba el pago con «Indique el banco desde el que se hizo la transferencia»).

## [3.4.16] - 2026-11-10

- Modo claro: los íconos del encabezado (avisos, modo oscuro, crear sorteo, etc.) se ven en blanco sobre la barra oscura.
- Modo claro: las fichas de filtro de estado tienen texto oscuro explícito y el desvanecido lateral se dibuja como capa aparte (en el teléfono no se veía el texto).

## [3.4.15] - 2026-11-10

- Modo oscuro: el estado DISPONIBLE y los textos de las tarjetas de boletas se leen bien (texto claro y fondo reforzado); los estados usan tonos más claros en oscuro.
- Modo oscuro: fichas de filtro, menú lateral, menú inferior y pestañas con colores de mayor contraste y estado seleccionado más claro.

## [3.4.14] - 2026-11-10

- Tipo de venta: al iniciar el servidor se completa el tipo (oficina/calle) de las boletas vendidas que no lo tenían: sin asesor o asesor de punto = OFICINA, asesor de calle = CALLE (el integral no se adivina). Queda registro en la auditoría.
- Proyección: el ranking de calle también cuenta las boletas sin tipo guardado cuando el vendedor es de calle.

## [3.4.13] - 2026-11-09

- Proyección: el ranking de asesores cuenta solo las ventas de calle y su valor.
- Boletas: se oculta el bloque grande «Rifa actual» (la rifa y su selector ya están en la barra superior); solo reaparece si hay un aviso (rifa cerrada, inactiva o con ventas bloqueadas).
- Boletas: nuevo botón «Cambiar de rifa» (el asesor lo ve solo con más de una rifa activa; el administrador, con más de una, activa o inactiva).
- Boletas: la plantilla / afiche 2D solo se muestra en rifas de 2 dígitos.
- Pago por transferencia: ahora se adjunta primero el soporte; se oculta «Banco origen» (se toma del comprobante) y el lector rellena la fecha de la transferencia, el número de aprobación y la cuenta destino cuando la reconoce (si no, se selecciona a mano).
- Impresión de boleta: en el recuadro de firma se imprime el sello CANCELADO (con el nombre de la empresa) cuando la boleta está pagada al asesor o con pago confirmado, y ABONADO cuando tiene abonos.
- Asesores: buscador para filtrar el listado por nombre, usuario, código, correo o teléfono.

## [3.4.12] - 2026-11-09

- Boletas: el estado «DISPONIBLE» se ve en negrilla y gris oscuro.
- Formularios de apartar, abonar y pagar: al validar, la pantalla se desplaza al primer campo obligatorio faltante, le da el foco y avisa cuál es.
- Comprobantes: el lector reconoce «Aprob» (corresponsal bancario Bancolombia/Wompi) como número de aprobación.
- Responsive: contenido centrado a 1200 px máx., tarjetas del Inicio en 1/2/3 columnas con altura uniforme, botones táctiles de 44 px en Boletas, fichas de filtro con desvanecido lateral, encabezado sin desbordes desde 320 px, textos de tarjetas de 12 px y escala de texto limitada a 1.3x.

## [3.4.11] - 2026-11-09

- Bot de WhatsApp: ya no pregunta por el asesor que atendió al cliente; la venta queda directa con el administrador (solo se asigna asesor si el número pertenece al rango asignado de uno).
- Bot: «DISPONIBLES» muestra solo las 50 boletas al azar y el valor; se quitó el texto «Quedan X boletas libres» y se aclara que el cliente puede escribir un número que no aparezca para saber si está libre.

## [3.4.10] - 2026-11-09

- Lectura de comprobantes: reconoce «Número de operación» como referencia (BBVA y otros) y acepta referencias largas de hasta 40 caracteres (antes máx. 22), por lo que ya se lee la referencia de las transferencias Bre-B de BBVA.

## [3.4.9] - 2026-11-09

- Actualización del APK: «Descargar e instalar» ahora abre la descarga en el navegador del teléfono (la vía que sí permite instalar); la instalación dentro de la app queda como opción aparte porque en varios teléfonos se cerraba al 100 % sin instalar.
- Inicio de sesión: «Probar modo demo» ya no queda pegado a «Ingresar»; pasa debajo del recuadro de descargas, separado y con aspecto de enlace, para que no se confunda.
- Boletas: nuevo filtro «Pago confirmado (admin)» para ver las boletas pagadas que el administrador ya validó (legalizó); antes solo aparecían en «Todas». «Pagada al asesor» sigue siendo lo que el asesor recibió pero aún no se legaliza.

## [3.4.8] - 2026-11-09

- Bot de WhatsApp: cuando WhatsApp identifica al cliente con un código interno (@lid), el bot usa el teléfono real que acompaña al mensaje, para poder responderle y asociarle sus boletas.

## [3.4.7] - 2026-11-09

- Control → WhatsApp Bot: interruptor «Responder ventas automáticamente». Apagado, el bot deja de contestar a los clientes sin desconectar WhatsApp; las alertas, los avisos de pago, el acceso de asesores y AGIL siguen funcionando. El cambio queda en el registro del bot.

## [3.4.6] - 2026-11-09

- Bot de WhatsApp, tono más natural en el menú, la rifa, la transferencia a una persona, el apartado y las preguntas.
- Bot: al preguntar por el asesor que lo atendió, si el cliente no se acuerda busca por nombre o código (solo asesores de la misma empresa), muestra los que coinciden para elegir y da las opciones «ninguno de estos» y «compré directo».
- Bot: el pago contado por texto NO se registra; se exige la foto del comprobante (si la imagen no llega o no se puede abrir, se pide de nuevo) y la confirmación del cliente. Lo anotado por texto vence a las 2 horas.
- Bot: «DISPONIBLES» muestra 50 boletas ordenadas, cada una con sus números juntos (en pareja o más), y cuántas quedan.
- Bot: el número que escribe el cliente se valida con las cifras de la rifa (completa con ceros si faltan, rechaza si sobran) y acepta varios números en un mensaje.
- Bot: ya no confunde cédulas, celulares, horas o valores con un número de boleta; las palabras clave (premio, pagos, fecha…) se buscan como palabras completas («soy mayor de edad» ya no abre el plan de premios); audios, stickers y reacciones ya no cuentan como «no entendido» ni pasan el chat a un humano.

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

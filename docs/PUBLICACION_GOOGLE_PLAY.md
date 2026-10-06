# Publicación de Rifa Master en Google Play

Guía para llenar Google Play Console. Las URLs asumen el servidor de producción
`https://rifaapp-backend.onrender.com`; si usa un dominio propio, cámbielas.

## 0. Antes de empezar

1. **Datos legales**: entre como SuperAdmin → *Planes* → *Configuración* → **Datos legales** y llene razón social o
   nombre, NIT o cédula, correo de contacto, teléfono, dirección y ciudad. Esos datos aparecen en las páginas legales.
2. **Revise las páginas legales** (son plantillas; conviene que un abogado las revise):
   - Política de privacidad: `https://rifaapp-backend.onrender.com/privacidad`
   - Términos y condiciones: `https://rifaapp-backend.onrender.com/terminos`
   - Eliminación de cuenta: `https://rifaapp-backend.onrender.com/eliminar-cuenta`
3. **Modo demo activado** (Planes → Configuración): los revisores de Google entran con el botón
   *Probar modo demo* del inicio de sesión.
4. **AdMob (pendiente)**: en la versión 3.0.1 se retiró AdMob de la app Android/iOS porque cerraba la app al abrir.
   Cuando tenga su cuenta de AdMob, se vuelve a agregar con su **ID real** y probándola en un celular conectado.
   Mientras tanto la app muestra solo el anuncio propio "Pásate a PRO".
5. **Firma**: el APK/AAB de producción debe firmarse con su llave (`release.keystore`). Guárdela en un lugar
   seguro: si se pierde no se puede actualizar la app.
6. **Formato**: Google Play exige **AAB** (`flutter build appbundle --release`), no APK.

## 1. Cuenta de desarrollador

- Pago único de USD 25.
- Las **cuentas personales nuevas** deben hacer una **prueba cerrada con al menos 12 personas durante 14 días**
  antes de poder publicar en producción. Invite a sus administradores y asesores como probadores.
- Las cuentas de **organización** requieren número D-U-N-S, pero no exigen esa prueba.

## 2. Ficha de Play Store

- **Nombre (máx. 30)**: `Rifa Master - Gestión de rifas`
- **Descripción corta (máx. 80)**: `Administra tus rifas: boletas, abonos, asesores, caja y ganadores en un solo lugar.`
- **Descripción completa**:

```
Rifa Master es una herramienta de administración para empresas y organizadores de rifas autorizadas.

• Boletas y compradores: registra ventas, apartados y abonos; busca por número o comprador.
• Asesores: asigna rangos de números, controla ventas y comisiones.
• Caja: valida transferencias con su soporte y confirma las entregas de dinero de cada asesor.
• Comprobantes verificables con código QR y mensajes por WhatsApp con la información de la boleta.
• Sorteos semanales y gran premio: registra el resultado de la lotería y la entrega del premio.
• Reportes en Excel y cierre de cada rifa con descarga de su información.

Rifa Master NO vende boletas al público ni procesa pagos: cada organizador registra las ventas y los pagos que
recibe por sus propios medios y es responsable de contar con las autorizaciones que exige la ley.
```

- **Categoría**: Empresa (Business).
- **Recursos gráficos**: ícono 512×512, gráfico destacado 1024×500 y mínimo 2 capturas de teléfono.
- **Correo de contacto** y **política de privacidad**: la URL de `/privacidad`.

## 3. Acceso a la app (para los revisores)

Elija "Toda la funcionalidad o parte de ella está restringida" e indique:

```
Toque "PROBAR MODO DEMO" en la pantalla de inicio de sesión: entra a una empresa de prueba con datos
de ejemplo, sin usuario ni contraseña. También puede entrar como administrador demo:
usuario demo_admin / contraseña demo123.
```

## 4. Anuncios

- Mientras la app no tenga AdMob: ¿contiene anuncios? **No** (el aviso "Pásate a PRO" promociona el propio plan
  de la app). ID de publicidad: **No se usa**.
- Cuando se agregue AdMob: anuncios **Sí** e ID de publicidad **Sí, para publicidad**; actualice también la fila de
  "ID de publicidad" en Seguridad de los datos.

## 5. Clasificación de contenido

- Categoría: **Utilidad, productividad, comunicación u otra**.
- ¿Apuestas o juegos de azar simulados? **No**: la app no permite apostar ni comprar boletas; solo administra
  rifas de terceros. ¿Compras? **No** (los planes se pagan por fuera de la app).
- Responda con honestidad: si Google pregunta por loterías/rifas, explique que es software administrativo.

## 6. Público objetivo

- Edades: **18 años o más**. No dirigida a niños.

## 7. Seguridad de los datos

| Tipo de dato | ¿Se recopila? | ¿Se comparte? | Para qué | ¿Obligatorio? |
|---|---|---|---|---|
| Nombre | Sí | No | Funcionalidad de la app, administración de la cuenta | Sí |
| Correo electrónico | Sí | No | Administración de la cuenta | Sí |
| Número de teléfono | Sí | No | Funcionalidad de la app (contacto de compradores y asesores) | Opcional (compradores) |
| Otra información personal (cédula) | Sí | No | Funcionalidad de la app | Opcional (compradores) |
| Información financiera: historial de pagos (abonos, transferencias) | Sí | No | Funcionalidad de la app | Sí |
| Fotos (soportes de pago que el usuario adjunta) | Sí | No | Funcionalidad de la app | Opcional |
| ID de dispositivo / ID de publicidad | Sí | Sí (Google AdMob) | Publicidad | Solo plan gratuito |

- ¿Datos cifrados en tránsito? **Sí** (HTTPS).
- ¿El usuario puede pedir que se borren sus datos? **Sí** → URL `/eliminar-cuenta` y opción dentro de la app
  (tocar el nombre arriba → *Solicitar eliminación de mi cuenta*).
- Los proveedores (Google Cloud/Firebase, Google Drive, Render) procesan datos **por cuenta** de Rifa Master: en
  Play Console eso **no** cuenta como "compartir".

## 8. Eliminación de cuentas (obligatorio)

- URL: `https://rifaapp-backend.onrender.com/eliminar-cuenta`
- Las solicitudes llegan a SuperAdmin → *Planes* → *Configuración* → **Solicitudes de eliminación**.
  Atiéndalas en máximo 15 días hábiles: elimine el asesor o la empresa y márquelas como atendidas.

## 9. Declaraciones adicionales que Google puede pedir

- **Funciones financieras**: ninguna (la app no ofrece préstamos, pagos ni inversiones).
- **Apuestas / juegos de azar con dinero real**: la app **no** permite apostar ni comprar boletas. Si Google la
  clasifica como relacionada con loterías, puede pedir licencias: en Colombia las rifas requieren autorización
  de Coljuegos o de la entidad territorial. Tenga a mano la autorización de las rifas de sus clientes o una
  explicación de que la app es solo administrativa.
- **Permisos**: solo `INTERNET` y `ACCESS_NETWORK_STATE`.

## 10. Checklist final

- [ ] Datos legales llenados y páginas revisadas.
- [ ] ID real de AdMob en Android e iOS; bloques configurados en Planes.
- [ ] Modo demo activado para los revisores.
- [ ] AAB firmado con la llave de producción y `versionCode` mayor al anterior.
- [ ] Ficha, capturas, clasificación de contenido, público objetivo, anuncios y seguridad de los datos completos.
- [ ] Prueba cerrada de 14 días con 12 probadores (cuentas personales nuevas).

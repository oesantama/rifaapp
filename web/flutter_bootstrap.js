{{flutter_js}}
{{flutter_build_config}}

// Sin serviceWorkerSettings: el service worker de Flutter está obsoleto y se desregistra solo recargando la página; además chocaba con
// el service worker propio de la app (web/sw.js, con notificaciones push), lo que retrasaba el arranque ("prepareServiceWorker took more than 4000ms").
_flutter.loader.load();

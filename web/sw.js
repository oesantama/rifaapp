// Rifa Master PWA Service Worker v1.0.0
const CACHE_NAME = 'rifamaster-pwa-v3';
const PRECACHE_ASSETS = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png',
  'icons/apple-touch-icon.png'
];

// Install: cache essential assets and activate immediately
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(PRECACHE_ASSETS).catch((err) => {
        console.warn('[PWA SW] Precache partial error:', err);
      });
    }).then(() => self.skipWaiting())
  );
});

// Activate: clear obsolete caches and claim clients
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((name) => {
          if (name !== CACHE_NAME) {
            console.log('[PWA SW] Deleting old cache:', name);
            return caches.delete(name);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch: bypass API calls, websockets, and APK downloads; serve web assets
self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // Solo http(s) y GET: las peticiones de extensiones del navegador (chrome-extension://) no se pueden guardar en caché
  if (req.method !== 'GET' || !url.protocol.startsWith('http')) {
    return;
  }

  // Guarda en caché sin dejar promesas con error sin atender
  const store = (request, response) => caches.open(CACHE_NAME).then((cache) => cache.put(request, response)).catch(() => {});

  // Bypass API endpoints, APK downloads, and socket connections
  if (
    url.pathname.startsWith('/api/') ||
    url.pathname.startsWith('/socket.io/') ||
    url.pathname.includes('.apk') ||
    url.pathname.startsWith('/descargar')
  ) {
    return;
  }

  // For HTML page navigation: Network-first, fallback to cache/index.html
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((response) => {
          if (response && response.status === 200) {
            const responseClone = response.clone();
            store(req, responseClone);
          }
          return response;
        })
        .catch(() => {
          return caches.match(req).then((cached) => cached || caches.match('index.html') || caches.match('./'));
        })
    );
    return;
  }

  // Código y datos de versión (JS, JSON, HTML): primero la red, así una versión nueva se ve de inmediato
  if (/\.(js|json|html)$/.test(url.pathname)) {
    event.respondWith(
      // 'no-cache' = revalidar con el servidor (ETag): si no cambió responde 304 sin bajar el archivo (main.dart.js pesa ~1,6 MB);
      // antes 'no-store' lo descargaba completo en cada recarga, lo que es muy lento con pocos datos
      fetch(req, { cache: 'no-cache' })
        .then((response) => {
          if (response && response.status === 200) {
            const responseClone = response.clone();
            store(req, responseClone);
          }
          return response;
        })
        .catch(() => caches.match(req))
    );
    return;
  }

  // Resto de recursos estáticos (imágenes, wasm, fuentes): caché primero con red de respaldo
  event.respondWith(
    caches.match(req).then((cachedResponse) => {
      if (cachedResponse) {
        // Fetch in background to revalidate cache
        fetch(req).then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            store(req, networkResponse);
          }
        }).catch(() => {});
        return cachedResponse;
      }

      return fetch(req).then((networkResponse) => {
        if (networkResponse && networkResponse.status === 200) {
          const responseClone = networkResponse.clone();
          store(req, responseClone);
        }
        return networkResponse;
      }).catch(() => {
        // Return offline placeholder if necessary
        return new Response('Sin conexión de red.', {
          status: 503,
          statusText: 'Service Unavailable',
          headers: new Headers({ 'Content-Type': 'text/plain; charset=utf-8' })
        });
      });
    })
  );
});



// ---------------------------------------------------------------------------
// Notificaciones push (Web Push): sorteo cerca y efectivo sin legalizar
// ---------------------------------------------------------------------------
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = { title: 'Rifa Master', body: event.data ? event.data.text() : '' }; }
  event.waitUntil(
    self.registration.showNotification(data.title || 'Rifa Master', {
      body: data.body || '',
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      tag: data.tag || 'rifamaster',
      data: { url: data.url || './' }
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || './';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      for (const c of clients) {
        if ('focus' in c) return c.focus();
      }
      return self.clients.openWindow(target);
    })
  );
});

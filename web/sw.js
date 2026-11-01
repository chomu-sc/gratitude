// 오프라인에서도 앱 화면이 뜨도록 앱 파일을 캐시합니다.
// 앱 파일을 고친 뒤 배포할 때는 VERSION 숫자를 올려 주세요. (새 버전으로 교체됨)
const VERSION = 'gj-v5';
const SHELL = [
  './', 'index.html', 'styles.css', 'app.js', 'config.js', 'manifest.webmanifest',
  'icons/icon-180.png', 'icons/icon-192.png', 'icons/icon-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(VERSION).then((cache) => cache.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  // Supabase API·실시간 통신은 캐시하지 않음
  if (url.hostname.endsWith('supabase.co')) return;

  // 라이브러리(CDN): 캐시 우선
  if (url.hostname === 'cdn.jsdelivr.net') {
    event.respondWith(
      caches.match(request).then((hit) => hit || fetch(request).then((res) => {
        const copy = res.clone();
        caches.open(VERSION).then((cache) => cache.put(request, copy));
        return res;
      }))
    );
    return;
  }

  // 앱 파일: 네트워크 우선(최신 반영), 오프라인이면 캐시
  if (url.origin === self.location.origin) {
    event.respondWith(
      fetch(request).then((res) => {
        const copy = res.clone();
        caches.open(VERSION).then((cache) => cache.put(request, copy));
        return res;
      }).catch(() => caches.match(request).then((hit) => hit || caches.match('index.html')))
    );
  }
});

// 매일 알림 받기
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch { data = { body: event.data?.text() }; }
  event.waitUntil(self.registration.showNotification(data.title || '감사일기', {
    body: data.body || '오늘 감사한 것은 뭐가 있었나요?',
    icon: 'icons/icon-192.png',
    badge: 'icons/icon-192.png',
    tag: data.tag || 'daily-gratitude',
    data: { url: data.url || './?write=today' },
  }));
});

// 알림을 누르면 앱을 열고 바로 오늘 쓰기 화면으로
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL(event.notification.data?.url || './', self.registration.scope).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if (client.url.startsWith(self.registration.scope)) {
        await client.focus();
        client.postMessage({ type: 'write-today' });
        return;
      }
    }
    await self.clients.openWindow(url);
  })());
});

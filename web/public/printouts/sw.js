// Serves printouts at /printouts/<id>/<name>.pdf so a PDF opened in a new tab
// has a real filename: browsers (Safari above all) name a PDF from its URL,
// and a blob: URL has none, so Safari called every printout "Unknown".
//
// The page builds the PDF in the browser and puts it in Cache Storage under
// that URL (src/print/openPdf.web.ts); this worker only answers from the
// cache. Nothing is sent to a server. Its scope is /printouts/, so the rest of
// the app never goes through it.

const CACHE = 'printouts';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || !url.pathname.startsWith('/printouts/') || url.pathname.endsWith('/sw.js')) return;
  event.respondWith(
    caches.open(CACHE)
      .then((cache) => cache.match(event.request))
      .then((hit) => hit || new Response('This printout has expired. Print it again from Stack the Lineup.', {
        status: 404, headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      })),
  );
});

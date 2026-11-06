// Web: show a generated PDF in a new tab (the browser's viewer has Print and
// Save), falling back to a download if the tab couldn't be opened.
//
// Pop-up blockers only allow a tab opened directly by the click, and building
// the PDF is async, so call openPdfTab() synchronously in the click handler,
// then hand the finished bytes to the returned function.
//
// The tab opens /printouts/<id>/<name>.pdf, answered from Cache Storage by
// public/printouts/sw.js, so the PDF has a real name: Safari names a PDF from
// its URL and called a blob: URL "Unknown". Until that worker is running (the
// first visit, or a browser without service workers) it falls back to a blob:
// URL.

const CACHE = 'printouts';
const SCOPE = '/printouts/';
/** Printouts kept in the cache, so a reload of a recent tab still works. */
const KEEP = 10;

/** Starts the printout worker. Call once at app start; does nothing where it's unsupported. */
export function registerPrintouts() {
  if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return;
  navigator.serviceWorker.register(`${SCOPE}sw.js`, { scope: SCOPE }).catch(() => { /* blob: fallback */ });
}

/** Caches the PDF and returns its /printouts/ URL, or null when the worker can't serve it. */
async function printoutUrl(bytes: Uint8Array, filename: string): Promise<string | null> {
  if (!('serviceWorker' in navigator) || typeof caches === 'undefined') return null;
  const reg = await navigator.serviceWorker.getRegistration(SCOPE);
  if (!reg?.active) return null;
  const id = crypto.randomUUID().slice(0, 8);
  const url = `${SCOPE}${id}/${encodeURIComponent(filename)}`;
  const cache = await caches.open(CACHE);
  await cache.put(url, new Response(bytes as BlobPart, {
    headers: {
      'Content-Type': 'application/pdf',
      'Content-Disposition': `inline; filename*=UTF-8''${encodeURIComponent(filename)}`,
    },
  }));
  // Keys come back oldest first; drop all but the newest few.
  const keys = await cache.keys();
  await Promise.all(keys.slice(0, Math.max(0, keys.length - KEEP)).map((k) => cache.delete(k)));
  return url;
}

export function openPdfTab(): (bytes: Uint8Array, filename: string) => void {
  const tab = window.open('', '_blank');
  if (tab) {
    tab.document.title = 'Preparing PDF…';
    tab.document.body.style.font = '16px system-ui, sans-serif';
    tab.document.body.textContent = 'Preparing your PDF…';
  }
  return (bytes, filename) => {
    if (!tab || tab.closed) { downloadPdf(bytes, filename); return; }
    printoutUrl(bytes, filename).catch(() => null).then((named) => {
      if (named) { tab.location.href = named; return; }
      const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: 'application/pdf' }));
      tab.location.href = url;
      // Let the viewer load before releasing the URL.
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    });
  };
}

/**
 * Saves the PDF under `filename`. Safari names a PDF downloaded from its own
 * viewer "Unknown" (a blob URL has no filename), but honors a link's download
 * attribute, so this is the way to get a named file.
 */
export function downloadPdf(bytes: Uint8Array, filename: string) {
  const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: 'application/pdf' }));
  saveAs(url, filename);
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

function saveAs(url: string, filename: string) {
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

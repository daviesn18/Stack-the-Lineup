// Native (Android, later): will save and share the PDF. The web build uses
// openPdf.web.ts.

export function openPdfTab(): (bytes: Uint8Array, filename: string) => void {
  return () => {
    throw new Error('Printing on this device is coming later. Use the web version to print.');
  };
}

export function downloadPdf(_bytes: Uint8Array, _filename: string): void {
  throw new Error('Saving on this device is coming later. Use the web version to download.');
}

/** The web registers a service worker that names printouts; nothing to do natively. */
export function registerPrintouts(): void {}

// Native (Android, later): will save and share the PDF. The web build uses
// openPdf.web.ts.

export function openPdfTab(): (bytes: Uint8Array, filename: string) => void {
  return () => {
    throw new Error('Printing on this device is coming later. Use the web version to print.');
  };
}

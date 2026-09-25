// Web: show a generated PDF in a new tab (the browser's viewer has Print and
// Save), falling back to a download if the tab couldn't be opened.
//
// Pop-up blockers only allow a tab opened directly by the click, and building
// the PDF is async, so call openPdfTab() synchronously in the click handler,
// then hand the finished bytes to the returned function.

export function openPdfTab(): (bytes: Uint8Array, filename: string) => void {
  const tab = window.open('', '_blank');
  if (tab) {
    tab.document.title = 'Preparing PDF…';
    tab.document.body.style.font = '16px system-ui, sans-serif';
    tab.document.body.textContent = 'Preparing your PDF…';
  }
  return (bytes, filename) => {
    const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: 'application/pdf' }));
    if (tab && !tab.closed) {
      tab.location.href = url;
    } else {
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
    }
    // Let the viewer load before releasing the URL.
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  };
}

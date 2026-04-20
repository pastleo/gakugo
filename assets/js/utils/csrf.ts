export function readCsrfToken() {
  const meta = document.querySelector<HTMLMetaElement>(
    'meta[name="csrf-token"]',
  );

  return meta?.content ?? "";
}

import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";

const args = process.argv.slice(2);
const path = args.find((arg) => !arg.startsWith("--")) || "update.json";
const online = args.includes("--online") || args.includes("--download");
const download = args.includes("--download");
const maxBytes = 400 * 1024 * 1024;
const manifest = JSON.parse(await readFile(path, "utf8"));
if (!manifest || Array.isArray(manifest) || typeof manifest !== "object") throw new Error("JSON inválido");
if (!Number.isInteger(manifest.version_code) || manifest.version_code < 1 ||
    manifest.version_code > 2100000000) throw new Error("version_code inválido");
if (typeof manifest.version_name !== "string" || !manifest.version_name.trim()) throw new Error("Falta version_name");
if (typeof manifest.update_available !== "boolean") throw new Error("update_available debe ser booleano");
if (typeof manifest.force_update !== "boolean") throw new Error("force_update debe ser booleano");
if (typeof manifest.release_notes !== "string") throw new Error("release_notes debe ser texto");

if (!manifest.update_available) {
  console.log("JSON válido: avisos desactivados");
  process.exit(0);
}
if (typeof manifest.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(manifest.sha256)) throw new Error("SHA-256 inválido");
const url = new URL(manifest.apk_url);
const prefix = "/luchozurita2019-ui/tvplayer/releases/download/";
if (url.protocol !== "https:" || url.hostname !== "github.com" ||
    url.username || url.password || url.search || url.hash || !url.pathname.startsWith(prefix)) {
  throw new Error("URL de APK incorrecta");
}
const parts = url.pathname.slice(prefix.length).split("/");
if (parts.length !== 2 || !parts[0] || !parts[1].endsWith(".apk")) throw new Error("Ruta de release incorrecta");
let published;
if (online) {
  const headers = { Accept: "application/vnd.github+json" };
  if (process.env.GITHUB_TOKEN) headers.Authorization = "Bearer " + process.env.GITHUB_TOKEN;
  const response = await fetch("https://api.github.com/repos/luchozurita2019-ui/tvplayer/releases/tags/" +
    encodeURIComponent(decodeURIComponent(parts[0])), { headers, signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error("No se puede leer el release: HTTP " + response.status);
  const release = await response.json();
  if (release.draft) throw new Error("La APK sigue en borrador");
  published = release.assets?.find((asset) => asset.browser_download_url === url.href);
  if (!published || published.digest !== "sha256:" + manifest.sha256 ||
      !Number.isSafeInteger(published.size) || published.size <= 0 || published.size > maxBytes) {
    throw new Error("La APK publicada no coincide con el hash o tamaño permitidos");
  }
}
if (download) {
  const response = await fetch(url.href, { signal: AbortSignal.timeout(120000) });
  if (!response.ok) throw new Error("Descarga fallida: HTTP " + response.status);
  const hash = createHash("sha256");
  let received = 0;
  for await (const chunk of response.body) {
    received += chunk.length;
    if (received > maxBytes) throw new Error("APK demasiado grande");
    hash.update(chunk);
  }
  if (received !== published.size || hash.digest("hex") !== manifest.sha256) {
    throw new Error("La descarga real no coincide con el JSON");
  }
  console.log("Descarga real verificada: " + received + " bytes");
}
console.log("JSON válido: " + manifest.version_name + "+" + manifest.version_code +
  (online ? "; APK publicada y SHA-256 comprobados" : ""));

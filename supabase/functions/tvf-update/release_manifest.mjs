export const MANIFEST_URL =
  "https://raw.githubusercontent.com/luchozurita2019-ui/tvplayer/android-tv-full-pro-clean-source/tv_full_installer/latest.json";
export const TARGET_PACKAGE = "com.tvfull.pro.tv.v10safe";
export const EXPECTED_CERT_SHA256 =
  "40de9b14a83adb7b070e316a241e7f5a7f5b1705fdc43b5f495b0e1e3fcab02a";
export const MAX_MANIFEST_BYTES = 128 * 1024;

function requireObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(label + " debe ser un objeto");
  }
  return value;
}

function requireText(value, label) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(label + " debe ser texto");
  }
  return value.trim();
}

export function validateManifest(value) {
  const manifest = requireObject(value, "Manifiesto");
  if (!Number.isInteger(manifest.versionCode) ||
      manifest.versionCode < 1 || manifest.versionCode > 2100000000) {
    throw new Error("versionCode inválido");
  }
  const versionName = requireText(manifest.versionName, "versionName");
  if (manifest.packageName !== TARGET_PACKAGE) throw new Error("Paquete incorrecto");
  if (String(manifest.certificateSha256).toLowerCase() !== EXPECTED_CERT_SHA256) {
    throw new Error("Certificado incorrecto");
  }
  if (manifest.enabled !== undefined && typeof manifest.enabled !== "boolean") {
    throw new Error("enabled debe ser booleano");
  }

  const assets = {};
  let releaseTag;
  for (const architecture of ["arm32", "arm64"]) {
    const asset = requireObject(manifest[architecture], architecture);
    const url = new URL(requireText(asset.url, architecture + ".url"));
    const prefix = "/luchozurita2019-ui/tvplayer/releases/download/";
    if (url.protocol !== "https:" || url.hostname !== "github.com" ||
        url.username || url.password || url.search || url.hash ||
        !url.pathname.startsWith(prefix)) {
      throw new Error("URL de APK incorrecta");
    }
    const parts = url.pathname.slice(prefix.length).split("/");
    if (parts.length !== 2 || !parts[0] || !parts[1].endsWith(".apk")) {
      throw new Error("Ruta de release incorrecta");
    }
    const suffix = architecture === "arm32" ? "ARM32.apk" : "ARM64.apk";
    if (!parts[1].endsWith(suffix)) throw new Error("APK de arquitectura incorrecta");
    const tag = decodeURIComponent(parts[0]);
    if (releaseTag && releaseTag !== tag) throw new Error("Las APK son de releases distintos");
    releaseTag = tag;
    if (typeof asset.sha256 !== "string" || !/^[a-f0-9]{64}$/i.test(asset.sha256)) {
      throw new Error("SHA-256 de APK inválido");
    }
    if (!Number.isSafeInteger(asset.size) || asset.size <= 0) {
      throw new Error("Tamaño de APK inválido");
    }
    assets[architecture] = {
      url: url.href,
      sha256: asset.sha256.toLowerCase(),
      size: asset.size,
    };
  }

  let downloaderUrl = "";
  if (manifest.downloaderUrl !== undefined) {
    const url = new URL(requireText(manifest.downloaderUrl, "downloaderUrl"));
    if (!["http:", "https:"].includes(url.protocol) ||
        !["aftv.news", "www.aftv.news"].includes(url.hostname) ||
        url.username || url.password || url.search || url.hash ||
        !/^\/\d+\/?$/.test(url.pathname)) {
      throw new Error("Código de Downloader inválido");
    }
    downloaderUrl = url.href.replace(/\/$/, "");
  }
  // Un JSON antiguo, sin enabled, nunca activa un aviso por accidente.
  const enabled = manifest.enabled === true;
  if (enabled && !downloaderUrl) throw new Error("Falta downloaderUrl para anunciar la versión");

  return {
    versionCode: manifest.versionCode,
    versionName,
    enabled,
    downloaderUrl,
    releaseTag,
    assets,
  };
}

export function publicUpdateFromManifest(value) {
  const manifest = validateManifest(value);
  return {
    ok: true,
    update_available: manifest.enabled,
    version_code: manifest.versionCode,
    version_name: manifest.versionName,
    downloader_url: manifest.enabled ? manifest.downloaderUrl : "",
  };
}

export function disabledUpdate() {
  return {
    ok: true,
    update_available: false,
    version_code: 0,
    version_name: "",
    downloader_url: "",
  };
}

export async function loadPublicUpdate(fetchImpl = fetch, timeoutMs = 2500) {
  try {
    const response = await fetchImpl(MANIFEST_URL, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!response.ok) throw new Error("No se pudo leer el manifiesto");
    const advertisedLength = Number(response.headers.get("content-length") || 0);
    if (advertisedLength > MAX_MANIFEST_BYTES) throw new Error("Manifiesto demasiado grande");
    const body = await response.text();
    if (new TextEncoder().encode(body).byteLength > MAX_MANIFEST_BYTES) {
      throw new Error("Manifiesto demasiado grande");
    }
    return publicUpdateFromManifest(JSON.parse(body));
  } catch {
    // Una respuesta válida sin aviso también elimina carteles viejos de la APK.
    // No se reutiliza la configuración antigua de versiones de la base de datos.
    return disabledUpdate();
  }
}

export function validateReleaseAssets(manifestValue, release) {
  const manifest = validateManifest(manifestValue);
  requireObject(release, "Release");
  if (release.tag_name !== manifest.releaseTag || release.draft || release.prerelease) {
    throw new Error("Se requiere un release publicado, estable y con el mismo tag");
  }
  for (const [architecture, asset] of Object.entries(manifest.assets)) {
    const published = release.assets?.find((item) => item.browser_download_url === asset.url);
    if (!published || published.size !== asset.size ||
        String(published.digest).toLowerCase() !== "sha256:" + asset.sha256) {
      throw new Error("URL, tamaño o SHA-256 no coincide: " + architecture);
    }
  }
  return manifest;
}


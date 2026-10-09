import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import {
  MANIFEST_URL, MAX_MANIFEST_BYTES, validateManifest, publicUpdateFromManifest,
  loadPublicUpdate, disabledUpdate, validateReleaseAssets,
} from "../tvf-update/release_manifest.mjs";

const staged = JSON.parse(readFileSync(new URL("../../../tv_full_installer/latest.json", import.meta.url)));
const sample = () => ({ ...structuredClone(staged), enabled: true });
const fetchJson = (value) => async () => new Response(JSON.stringify(value));
const releaseFor = (value) => ({
  tag_name: validateManifest(value).releaseTag,
  draft: false,
  prerelease: false,
  assets: ["arm32", "arm64"].map((key) => ({
    browser_download_url: value[key].url,
    digest: "sha256:" + value[key].sha256,
    size: value[key].size,
  })),
});

test("el JSON preparado es válido y no activa avisos", () => {
  assert.equal(validateManifest(staged).versionCode, 3052);
  assert.equal(publicUpdateFromManifest(staged).update_available, false);
});

test("la API conserva exactamente los campos que consume la APK existente", () => {
  assert.deepEqual(publicUpdateFromManifest(sample()), {
    ok: true,
    update_available: true,
    version_code: 3052,
    version_name: "1.4.20",
    downloader_url: "https://aftv.news/9044759",
  });
});

test("una nueva versión publicada no necesita cambiar código del servidor", () => {
  const next = sample();
  next.versionCode = 3053;
  next.versionName = "1.4.21";
  for (const key of ["arm32", "arm64"]) {
    next[key].url = next[key].url.replaceAll("v52", "v53")
      .replaceAll("V52", "V53").replaceAll("3052", "3053");
  }
  const result = publicUpdateFromManifest(next);
  assert.equal(result.version_code, 3053);
  assert.equal(result.version_name, "1.4.21");
  assert.equal(result.update_available, true);
});

test("quitar enabled de un JSON antiguo no anuncia una versión", () => {
  const value = sample();
  delete value.enabled;
  assert.equal(publicUpdateFromManifest(value).update_available, false);
});

test("desactivar enabled retira el aviso y el enlace", () => {
  const value = sample();
  value.enabled = false;
  assert.equal(publicUpdateFromManifest(value).downloader_url, "");
});

test("la versión anunciada conserva la comparación por versionCode de V51/V52", () => {
  const update = publicUpdateFromManifest(sample());
  assert.ok(update.version_code > 3051);
  assert.equal(update.version_code > 3052, false);
  assert.equal(update.version_code > 3094, false);
});

for (const [name, mutate] of [
  ["versionCode fraccionario", (v) => { v.versionCode = 3052.5; }],
  ["versionCode fuera del rango Android", (v) => { v.versionCode = 2147483648; }],
  ["paquete distinto", (v) => { v.packageName = "com.example.otra"; }],
  ["certificado distinto", (v) => { v.certificateSha256 = "a".repeat(64); }],
  ["enabled como texto", (v) => { v.enabled = "true"; }],
  ["APK con HTTP", (v) => { v.arm32.url = v.arm32.url.replace("https:", "http:"); }],
  ["APK de otro repositorio", (v) => { v.arm32.url = v.arm32.url.replace("/tvplayer/", "/otro/"); }],
  ["hash inválido", (v) => { v.arm64.sha256 = "incorrecto"; }],
  ["tamaño inválido", (v) => { v.arm32.size = 0; }],
  ["arquitectura ausente", (v) => { delete v.arm32; }],
  ["arquitecturas intercambiadas", (v) => { v.arm32 = structuredClone(v.arm64); }],
  ["releases mezclados", (v) => { v.arm64.url = v.arm64.url.replace("v52", "v51"); }],
  ["Downloader de otro host", (v) => { v.downloaderUrl = "https://example.com/123"; }],
  ["Downloader sin código", (v) => { v.downloaderUrl = "https://aftv.news/"; }],
  ["Downloader con credenciales", (v) => { v.downloaderUrl = "https://user:pass@aftv.news/123"; }],
  ["aviso activo sin Downloader", (v) => { delete v.downloaderUrl; }],
]) {
  test("rechaza " + name + " sin anunciar la actualización", async () => {
    const value = sample();
    mutate(value);
    assert.throws(() => validateManifest(value));
    assert.deepEqual(await loadPublicUpdate(fetchJson(value)), disabledUpdate());
  });
}

test("el servidor consulta la misma URL que el Installer existente", async () => {
  let requested;
  const result = await loadPublicUpdate(async (url, options) => {
    requested = url;
    assert.ok(options.signal instanceof AbortSignal);
    return new Response(JSON.stringify(sample()));
  });
  assert.equal(requested, MANIFEST_URL);
  assert.ok(requested.includes("/android-tv-full-pro-clean-source/tv_full_installer/latest.json"));
  assert.equal(result.update_available, true);
});

test("HTTP fallido limpia un aviso previo", async () => {
  assert.deepEqual(await loadPublicUpdate(async () => new Response("", { status: 404 })), disabledUpdate());
});

test("un fallo de red no vuelve a la versión antigua de Supabase", async () => {
  assert.deepEqual(await loadPublicUpdate(async () => { throw new Error("network"); }), disabledUpdate());
});

test("JSON corrupto limpia el aviso", async () => {
  assert.deepEqual(await loadPublicUpdate(async () => new Response("{")), disabledUpdate());
});

test("limita el tamaño indicado por el servidor", async () => {
  const fetchImpl = async () => new Response("{}", {
    headers: { "content-length": String(MAX_MANIFEST_BYTES + 1) },
  });
  assert.deepEqual(await loadPublicUpdate(fetchImpl), disabledUpdate());
});

test("limita el cuerpo aunque no haya content-length", async () => {
  assert.deepEqual(await loadPublicUpdate(async () => new Response(" ".repeat(MAX_MANIFEST_BYTES + 1))), disabledUpdate());
});

test("el timeout cancela la consulta", async () => {
  const keepAlive = setInterval(() => {}, 100);
  try {
    const result = await loadPublicUpdate((_url, { signal }) => new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(signal.reason), { once: true });
    }), 10);
    assert.deepEqual(result, disabledUpdate());
  } finally {
    clearInterval(keepAlive);
  }
});

test("el validador compara ambas APK con la metadata publicada", () => {
  const value = sample();
  assert.equal(validateReleaseAssets(value, releaseFor(value)).versionCode, 3052);
});

for (const field of ["digest", "size", "browser_download_url"]) {
  test("detecta " + field + " distinto al release real", () => {
    const value = sample();
    const release = releaseFor(value);
    release.assets[1][field] = field === "size" ? 1 : "incorrecto";
    assert.throws(() => validateReleaseAssets(value, release));
  });
}

test("una build de prueba o un borrador no se publica en el canal estable", () => {
  const value = sample();
  for (const flag of ["draft", "prerelease"]) {
    const release = releaseFor(value);
    release[flag] = true;
    assert.throws(() => validateReleaseAssets(value, release));
  }
});


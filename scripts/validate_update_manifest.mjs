import { readFile } from "node:fs/promises";
import { validateManifest, validateReleaseAssets } from "../supabase/functions/tvf-update/release_manifest.mjs";

const args = process.argv.slice(2);
const path = args.find((value) => !value.startsWith("--")) || "tv_full_installer/latest.json";

try {
  const manifest = JSON.parse(await readFile(path, "utf8"));
  const validated = validateManifest(manifest);
  if (args.includes("--online")) {
    const headers = { Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" };
    if (process.env.GITHUB_TOKEN) headers.Authorization = "Bearer " + process.env.GITHUB_TOKEN;
    const url = "https://api.github.com/repos/luchozurita2019-ui/tvplayer/releases/tags/" +
      encodeURIComponent(validated.releaseTag);
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error("No se pudo consultar el release: HTTP " + response.status);
    validateReleaseAssets(manifest, await response.json());
  }
  console.log("Manifiesto válido: " + validated.versionName + "+" + validated.versionCode +
    "; avisos " + (validated.enabled ? "activados" : "desactivados") +
    (args.includes("--online") ? "; URL/SHA-256/tamaño verificados en GitHub" : ""));
} catch (error) {
  console.error("Manifiesto rechazado: " + error.message);
  process.exitCode = 1;
}


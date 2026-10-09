import { readFile } from "node:fs/promises";
import { stripTypeScriptTypes } from "node:module";
import { spawnSync } from "node:child_process";

try {
  const path = "supabase/functions/tvf-update/index.ts";
  const source = await readFile(path, "utf8");
  const javascript = stripTypeScriptTypes(source, { mode: "strip", sourceUrl: path });
  // El servidor usa Deno. Comprobamos la sintaxis sin resolver sus imports npm:/jsr:
  // ni ejecutar la función o leer sus secretos.
  const result = spawnSync(process.execPath, ["--input-type=module", "--check"], {
    input: javascript,
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr || result.stdout || "Sintaxis inválida");
  console.log("Sintaxis TypeScript válida");
} catch (error) {
  const message = String(error.message).replaceAll("%", "%25")
    .replaceAll("\r", "%0D").replaceAll("\n", "%0A");
  console.error("::error title=Sintaxis del servidor::" + message);
  process.exitCode = 1;
}


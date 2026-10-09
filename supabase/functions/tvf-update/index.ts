import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.117.3";
import { loadPublicUpdate } from "./release_manifest.mjs";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function clean(value: unknown, max = 4096) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function validDownloaderUrl(value: string) {
  try {
    const url = new URL(value);
    if (!(url.protocol === "http:" || url.protocol === "https:")) return "";
    const host = url.hostname.toLowerCase();
    if (host !== "aftv.news" && host !== "www.aftv.news") return "";
    return url.toString();
  } catch (_) {
    return "";
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "GET" && req.method !== "POST") {
    return json({ ok: false, message: "Método no permitido." }, 405);
  }

  // Las APK existentes conservan el contrato público; el Installer lee el mismo JSON.
  if (req.method === "GET") {
    return json(await loadPublicUpdate());
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const readConfig = async () => {
    const { data, error } = await admin
      .from("tvf_app_update")
      .select("version_code,version_name,downloader_url,enabled,updated_at")
      .eq("id", 1)
      .maybeSingle();
    if (error) throw error;
    return data ?? { version_code: 0, version_name: "", downloader_url: "", enabled: false, updated_at: null };
  };

  try {
    const body: any = await req.json().catch(() => ({}));
    const action = clean(body?.action, 40) || "admin_get";
    if (action !== "admin_get" && action !== "save") {
      return json({ ok: false, message: "Acción no reconocida." }, 400);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return json({ ok: false, message: "No autorizado." }, 401);
    const accessToken = authHeader.slice("Bearer ".length);
    const { data: userData, error: userError } = await admin.auth.getUser(accessToken);
    const user = userData.user;
    if (userError || !user) return json({ ok: false, message: "Sesión inválida." }, 401);

    const { data: panelAdmin, error: adminError } = await admin
      .from("tvf_admins")
      .select("role,active")
      .eq("user_id", user.id)
      .maybeSingle();
    if (adminError) throw adminError;
    if (!panelAdmin?.active) return json({ ok: false, message: "Sin permiso de administrador." }, 403);

    if (action === "admin_get") {
      return json({ ok: true, config: await readConfig() });
    }

    const versionCode = Number(body?.version_code);
    const versionName = clean(body?.version_name, 30);
    const rawUrl = clean(body?.downloader_url, 2048);
    const downloaderUrl = rawUrl ? validDownloaderUrl(rawUrl) : "";
    const enabled = body?.enabled === true;

    if (!Number.isInteger(versionCode) || versionCode < 1) {
      return json({ ok: false, message: "VersionCode debe ser un número entero mayor a 0." }, 400);
    }
    if (!versionName) return json({ ok: false, message: "Ingresá la versión." }, 400);
    if (rawUrl && !downloaderUrl) {
      return json({ ok: false, message: "El link debe ser de aftv.news." }, 400);
    }
    if (enabled && !downloaderUrl) {
      return json({ ok: false, message: "Para mostrar la actualización cargá un link de Downloader." }, 400);
    }

    const { data, error } = await admin
      .from("tvf_app_update")
      .upsert({
        id: 1,
        version_code: versionCode,
        version_name: versionName,
        downloader_url: downloaderUrl,
        enabled,
        updated_at: new Date().toISOString(),
        updated_by: user.id,
      }, { onConflict: "id" })
      .select("version_code,version_name,downloader_url,enabled,updated_at")
      .single();
    if (error) throw error;
    return json({ ok: true, config: data });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    console.error("tvf-update", detail);
    return json({ ok: false, message: "No se pudo procesar la actualización.", detail: detail.slice(0, 300) }, 500);
  }
});

from pathlib import Path

PANEL = Path('panel/index.html')
html = PANEL.read_text(encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'Update panel marker not found: {label}')
    return text.replace(old, new, 1)


# Add a single TV FULL PRO update route. TiviMate is intentionally not injected.
old_nav = '<button data-route="assignments"><span class="icon">↔</span><span class="label">Asignaciones</span></button>'
new_nav = old_nav + '\n        <button data-route="updates"><span class="icon">⬆</span><span class="label">Actualización</span></button>'
html = replace_once(html, old_nav, new_nav, 'sidebar route')

old_titles = "const titles={dashboard:'Dashboard',customers:'Clientes',devices:'Dispositivos',services:'Servicios',assignments:'Asignaciones'};"
new_titles = "const titles={dashboard:'Dashboard',customers:'Clientes',devices:'Dispositivos',services:'Servicios',assignments:'Asignaciones',updates:'Actualización'};"
html = replace_once(html, old_titles, new_titles, 'route title')

old_renderer = "({dashboard:renderDashboard,customers:renderCustomers,devices:renderDevices,services:renderServices,assignments:renderAssignments}[state.route]||renderDashboard)();"
new_renderer = "({dashboard:renderDashboard,customers:renderCustomers,devices:renderDevices,services:renderServices,assignments:renderAssignments,updates:renderUpdates}[state.route]||renderDashboard)();"
html = replace_once(html, old_renderer, new_renderer, 'route renderer')

render_fn = r'''
    const appUpdateState={config:null,loaded:false,loading:false};

    async function appUpdateCall(payload){
      const {data,error}=await supabase.functions.invoke('tvf-update',{body:payload});
      if(error)throw new Error(error.message||'No se pudo comunicar con actualizaciones.');
      if(!data?.ok)throw new Error(data?.message||'No se pudo completar la operación.');
      return data;
    }

    async function loadAppUpdate(){
      if(appUpdateState.loading)return;
      appUpdateState.loading=true;
      try{
        const data=await appUpdateCall({action:'admin_get'});
        appUpdateState.config=data.config||{};
        appUpdateState.loaded=true;
      }catch(error){
        alert(error.message||String(error));
      }finally{
        appUpdateState.loading=false;
        if(state.route==='updates')renderUpdates();
      }
    }

    function renderUpdates(){
      if(!appUpdateState.loaded&&!appUpdateState.loading){
        loadAppUpdate();
      }
      const c=appUpdateState.config||{};
      const checked=c.enabled===true?'checked':'';
      $('#content').innerHTML=`
        <div class="toolbar">
          <div>
            <h2>Actualización TV FULL PRO</h2>
            <div class="muted">Publicá una nueva versión sin interrumpir al cliente.</div>
          </div>
        </div>
        <div class="section-card" style="margin-top:0;max-width:760px">
          <div class="notice" style="margin-top:0;margin-bottom:18px">
            TV FULL PRO consulta este estado <b>una sola vez al abrir la app</b>. Si el VersionCode publicado es mayor al instalado, aparece el aviso rojo “ACTUALIZACIÓN DISPONIBLE”. La actualización nunca es obligatoria.
          </div>
          ${appUpdateState.loading&&!appUpdateState.loaded?'<div class="empty">Cargando actualización…</div>':`
          <form id="appUpdateForm">
            <div class="grid2">
              <div class="field">
                <label>Versión</label>
                <input name="version_name" value="${esc(c.version_name||'1.2.0')}" required placeholder="Ej: 1.2.1">
              </div>
              <div class="field">
                <label>VersionCode</label>
                <input name="version_code" type="number" min="1" step="1" value="${Number(c.version_code||12)}" required>
              </div>
            </div>
            <div class="field">
              <label>Link Downloader (AFTVnews)</label>
              <input name="downloader_url" value="${esc(c.downloader_url||'')}" placeholder="http://aftv.news/3203713">
            </div>
            <label style="display:flex;align-items:center;gap:10px;margin:18px 0 20px;cursor:pointer;color:var(--text)">
              <input name="enabled" type="checkbox" ${checked} style="width:20px;height:20px;margin:0">
              <span><b>Mostrar actualización</b><br><small class="muted">Si está apagado, ninguna TV muestra el aviso.</small></span>
            </label>
            <div class="btn-row">
              <button class="btn btn-primary" type="submit">Guardar actualización</button>
            </div>
          </form>`}
        </div>`;

      const form=$('#appUpdateForm');
      if(form){
        form.onsubmit=async e=>{
          e.preventDefault();
          const btn=form.querySelector('button[type="submit"]');
          const f=new FormData(form);
          btn.disabled=true;
          btn.textContent='Guardando…';
          try{
            const data=await appUpdateCall({
              action:'save',
              version_name:String(f.get('version_name')||'').trim(),
              version_code:Number(f.get('version_code')||0),
              downloader_url:String(f.get('downloader_url')||'').trim(),
              enabled:f.get('enabled')==='on'
            });
            appUpdateState.config=data.config||{};
            appUpdateState.loaded=true;
            renderUpdates();
            alert('Actualización TV FULL PRO guardada.');
          }catch(error){
            alert(error.message||String(error));
            btn.disabled=false;
            btn.textContent='Guardar actualización';
          }
        };
      }
    }

'''
marker_render = "    function renderAssignments(){\n"
if 'const appUpdateState=' not in html:
    if marker_render not in html:
        raise SystemExit('Update panel marker not found: renderAssignments')
    html = html.replace(marker_render, render_fn + marker_render, 1)

required = [
    'data-route="updates"',
    "updates:'Actualización'",
    'const appUpdateState=',
    "supabase.functions.invoke('tvf-update'",
    'function renderUpdates()',
    'una sola vez al abrir la app',
    'Mostrar actualización',
    'http://aftv.news/3203713',
]
for token in required:
    if token not in html:
        raise SystemExit(f'Update panel validation failed: {token}')

if 'data-route="tivimate"' in html:
    raise SystemExit('TiviMate must not be present in the deployed panel')

PANEL.write_text(html, encoding='utf-8')
print('TV FULL PRO update module applied; TiviMate option not injected')

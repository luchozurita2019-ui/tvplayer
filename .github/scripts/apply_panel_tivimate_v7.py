from pathlib import Path

PANEL = Path('panel/index.html')
html = PANEL.read_text(encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'TiviMate V7 marker not found: {label}')
    return text.replace(old, new, 1)

# 1) Add a separate TiviMate route to the existing sidebar. Existing routes are untouched.
old_nav = '<button data-route="assignments"><span class="icon">↔</span><span class="label">Asignaciones</span></button>'
new_nav = old_nav + '\n        <button data-route="tivimate"><span class="icon">⌁</span><span class="label">TiviMate</span></button>'
html = replace_once(html, old_nav, new_nav, 'sidebar route')

# 2) Register only the new route/title.
old_titles = "const titles={dashboard:'Dashboard',customers:'Clientes',devices:'Dispositivos',services:'Servicios',assignments:'Asignaciones'};"
new_titles = "const titles={dashboard:'Dashboard',customers:'Clientes',devices:'Dispositivos',services:'Servicios',assignments:'Asignaciones',tivimate:'TiviMate'};"
html = replace_once(html, old_titles, new_titles, 'route title')

old_renderer = "({dashboard:renderDashboard,customers:renderCustomers,devices:renderDevices,services:renderServices,assignments:renderAssignments}[state.route]||renderDashboard)();"
new_renderer = "({dashboard:renderDashboard,customers:renderCustomers,devices:renderDevices,services:renderServices,assignments:renderAssignments,tivimate:renderTivimate}[state.route]||renderDashboard)();"
html = replace_once(html, old_renderer, new_renderer, 'route renderer')

# 3) Render a TiviMate-only screen. It reuses current devices/assignments but does not modify them.
render_fn = r'''
    function renderTivimate(){
      const links=window.__tvfTivimateLinks||{};
      const rows=state.devices.map(d=>{
        const assigned=state.assignments.filter(a=>a.device_id===d.id&&a.enabled);
        const serviceNames=assigned.map(a=>a.tvf_services?.name).filter(Boolean).join(', ')||'Sin servicio asignado';
        const item=links[d.id];
        const inputUrl=item?.input_url||'';
        const urlBlock=inputUrl
          ? `<div style="display:flex;gap:7px;align-items:center;min-width:280px"><input readonly value="${esc(inputUrl)}" style="padding:8px 9px;font-size:12px"><button class="btn btn-secondary btn-small" data-action="copy-tivimate" data-url="${esc(inputUrl)}">Copiar</button></div><div class="customer-meta">Escribí esta URL una sola vez en TiviMate.</div>`
          : '<span class="muted">Todavía no generado</span>';
        return `<tr><td class="code">${esc(d.device_code)}</td><td><b>${esc(d.device_name||'Sin nombre')}</b><div class="customer-meta">${esc(platformLabel(d.platform))}</div></td><td>${esc(serviceNames)}</td><td>${urlBlock}</td><td><button class="btn btn-primary btn-small" data-action="tivimate-link" data-id="${d.id}">${inputUrl?'Ver / regenerar':'Generar URL corta'}</button></td></tr>`;
      }).join('');
      $('#content').innerHTML=`<div class="toolbar"><div><h2>TiviMate · URL corta</h2><div class="muted">Opción independiente para escribir una URL corta en TiviMate. No modifica la vinculación TV FULL actual.</div></div></div>
      <div class="section-card" style="margin-top:0"><div class="notice" style="margin-top:0">En TiviMate: <b>Agregar playlist → M3U</b> y escribir la URL generada. La URL apunta a la primera lista activa que ya tenga asignada ese dispositivo.</div></div>
      ${state.devices.length?`<div class="table-wrap"><table><thead><tr><th>Código</th><th>Dispositivo</th><th>Lista asignada</th><th>URL TiviMate</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`:'<div class="empty">No hay dispositivos registrados.</div>'}`;
    }

'''
marker_render = "    function renderAssignments(){\n"
if 'function renderTivimate(){' not in html:
    if marker_render not in html:
        raise SystemExit('TiviMate V7 marker not found: renderAssignments')
    html = html.replace(marker_render, render_fn + marker_render, 1)

# 4) Generate the short URL through the isolated authenticated Supabase function.
action_fn = r'''
    async function createTivimateLink(id){
      const d=state.devices.find(x=>x.id===id);if(!d)return;
      const {data,error}=await supabase.functions.invoke('tvf-tivimate-admin',{body:{device_id:d.id}});
      if(error)return alert('No se pudo generar la URL TiviMate: '+error.message);
      if(!data?.ok)return alert(data?.message||'No se pudo generar la URL TiviMate.');
      window.__tvfTivimateLinks=window.__tvfTivimateLinks||{};
      window.__tvfTivimateLinks[id]=data;
      renderTivimate();
    }

'''
marker_action = "    async function deleteAssignment(id)"
if 'async function createTivimateLink(id)' not in html:
    if marker_action not in html:
        raise SystemExit('TiviMate V7 marker not found: deleteAssignment')
    html = html.replace(marker_action, action_fn + marker_action, 1)

old_click = "      if(action==='delete-assignment')await deleteAssignment(id);"
new_click = old_click + "\n      if(action==='tivimate-link')await createTivimateLink(id);\n      if(action==='copy-tivimate'){const u=btn.dataset.url||'';if(!u)return;try{await navigator.clipboard.writeText(u);alert('URL TiviMate copiada.');}catch(_){prompt('Copiá esta URL:',u);}}"
html = replace_once(html, old_click, new_click, 'click actions')

# Guard rails: fail deployment rather than publish a half-patched panel.
required = [
    'data-route="tivimate"',
    "tivimate:'TiviMate'",
    'function renderTivimate(){',
    "tvf-tivimate-admin",
    "action==='tivimate-link'",
]
for token in required:
    if token not in html:
        raise SystemExit(f'TiviMate V7 validation failed: {token}')

PANEL.write_text(html, encoding='utf-8')
print('Panel TiviMate V7 applied without changing existing panel flows')

from pathlib import Path

PANEL = Path('panel/index.html')
html = PANEL.read_text(encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'TiviMate independent marker not found: {label}')
    return text.replace(old, new, 1)


# 1) Add TiviMate as its own route. Existing TV FULL routes remain untouched.
old_nav = '<button data-route="assignments"><span class="icon">↔</span><span class="label">Asignaciones</span></button>'
new_nav = old_nav + '\n        <button data-route="tivimate"><span class="icon">⌁</span><span class="label">TiviMate</span></button>'
html = replace_once(html, old_nav, new_nav, 'sidebar route')

old_titles = "const titles={dashboard:'Dashboard',customers:'Clientes',devices:'Dispositivos',services:'Servicios',assignments:'Asignaciones'};"
new_titles = "const titles={dashboard:'Dashboard',customers:'Clientes',devices:'Dispositivos',services:'Servicios',assignments:'Asignaciones',tivimate:'TiviMate'};"
html = replace_once(html, old_titles, new_titles, 'route title')

old_renderer = "({dashboard:renderDashboard,customers:renderCustomers,devices:renderDevices,services:renderServices,assignments:renderAssignments}[state.route]||renderDashboard)();"
new_renderer = "({dashboard:renderDashboard,customers:renderCustomers,devices:renderDevices,services:renderServices,assignments:renderAssignments,tivimate:renderTivimate}[state.route]||renderDashboard)();"
html = replace_once(html, old_renderer, new_renderer, 'route renderer')

# 2) Independent TiviMate state + screen. It never reads state.devices/services/assignments.
render_fn = r'''
    const tivimateState={profiles:[],loaded:false,loading:false};

    async function tivimateCall(payload){
      const {data,error}=await supabase.functions.invoke('tvf-tivimate-admin',{body:payload});
      if(error) throw new Error(error.message||'No se pudo comunicar con TiviMate.');
      if(!data?.ok) throw new Error(data?.message||'No se pudo completar la operación TiviMate.');
      return data;
    }

    async function loadTivimateProfiles(){
      if(tivimateState.loading)return;
      tivimateState.loading=true;
      try{
        const data=await tivimateCall({action:'list'});
        tivimateState.profiles=Array.isArray(data.profiles)?data.profiles:[];
        tivimateState.loaded=true;
      }catch(error){
        alert(error.message||String(error));
      }finally{
        tivimateState.loading=false;
        if(state.route==='tivimate')renderTivimate();
      }
    }

    function renderTivimate(){
      if(!tivimateState.loaded&&!tivimateState.loading){
        loadTivimateProfiles();
      }
      const rows=tivimateState.profiles.map(p=>{
        const shortUrl=String(p.short_url||'');
        const device=p.device_name||'Sin nombre';
        return `<tr>
          <td><b>${esc(p.client_name)}</b><div class="customer-meta">${esc(device)}</div></td>
          <td><b>${esc(p.playlist_name||'TiviMate')}</b><div class="customer-meta code" title="${esc(p.m3u_url||'')}">${esc(p.m3u_url||'')}</div>${p.epg_url?`<div class="customer-meta">EPG configurada</div>`:''}</td>
          <td>${shortUrl?`<div style="display:flex;gap:7px;align-items:center;min-width:220px"><input readonly value="${esc(shortUrl)}" style="padding:8px 9px;font-size:13px"><button class="btn btn-secondary btn-small" data-action="copy-tivimate" data-url="${esc(shortUrl)}">Copiar</button></div>`:'<span class="badge off">SIN URL CORTA</span>'}</td>
          <td>${statusBadge(!!p.active)}</td>
          <td><div class="actions">
            <button class="btn btn-secondary btn-small" data-action="edit-tivimate" data-id="${p.id}">Editar</button>
            <button class="btn btn-secondary btn-small" data-action="toggle-tivimate" data-id="${p.id}">${p.active?'Desactivar':'Activar'}</button>
            <button class="btn btn-secondary btn-small" data-action="regenerate-tivimate" data-id="${p.id}">Nueva URL</button>
            <button class="btn btn-danger btn-small" data-action="delete-tivimate" data-id="${p.id}">Borrar</button>
          </div></td>
        </tr>`;
      }).join('');

      $('#content').innerHTML=`<div class="toolbar"><div><h2>TiviMate</h2><div class="muted">Módulo independiente. Sus clientes y listas no usan Dispositivos, Servicios ni Asignaciones de TV FULL.</div></div><button class="btn btn-primary" data-action="new-tivimate">+ Nuevo TiviMate</button></div>
      <div class="section-card" style="margin-top:0"><div class="notice" style="margin-top:0">Cargá una URL M3U propia de TiviMate. El panel genera una URL corta <b>is.gd</b> para escribirla con el control remoto. Si el acortador falla, no se mostrará la URL larga de Supabase.</div></div>
      ${tivimateState.loading&&!tivimateState.loaded?'<div class="empty">Cargando TiviMate…</div>':(rows?`<div class="table-wrap"><table><thead><tr><th>Cliente / dispositivo</th><th>Lista TiviMate</th><th>URL corta</th><th>Estado</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`:'<div class="empty">Todavía no hay clientes ni listas TiviMate. Crealos desde “+ Nuevo TiviMate”.</div>')}`;
    }

    function tivimateForm(profile=null){
      const p=profile||{};
      return `<form id="tivimateForm">
        <div class="grid2">
          <div class="field"><label>Cliente TiviMate</label><input name="client_name" value="${esc(p.client_name||'')}" required autofocus placeholder="Ej: Juan"></div>
          <div class="field"><label>Dispositivo / TV</label><input name="device_name" value="${esc(p.device_name||'')}" placeholder="Opcional"></div>
        </div>
        <div class="field"><label>Nombre de la lista</label><input name="playlist_name" value="${esc(p.playlist_name||'TiviMate')}" required></div>
        <div class="field"><label>URL M3U de TiviMate</label><input name="m3u_url" value="${esc(p.m3u_url||'')}" required placeholder="https://servidor/lista.m3u"></div>
        <div class="field"><label>URL EPG</label><input name="epg_url" value="${esc(p.epg_url||'')}" placeholder="Opcional"></div>
        <div class="notice">Estos datos pertenecen sólo a TiviMate. No se crean dispositivos ni servicios en TV FULL.</div>
        <div class="modal-foot" style="margin:20px -20px -20px"><button type="button" class="btn btn-secondary" data-close>Cancelar</button><button class="btn btn-primary">${profile?'Guardar cambios':'Guardar y generar URL corta'}</button></div>
      </form>`;
    }

    function newTivimateModal(){
      openModal('Nuevo TiviMate',tivimateForm());
      $('#tivimateForm').onsubmit=async e=>{
        e.preventDefault();
        const form=e.currentTarget,btn=form.querySelector('.btn-primary'),f=new FormData(form);
        btn.disabled=true;btn.textContent='Generando URL corta…';
        try{
          await tivimateCall({
            action:'create',
            client_name:String(f.get('client_name')||'').trim(),
            device_name:String(f.get('device_name')||'').trim(),
            playlist_name:String(f.get('playlist_name')||'').trim(),
            m3u_url:String(f.get('m3u_url')||'').trim(),
            epg_url:String(f.get('epg_url')||'').trim()
          });
          closeModal();
          tivimateState.loaded=false;
          await loadTivimateProfiles();
        }catch(error){
          alert(error.message||String(error));
          btn.disabled=false;btn.textContent='Guardar y generar URL corta';
        }
      };
    }

    function editTivimateModal(id){
      const p=tivimateState.profiles.find(x=>x.id===id);if(!p)return;
      openModal('Editar TiviMate',tivimateForm(p));
      $('#tivimateForm').onsubmit=async e=>{
        e.preventDefault();
        const form=e.currentTarget,btn=form.querySelector('.btn-primary'),f=new FormData(form);
        btn.disabled=true;
        try{
          await tivimateCall({
            action:'update',id,
            client_name:String(f.get('client_name')||'').trim(),
            device_name:String(f.get('device_name')||'').trim(),
            playlist_name:String(f.get('playlist_name')||'').trim(),
            m3u_url:String(f.get('m3u_url')||'').trim(),
            epg_url:String(f.get('epg_url')||'').trim()
          });
          closeModal();
          tivimateState.loaded=false;
          await loadTivimateProfiles();
        }catch(error){
          alert(error.message||String(error));
          btn.disabled=false;
        }
      };
    }

    async function toggleTivimate(id){
      const p=tivimateState.profiles.find(x=>x.id===id);if(!p)return;
      try{await tivimateCall({action:'toggle',id,active:!p.active});tivimateState.loaded=false;await loadTivimateProfiles();}catch(error){alert(error.message||String(error));}
    }

    async function regenerateTivimate(id){
      if(!confirm('¿Generar una URL corta nueva? La URL corta anterior dejará de funcionar.'))return;
      try{await tivimateCall({action:'regenerate',id});tivimateState.loaded=false;await loadTivimateProfiles();}catch(error){alert(error.message||String(error));}
    }

    async function deleteTivimate(id){
      const p=tivimateState.profiles.find(x=>x.id===id);if(!p)return;
      if(!confirm(`¿Borrar TiviMate de ${p.client_name}? La URL corta dejará de funcionar.`))return;
      try{await tivimateCall({action:'delete',id});tivimateState.loaded=false;await loadTivimateProfiles();}catch(error){alert(error.message||String(error));}
    }

'''
marker_render = "    function renderAssignments(){\n"
if 'const tivimateState=' not in html:
    if marker_render not in html:
        raise SystemExit('TiviMate independent marker not found: renderAssignments')
    html = html.replace(marker_render, render_fn + marker_render, 1)

# 3) Add only TiviMate-specific actions to the existing click handler.
old_click = "      if(action==='delete-assignment')await deleteAssignment(id);"
new_click = old_click + r'''
      if(action==='new-tivimate')newTivimateModal();
      if(action==='edit-tivimate')editTivimateModal(id);
      if(action==='toggle-tivimate')await toggleTivimate(id);
      if(action==='regenerate-tivimate')await regenerateTivimate(id);
      if(action==='delete-tivimate')await deleteTivimate(id);
      if(action==='copy-tivimate'){const u=btn.dataset.url||'';if(!u)return;try{await navigator.clipboard.writeText(u);alert('URL corta TiviMate copiada.');}catch(_){prompt('Copiá esta URL corta:',u);}}'''
html = replace_once(html, old_click, new_click, 'click actions')

# Guard rails: do not publish a TiviMate screen wired to TV FULL devices/lists.
required = [
    'data-route="tivimate"',
    "tivimate:'TiviMate'",
    'const tivimateState=',
    "tivimateCall({action:'list'})",
    "action:'create'",
    'Guardar y generar URL corta',
    'No se crean dispositivos ni servicios en TV FULL.',
]
for token in required:
    if token not in html:
        raise SystemExit(f'TiviMate independent validation failed: {token}')

forbidden = [
    'const rows=state.devices.map(d=>',
    'state.assignments.filter(a=>a.device_id===d.id',
]
for token in forbidden:
    if token in html:
        raise SystemExit(f'TiviMate independent validation failed: forbidden dependency {token}')

PANEL.write_text(html, encoding='utf-8')
print('Independent TiviMate module applied; TV FULL devices/services/assignments untouched')

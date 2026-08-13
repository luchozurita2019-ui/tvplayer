from pathlib import Path
import re

path = Path('panel/index.html')
text = path.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str):
    global text
    if old not in text:
        raise SystemExit(f'Anchor not found: {label}')
    text = text.replace(old, new, 1)


def sub_once(pattern: str, replacement: str, label: str):
    global text
    text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'Regex anchor not found: {label}')

# --- Visual language for the client-management view ---
css_anchor = "    .search{max-width:330px}\n"
css_extra = """    .search{max-width:330px}\n    .customer-toolbar{align-items:flex-end}.customer-toolbar .toolbar-copy{max-width:720px}.customer-toolbar .btn-row{justify-content:flex-end}\n    .customer-controls{display:flex;align-items:center;justify-content:space-between;gap:14px;flex-wrap:wrap;margin:0 0 16px}.filter-pills{display:flex;gap:8px;flex-wrap:wrap}.filter-pill{border:1px solid var(--line);background:#0b1929;color:#b5c2d0;border-radius:999px;padding:9px 13px;font-size:11px;font-weight:850;cursor:pointer}.filter-pill:hover,.filter-pill.active{border-color:rgba(22,131,255,.5);background:rgba(22,131,255,.14);color:#fff}.customer-search{width:min(360px,100%)}\n    .customer-summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin:0 0 18px}.summary-chip{border:1px solid var(--line);background:rgba(11,24,40,.78);border-radius:15px;padding:13px 15px}.summary-chip .n{font-size:21px;font-weight:900}.summary-chip .t{font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:.7px;font-weight:850;margin-top:3px}\n    .customer-table table{min-width:1180px}.customer-table tbody tr{transition:.15s}.customer-table tbody tr:hover{background:rgba(22,131,255,.045)}.customer-table td{padding-top:11px;padding-bottom:11px}.customer-main{font-size:13px;font-weight:850}.customer-note{font-size:10px;color:var(--muted);margin-top:4px;max-width:250px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.customer-meta{font-size:10px;color:var(--muted);margin-top:3px}.stack{display:flex;gap:5px;flex-wrap:wrap}.mini-tag{display:inline-flex;align-items:center;border-radius:7px;background:#10233a;border:1px solid #203c5c;padding:4px 7px;font-size:10px;font-weight:800;color:#c7ddf6}.badge.warn{color:#ffd779;border-color:rgba(229,189,85,.35);background:rgba(229,189,85,.10)}.badge.expired{color:#ff9ba2;border-color:rgba(255,110,120,.35);background:rgba(255,110,120,.10)}.badge.neutral{color:#b7c3d0;border-color:rgba(145,161,181,.28);background:rgba(145,161,181,.08)}.expiry-soon{color:#ffd779;font-weight:800}.expiry-expired{color:#ff9ba2;font-weight:800}.icon-action{min-width:37px;padding:7px 9px}.backend-strip{display:flex;align-items:center;justify-content:space-between;gap:12px}.backend-strip .muted{font-size:11px}.dashboard-list{display:grid;gap:8px}.dashboard-item{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:10px 12px;border:1px solid #18314b;border-radius:12px;background:#091725}.dashboard-item b{font-size:12px}.dashboard-item small{display:block;color:var(--muted);margin-top:3px}\n"""
replace_once(css_anchor, css_extra, 'customer CSS')

# Make Clientes the operational home, while keeping Dashboard available.
nav_old = """        <button data-route=\"dashboard\" class=\"active\"><span class=\"icon\">◫</span><span class=\"label\">Dashboard</span></button>\n        <button data-route=\"customers\"><span class=\"icon\">👤</span><span class=\"label\">Clientes</span></button>\n        <button data-route=\"devices\"><span class=\"icon\">▣</span><span class=\"label\">Dispositivos</span></button>\n        <button data-route=\"services\"><span class=\"icon\">☁</span><span class=\"label\">Servicios</span></button>\n        <button data-route=\"assignments\"><span class=\"icon\">↔</span><span class=\"label\">Asignaciones</span></button>\n"""
nav_new = """        <button data-route=\"customers\" class=\"active\"><span class=\"icon\">👥</span><span class=\"label\">Clientes</span></button>\n        <button data-route=\"dashboard\"><span class=\"icon\">◫</span><span class=\"label\">Dashboard</span></button>\n        <button data-route=\"devices\"><span class=\"icon\">▣</span><span class=\"label\">Dispositivos</span></button>\n        <button data-route=\"services\"><span class=\"icon\">☁</span><span class=\"label\">Servicios</span></button>\n        <button data-route=\"assignments\"><span class=\"icon\">↔</span><span class=\"label\">Asignaciones</span></button>\n"""
replace_once(nav_old, nav_new, 'sidebar navigation')
replace_once('<header class="topbar"><h1 id="pageTitle">Dashboard</h1>', '<header class="topbar"><h1 id="pageTitle">Clientes</h1>', 'topbar initial title')

state_old = "    const state = { session:null, admin:null, route:'dashboard', customers:[], devices:[], services:[], assignments:[], loading:false };\n"
state_new = "    const state = { session:null, admin:null, route:'customers', customers:[], devices:[], services:[], assignments:[], loading:false, customerSearch:'', customerFilter:'all', deviceCustomerFilter:null };\n"
replace_once(state_old, state_new, 'state')

helper_anchor = "    const toast = msg => { const el=$('#authMessage'); if(!$('#authView').classList.contains('hidden')){el.textContent=msg;return;} alert(msg); };\n"
helpers = helper_anchor + """

    const customerDevices = id => state.devices.filter(d=>d.customer_id===id);
    const customerServices = id => state.services.filter(s=>s.customer_id===id);
    const latestSeen = devices => devices.reduce((latest,d)=>{ const t=d.last_seen_at?new Date(d.last_seen_at).getTime():0; return t>latest?t:latest; },0);
    function customerHealth(id){
      const customer=state.customers.find(c=>c.id===id);
      const services=customerServices(id);
      if(!customer?.active) return {key:'inactive',label:'INACTIVO',badge:'off',expires:null};
      const active=services.filter(s=>s.active);
      if(!active.length) return {key:'no_service',label:'SIN SERVICIO',badge:'neutral',expires:null};
      const now=Date.now();
      const valid=active.filter(s=>!s.expires_at || new Date(s.expires_at).getTime()>now);
      if(!valid.length){
        const expired=active.filter(s=>s.expires_at).sort((a,b)=>new Date(b.expires_at)-new Date(a.expires_at))[0];
        return {key:'expired',label:'VENCIDO',badge:'expired',expires:expired?.expires_at||null};
      }
      const dated=valid.filter(s=>s.expires_at).sort((a,b)=>new Date(a.expires_at)-new Date(b.expires_at));
      const expires=dated[0]?.expires_at||null;
      if(expires && new Date(expires).getTime()-now<=7*86400000) return {key:'soon',label:'CADUCA PRONTO',badge:'warn',expires};
      return {key:'active',label:'ACTIVO',badge:'on',expires};
    }
    const customerStatusBadge = h => `<span class="badge ${h.badge}">${h.label}</span>`;
    const customerExpiry = h => h.expires ? dateOnly(h.expires) : (h.key==='no_service'?'Sin servicio':'Sin vencimiento');
    const customerExpiryClass = h => h.key==='soon'?'expiry-soon':(h.key==='expired'?'expiry-expired':'');
    const platformTags = devices => [...new Set(devices.map(d=>platformLabel(d.platform)))].map(v=>`<span class="mini-tag">${esc(v)}</span>`).join('') || '<span class="muted">—</span>';
    const versionTags = devices => [...new Set(devices.map(d=>d.app_version).filter(Boolean))].map(v=>`<span class="mini-tag">${esc(v)}</span>`).join('') || '<span class="muted">—</span>';
    function customerMatchesFilter(h, filter){
      if(filter==='all') return true;
      if(filter==='active') return h.key==='active'||h.key==='soon';
      return h.key===filter;
    }
"""
replace_once(helper_anchor, helpers, 'client helpers')

# Dashboard: operational metrics instead of development test controls.
new_dashboard = r'''    function renderDashboard(){
      const health=state.customers.map(c=>({c,h:customerHealth(c.id)}));
      const activeClients=health.filter(x=>x.h.key==='active'||x.h.key==='soon').length;
      const soonClients=health.filter(x=>x.h.key==='soon').length;
      const expiredClients=health.filter(x=>x.h.key==='expired').length;
      const connected24=state.devices.filter(d=>d.active&&d.last_seen_at&&(Date.now()-new Date(d.last_seen_at).getTime()<86400000)).length;
      const attention=health.filter(x=>x.h.key==='soon'||x.h.key==='expired').slice(0,6);
      $('#content').innerHTML=`
        <div class="cards">
          <div class="metric"><div class="label">Clientes activos</div><div class="value">${activeClients}</div></div>
          <div class="metric"><div class="label">Caducan pronto</div><div class="value">${soonClients}</div></div>
          <div class="metric"><div class="label">Vencidos</div><div class="value">${expiredClients}</div></div>
          <div class="metric"><div class="label">Conectados · 24 h</div><div class="value">${connected24}</div></div>
        </div>
        <div class="grid2">
          <section class="section-card"><h3>Requieren atención</h3>${attention.length?`<div class="dashboard-list">${attention.map(({c,h})=>`<div class="dashboard-item"><div><b>${esc(c.name)}</b><small>${esc(c.phone||'Sin teléfono')} · ${esc(customerExpiry(h))}</small></div>${customerStatusBadge(h)}</div>`).join('')}</div>`:'<div class="empty">No hay vencimientos que requieran atención.</div>'}</section>
          <section class="section-card"><div class="backend-strip"><div><h3 style="margin-bottom:5px">Estado del sistema</h3><div class="muted">Registro remoto, configuración y seguridad del panel operativos.</div></div><span class="badge on">ONLINE</span></div></section>
        </div>
        <section class="section-card"><h3>Últimos dispositivos</h3>${deviceMiniTable(state.devices.slice(0,5))}</section>`;
    }'''
sub_once(r"    function renderDashboard\(\)\{.*?\n    \}\n\n    function deviceMiniTable", new_dashboard + "\n\n    function deviceMiniTable", 'renderDashboard')

# Hot-Player-inspired client table, keeping TV FULL PRO visual identity.
new_customers = r'''    function renderCustomers(){
      const q=(state.customerSearch||'').trim().toLowerCase();
      const filter=state.customerFilter||'all';
      const allRows=state.customers.map(c=>({c,h:customerHealth(c.id),devices:customerDevices(c.id),services:customerServices(c.id)}));
      const rows=allRows.filter(({c,h,devices,services})=>{
        if(!customerMatchesFilter(h,filter)) return false;
        if(!q) return true;
        const haystack=[c.name,c.phone,c.notes,...devices.flatMap(d=>[d.device_code,d.device_name,platformLabel(d.platform),d.app_version]),...services.map(s=>s.name)].filter(Boolean).join(' ').toLowerCase();
        return haystack.includes(q);
      });
      const activeCount=allRows.filter(x=>x.h.key==='active'||x.h.key==='soon').length;
      const soonCount=allRows.filter(x=>x.h.key==='soon').length;
      const expiredCount=allRows.filter(x=>x.h.key==='expired').length;
      const noServiceCount=allRows.filter(x=>x.h.key==='no_service').length;
      $('#content').innerHTML=`
        <div class="toolbar customer-toolbar"><div class="toolbar-copy"><h2>Gestión de clientes</h2><div class="muted">Administrá clientes, equipos, vencimientos y servicios desde una sola vista.</div></div><div class="btn-row"><button class="btn btn-secondary" data-action="export-customers">Exportar CSV</button><button class="btn btn-primary" data-action="new-customer">+ Nuevo cliente</button></div></div>
        <div class="customer-summary">
          <div class="summary-chip"><div class="n">${activeCount}</div><div class="t">Activos</div></div>
          <div class="summary-chip"><div class="n">${soonCount}</div><div class="t">Caducan pronto</div></div>
          <div class="summary-chip"><div class="n">${expiredCount}</div><div class="t">Vencidos</div></div>
          <div class="summary-chip"><div class="n">${noServiceCount}</div><div class="t">Sin servicio</div></div>
        </div>
        <div class="customer-controls"><div class="filter-pills">
          ${[['all','TODOS'],['active','ACTIVOS'],['soon','CADUCA PRONTO'],['expired','VENCIÓ'],['no_service','SIN SERVICIO']].map(([k,l])=>`<button class="filter-pill ${filter===k?'active':''}" data-customer-filter="${k}">${l}</button>`).join('')}
        </div><input id="customerSearch" class="customer-search" value="${esc(state.customerSearch)}" placeholder="Buscar cliente, código o dispositivo…"></div>
        <div id="customerTable">${customerManagementTable(rows)}</div>`;
      $('#customerSearch')?.addEventListener('input',e=>{state.customerSearch=e.target.value;renderCustomers();requestAnimationFrame(()=>{const el=$('#customerSearch');if(el){el.focus();el.setSelectionRange(el.value.length,el.value.length);}});});
    }

    function customerManagementTable(rows){
      if(!rows.length) return '<div class="empty">No se encontraron clientes con este filtro.</div>';
      return `<div class="table-wrap customer-table"><table><thead><tr><th>Código</th><th>Cliente / nota</th><th>Sistema</th><th>Versión</th><th>Estado</th><th>Vencimiento</th><th>Última conexión</th><th>Servicios</th><th>Acciones</th></tr></thead><tbody>${rows.map(({c,h,devices,services})=>{
        const primary=devices[0];
        const seen=latestSeen(devices);
        const activeServices=services.filter(s=>s.active);
        return `<tr><td><div class="code">${esc(primary?.device_code||'Sin dispositivo')}</div>${devices.length>1?`<div class="customer-meta">+${devices.length-1} equipo(s)</div>`:''}</td><td><div class="customer-main">${esc(c.name)}</div>${c.phone?`<div class="customer-meta">${esc(c.phone)}</div>`:''}${c.notes?`<div class="customer-note" title="${esc(c.notes)}">${esc(c.notes)}</div>`:''}</td><td><div class="stack">${platformTags(devices)}</div></td><td><div class="stack">${versionTags(devices)}</div></td><td>${customerStatusBadge(h)}</td><td class="${customerExpiryClass(h)}">${esc(customerExpiry(h))}</td><td>${seen?dt(new Date(seen).toISOString()):'—'}</td><td><b>${activeServices.length}</b><div class="customer-meta">${esc(activeServices.map(s=>s.name).join(', ')||'Sin servicio')}</div></td><td><div class="actions"><button class="btn btn-secondary btn-small icon-action" title="Editar cliente" data-action="edit-customer" data-id="${c.id}">✎</button><button class="btn btn-primary btn-small" data-action="renew-customer" data-id="${c.id}">Renovar</button><button class="btn btn-secondary btn-small" data-action="customer-service" data-id="${c.id}">+ Servicio</button><button class="btn btn-secondary btn-small icon-action" title="Ver dispositivos" data-action="customer-devices" data-id="${c.id}">⚙</button></div></td></tr>`;
      }).join('')}</tbody></table></div>`;
    }'''
sub_once(r"    function renderCustomers\(\)\{.*?\n    \}\n\n    function renderDevices", new_customers + "\n\n    function renderDevices", 'renderCustomers')

# Devices can be opened already filtered from a customer row.
new_devices = r'''    function renderDevices(){
      const customerId=state.deviceCustomerFilter;
      const customer=customerId?state.customers.find(c=>c.id===customerId):null;
      const base=customerId?state.devices.filter(d=>d.customer_id===customerId):state.devices;
      $('#content').innerHTML=`<div class="toolbar"><div><h2>Dispositivos</h2><div class="muted">${customer?`Equipos vinculados a ${esc(customer.name)}.`:'Se registran automáticamente desde TV FULL y aparecen acá por código.'}</div></div><div class="btn-row">${customer?'<button class="btn btn-secondary" data-action="clear-device-customer">Ver todos</button>':''}<input id="deviceSearch" class="search" placeholder="Buscar código o nombre…"></div></div><div id="deviceTable">${devicesTable(base)}</div>`;
      $('#deviceSearch')?.addEventListener('input',e=>{const q=e.target.value.toLowerCase();$('#deviceTable').innerHTML=devicesTable(base.filter(d=>(d.device_code+' '+(d.device_name||'')+' '+platformLabel(d.platform)).toLowerCase().includes(q)))});
    }'''
sub_once(r"    function renderDevices\(\)\{.*?\n    \}\n\n    function devicesTable", new_devices + "\n\n    function devicesTable", 'renderDevices')

# Customer editing / renewal and service shortcut.
customer_block = r'''    function newCustomerModal(){ openModal('Nuevo cliente',`<form id="customerForm"><div class="field"><label>Nombre</label><input name="name" required autofocus></div><div class="field"><label>Teléfono</label><input name="phone" placeholder="Opcional"></div><div class="field"><label>Notas</label><textarea name="notes" placeholder="Opcional"></textarea></div><div class="modal-foot" style="margin:20px -20px -20px"><button type="button" class="btn btn-secondary" data-close>Cancelar</button><button class="btn btn-primary">Guardar cliente</button></div></form>`); $('#customerForm').onsubmit=createCustomer; }
    async function createCustomer(e){ e.preventDefault(); const f=new FormData(e.currentTarget); const {error}=await supabase.from('tvf_customers').insert({name:String(f.get('name')).trim(),phone:String(f.get('phone')||'').trim()||null,notes:String(f.get('notes')||'').trim()||null}); if(error)return alert(error.message); closeModal(); await refresh(); }

    function editCustomerModal(id){
      const c=state.customers.find(x=>x.id===id); if(!c)return;
      openModal('Editar cliente',`<form id="editCustomerForm"><div class="field"><label>Nombre</label><input name="name" value="${esc(c.name)}" required autofocus></div><div class="field"><label>Teléfono</label><input name="phone" value="${esc(c.phone||'')}"></div><div class="field"><label>Notas</label><textarea name="notes">${esc(c.notes||'')}</textarea></div><div class="field"><label>Estado</label><select name="active"><option value="true" ${c.active?'selected':''}>Activo</option><option value="false" ${!c.active?'selected':''}>Inactivo</option></select></div><div class="modal-foot" style="margin:20px -20px -20px"><button type="button" class="btn btn-secondary" data-close>Cancelar</button><button class="btn btn-primary">Guardar cambios</button></div></form>`);
      $('#editCustomerForm').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.currentTarget);const {error}=await supabase.from('tvf_customers').update({name:String(f.get('name')).trim(),phone:String(f.get('phone')||'').trim()||null,notes:String(f.get('notes')||'').trim()||null,active:f.get('active')==='true'}).eq('id',id);if(error)return alert(error.message);closeModal();await refresh();};
    }

    function renewCustomerModal(id){
      const c=state.customers.find(x=>x.id===id); const services=customerServices(id); if(!c)return;
      if(!services.length) return alert('Este cliente todavía no tiene servicios. Usá “+ Servicio” para crear uno.');
      const plus30=new Date(Date.now()+30*86400000).toISOString().slice(0,10);
      openModal('Renovar servicio',`<form id="renewCustomerForm"><div class="notice" style="margin:0 0 16px">Cliente: <b>${esc(c.name)}</b></div><div class="field"><label>Servicio</label><select name="service_id">${services.map(s=>`<option value="${s.id}">${esc(s.name)} · ${esc(s.service_type.toUpperCase())}</option>`).join('')}</select></div><div class="field"><label>Nueva fecha de vencimiento</label><input name="expires_at" type="date" value="${plus30}" required></div><div class="modal-foot" style="margin:20px -20px -20px"><button type="button" class="btn btn-secondary" data-close>Cancelar</button><button class="btn btn-primary">Renovar</button></div></form>`);
      $('#renewCustomerForm').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.currentTarget);const serviceId=String(f.get('service_id'));const expires=String(f.get('expires_at'));const {error}=await supabase.from('tvf_services').update({expires_at:new Date(expires+'T23:59:59').toISOString(),active:true}).eq('id',serviceId);if(error)return alert(error.message);closeModal();await refresh();};
    }

    function exportCustomersCsv(){
      const rows=[['Cliente','Telefono','Estado','Vencimiento','Dispositivos','Sistemas','Servicios']];
      for(const c of state.customers){const devices=customerDevices(c.id),services=customerServices(c.id),h=customerHealth(c.id);rows.push([c.name,c.phone||'',h.label,customerExpiry(h),devices.map(d=>d.device_code).join(' | '),[...new Set(devices.map(d=>platformLabel(d.platform)))].join(' | '),services.map(s=>s.name).join(' | ')]);}
      const csv=rows.map(r=>r.map(v=>'"'+String(v??'').replaceAll('"','""')+'"').join(',')).join('\n');
      const a=document.createElement('a');a.href=URL.createObjectURL(new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'}));a.download='tv-full-clientes.csv';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(a.href),1000);
    }'''
sub_once(r"    function newCustomerModal\(\).*?\n    async function createCustomer\(e\).*?\n\n    function editDeviceModal", customer_block + "\n\n    function editDeviceModal", 'customer modal block')

# Allow creating a service directly for a selected customer.
replace_once("    function newServiceModal(){ openModal('Nuevo servicio remoto',`<form id=\"serviceForm\"><div class=\"grid2\"><div class=\"field\"><label>Nombre</label><input name=\"name\" required autofocus placeholder=\"Ej: FULL TV Juan\"></div><div class=\"field\"><label>Cliente</label><select name=\"customer_id\">${customerOptions()}</select></div></div>", "    function newServiceModal(customerId=''){ openModal('Nuevo servicio remoto',`<form id=\"serviceForm\"><div class=\"grid2\"><div class=\"field\"><label>Nombre</label><input name=\"name\" required autofocus placeholder=\"Ej: FULL TV Juan\"></div><div class=\"field\"><label>Cliente</label><select name=\"customer_id\">${customerOptions(customerId)}</select></div></div>", 'newServiceModal selected customer')

# Extend delegated actions and customer filter pills.
event_anchor = """      if(action==='new-customer')newCustomerModal();\n      if(action==='edit-device')editDeviceModal(id);\n"""
event_repl = """      if(btn.dataset.customerFilter){state.customerFilter=btn.dataset.customerFilter;renderCustomers();return;}\n      if(action==='new-customer')newCustomerModal();\n      if(action==='edit-customer')editCustomerModal(id);\n      if(action==='renew-customer')renewCustomerModal(id);\n      if(action==='customer-service')newServiceModal(id);\n      if(action==='customer-devices'){state.deviceCustomerFilter=id;state.route='devices';render();}\n      if(action==='clear-device-customer'){state.deviceCustomerFilter=null;renderDevices();}\n      if(action==='export-customers')exportCustomersCsv();\n      if(action==='edit-device')editDeviceModal(id);\n"""
replace_once(event_anchor, event_repl, 'customer actions')

# The old development helpers may remain in source for rollback/testing, but are no longer exposed in the UI.
if 'Prueba del sistema' in text:
    raise SystemExit('Development test card still exposed in rendered dashboard')
if 'Gestión de clientes' not in text or 'Exportar CSV' not in text or "route:'customers'" not in text:
    raise SystemExit('V3 client management markers missing')

path.write_text(text, encoding='utf-8')
print('TV FULL panel client management V3 applied')

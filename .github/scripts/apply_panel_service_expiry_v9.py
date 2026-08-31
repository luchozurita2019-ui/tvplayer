from pathlib import Path
import re

path = Path('panel/index.html')
text = path.read_text(encoding='utf-8')

css_marker = ".expiry-expired{color:#ff9ba2;font-weight:800}.icon-action"
css_replacement = ".expiry-expired{color:#ff9ba2;font-weight:800}.service-row-soon{background:rgba(255,110,120,.075)}.service-row-expired{background:rgba(255,110,120,.14);box-shadow:inset 4px 0 0 var(--red)}.service-row-soon:hover,.service-row-expired:hover{background:rgba(255,110,120,.17)!important}.service-expiry{font-weight:900;white-space:nowrap}.service-expiry.soon,.service-expiry.expired{color:#ff9ba2}.service-expiry small{display:block;margin-top:3px;font-size:9px;color:var(--muted);font-weight:700}.service-expiry.expired small{color:#ff9ba2}.icon-action"
if ".service-row-soon{" not in text:
    if css_marker not in text:
        raise SystemExit('service expiry CSS marker not found')
    text = text.replace(css_marker, css_replacement, 1)

helper_marker = "    const customerExpiryClass = h => h.key==='soon'?'expiry-soon':(h.key==='expired'?'expiry-expired':'');\n"
helper_code = """    const customerExpiryClass = h => h.key==='soon'?'expiry-soon':(h.key==='expired'?'expiry-expired':'');
    function providerExpiry(result){
      const raw=result?.expires_at||result?.details?.expires_at||null;
      if(!raw)return null;
      const d=new Date(raw);
      return Number.isNaN(d.getTime())?null:d.toISOString();
    }
    function serviceExpiryInfo(service){
      if(!service?.expires_at)return {key:'none',date:null,days:null,label:'Sin vencimiento'};
      const d=new Date(service.expires_at);
      if(Number.isNaN(d.getTime()))return {key:'none',date:null,days:null,label:'Sin vencimiento'};
      const diff=d.getTime()-Date.now();
      const days=Math.ceil(diff/86400000);
      if(diff<0)return {key:'expired',date:d,days,label:'VENCIDA'};
      if(days<=7)return {key:'soon',date:d,days,label:days<=1?'VENCE HOY':`VENCE EN ${days} DÍAS`};
      return {key:'active',date:d,days,label:'ACTIVA'};
    }
    const serviceExpiryRowClass = info => info.key==='expired'?'service-row-expired':(info.key==='soon'?'service-row-soon':'');
    const serviceExpiryCell = info => {
      if(!info.date)return '<span class=\"muted\">Sin vencimiento</span>';
      const cls=info.key==='expired'?'expired':(info.key==='soon'?'soon':'');
      const headline=(info.key==='expired'||info.key==='soon')?info.label:dateOnly(info.date.toISOString());
      const detail=(info.key==='expired'||info.key==='soon')?dateOnly(info.date.toISOString()):'';
      return `<div class=\"service-expiry ${cls}\">${esc(headline)}${detail?`<small>${esc(detail)}</small>`:''}</div>`;
    };
"""
if "function serviceExpiryInfo(service)" not in text:
    if helper_marker not in text:
        raise SystemExit('service expiry helper marker not found')
    text = text.replace(helper_marker, helper_code, 1)

services_pattern = re.compile(r"    function renderServices\(\)\{.*?\n    function renderAssignments\(\)\{", re.S)
services_replacement = """    function renderServices(){
      $('#content').innerHTML=`<div class=\"toolbar\"><div><h2>Servicios</h2><div class=\"muted\">El panel muestra el vencimiento informado por el proveedor cuando está disponible. Las listas que vencen dentro de 7 días o ya vencieron se resaltan en rojo.</div></div><button class=\"btn btn-primary\" data-action=\"new-service\">+ Nuevo servicio</button></div>
      ${state.services.length?`<div class=\"table-wrap\"><table><thead><tr><th>Servicio</th><th>Tipo</th><th>Cliente</th><th>Servidor / URL</th><th>Credencial</th><th>Vence</th><th>Conexión</th><th>Habilitado</th><th></th></tr></thead><tbody>${state.services.map(s=>{const expiry=serviceExpiryInfo(s);return `<tr class=\"${serviceExpiryRowClass(expiry)}\"><td><b>${esc(s.name)}</b>${s.validated_at?`<div class=\"customer-meta\">Validado: ${dt(s.validated_at)}</div>`:''}</td><td><span class=\"badge\">${esc(s.service_type.toUpperCase())}</span></td><td>${esc(customerName(s.customer_id))}</td><td class=\"code\">${esc(s.service_type==='m3u'?(s.m3u_url||''):(s.server_url||''))}</td><td>${s.service_type==='xtream'?`${esc(s.username||'')} · ••••••`:'—'}</td><td>${serviceExpiryCell(expiry)}</td><td>${validationBadge(s)}</td><td>${statusBadge(s.active)}</td><td><div class=\"actions\"><button class=\"btn btn-secondary btn-small\" data-action=\"validate-service\" data-id=\"${s.id}\">Validar</button><button class=\"btn btn-secondary btn-small\" data-action=\"toggle-service\" data-id=\"${s.id}\">${s.active?'Desactivar':'Activar'}</button><button class=\"btn btn-danger btn-small\" data-action=\"delete-service\" data-id=\"${s.id}\">Borrar</button></div></td></tr>`;}).join('')}</tbody></table></div>`:'<div class=\"empty\">No hay servicios todavía.</div>'}`;
    }

    function renderAssignments(){"""
if "Las listas que vencen dentro de 7 días" not in text:
    text, n = services_pattern.subn(services_replacement, text, count=1)
    if n != 1:
        raise SystemExit('renderServices block not found')

modal_pattern = re.compile(r"    function newServiceModal\(customerId=''\)\{.*?\n    async function createService\(e\)\{", re.S)
modal_replacement = """    function newServiceModal(customerId=''){ openModal('Nuevo servicio remoto',`<form id=\"serviceForm\"><div class=\"grid2\"><div class=\"field\"><label>Nombre</label><input name=\"name\" required autofocus placeholder=\"Ej: FULL TV Juan\"></div><div class=\"field\"><label>Cliente</label><select name=\"customer_id\">${customerOptions(customerId)}</select></div></div><div class=\"grid2\"><div class=\"field\"><label>Tipo</label><select id=\"serviceType\" name=\"service_type\"><option value=\"m3u\">M3U</option><option value=\"xtream\">Xtream</option></select></div><div class=\"field\"><label>Vencimiento</label><input name=\"expires_at\" type=\"date\"><div class=\"customer-meta\">Podés dejarlo vacío: si el proveedor informa la fecha, se completa automáticamente.</div></div></div><div id=\"m3uFields\"><div class=\"field\"><label>URL M3U</label><input name=\"m3u_url\" placeholder=\"http://servidor/get.php?username=...\"></div></div><div id=\"xtreamFields\" class=\"hidden\"><div class=\"field\"><label>Servidor / Host</label><input name=\"server_url\" placeholder=\"http://servidor:puerto\"></div><div class=\"grid2\"><div class=\"field\"><label>Usuario</label><input name=\"username\"></div><div class=\"field\"><label>Contraseña</label><input name=\"password\" type=\"password\"></div></div></div><div class=\"notice\" style=\"margin:4px 0 0\">En Xtream, y en enlaces M3U que incluyan usuario y contraseña, TV FULL intentará leer automáticamente la fecha de vencimiento publicada por el proveedor.</div><div class=\"modal-foot\" style=\"margin:20px -20px -20px\"><button type=\"button\" class=\"btn btn-secondary\" data-close>Cancelar</button><button class=\"btn btn-primary\">Validar y guardar</button></div></form>`); const t=$('#serviceType'); t.onchange=()=>{$('#m3uFields').classList.toggle('hidden',t.value!=='m3u');$('#xtreamFields').classList.toggle('hidden',t.value!=='xtream');}; $('#serviceForm').onsubmit=createService; }
    async function createService(e){"""
if "se completa automáticamente" not in text:
    text, n = modal_pattern.subn(modal_replacement, text, count=1)
    if n != 1:
        raise SystemExit('newServiceModal block not found')

create_pattern = re.compile(r"    async function createService\(e\)\{.*?\n    function assignmentModal\(\)\{", re.S)
create_replacement = """    async function createService(e){
      e.preventDefault();
      const form=e.currentTarget,submit=form.querySelector('button[type=\"submit\"],button:not([type])');
      const f=new FormData(form),type=String(f.get('service_type')),expires=String(f.get('expires_at')||'');
      const row={name:String(f.get('name')).trim(),customer_id:String(f.get('customer_id')||'')||null,service_type:type,expires_at:expires?new Date(expires+'T23:59:59').toISOString():null,active:false,server_url:null,username:null,password:null,m3u_url:null};
      if(type==='m3u'){
        row.m3u_url=String(f.get('m3u_url')||'').trim();
        if(!row.m3u_url)return alert('Ingresá la URL M3U.');
      }else{
        row.server_url=String(f.get('server_url')||'').trim();row.username=String(f.get('username')||'').trim();row.password=String(f.get('password')||'');
        if(!row.server_url||!row.username||!row.password)return alert('Completá servidor, usuario y contraseña.');
      }
      if(submit){submit.disabled=true;submit.textContent='Validando…';}
      const result=await runServiceValidation({service_type:row.service_type,m3u_url:row.m3u_url,server_url:row.server_url,username:row.username,password:row.password});
      if(!result.ok){
        if(submit){submit.disabled=false;submit.textContent='Validar y guardar';}
        return alert(`No se guardó el servicio porque la fuente no pudo validarse.\n\n${result.message}`);
      }
      const detectedExpiry=providerExpiry(result);
      const autoApplied=!row.expires_at&&!!detectedExpiry;
      if(autoApplied)row.expires_at=detectedExpiry;
      Object.assign(row,validationFields(result),{active:true});
      const {error}=await supabase.from('tvf_services').insert(row);
      if(error){if(submit){submit.disabled=false;submit.textContent='Validar y guardar';}return alert(error.message);}
      closeModal();await refresh();
      if(autoApplied)alert(`Servicio guardado.\n\nEl proveedor informa vencimiento: ${dateOnly(detectedExpiry)}`);
    }

    function assignmentModal(){"""
if "const autoApplied=!row.expires_at&&!!detectedExpiry;" not in text:
    text, n = create_pattern.subn(create_replacement, text, count=1)
    if n != 1:
        raise SystemExit('createService block not found')

old_validate = """      const result=await runServiceValidation({service_id:id});
      const update={...validationFields(result)};
      if(!result.ok) update.active=false;
"""
new_validate = """      const result=await runServiceValidation({service_id:id});
      const detectedExpiry=providerExpiry(result);
      const update={...validationFields(result)};
      if(!service.expires_at&&detectedExpiry) update.expires_at=detectedExpiry;
      if(!result.ok) update.active=false;
"""
if "if(!service.expires_at&&detectedExpiry) update.expires_at=detectedExpiry;" not in text:
    if old_validate not in text:
        raise SystemExit('validateExistingService update marker not found')
    text = text.replace(old_validate, new_validate, 1)

old_toggle = """      const result=await runServiceValidation({service_id:id});
      const update={...validationFields(result),active:!!result.ok};
      const {error}=await supabase.from('tvf_services').update(update).eq('id',id);
"""
new_toggle = """      const result=await runServiceValidation({service_id:id});
      const detectedExpiry=providerExpiry(result);
      const update={...validationFields(result),active:!!result.ok};
      if(!s.expires_at&&detectedExpiry) update.expires_at=detectedExpiry;
      const {error}=await supabase.from('tvf_services').update(update).eq('id',id);
"""
if "if(!s.expires_at&&detectedExpiry) update.expires_at=detectedExpiry;" not in text:
    if old_toggle not in text:
        raise SystemExit('toggleService expiry marker not found')
    text = text.replace(old_toggle, new_toggle, 1)

path.write_text(text, encoding='utf-8')

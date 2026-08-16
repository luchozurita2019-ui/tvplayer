from pathlib import Path
import re

path = Path('panel/index.html')
text = path.read_text(encoding='utf-8')
original = text


def replace_once(old: str, new: str, label: str):
    global text
    if new in text:
        return
    if old not in text:
        raise SystemExit(f'Patch marker not found: {label}')
    text = text.replace(old, new, 1)


replace_once(
    "    const statusBadge = active => `<span class=\"badge ${active?'on':'off'}\">${active?'ACTIVO':'INACTIVO'}</span>`;\n",
    "    const statusBadge = active => `<span class=\"badge ${active?'on':'off'}\">${active?'ACTIVO':'INACTIVO'}</span>`;\n"
    "    const validationBadge = service => { const status=service.validation_status||'unknown'; const title=esc(service.validation_message||'Sin validar'); if(status==='online') return `<span class=\"badge on\" title=\"${title}\">ONLINE</span>${service.validation_latency_ms!=null?`<div class=\"customer-meta\">${Number(service.validation_latency_ms)} ms</div>`:''}`; if(status==='error') return `<span class=\"badge off\" title=\"${title}\">ERROR</span>`; return `<span class=\"badge neutral\" title=\"${title}\">SIN VALIDAR</span>`; };\n",
    'validation badge',
)

replace_once(
    "        supabase.from('tvf_services').select('id,name,service_type,server_url,username,password,m3u_url,active,expires_at,customer_id,created_at').order('created_at',{ascending:false}),",
    "        supabase.from('tvf_services').select('id,name,service_type,server_url,username,password,m3u_url,active,expires_at,customer_id,created_at,validation_status,validated_at,validation_message,validation_latency_ms').order('created_at',{ascending:false}),",
    'service validation columns',
)

render_pattern = re.compile(r"    function renderServices\(\)\{.*?\n    \}\n\n    function renderAssignments\(\)\{", re.S)
render_replacement = '''    function renderServices(){
      $('#content').innerHTML=`<div class="toolbar"><div><h2>Servicios</h2><div class="muted">Las listas se validan antes de habilitarse. “Habilitado” indica permiso administrativo; “Conexión” confirma si la fuente respondió correctamente.</div></div><button class="btn btn-primary" data-action="new-service">+ Nuevo servicio</button></div>
      ${state.services.length?`<div class="table-wrap"><table><thead><tr><th>Servicio</th><th>Tipo</th><th>Cliente</th><th>Servidor / URL</th><th>Credencial</th><th>Vence</th><th>Conexión</th><th>Habilitado</th><th></th></tr></thead><tbody>${state.services.map(s=>`<tr><td><b>${esc(s.name)}</b>${s.validated_at?`<div class="customer-meta">Validado: ${dt(s.validated_at)}</div>`:''}</td><td><span class="badge">${esc(s.service_type.toUpperCase())}</span></td><td>${esc(customerName(s.customer_id))}</td><td class="code">${esc(s.service_type==='m3u'?(s.m3u_url||''):(s.server_url||''))}</td><td>${s.service_type==='xtream'?`${esc(s.username||'')} · ••••••`:'—'}</td><td>${esc(dateOnly(s.expires_at))}</td><td>${validationBadge(s)}</td><td>${statusBadge(s.active)}</td><td><div class="actions"><button class="btn btn-secondary btn-small" data-action="validate-service" data-id="${s.id}">Validar</button><button class="btn btn-secondary btn-small" data-action="toggle-service" data-id="${s.id}">${s.active?'Desactivar':'Activar'}</button><button class="btn btn-danger btn-small" data-action="delete-service" data-id="${s.id}">Borrar</button></div></td></tr>`).join('')}</tbody></table></div>`:'<div class="empty">No hay servicios todavía.</div>'}`;
    }

    function renderAssignments(){'''
if 'Las listas se validan antes de habilitarse.' not in text:
    text, count = render_pattern.subn(render_replacement, text, count=1)
    if count != 1:
        raise SystemExit('Patch marker not found: renderServices')

replace_once(
    "    function serviceOptions(){ return state.services.filter(s=>s.active).map(s=>`<option value=\"${s.id}\">${esc(s.name)} · ${esc(s.service_type.toUpperCase())}</option>`).join(''); }",
    "    function serviceOptions(){ return state.services.filter(s=>s.active&&s.validation_status!=='error').map(s=>`<option value=\"${s.id}\">${esc(s.name)} · ${esc(s.service_type.toUpperCase())}</option>`).join(''); }",
    'assignment service filtering',
)

helpers_marker = "    function newServiceModal(customerId=''){"
helpers = '''    async function runServiceValidation(payload){
      const {data,error}=await supabase.functions.invoke('tvf-service-validate',{body:payload});
      if(error) return {ok:false,status:'error',message:error.message||'No se pudo ejecutar la validación.',checked_at:new Date().toISOString()};
      return data||{ok:false,status:'error',message:'El validador no devolvió una respuesta.',checked_at:new Date().toISOString()};
    }

    function validationFields(result){
      const latency=Number(result?.latency_ms);
      return {
        validation_status:result?.ok?'online':'error',
        validated_at:result?.checked_at||new Date().toISOString(),
        validation_message:String(result?.message|| (result?.ok?'Validación correcta.':'La fuente no respondió correctamente.')).slice(0,500),
        validation_latency_ms:Number.isFinite(latency)?Math.round(latency):null,
      };
    }

    async function validateExistingService(id,{showMessage=true,refreshAfter=true}={}){
      const service=state.services.find(x=>x.id===id);
      if(!service) return {ok:false,status:'error',message:'Servicio no encontrado.'};
      const result=await runServiceValidation({service_id:id});
      const update={...validationFields(result)};
      if(!result.ok) update.active=false;
      const {error}=await supabase.from('tvf_services').update(update).eq('id',id);
      if(error){ if(showMessage) alert(error.message); return {ok:false,status:'error',message:error.message}; }
      if(showMessage) alert(result.ok?`✓ ${result.message}`:`✕ ${result.message}\n\nEl servicio quedó INACTIVO para que no se entregue a los dispositivos.`);
      if(refreshAfter) await refresh();
      return result;
    }

'''
if 'async function runServiceValidation(payload)' not in text:
    if helpers_marker not in text:
        raise SystemExit('Patch marker not found: validation helpers')
    text = text.replace(helpers_marker, helpers + helpers_marker, 1)

text = text.replace('>Guardar servicio</button></div></form>`); const t=', '>Validar y guardar</button></div></form>`); const t=', 1)

create_pattern = re.compile(r"    async function createService\(e\)\{.*?\}\n\n    function assignmentModal", re.S)
create_replacement = '''    async function createService(e){
      e.preventDefault();
      const form=e.currentTarget,submit=form.querySelector('button[type="submit"],button:not([type])');
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
      Object.assign(row,validationFields(result),{active:true});
      const {error}=await supabase.from('tvf_services').insert(row);
      if(error){if(submit){submit.disabled=false;submit.textContent='Validar y guardar';}return alert(error.message);}
      closeModal();await refresh();
    }

    function assignmentModal'''
if 'No se guardó el servicio porque la fuente no pudo validarse.' not in text:
    text, count = create_pattern.subn(create_replacement, text, count=1)
    if count != 1:
        raise SystemExit('Patch marker not found: createService')

renew_old = "$('#renewCustomerForm').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.currentTarget);const serviceId=String(f.get('service_id'));const expires=String(f.get('expires_at'));const {error}=await supabase.from('tvf_services').update({expires_at:new Date(expires+'T23:59:59').toISOString(),active:true}).eq('id',serviceId);if(error)return alert(error.message);closeModal();await refresh();};"
renew_new = "$('#renewCustomerForm').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.currentTarget);const serviceId=String(f.get('service_id'));const expires=String(f.get('expires_at'));const result=await runServiceValidation({service_id:serviceId});const update={expires_at:new Date(expires+'T23:59:59').toISOString(),active:!!result.ok,...validationFields(result)};const {error}=await supabase.from('tvf_services').update(update).eq('id',serviceId);if(error)return alert(error.message);closeModal();await refresh();if(!result.ok)alert(`La fecha se renovó, pero el servicio quedó INACTIVO porque no superó la validación.\\n\\n${result.message}`);};"
replace_once(renew_old, renew_new, 'renew validation')

toggle_pattern = re.compile(r"    async function toggleService\(id\)\{.*?\}\n", re.S)
toggle_replacement = '''    async function toggleService(id){
      const s=state.services.find(x=>x.id===id);if(!s)return;
      if(s.active){
        const {error}=await supabase.from('tvf_services').update({active:false}).eq('id',id);
        if(error)return alert(error.message);await refresh();return;
      }
      const result=await runServiceValidation({service_id:id});
      const update={...validationFields(result),active:!!result.ok};
      const {error}=await supabase.from('tvf_services').update(update).eq('id',id);
      if(error)return alert(error.message);
      if(!result.ok)alert(`No se pudo activar el servicio.\\n\\n${result.message}`);
      await refresh();
    }
'''
if 'No se pudo activar el servicio.' not in text:
    text, count = toggle_pattern.subn(toggle_replacement, text, count=1)
    if count != 1:
        raise SystemExit('Patch marker not found: toggleService')

replace_once(
    "      if(action==='toggle-service')await toggleService(id);",
    "      if(action==='validate-service')await validateExistingService(id);\n      if(action==='toggle-service')await toggleService(id);",
    'validate service click',
)

if text == original:
    print('Panel already patched')
else:
    path.write_text(text, encoding='utf-8')
    print('Panel service validation patch applied')

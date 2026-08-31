from pathlib import Path
import re

path = Path('panel/index.html')
text = path.read_text(encoding='utf-8')

# Remote validation is advisory only. A slow or unreachable provider must never
# prevent an administrator from saving, enabling, renewing, or assigning a service.
text = text.replace(
    'Las listas se validan antes de habilitarse. “Habilitado” indica permiso administrativo; “Conexión” confirma si la fuente respondió correctamente.',
    'La validación remota es informativa. “Habilitado” lo controla el administrador y “Conexión” muestra si Supabase pudo comprobar la fuente.',
)
text = text.replace(
    'El panel muestra el vencimiento informado por el proveedor cuando está disponible. Las listas que vencen dentro de 7 días o ya vencieron se resaltan en rojo.',
    'El panel muestra el vencimiento informado por el proveedor cuando está disponible. La validación remota es informativa y nunca bloquea el guardado. Las listas que vencen dentro de 7 días o ya vencieron se resaltan en rojo.',
)
text = text.replace('>Validar y guardar</button>', '>Guardar servicio</button>')
text = text.replace("function serviceOptions(){ return state.services.filter(s=>s.active&&s.validation_status!=='error')", "function serviceOptions(){ return state.services.filter(s=>s.active)")

validation_pattern = re.compile(r"    function validationFields\(result\)\{.*?\n    \}\n\n    async function validateExistingService", re.S)
validation_replacement = '''    function validationFields(result){
      const latency=Number(result?.latency_ms);
      const message=String(result?.message|| (result?.ok?'Validación correcta.':'No se pudo verificar remotamente.')).slice(0,500);
      const definitive=!result?.ok&&/(credenciales|no está activa|banned|disabled|expired|http 401|http 403|falta la url|faltan servidor|tipo de servicio no compatible)/i.test(message);
      return {
        validation_status:result?.ok?'online':(definitive?'error':'unknown'),
        validated_at:result?.checked_at||new Date().toISOString(),
        validation_message:message,
        validation_latency_ms:Number.isFinite(latency)?Math.round(latency):null,
      };
    }

    async function validateExistingService'''
text, count = validation_pattern.subn(validation_replacement, text, count=1)
if count != 1:
    raise SystemExit('Nonblocking validation marker not found: validationFields')

existing_pattern = re.compile(r"    async function validateExistingService\(id,\{showMessage=true,refreshAfter=true\}=\{\}\)\{.*?\n    \}\n\n    function newServiceModal", re.S)
existing_replacement = '''    async function validateExistingService(id,{showMessage=true,refreshAfter=true}={}){
      const service=state.services.find(x=>x.id===id);
      if(!service) return {ok:false,status:'error',message:'Servicio no encontrado.'};
      const result=await runServiceValidation({service_id:id});
      const detectedExpiry=providerExpiry(result);
      const update={...validationFields(result)};
      if(!service.expires_at&&detectedExpiry) update.expires_at=detectedExpiry;
      const {error}=await supabase.from('tvf_services').update(update).eq('id',id);
      if(error){ if(showMessage) alert(error.message); return {ok:false,status:'error',message:error.message}; }
      if(showMessage){
        if(result.ok) alert(`✓ ${result.message}`);
        else alert(`No se pudo verificar remotamente.\n\n${result.message}\n\nEl servicio permanece ${service.active?'ACTIVO':'INACTIVO'}.`);
      }
      if(refreshAfter) await refresh();
      return result;
    }

    function newServiceModal'''
text, count = existing_pattern.subn(existing_replacement, text, count=1)
if count != 1:
    raise SystemExit('Nonblocking validation marker not found: validateExistingService')

create_pattern = re.compile(r"    async function createService\(e\)\{.*?\n    function assignmentModal\(\)\{", re.S)
create_replacement = '''    async function createService(e){
      e.preventDefault();
      const form=e.currentTarget,submit=form.querySelector('button[type="submit"],button:not([type])');
      const f=new FormData(form),type=String(f.get('service_type')),expires=String(f.get('expires_at')||'');
      const row={name:String(f.get('name')).trim(),customer_id:String(f.get('customer_id')||'')||null,service_type:type,expires_at:expires?new Date(expires+'T23:59:59').toISOString():null,active:true,server_url:null,username:null,password:null,m3u_url:null};
      if(type==='m3u'){
        row.m3u_url=String(f.get('m3u_url')||'').trim();
        if(!row.m3u_url)return alert('Ingresá la URL M3U.');
        try{const u=new URL(row.m3u_url);if(!['http:','https:'].includes(u.protocol))throw new Error();}catch(_){return alert('La URL M3U debe ser una dirección http o https válida.');}
      }else{
        row.server_url=String(f.get('server_url')||'').trim();row.username=String(f.get('username')||'').trim();row.password=String(f.get('password')||'');
        if(!row.server_url||!row.username||!row.password)return alert('Completá servidor, usuario y contraseña.');
        try{const u=new URL(row.server_url);if(!['http:','https:'].includes(u.protocol))throw new Error();}catch(_){return alert('El servidor Xtream debe ser una dirección http o https válida.');}
      }
      if(submit){submit.disabled=true;submit.textContent='Guardando…';}
      const {data:created,error}=await supabase.from('tvf_services').insert(row).select('id').single();
      if(error){if(submit){submit.disabled=false;submit.textContent='Guardar servicio';}return alert(error.message);}
      closeModal();
      await refresh();
      if(created?.id) validateExistingService(created.id,{showMessage:false,refreshAfter:true});
    }

    function assignmentModal(){'''
text, count = create_pattern.subn(create_replacement, text, count=1)
if count != 1:
    raise SystemExit('Nonblocking validation marker not found: createService')

renew_pattern = re.compile(r"\$\('#renewCustomerForm'\)\.onsubmit=async e=>\{.*?\};", re.S)
renew_replacement = "$('#renewCustomerForm').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.currentTarget);const serviceId=String(f.get('service_id'));const expires=String(f.get('expires_at'));const {error}=await supabase.from('tvf_services').update({expires_at:new Date(expires+'T23:59:59').toISOString(),active:true}).eq('id',serviceId);if(error)return alert(error.message);closeModal();await refresh();validateExistingService(serviceId,{showMessage:false,refreshAfter:true});};"
text, count = renew_pattern.subn(renew_replacement, text, count=1)
if count != 1:
    raise SystemExit('Nonblocking validation marker not found: renewCustomerForm')

toggle_pattern = re.compile(r"    async function toggleService\(id\)\{.*?\n    \}\n", re.S)
toggle_replacement = '''    async function toggleService(id){
      const s=state.services.find(x=>x.id===id);if(!s)return;
      const next=!s.active;
      const {error}=await supabase.from('tvf_services').update({active:next}).eq('id',id);
      if(error)return alert(error.message);
      await refresh();
      if(next) validateExistingService(id,{showMessage:false,refreshAfter:true});
    }
'''
text, count = toggle_pattern.subn(toggle_replacement, text, count=1)
if count != 1:
    raise SystemExit('Nonblocking validation marker not found: toggleService')

# Guard against the old blocking behavior coming back through another patch.
for forbidden in [
    'No se guardó el servicio porque la fuente no pudo validarse.',
    'El servicio quedó INACTIVO para que no se entregue a los dispositivos.',
    'No se pudo activar el servicio.',
    'La fecha se renovó, pero el servicio quedó INACTIVO',
]:
    if forbidden in text:
        raise SystemExit(f'Blocking validation behavior still present: {forbidden}')

required = [
    '>Guardar servicio</button>',
    "validation_status:result?.ok?'online':(definitive?'error':'unknown')",
    "const row={name:String(f.get('name')).trim()",
    "active:true,server_url:null",
    "validateExistingService(created.id,{showMessage:false,refreshAfter:true})",
    "function serviceOptions(){ return state.services.filter(s=>s.active)",
]
for marker in required:
    if marker not in text:
        raise SystemExit(f'Nonblocking validation guard failed: {marker}')

path.write_text(text, encoding='utf-8')
print('Nonblocking service validation applied')

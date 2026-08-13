from pathlib import Path

path = Path('panel/index.html')
text = path.read_text(encoding='utf-8')

repls = [
("const { data,error }=await supabase.auth.signUp({email,password});",
 "const { data,error }=await supabase.auth.signUp({email,password,options:{emailRedirectTo:'https://luchozurita2019-ui.github.io/tvplayer/'}});") ,
("<button class=\"btn btn-secondary btn-small\" data-action=\"edit-device\" data-id=\"${d.id}\">Editar</button></div>",
 "<button class=\"btn btn-secondary btn-small\" data-action=\"edit-device\" data-id=\"${d.id}\">Editar</button><button class=\"btn btn-danger btn-small\" data-action=\"delete-device\" data-id=\"${d.id}\">Borrar</button></div>"),
("<td><button class=\"btn btn-secondary btn-small\" data-action=\"toggle-service\" data-id=\"${s.id}\">${s.active?'Desactivar':'Activar'}</button></td>",
 "<td><div class=\"actions\"><button class=\"btn btn-secondary btn-small\" data-action=\"toggle-service\" data-id=\"${s.id}\">${s.active?'Desactivar':'Activar'}</button><button class=\"btn btn-danger btn-small\" data-action=\"delete-service\" data-id=\"${s.id}\">Borrar</button></div></td>"),
("function deviceOptions(){ return state.devices.filter(d=>d.active).map(d=>`<option value=\"${d.id}\">${esc(d.device_name||d.device_code)} · ${esc(platformLabel(d.platform))}</option>`).join(''); }",
 "function deviceOptions(){ return state.devices.filter(d=>d.active).map(d=>`<option value=\"${d.id}\">${esc(d.device_name||d.device_code)} · ${esc(platformLabel(d.platform))} · ${esc(d.device_code)}</option>`).join(''); }"),
("async function deleteAssignment(id){if(!confirm('¿Quitar este servicio del dispositivo?'))return;const {error}=await supabase.from('tvf_device_services').delete().eq('id',id);if(error)return alert(error.message);await refresh();}",
 "async function deleteAssignment(id){if(!confirm('¿Quitar este servicio del dispositivo?'))return;const {error}=await supabase.from('tvf_device_services').delete().eq('id',id);if(error)return alert(error.message);await refresh();}\n    async function deleteDevice(id){const d=state.devices.find(x=>x.id===id);if(!d)return;if(!confirm(`¿Borrar el dispositivo ${d.device_code}? Sus asignaciones también se eliminarán.`))return;const {error}=await supabase.from('tvf_devices').delete().eq('id',id);if(error)return alert(error.message);await refresh();}\n    async function deleteService(id){const s=state.services.find(x=>x.id===id);if(!s)return;if(!confirm(`¿Borrar el servicio ${s.name}? Se quitará de todos los dispositivos asignados.`))return;const {error}=await supabase.from('tvf_services').delete().eq('id',id);if(error)return alert(error.message);await refresh();}"),
("closeModal();await refresh();showResult('Configuración recibida por TV FULL',data);",
 "closeModal();await refresh();const safe=JSON.parse(JSON.stringify(data||{}));if(Array.isArray(safe.services)){safe.services=safe.services.map(s=>{const c={...s};if(c.url){try{const u=new URL(c.url);if(u.searchParams.has('username'))u.searchParams.set('username','***');if(u.searchParams.has('password'))u.searchParams.set('password','***');c.url=u.toString();}catch(_){c.url='URL protegida';}}if(c.username)c.username='***';if(c.password)c.password='***';return c;});}showResult('Configuración recibida por TV FULL',safe);"),
("if(action==='edit-device')editDeviceModal(id);",
 "if(action==='edit-device')editDeviceModal(id);\n      if(action==='delete-device')await deleteDevice(id);"),
("if(action==='toggle-service')await toggleService(id);",
 "if(action==='toggle-service')await toggleService(id);\n      if(action==='delete-service')await deleteService(id);")
]

for old, new in repls:
    if old not in text:
        raise SystemExit(f'Missing expected snippet: {old[:120]}')
    text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
print('Panel cleanup V2 patch applied')

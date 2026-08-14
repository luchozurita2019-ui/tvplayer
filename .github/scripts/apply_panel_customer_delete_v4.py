from pathlib import Path

path = Path('panel/index.html')
text = path.read_text(encoding='utf-8')

old_actions = '''<button class="btn btn-secondary btn-small icon-action" title="Editar cliente" data-action="edit-customer" data-id="${c.id}">✎</button><button class="btn btn-primary btn-small" data-action="renew-customer" data-id="${c.id}">Renovar</button><button class="btn btn-secondary btn-small" data-action="customer-service" data-id="${c.id}">+ Servicio</button><button class="btn btn-secondary btn-small icon-action" title="Ver dispositivos" data-action="customer-devices" data-id="${c.id}">⚙</button>'''
new_actions = old_actions + '''<button class="btn btn-danger btn-small icon-action" title="Borrar cliente" data-action="delete-customer" data-id="${c.id}">🗑</button>'''

if 'data-action="delete-customer"' not in text:
    if old_actions not in text:
        raise SystemExit('Customer action anchor not found')
    text = text.replace(old_actions, new_actions, 1)

anchor = "    async function toggleService(id){const s=state.services.find(x=>x.id===id);if(!s)return;const {error}=await supabase.from('tvf_services').update({active:!s.active}).eq('id',id);if(error)return alert(error.message);await refresh();}\n"
delete_fn = '''    async function deleteCustomer(id){
      const c=state.customers.find(x=>x.id===id); if(!c)return;
      const devices=customerDevices(id).length;
      const services=customerServices(id).length;
      const detail=[];
      if(devices) detail.push(`${devices} dispositivo(s)`);
      if(services) detail.push(`${services} servicio(s)`);
      const linked=detail.length?`\\n\\n${detail.join(' y ')} quedarán sin cliente, pero NO se borrarán.`:'';
      if(!confirm(`¿Borrar al cliente “${c.name}”?${linked}`))return;
      const {error}=await supabase.from('tvf_customers').delete().eq('id',id);
      if(error)return alert(`No se pudo borrar el cliente: ${error.message}`);
      await refresh();
    }

'''
if 'async function deleteCustomer(id)' not in text:
    if anchor not in text:
        raise SystemExit('Delete function anchor not found')
    text = text.replace(anchor, delete_fn + anchor, 1)

event_anchor = "      if(action==='export-customers')exportCustomersCsv();\n      if(action==='edit-device')editDeviceModal(id);\n"
event_repl = "      if(action==='export-customers')exportCustomersCsv();\n      if(action==='delete-customer')await deleteCustomer(id);\n      if(action==='edit-device')editDeviceModal(id);\n"
if "if(action==='delete-customer')" not in text:
    if event_anchor not in text:
        raise SystemExit('Delete event anchor not found')
    text = text.replace(event_anchor, event_repl, 1)

required = [
    'data-action="delete-customer"',
    'async function deleteCustomer(id)',
    "if(action==='delete-customer')await deleteCustomer(id);",
]
for marker in required:
    if marker not in text:
        raise SystemExit(f'Missing marker: {marker}')

path.write_text(text, encoding='utf-8')
print('Customer delete enabled safely')

from pathlib import Path

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
    "supabase.from('tvf_devices').select('id,device_code,device_name,platform,app_version,active,last_seen_at,customer_id,created_at')",
    "supabase.from('tvf_devices').select('id,device_code,device_name,platform,app_version,active,access_status,last_seen_at,customer_id,created_at')",
    'device access_status select',
)

status_anchor = "    const statusBadge = active => `<span class=\"badge ${active?'on':'off'}\">${active?'ACTIVO':'INACTIVO'}</span>`;\n"
device_badge = "    const deviceStatusBadge = d => (!d?.active && d?.access_status==='payment_due') ? `<span class=\"badge warn\">FALTA DE PAGO</span>` : statusBadge(!!d?.active);\n"
if 'const deviceStatusBadge = d =>' not in text:
    if status_anchor not in text:
        raise SystemExit('Patch marker not found: status badge')
    text = text.replace(status_anchor, status_anchor + device_badge, 1)

if 'statusBadge(d.active)' in text:
    text = text.replace('statusBadge(d.active)', 'deviceStatusBadge(d)')

replace_once(
    '<div class="field"><label>Estado</label><select name="active"><option value="true" ${d.active?\'selected\':\'\'}>Activo</option><option value="false" ${!d.active?\'selected\':\'\'}>Inactivo</option></select></div>',
    '<div class="field"><label>Estado de acceso</label><select name="access_state"><option value="active" ${d.active?\'selected\':\'\'}>Activo</option><option value="payment_due" ${!d.active&&d.access_status===\'payment_due\'?\'selected\':\'\'}>Falta de pago</option><option value="inactive" ${!d.active&&d.access_status!==\'payment_due\'?\'selected\':\'\'}>Inactivo</option></select></div>',
    'device access status selector',
)

replace_once(
    "customer_id:String(f.get('customer_id')||'')||null,active:f.get('active')==='true'",
    "customer_id:String(f.get('customer_id')||'')||null,active:f.get('access_state')==='active',access_status:f.get('access_state')==='payment_due'?'payment_due':'active'",
    'device access status update',
)

if text == original:
    print('Panel payment status already patched')
else:
    path.write_text(text, encoding='utf-8')
    print('Panel payment status patch applied')

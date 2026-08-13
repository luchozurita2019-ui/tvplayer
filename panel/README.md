# TV FULL PRO · Panel remoto V1

Panel web para administrar clientes, dispositivos y servicios remotos de TV FULL PRO.

## Backend

Supabase project: `ghsoudpjlnjmhiragkrm`

Panel publicado temporalmente mediante Edge Function:

`https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1/tvf-panel`

La Edge Function sirve `panel/index.html` directamente desde esta rama de GitHub, de modo que el repositorio sigue siendo la fuente del panel.

## Seguridad

- El navegador usa solamente una Supabase publishable key.
- La service-role key permanece únicamente del lado servidor.
- `tvf_devices`, `tvf_services`, `tvf_device_services` y `tvf_customers` tienen RLS y requieren una cuenta administradora autorizada.
- La primera cuenta autenticada puede reclamar el rol `owner` mediante `tvf-admin-bootstrap` solamente mientras `tvf_admins` esté vacío.
- `tvf-device-config` exige `device_code` + `device_secret`; el secreto solo se guarda como SHA-256 en la base.

## Flujo V1

1. Crear/confirmar la primera cuenta del panel.
2. Crear un cliente.
3. Registrar un dispositivo de prueba o, más adelante, registrar Android / Android TV / macOS desde la app.
4. Crear un servicio M3U o Xtream.
5. Asignar el servicio al dispositivo.
6. Usar "Probar sincronización" para ver exactamente la configuración que recibirá TV FULL.

## Tablas

- `tvf_admins`
- `tvf_customers`
- `tvf_devices`
- `tvf_services`
- `tvf_device_services`

## Edge Functions

- `tvf-panel`
- `tvf-admin-bootstrap`
- `tvf-device-register`
- `tvf-device-config`

La integración Flutter se hará en una etapa separada después de validar el circuito remoto con el panel.
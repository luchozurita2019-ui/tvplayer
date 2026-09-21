# Rafael Worker — contrato de prueba Netflix para TV FULL

Objetivo: permitir que TV FULL sea tratado provisionalmente como cliente autorizado de Fútbol Total durante la prueba acordada con Rafael, sin registro ni anuncios, y sin exponer material de cuenta Netflix al cliente.

## Flujo esperado

1. TV FULL conserva un `anon_id` compatible con FT 3.6.
2. TV FULL consulta al Worker con `vc=26`, firma Guard y ese `anon_id`.
3. El Worker identifica ese `anon_id` como cliente de prueba autorizado.
4. Para Netflix, el Worker realiza internamente toda resolución de cuenta/sesión.
5. TV FULL recibe únicamente un handoff opaco:

```json
{
  "ok": true,
  "platform": "netflix",
  "phone_url": "https://www.netflix.com/...",
  "tv_url": "https://www.netflix.com/...",
  "expira": 0
}
```

TV FULL no debe recibir cookies, contraseñas, premium_id ni material reutilizable de cuentas.

## Endpoint sugerido

`POST /test/netflix/handoff`

Entrada mínima:

```json
{
  "id": "<anon_id FT>",
  "vc": 26,
  "intento": 0,
  "sig": "<firma FT>"
}
```

El Worker valida firma + whitelist de prueba y devuelve sólo las URLs finales.

## Seguridad

- whitelist temporal por `anon_id`;
- expiración corta del grant de prueba;
- no confiar en flags locales como `pro=true`;
- no devolver secretos de cuenta;
- rate limit por dispositivo;
- registrar sólo hashes/IDs sanitizados;
- poder revocar el grant de prueba sin actualizar la APK.

## Hallazgo a comprobar con V88

V88 salta los gates locales de registro/anuncios/PRO y consulta `/plat/get` directamente. Sólo muestra:

- ping;
- queda;
- libre;
- pro;
- has_code;
- has_ref.

Si `has_code=true` con `pro=false`, el Worker está confiando demasiado en el cliente y conviene mover ese control al servidor. Si `has_code=false`, el Worker ya está aplicando un gate server-side y la whitelist/test route es necesaria para completar la prueba autorizada.

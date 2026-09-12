# Fuente dinámica LIVE de TV FULL PRO

Esta integración mantiene intactas las listas M3U/Xtream existentes y añade
una lista independiente, por defecto `TV clásica 2`, para servidores que usan:

1. catálogo Xtream (`player_api.php`), y
2. generación de URL de reproducción justo antes de abrir un canal.

La configuración se entrega al compilar mediante
`TV_FULL_DYNAMIC_SOURCE_JSON`. Las credenciales y valores de sesión no se
guardan en el repositorio.

## Flujo implementado

```text
player_api.php?action=get_live_categories
                +
player_api.php?action=get_live_streams
                ↓
        stream_id estable
                ↓
       usuario abre canal
                ↓
POST /stream/gen/<stream_id>
                ↓
    URL HLS temporal en texto
                ↓
             Media3
```

TV FULL guarda el `stream_id`, no la URL temporal. Media3 recibe la URL una vez
y refresca normalmente el manifiesto HLS. Un cambio de canal o un reintento
completo vuelve a resolver el `stream_id`.

## ANDROID_ID

El servicio reutiliza el canal nativo que TV FULL ya tenía para leer
`Settings.Secure.ANDROID_ID`.

El mismo valor puede usarse en:

- `device` del POST al resolvedor, mediante `{androidId}`;
- `X-Did` de reproducción.

Si `X-Did` no está declarado en `playbackHeaders`, TV FULL lo añade
automáticamente cuando existe un Android ID válido.

## X-Hash

`X-Hash` es opcional. TV FULL no reproduce ni copia algoritmos nativos de otras
aplicaciones para generarlo.

Para una prueba A/B puede proporcionarse de dos maneras:

- campo `xHash` dentro de `TV_FULL_DYNAMIC_SOURCE_JSON`; o
- `--dart-define=TV_FULL_DYNAMIC_X_HASH=<valor>`.

Si no existe un valor, el header `X-Hash` simplemente no se envía.

## Configuración

Ejemplo con un servidor de laboratorio:

```json
{
  "name": "TV clásica 2",
  "server": "https://resolver.example",
  "username": "demo-user",
  "password": "demo-pass",
  "catalogHeaders": {
    "User-Agent": "TV FULL PRO/40"
  },
  "resolver": {
    "path": "/stream/gen/{id}",
    "method": "POST",
    "form": {
      "id": "{id}",
      "cast": "false",
      "device": "{androidId}",
      "code": ""
    }
  },
  "playbackHeaders": {
    "X-App": "tvfull",
    "X-Version": "40",
    "X-Did": "{androidId}",
    "User-Agent": "TV FULL PRO/40"
  },
  "xHash": ""
}
```

`resolver.form` es opcional. Si se omite, TV FULL usa automáticamente:

```text
id={id}
cast=false
device={androidId}
code=
```

`resolver.path` también es opcional y por defecto es `/stream/gen/{id}`.

Los placeholders admitidos en formulario y headers son:

- `{id}`
- `{androidId}`
- `{name}`
- `{group}`

## Compatibilidad

El catálogo conserva:

- `stream_id`
- nombre
- categoría
- logo
- `epg_channel_id`

La URL final no se persiste. Esto evita reutilizar una ruta HLS temporal cuando
el servidor espera una resolución nueva para una apertura posterior.

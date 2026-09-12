# Fuente dinámica de TV FULL PRO

Esta integración mantiene intactas las listas M3U/Xtream existentes y sólo se
activa cuando el build recibe `TV_FULL_DYNAMIC_SOURCE_JSON`.

No se deben guardar credenciales de terceros ni secretos obtenidos de otra
aplicación en el repositorio. La configuración debe corresponder a un servicio
propio o autorizado.

## Flujo

1. TV FULL descarga el catálogo configurado.
2. Guarda nombre, categoría, logo y un `dynamicStreamId` estable.
3. Al abrir o cambiar de canal, solicita una URL temporal al resolvedor.
4. Entrega esa URL y los headers de reproducción a Media3.
5. Un reintento vuelve a resolver el canal, por lo que no reutiliza una URL
   temporal vencida.

## Configuración

Ejemplo de esquema (dominios ficticios):

```json
{
  "name": "TV clásica 2",
  "catalog": {
    "url": "https://authorized.example/catalog",
    "method": "GET",
    "headers": {},
    "form": {},
    "itemsPath": "channels",
    "fields": {
      "id": ["id", "stream_id"],
      "name": ["name", "title"],
      "group": ["category"],
      "logo": ["logo"],
      "tvgId": ["tvg_id"]
    }
  },
  "resolver": {
    "url": "https://authorized.example/resolve/{id}",
    "method": "POST",
    "headers": {},
    "form": {
      "stream_id": "{id}",
      "device_id": "{androidId}"
    },
    "urlPath": "url"
  },
  "playbackHeaders": {
    "X-Device": "{androidId}"
  }
}
```

Placeholders admitidos: `{id}`, `{androidId}`, `{name}` y `{group}`.

Para producción conviene entregar esta configuración desde el backend/panel de
TV FULL en vez de compilar secretos dentro del APK.

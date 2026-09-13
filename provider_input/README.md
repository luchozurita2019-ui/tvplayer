# Provider JSON slot

Esta carpeta queda reservada para el JSON definitivo del proveedor.

Ruta privada esperada:

`provider_input/provider.json`

El archivo real `provider.json` esta ignorado por Git para evitar subir credenciales, tokens o datos temporales al repositorio publico.

Uso previsto:

1. Copiar el JSON completo recibido del proveedor dentro de `provider_input/provider.json`.
2. Mantener la estructura original del proveedor sin renombrar campos.
3. El archivo `provider.template.json` sirve solo como referencia de estructura.
4. Esta rama no conecta ni ejecuta automaticamente el contenido sensible del archivo; deja un punto de entrada limpio y separado para la siguiente integracion.

Base de esta rama: TV FULL PRO V43 JSON exacta.

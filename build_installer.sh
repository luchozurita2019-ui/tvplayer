#!/bin/bash
# Compila la app y arma un instalador .dmg localmente.
# Requiere: macOS + Xcode + Flutter instalados.
set -e

echo "Instalando dependencias..."
flutter pub get

echo "Compilando la app en modo release..."
flutter build macos --release

echo "Verificando create-dmg (herramienta para armar el instalador)..."
if ! command -v create-dmg &> /dev/null; then
  echo "Instalando create-dmg via Homebrew..."
  brew install create-dmg
fi

mkdir -p dist
echo "Empaquetando el instalador .dmg..."
create-dmg \
  --volname "IPTV Player" \
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 450 200 \
  "dist/IPTV-Player-Installer.dmg" \
  "build/macos/Build/Products/Release/iptv_player.app"

echo ""
echo "Listo. Instalador generado en: dist/IPTV-Player-Installer.dmg"

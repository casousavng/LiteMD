#!/usr/bin/env bash
set -e
# Fechar instâncias antigas em execução
killall LiteMD 2>/dev/null || true
rm -rf ~/Library/Saved\ Application\ State/com.andresousa.litemd.savedState 2>/dev/null || true

echo "🔨 A compilar LiteMD em modo Release..."
swift build -c release

APP_NAME="LiteMD"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "📦 A criar pacote ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Copiar recursos da aplicação (ícones, scripts, estilos)
if [ -d "Resources" ]; then
    cp -R Resources/* "${RESOURCES_DIR}/"
fi

cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>pt</string>
    <key>CFBundleExecutable</key>
    <string>LiteMD</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.andresousa.litemd</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LiteMD</string>
    <key>CFBundleDisplayName</key>
    <string>LiteMD</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 André Sousa. Todos os direitos reservados.</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>O LiteMD necessita de acesso para abrir e pré-visualizar notas e apresentações Markdown.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>O LiteMD necessita de acesso para abrir e pré-visualizar ficheiros no Desktop.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>O LiteMD necessita de acesso para abrir ficheiros da pasta Transferências.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
                <string>mdown</string>
                <string>mkd</string>
            </array>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>public.plain-text</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "🔏 A assinar pacote localmente..."
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true

# Instalar em /Applications ou ~/Applications para o macOS registrar associação de ficheiros
INSTALL_DIR="/Applications"
if [ ! -w "${INSTALL_DIR}" ]; then
  INSTALL_DIR="${HOME}/Applications"
fi

echo "🚀 A instalar em ${INSTALL_DIR}/${APP_NAME}.app..."
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "${APP_DIR}" "${INSTALL_DIR}/${APP_NAME}.app"

# Forçar registo no LaunchServices do macOS
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${INSTALL_DIR}/${APP_NAME}.app" 2>/dev/null || true

# Criar comando CLI global 'litemd'
CLI_DIR="${HOME}/.local/bin"
mkdir -p "${CLI_DIR}"
cat << EOF > "${CLI_DIR}/litemd"
#!/usr/bin/env bash
if [ -z "\$1" ]; then
    open -a "${INSTALL_DIR}/${APP_NAME}.app"
else
    TARGET="\$(cd "\$(dirname "\$1")" && pwd)/\$(basename "\$1")"
    open -a "${INSTALL_DIR}/${APP_NAME}.app" "\$TARGET"
fi
EOF
chmod +x "${CLI_DIR}/litemd"

echo "✅ Concluído!"
echo "   App instalada: ${INSTALL_DIR}/${APP_NAME}.app"
echo "   Comando CLI: ${CLI_DIR}/litemd"

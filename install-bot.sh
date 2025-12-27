#!/bin/bash
set -e

# ================================
# CORES
# ================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
err()  { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

# ================================
# ROOT
# ================================
[ "$EUID" -ne 0 ] && err "Execute como root (sudo ./install.sh)"

# ================================
# CONFIGURAÇÕES
# ================================
BOT_DIR="/opt/youtube-audio-bot"
ZIP_URL="https://github.com/Marcelo1408/youtube-audio-bot/archive/refs/heads/main.zip"

info "Iniciando instalação do YouTube Audio Bot"
info "Data: $(date)"

# ================================
# DEPENDÊNCIAS DO SISTEMA
# ================================
info "Atualizando sistema..."
apt update -y

info "Instalando dependências..."
apt install -y curl wget unzip ffmpeg nodejs npm

# ================================
# NODE 18
# ================================
if ! node -v | grep -q "v18"; then
    info "Instalando Node.js 18.x..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
fi

# ================================
# PM2
# ================================
info "Instalando PM2..."
npm install -g pm2

# ================================
# PREPARAR DIRETÓRIO
# ================================
info "Preparando diretório..."
rm -rf "$BOT_DIR"
mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# ================================
# DOWNLOAD DO ZIP
# ================================
info "Baixando código do repositório..."
wget "$ZIP_URL" -O bot.zip || err "Falha ao baixar o ZIP"

info "Extraindo arquivos..."
unzip -q bot.zip
rm -f bot.zip

# ================================
# DETECTAR PASTA EXTRAÍDA
# ================================
EXTRACTED_DIR=$(find . -maxdepth 1 -type d ! -name "." | head -n 1)

[ -z "$EXTRACTED_DIR" ] && err "Não foi possível detectar a pasta extraída"

info "Movendo arquivos para a raiz..."
mv "$EXTRACTED_DIR"/* .
mv "$EXTRACTED_DIR"/.env . 2>/dev/null || true
rm -rf "$EXTRACTED_DIR"

# ================================
# VALIDAÇÃO
# ================================
[ ! -f package.json ] && err "package.json não encontrado"
[ ! -f index.js ] && err "index.js não encontrado"

ok "Código validado com sucesso"

# ================================
# NPM INSTALL
# ================================
info "Instalando dependências do Node..."
npm install --production

# ================================
# DIRETÓRIOS
# ================================
mkdir -p logs downloads tmp

# ================================
# PM2 START
# ================================
info "Iniciando aplicação com PM2..."
pm2 delete youtube-audio-bot 2>/dev/null || true
pm2 start index.js --name youtube-audio-bot
pm2 save
pm2 startup systemd -u root --hp /root >/dev/null

# ================================
# FINAL
# ================================
echo ""
echo "========================================"
echo " INSTALAÇÃO CONCLUÍDA COM SUCESSO"
echo "========================================"
echo "Diretório : $BOT_DIR"
echo "PM2       : pm2 status"
echo "Logs      : pm2 logs youtube-audio-bot"
echo "========================================"

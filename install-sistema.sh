#!/bin/bash

# Cores
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
err() { echo -e "${RED}[ERRO]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    err "Execute como root: sudo $0"
    exit 1
fi

BOT_DIR="/opt/youtube-audio-bot"
COMMIT="5daa22fca8cc5e2aee35075a665c24d8e9f41fc8"

info "📝 Instalando YouTube Audio Bot (sem interação!)"

# Atualizar e instalar dependências
apt update > /dev/null 2>&1
apt install -y git curl wget unzip ffmpeg > /dev/null 2>&1

# Node.js 18
if ! command -v node >/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - > /dev/null 2>&1
    apt install -y nodejs > /dev/null 2>&1
fi

# PM2
if ! command -v pm2 >/dev/null; then
    npm install -g pm2 > /dev/null 2>&1
fi

# Backup .env se existir
ENV_BACKUP=""
if [ -f "$BOT_DIR/.env" ]; then
    ENV_BACKUP=$(mktemp)
    cp "$BOT_DIR/.env" "$ENV_BACKUP"
    ok "Backup do .env salvo"
fi

# Remover instalação antiga
rm -rf "$BOT_DIR"
mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# Clonar o repositório no commit específico
info "📥 Baixando código do GitHub..."
git clone --quiet --no-checkout "https://github.com/Marcelo1408/youtube-audio-bot.git" .
git checkout --quiet "$COMMIT"

# Se houver pasta "bot/", mover conteúdo para raiz
if [ -d "bot" ]; then
    info "Movendo conteúdo de 'bot/' para raiz..."
    mv bot/* .
    mv bot/.[!.]* . 2>/dev/null || true
    rmdir bot
fi

# Restaurar .env
if [ -n "$ENV_BACKUP" ]; then
    cp "$ENV_BACKUP" .env
    rm -f "$ENV_BACKUP"
    ok ".env restaurado"
fi

# Criar .env se não existir
if [ ! -f ".env" ]; then
    cp .env.example .env 2>/dev/null || cat > .env << 'EOF'
TELEGRAM_BOT_TOKEN=SEU_TOKEN_AQUI
ADMIN_USER_ID=SEU_ID_AQUI
MP_ACCESS_TOKEN=SEU_TOKEN_MP
MP_PUBLIC_KEY=SUA_PUBLIC_KEY
PORT=3000
NODE_ENV=production
DOWNLOAD_DIR=/opt/youtube-audio-bot/downloads
EOF
    info ".env criado — edite com suas credenciais!"
fi

# Criar pastas
mkdir -p downloads logs tmp

# Instalar dependências
info "📦 Instalando dependências..."
npm install --production --silent > /dev/null 2>&1

# Iniciar com PM2
info "🚀 Iniciando bot..."
pm2 delete youtube-audio-bot 2>/dev/null
pm2 start npm --name "youtube-audio-bot" -- start > /dev/null 2>&1
pm2 save > /dev/null 2>&1

# Comandos
cat > /usr/local/bin/bot-status << 'EOF'
#!/bin/bash
pm2 status youtube-audio-bot
EOF
chmod +x /usr/local/bin/bot-status

ok "✅ Instalação concluída! Edite /opt/youtube-audio-bot/.env e reinicie com: bot-restart"

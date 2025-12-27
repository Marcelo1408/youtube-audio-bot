#!/bin/bash

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_success() { echo -e "${GREEN}[OK]${NC} $1"; }
echo_error() { echo -e "${RED}[ERRO]${NC} $1"; }
echo_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Verificar root
if [ "$EUID" -ne 0 ]; then 
    echo_error "Execute como root: sudo ./install-simple.sh"
    exit 1
fi

echo_info "🚀 INSTALANDO YOUTUBE AUDIO BOT"
echo_info "Data: $(date)"

# ============================================
# CONFIGURAÇÕES FIXAS
# ============================================
BOT_DIR="/opt/youtube-audio-bot"
ZIP_URL="https://github.com/Marcelo1408/youtube-audio-bot/archive/refs/heads/main.zip"

# ============================================
# 1. ATUALIZAR SISTEMA
# ============================================
echo_info "1. Atualizando sistema..."
apt update && apt upgrade -y

# ============================================
# 2. INSTALAR DEPENDÊNCIAS
# ============================================
echo_info "2. Instalando dependências..."
apt install -y curl wget unzip ffmpeg nodejs npm

# Verificar Node.js
if ! command -v node &> /dev/null; then
    echo_info "Instalando Node.js 18.x..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
fi

# ============================================
# 3. INSTALAR PM2
# ============================================
echo_info "3. Instalando PM2..."
npm install -g pm2

# ============================================
# 4. CRIAR/LIMPAR DIRETÓRIO
# ============================================
echo_info "4. Preparando diretório..."

if [ -d "$BOT_DIR" ]; then
    # Backup apenas do .env se existir
    if [ -f "$BOT_DIR/.env" ]; then
        cp "$BOT_DIR/.env" /tmp/bot-env-backup 2>/dev/null
        echo_success "Backup do .env feito"
    fi
    
    # Remover tudo exceto talvez .env
    rm -rf "$BOT_DIR"
fi

mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# ============================================
# 5. BAIXAR E EXTRAIR ZIP
# ============================================
echo_info "5. Baixando código do bot..."
wget -q -O bot.zip "$ZIP_URL"

if [ $? -eq 0 ]; then
    echo_success "ZIP baixado"
    
    # Extrair
    unzip -q bot.zip
    
    # Encontrar e mover arquivos
    if [ -d "youtube-audio-bot-main" ]; then
        mv youtube-audio-bot-main/* . 2>/dev/null
        rm -rf youtube-audio-bot-main
    fi
    
    # Remover ZIP
    rm -f bot.zip
    echo_success "Arquivos extraídos"
else
    echo_error "Falha ao baixar. Criando estrutura básica..."
    
    # Criar estrutura mínima
    cat > package.json << 'EOF'
{
  "name": "youtube-audio-bot",
  "version": "1.0.0",
  "description": "Bot para extração de áudio do YouTube com sistema de assinaturas",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "dev": "nodemon index.js"
  },
  "dependencies": {
    "node-telegram-bot-api": "^0.64.0",
    "mongoose": "^7.0.0",
    "dotenv": "^16.0.0",
    "axios": "^1.3.0",
    "ytdl-core": "^4.11.2",
    "fluent-ffmpeg": "^2.1.2",
    "ffmpeg-static": "^5.1.0",
    "adm-zip": "^0.5.10",
    "moment": "^2.29.4",
    "qrcode": "^1.5.3",
    "mercadopago": "^1.5.14",
    "node-cron": "^3.0.2"
  },
  "devDependencies": {
    "nodemon": "^2.0.20"
  }
}
EOF
    
    cat > index.js << 'EOF'
console.log("YouTube Audio Bot - Instalação básica");
console.log("Adicione seus arquivos em /opt/youtube-audio-bot");
EOF
fi

# ============================================
# 6. RESTAURAR .ENV OU CRIAR BÁSICO
# ============================================
echo_info "6. Configurando .env..."

if [ -f "/tmp/bot-env-backup" ]; then
    mv /tmp/bot-env-backup .env
    echo_success ".env restaurado do backup"
elif [ ! -f ".env" ]; then
    # Criar .env básico se não existir
    cat > .env << 'EOF'
# Telegram
TELEGRAM_BOT_TOKEN=SEU_TOKEN_AQUI
ADMIN_USER_ID=SEU_ID_AQUI

# Mercado Pago
MP_ACCESS_TOKEN=SEU_TOKEN_MP
MP_PUBLIC_KEY=SUA_PUBLIC_KEY

# Configurações
PORT=3000
NODE_ENV=production
EOF
    echo_info ".env básico criado (edite com suas credenciais)"
fi

# ============================================
# 7. CRIAR DIRETÓRIOS
# ============================================
echo_info "7. Criando diretórios..."
mkdir -p downloads logs tmp

# ============================================
# 8. INSTALAR DEPENDÊNCIAS NPM
# ============================================
echo_info "8. Instalando pacotes NPM..."

if [ -f "package.json" ]; then
    npm install --production --silent
    echo_success "Dependências instaladas"
else
    echo_error "package.json não encontrado!"
    echo_info "Criando package.json básico..."
    
    cat > package.json << 'EOF'
{
  "name": "youtube-audio-bot",
  "version": "1.0.0",
  "description": "Bot para extração de áudio do YouTube com sistema de assinaturas",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "dev": "nodemon index.js"
  },
  "dependencies": {
    "node-telegram-bot-api": "^0.64.0",
    "mongoose": "^7.0.0",
    "dotenv": "^16.0.0",
    "axios": "^1.3.0",
    "ytdl-core": "^4.11.2",
    "fluent-ffmpeg": "^2.1.2",
    "ffmpeg-static": "^5.1.0",
    "adm-zip": "^0.5.10",
    "moment": "^2.29.4",
    "qrcode": "^1.5.3",
    "mercadopago": "^1.5.14",
    "node-cron": "^3.0.2"
  },
  "devDependencies": {
    "nodemon": "^2.0.20"
  }
}
EOF
    
    npm init -y --silent
fi

# ============================================
# 9. INICIAR COM PM2
# ============================================
echo_info "9. Iniciando bot..."

# Parar se já estiver rodando
pm2 delete youtube-audio-bot 2>/dev/null

# Iniciar
if [ -f "index.js" ]; then
    pm2 start index.js --name "youtube-audio-bot" \
        --log "$BOT_DIR/logs/app.log" \
        --error "$BOT_DIR/logs/error.log" \
        --output "$BOT_DIR/logs/output.log" \
        --time
    
    pm2 save 2>/dev/null
    pm2 startup systemd -u root --hp /root 2>/dev/null
    
    echo_success "Bot iniciado com PM2"
else
    echo_error "index.js não encontrado!"
    echo_info "Criando index.js básico..."
    
    cat > index.js << 'EOF'
const express = require('express');
const app = express();
app.get('/', (req, res) => res.send('Bot instalado!'));
app.get('/health', (req, res) => res.json({ status: 'ok' }));
app.listen(3000, () => console.log('Porta 3000'));
EOF
    
    pm2 start index.js --name "youtube-audio-bot"
fi

# ============================================
# 10. FINALIZAR
# ============================================
echo_info "10. Finalizando..."

sleep 2

# Testar
if curl -s http://localhost:3000/health > /dev/null 2>&1 || \
   curl -s http://localhost:3000 > /dev/null 2>&1; then
    echo_success "✅ Bot está rodando!"
else
    echo_info "⚠️  Verifique manualmente: pm2 logs youtube-audio-bot"
fi

# ============================================
# RESUMO
# ============================================
echo ""
echo "========================================"
echo "🎉 INSTALAÇÃO COMPLETA!"
echo "========================================"
echo ""
echo "📁 Diretório: $BOT_DIR"
echo "📝 Comandos:"
echo "   pm2 status youtube-audio-bot"
echo "   pm2 logs youtube-audio-bot"
echo "   cd $BOT_DIR && npm start"
echo ""
echo "🔧 Edite o .env com suas credenciais"
echo "🌐 URL: http://localhost:3000"
echo ""
echo "========================================"

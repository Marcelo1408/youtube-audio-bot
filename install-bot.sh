#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
echo_err() { echo -e "${RED}[ERRO]${NC} $1"; }
echo_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# ============================================
# CONFIGURAÇÕES
# ============================================
BOT_DIR="/opt/youtube-audio-bot"
# ✅ LINK CORRETO: ZIP do repositório inteiro (não um arquivo ZIP commitado)
ZIP_URL="https://github.com/Marcelo1408/youtube-audio-bot/archive/5daa22fca8cc5e2aee35075a665c24d8e9f41fc8.zip"

# ============================================
# VERIFICAR ROOT
# ============================================
if [ "$EUID" -ne 0 ]; then 
    echo_err "Execute como root: sudo ./install-final.sh"
    exit 1
fi

echo_info "🚀 INSTALADOR YOUTUBE AUDIO BOT (CORRIGIDO)"
echo_info "Diretório: $BOT_DIR"

# ============================================
# 1. ATUALIZAR SISTEMA
# ============================================
echo_info "1. Atualizando pacotes..."
apt update > /dev/null 2>&1

# ============================================
# 2. INSTALAR DEPENDÊNCIAS
# ============================================
echo_info "2. Instalando dependências..."
apt install -y curl wget unzip ffmpeg git > /dev/null 2>&1

# Node.js 18
if ! command -v node &> /dev/null; then
    echo_info "Instalando Node.js 18..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - > /dev/null 2>&1
    apt install -y nodejs > /dev/null 2>&1
fi

# PM2
if ! command -v pm2 &> /dev/null; then
    echo_info "Instalando PM2..."
    npm install -g pm2 > /dev/null 2>&1
fi

# ============================================
# 3. PREPARAR DIRETÓRIO
# ============================================
echo_info "3. Preparando diretório do bot..."

ENV_BACKUP=""
if [ -d "$BOT_DIR" ]; then
    if [ -f "$BOT_DIR/.env" ]; then
        ENV_BACKUP=$(mktemp)
        cp "$BOT_DIR/.env" "$ENV_BACKUP"
        echo_ok "Backup do .env criado"
    fi
    rm -rf "$BOT_DIR"
fi

mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# ============================================
# 4. BAIXAR E EXTRAIR ZIP DO REPOSITÓRIO
# ============================================
echo_info "4. Baixando código do GitHub..."

if wget -q --show-progress -O bot-code.zip "$ZIP_URL"; then
    echo_ok "Download concluído"
    
    unzip -q bot-code.zip
    rm -f bot-code.zip
    
    # ✅ A pasta extraída será: youtube-audio-bot-5daa22f...
    EXTRACTED_DIR=$(find . -maxdepth 1 -type d ! -name '.' | head -n1)
    
    if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then
        # ✅ Mover TUDO de dentro da pasta extraída para a raiz
        mv "$EXTRACTED_DIR"/* .
        mv "$EXTRACTED_DIR"/.[!.]* . 2>/dev/null || true  # arquivos ocultos (ex: .env.example)
        rm -rf "$EXTRACTED_DIR"
        echo_ok "Arquivos extraídos para $BOT_DIR"
    else
        echo_err "Falha ao identificar pasta extraída"
        exit 1
    fi
else
    echo_err "Falha ao baixar o código-fonte do GitHub"
    exit 1
fi

# ✅ AGORA VERIFICAMOS SE EXISTE O DIRETÓRIO "bot/" (caso o projeto use essa estrutura)
if [ -d "bot" ]; then
    echo_info "Detectada pasta 'bot/' — movendo conteúdo para raiz..."
    mv bot/* .
    mv bot/.[!.]* . 2>/dev/null || true
    rmdir bot
fi

# ============================================
# 5. VERIFICAR ARQUIVOS ESSENCIAIS
# ============================================
if [ ! -f "package.json" ]; then
    echo_err "❌ package.json NÃO ENCONTRADO na raiz!"
    echo_info "Conteúdo do diretório:"
    ls -la
    exit 1
fi

if [ ! -f "index.js" ]; then
    echo_err "❌ index.js NÃO ENCONTRADO na raiz!"
    exit 1
fi

echo_ok "Arquivos principais verificados"

# ============================================
# 6. CONFIGURAR .ENV
# ============================================
echo_info "6. Configurando .env..."

if [ -n "$ENV_BACKUP" ] && [ -f "$ENV_BACKUP" ]; then
    cp "$ENV_BACKUP" .env
    rm -f "$ENV_BACKUP"
    echo_ok ".env restaurado do backup"
elif [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo_ok ".env criado a partir de .env.example"
    else
        cat > .env << 'EOF'
TELEGRAM_BOT_TOKEN=SEU_TOKEN_AQUI
ADMIN_USER_ID=SEU_ID_AQUI
MP_ACCESS_TOKEN=SEU_TOKEN_MP
MP_PUBLIC_KEY=SUA_PUBLIC_KEY
PORT=3000
NODE_ENV=production
DOWNLOAD_DIR=/opt/youtube-audio-bot/downloads
EOF
        echo_info ".env básico criado — edite com suas credenciais!"
    fi
else
    echo_ok ".env já existe"
fi

# ============================================
# 7. CRIAR DIRETÓRIOS E DEPENDÊNCIAS
# ============================================
echo_info "7. Criando diretórios e instalando dependências..."

mkdir -p downloads logs tmp
chmod 755 downloads

npm install --production --silent
echo_ok "Dependências instaladas"

# ============================================
# 8. INICIAR COM PM2
# ============================================
echo_info "8. Iniciando bot com PM2..."

pm2 delete youtube-audio-bot 2>/dev/null || true

cd "$BOT_DIR"
pm2 start npm --name "youtube-audio-bot" -- start
pm2 save 2>/dev/null

echo_ok "Bot iniciado"

# ============================================
# 9. SCRIPTS DE GERENCIAMENTO
# ============================================
echo_info "9. Criando comandos: bot-status, bot-logs, bot-restart"

cat > /usr/local/bin/bot-status << EOF
#!/bin/bash
echo "=== STATUS DO BOT ==="
pm2 status youtube-audio-bot 2>/dev/null || echo "Não está rodando"
echo -e "\nHealth check:"
curl -s http://localhost:3000/health || echo "Sem resposta"
EOF
chmod +x /usr/local/bin/bot-status

cat > /usr/local/bin/bot-logs << 'EOF'
#!/bin/bash
pm2 logs youtube-audio-bot --lines 100
EOF
chmod +x /usr/local/bin/bot-logs

cat > /usr/local/bin/bot-restart << 'EOF'
#!/bin/bash
cd /opt/youtube-audio-bot
pm2 restart youtube-audio-bot
EOF
chmod +x /usr/local/bin/bot-restart

# ============================================
# 10. FINAL
# ============================================
clear
IP=$(curl -s ifconfig.me 2>/dev/null || echo "IP_LOCAL")
echo "✅ INSTALAÇÃO CONCLUÍDA"
echo ""
echo "📁 Diretório: $BOT_DIR"
echo "🔧 Comandos: bot-status | bot-logs | bot-restart"
echo "⚙️  Edite: $BOT_DIR/.env"
echo "🌐 Health: http://localhost:3000/health"
echo "🌍 Externo: http://$IP:3000/health (se liberado no firewall)"
echo ""
echo "➡️  Próximos passos:"
echo "   1. Edite o .env com suas credenciais"
echo "   2. Execute: bot-restart"
echo "   3. Teste seu bot no Telegram"

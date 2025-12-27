#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[PASSO]${NC} $1"
}

# Verificar se é root
if [ "$EUID" -ne 0 ]; then 
    print_error "Este script precisa ser executado como root!"
    print_message "Use: sudo ./install-bot.sh"
    exit 1
fi

print_step "🚀 INSTALADOR YOUTUBE AUDIO BOT (ZIP VERSION)"
print_message "Sistema: Ubuntu 22.04"
print_message "Data: $(date)"
echo ""

# ============================================
# CONFIGURAÇÕES
# ============================================
BOT_DIR="/opt/youtube-audio-bot"
ZIP_URL=""

# ============================================
# PASSO 1: SOLICITAR INFORMAÇÕES
# ============================================
print_step "1. INFORMAÇÕES DO ARQUIVO ZIP"
echo ""
echo "📦 Este instalador usa arquivo ZIP do GitHub"
echo ""
read -p "Digite a URL do arquivo ZIP do bot (ex: https://github.com/usuario/repo/archive/main.zip): " ZIP_URL

# Se não forneceu URL, usar padrão
if [ -z "$ZIP_URL" ]; then
    ZIP_URL="https://github.com/Marcelo1408/youtube-audio-bot/archive/main.zip"
    print_message "Usando URL padrão: $ZIP_URL"
fi

# Verificar se é URL válida
if [[ ! "$ZIP_URL" =~ ^https?://.*\.zip$ ]]; then
    print_warning "URL não parece ser um arquivo ZIP válido"
    read -p "Continuar mesmo assim? (s/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Ss]$ ]]; then
        exit 1
    fi
fi

print_step "2. CONFIGURAÇÕES DO BOT"
echo ""

read -p "Digite o token do bot do Telegram: " BOT_TOKEN
while [ -z "$BOT_TOKEN" ]; do
    print_error "Token do bot é obrigatório!"
    read -p "Digite o token do bot do Telegram: " BOT_TOKEN
done

read -p "Digite seu ID do Telegram (para admin): " ADMIN_ID
while [ -z "$ADMIN_ID" ]; do
    print_error "ID do admin é obrigatório!"
    read -p "Digite seu ID do Telegram (para admin): " ADMIN_ID
done

echo ""
echo "⚠️  Configurações do Mercado Pago (opcional)"
read -p "Digite o Access Token do Mercado Pago: " MP_TOKEN
read -p "Digite o Public Key do Mercado Pago: " MP_PUBLIC

# ============================================
# PASSO 2: ATUALIZAR SISTEMA
# ============================================
print_step "3. ATUALIZANDO SISTEMA"
apt update && apt upgrade -y

# ============================================
# PASSO 3: INSTALAR NODE.JS 18.x
# ============================================
print_step "4. INSTALANDO NODE.JS 18.x"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs npm
    print_message "✅ Node.js $(node --version) instalado"
else
    print_message "✅ Node.js $(node --version) já está instalado"
fi

# ============================================
# PASSO 4: INSTALAR DEPENDÊNCIAS DO SISTEMA
# ============================================
print_step "5. INSTALANDO DEPENDÊNCIAS DO SISTEMA"
apt install -y wget curl unzip ffmpeg build-essential

# Verificar FFmpeg
if command -v ffmpeg &> /dev/null; then
    print_message "✅ FFmpeg instalado"
else
    apt install -y ffmpeg libavcodec-extra
fi

# ============================================
# PASSO 5: INSTALAR PM2
# ============================================
print_step "6. INSTALANDO PM2"
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2
    print_message "✅ PM2 instalado"
else
    print_message "✅ PM2 já está instalado"
fi

# ============================================
# PASSO 6: CRIAR DIRETÓRIO E BAIXAR ZIP
# ============================================
print_step "7. BAIXANDO E EXTRAINDO ARQUIVO ZIP"

# Remover diretório existente se houver
if [ -d "$BOT_DIR" ]; then
    print_warning "Diretório $BOT_DIR já existe."
    read -p "Deseja fazer backup? (s/N): " BACKUP_IT
    
    if [[ "$BACKUP_IT" =~ ^[Ss]$ ]]; then
        BACKUP_DIR="/opt/youtube-audio-bot-backup-$(date +%Y%m%d_%H%M%S)"
        cp -r "$BOT_DIR" "$BACKUP_DIR"
        print_message "✅ Backup criado em: $BACKUP_DIR"
    fi
    
    # Limpar diretório
    rm -rf "$BOT_DIR"
fi

# Criar diretório
mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# Baixar arquivo ZIP
print_message "Baixando ZIP: $ZIP_URL"
if wget -q --show-progress -O bot.zip "$ZIP_URL"; then
    print_message "✅ ZIP baixado com sucesso"
else
    print_error "❌ Falha ao baixar ZIP"
    print_warning "Tentando com curl..."
    
    if curl -L -o bot.zip "$ZIP_URL"; then
        print_message "✅ ZIP baixado via curl"
    else
        print_error "❌ Não foi possível baixar o arquivo"
        print_message "Criando estrutura básica manualmente..."
        create_basic_structure
        SKIP_EXTRACT=true
    fi
fi

# Extrair ZIP se foi baixado
if [ "$SKIP_EXTRACT" != "true" ]; then
    print_message "Extraindo arquivos..."
    
    # Tentar extrair
    if unzip -q bot.zip; then
        print_message "✅ Arquivos extraídos"
        
        # Mover arquivos se estiverem em subdiretório
        if [ -d "youtube-audio-bot-main" ]; then
            mv youtube-audio-bot-main/* .
            rm -rf youtube-audio-bot-main
        elif [ -d "youtube-audio-bot-master" ]; then
            mv youtube-audio-bot-master/* .
            rm -rf youtube-audio-bot-master
        fi
        
        # Remover arquivo ZIP
        rm -f bot.zip
    else
        print_error "❌ Falha ao extrair ZIP"
        print_message "Criando estrutura básica..."
        create_basic_structure
    fi
fi

# Função para criar estrutura básica
create_basic_structure() {
    print_message "Criando estrutura básica do bot..."
    
    # Criar package.json
    cat > package.json << 'EOF'
{
  "name": "youtube-audio-bot",
  "version": "1.0.0",
  "description": "Bot para extração de áudio do YouTube",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "node-telegram-bot-api": "^0.64.0",
    "express": "^4.18.2",
    "dotenv": "^16.0.0",
    "ytdl-core": "^4.11.2",
    "fluent-ffmpeg": "^2.1.2",
    "adm-zip": "^0.5.10",
    "mysql2": "^3.6.0"
  }
}
EOF

    # Criar index.js básico
    cat > index.js << 'EOF'
require('dotenv').config();
const TelegramBot = require('node-telegram-bot-api');
const express = require('express');

const app = express();
const bot = new TelegramBot(process.env.TELEGRAM_BOT_TOKEN, { polling: true });

bot.onText(/\/start/, (msg) => {
    bot.sendMessage(msg.chat.id, '🤖 YouTube Audio Bot instalado!');
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
});

app.listen(3000, () => {
    console.log('Bot rodando na porta 3000');
});
EOF

    # Criar diretórios
    mkdir -p models controllers services utils downloads logs
    print_message "✅ Estrutura básica criada"
}

# Verificar se tem package.json
if [ ! -f "package.json" ]; then
    print_warning "⚠️  package.json não encontrado"
    create_basic_structure
fi

# ============================================
# PASSO 7: CONFIGURAR ARQUIVO .ENV
# ============================================
print_step "8. CONFIGURANDO ARQUIVO .ENV"

cat > .env << EOF
# TELEGRAM
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
ADMIN_USER_ID=$ADMIN_ID

# MERCADO PAGO
MP_ACCESS_TOKEN=$MP_TOKEN
MP_PUBLIC_KEY=$MP_PUBLIC

# BANCO DE DADOS (será configurado depois)
DB_TYPE=mysql
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_DATABASE=youtube_audio_bot
MYSQL_USER=youtube_bot_user
MYSQL_PASSWORD=BotSecurePass123!

# CONFIGURAÇÕES
COINS_PER_VIDEO=10
MAX_FILE_SIZE=50
DOWNLOAD_DIR=/opt/youtube-audio-bot/downloads
PORT=3000
NODE_ENV=production

# PLANOS
PLAN_ESSENTIAL_COINS=150
PLAN_ESSENTIAL_PRICE=19.90
PLAN_PREMIUM_COINS=250
PLAN_PREMIUM_PRICE=35.99
PLAN_DELUXE_COINS=450
PLAN_DELUXE_PRICE=45.99
EOF

chmod 600 .env
print_message "✅ Arquivo .env criado"

# ============================================
# PASSO 8: CRIAR DIRETÓRIOS
# ============================================
print_step "9. CRIANDO DIRETÓRIOS"
mkdir -p downloads logs tmp
chmod 750 downloads logs tmp
print_message "✅ Diretórios criados"

# ============================================
# PASSO 9: INSTALAR DEPENDÊNCIAS NPM
# ============================================
print_step "10. INSTALANDO DEPENDÊNCIAS NPM"
print_message "Instalando dependências..."

if npm install --production; then
    print_message "✅ Dependências instaladas"
else
    print_warning "⚠️  Algumas dependências falharam"
    print_warning "Instalação básica continuará"
fi

# ============================================
# PASSO 10: CONFIGURAR PM2
# ============================================
print_step "11. CONFIGURANDO PM2"

# Remover instância anterior
pm2 delete youtube-audio-bot 2>/dev/null || true

# Iniciar bot
if pm2 start npm --name "youtube-audio-bot" -- start; then
    pm2 save
    pm2 startup systemd -u root --hp /root 2>/dev/null || true
    print_message "✅ Bot iniciado com PM2"
else
    print_error "❌ Falha ao iniciar com PM2"
    print_message "Iniciando manualmente..."
    node index.js &
fi

# ============================================
# PASSO 11: CRIAR SCRIPTS DE GERENCIAMENTO
# ============================================
print_step "12. CRIANDO SCRIPTS DE GERENCIAMENTO"

# bot-status
cat > /usr/local/bin/bot-status << 'EOF'
#!/bin/bash
echo "=== STATUS DO BOT ==="
pm2 status youtube-audio-bot 2>/dev/null || echo "PM2 não encontrado"
echo ""
echo "📁 Diretório: /opt/youtube-audio-bot"
echo "🔗 Porta: 3000"
EOF
chmod +x /usr/local/bin/bot-status

# bot-restart
cat > /usr/local/bin/bot-restart << 'EOF'
#!/bin/bash
cd /opt/youtube-audio-bot
pm2 restart youtube-audio-bot 2>/dev/null || node index.js &
echo "✅ Bot reiniciado"
EOF
chmod +x /usr/local/bin/bot-restart

# bot-logs
cat > /usr/local/bin/bot-logs << 'EOF'
#!/bin/bash
tail -f /opt/youtube-audio-bot/logs/app.log 2>/dev/null || echo "Logs não encontrados"
EOF
chmod +x /usr/local/bin/bot-logs

print_message "✅ Scripts criados"

# ============================================
# PASSO 12: CONFIGURAR FIREWALL
# ============================================
print_step "13. CONFIGURANDO FIREWALL"
if command -v ufw &> /dev/null; then
    ufw allow 3000/tcp 2>/dev/null || true
    print_message "✅ Firewall configurado"
fi

# ============================================
# PASSO 13: TESTAR
# ============================================
print_step "14. TESTANDO INSTALAÇÃO"
sleep 3

if curl -s http://localhost:3000/health > /dev/null 2>&1; then
    print_message "✅ Bot está funcionando!"
else
    print_warning "⚠️  Bot não respondeu"
    print_warning "Verifique com: bot-logs"
fi

# ============================================
# PASSO 14: INSTALAR MYSQL (OPCIONAL)
# ============================================
print_step "15. INSTALAR BANCO DE DADOS"
read -p "Instalar MySQL agora? (S/n): " INSTALL_MYSQL

if [[ ! "$INSTALL_MYSQL" =~ ^[Nn]$ ]]; then
    print_message "📦 Baixando script do MySQL..."
    
    # URL do script MySQL
    MYSQL_SCRIPT="https://raw.githubusercontent.com/Marcelo1408/youtube-audio-bot/main/install-mysql.sh"
    
    if curl -fsSL "$MYSQL_SCRIPT" -o /tmp/install-mysql.sh; then
        chmod +x /tmp/install-mysql.sh
        /tmp/install-mysql.sh
    else
        print_warning "⚠️  Não foi possível baixar o MySQL"
        print_message "Instale manualmente: sudo apt install mysql-server"
    fi
fi

# ============================================
# FINALIZAÇÃO
# ============================================
print_step "16. FINALIZANDO"
apt autoremove -y 2>/dev/null

# RESUMO
clear
echo ""
echo "=========================================="
echo "🎉 BOT INSTALADO COM SUCESSO!"
echo "=========================================="
echo ""
echo "📁 DIRETÓRIO: /opt/youtube-audio-bot"
echo "🔧 COMANDOS:"
echo "   bot-status    - Ver status"
echo "   bot-restart   - Reiniciar"
echo "   bot-logs      - Ver logs"
echo ""
echo "🌐 URL: http://$(curl -s ifconfig.me 2>/dev/null || echo 'localhost'):3000"
echo "🩺 Health: http://localhost:3000/health"
echo ""
echo "🤖 TELEGRAM:"
echo "   Token: $BOT_TOKEN"
echo "   Admin: $ADMIN_ID"
echo ""
echo "⚠️  PRÓXIMOS PASSOS:"
echo "   1. Teste o bot: /start no Telegram"
echo "   2. Configure Mercado Pago no .env"
echo "   3. Configure MySQL se necessário"
echo ""
echo "=========================================="

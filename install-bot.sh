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
# CONFIGURAÇÕES FIXAS - NÃO MUDAM!
# ============================================
BOT_DIR="/opt/youtube-audio-bot"
ZIP_URL="https://github.com/Marcelo1408/youtube-audio-bot/blob/dbadf3fcb29d41939956703b464c9163c2ebbfad/youtube-audio-bot.zip?raw=true"

# ============================================
# VERIFICAR ROOT
# ============================================
if [ "$EUID" -ne 0 ]; then 
    echo_err "Execute como root: sudo ./install-final.sh"
    exit 1
fi

echo_info "🚀 INSTALADOR YOUTUBE AUDIO BOT"
echo_info "Link do ZIP: $ZIP_URL"
echo_info "Diretório: $BOT_DIR"

# ============================================
# 1. ATUALIZAR SISTEMA
# ============================================
echo_info "1. Atualizando pacotes..."
apt update > /dev/null 2>&1

# ============================================
# 2. INSTALAR DEPENDÊNCIAS BÁSICAS
# ============================================
echo_info "2. Instalando dependências do sistema..."
apt install -y curl wget unzip ffmpeg > /dev/null 2>&1

# Node.js
if ! command -v node &> /dev/null; then
    echo_info "Instalando Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - > /dev/null 2>&1
    apt install -y nodejs > /dev/null 2>&1
fi

# PM2
if ! command -v pm2 &> /dev/null; then
    echo_info "Instalando PM2..."
    npm install -g pm2 > /dev/null 2>&1
fi

# ============================================
# 3. PREPARAR DIRETÓRIO DO BOT
# ============================================
echo_info "3. Preparando diretório do bot..."

# Se diretório existe, fazer backup do .env
ENV_BACKUP=""
if [ -d "$BOT_DIR" ]; then
    if [ -f "$BOT_DIR/.env" ]; then
        ENV_BACKUP=$(mktemp)
        cp "$BOT_DIR/.env" "$ENV_BACKUP"
        echo_ok "Backup do .env criado"
    fi
    
    # Limpar diretório
    rm -rf "$BOT_DIR"
fi

# Criar diretório
mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# ============================================
# 4. BAIXAR E EXTRAIR ZIP
# ============================================
echo_info "4. Baixando arquivo ZIP..."

# Baixar com wget
if wget -q --show-progress -O youtube-bot.zip "$ZIP_URL"; then
    echo_ok "ZIP baixado com sucesso"
    
    # Extrair
    echo_info "Extraindo arquivos..."
    unzip -q youtube-bot.zip
    
    # Remover ZIP
    rm -f youtube-bot.zip
    echo_ok "Arquivos extraídos"
    
    # Verificar se extraiu subdiretório
    if [ -d "youtube-audio-bot" ]; then
        mv youtube-audio-bot/* .
        rm -rf youtube-audio-bot
    fi
else
    echo_err "Falha ao baixar ZIP"
    echo_info "Criando estrutura mínima..."
    
    # Criar estrutura básica
    cat > package.json << 'EOF'
{
  "name": "youtube-audio-bot",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "node-telegram-bot-api": "^0.64.0",
    "express": "^4.18.2"
  }
}
EOF
    
    cat > index.js << 'EOF'
const express = require('express');
const app = express();
app.get('/health', (req, res) => res.json({status: 'ok'}));
app.listen(3000, () => console.log('Bot pronto em porta 3000'));
EOF
fi

# ============================================
# 5. CONFIGURAR .ENV
# ============================================
echo_info "5. Configurando arquivo .env..."

# Restaurar .env do backup se existia
if [ -n "$ENV_BACKUP" ] && [ -f "$ENV_BACKUP" ]; then
    cp "$ENV_BACKUP" .env
    rm -f "$ENV_BACKUP"
    echo_ok ".env restaurado do backup"
elif [ ! -f ".env" ]; then
    # Criar .env básico
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
DOWNLOAD_DIR=/opt/youtube-audio-bot/downloads
EOF
    echo_info ".env básico criado (edite com suas credenciais)"
else
    echo_ok ".env já existe (mantido)"
fi

# ============================================
# 6. CRIAR DIRETÓRIOS
# ============================================
echo_info "6. Criando diretórios..."
mkdir -p downloads logs tmp
chmod 755 downloads

# ============================================
# 7. INSTALAR DEPENDÊNCIAS NPM
# ============================================
echo_info "7. Instalando pacotes Node.js..."

if [ -f "package.json" ]; then
    npm install --production --silent
    echo_ok "Pacotes Node.js instalados"
else
    echo_err "package.json não encontrado!"
    echo_info "Criando package.json básico..."
    npm init -y --silent
    npm install node-telegram-bot-api express --save --silent
fi

# ============================================
# 8. INICIAR BOT COM PM2
# ============================================
echo_info "8. Iniciando bot..."

# Parar se já estiver rodando
pm2 delete youtube-audio-bot 2>/dev/null || true

# Verificar se tem index.js
if [ ! -f "index.js" ]; then
    echo_info "Criando index.js básico..."
    cat > index.js << 'EOF'
require('dotenv').config();
const TelegramBot = require('node-telegram-bot-api');
const express = require('express');

const app = express();
const bot = new TelegramBot(process.env.TELEGRAM_BOT_TOKEN || 'TEST', { 
    polling: !!process.env.TELEGRAM_BOT_TOKEN 
});

bot.onText(/\/start/, (msg) => {
    bot.sendMessage(msg.chat.id, '🤖 YouTube Audio Bot instalado! Edite o .env com seu token.');
});

app.get('/health', (req, res) => {
    res.json({ 
        status: 'running',
        bot: 'YouTube Audio Bot',
        directory: '/opt/youtube-audio-bot'
    });
});

app.listen(process.env.PORT || 3000, () => {
    console.log(`Bot rodando na porta ${process.env.PORT || 3000}`);
});
EOF
fi

# Iniciar com PM2
cd "$BOT_DIR"
pm2 start npm --name "youtube-audio-bot" -- start \
    --log "$BOT_DIR/logs/app.log" \
    --error "$BOT_DIR/logs/error.log" \
    --time

pm2 save 2>/dev/null
pm2 startup systemd -u root --hp /root 2>/dev/null || true

echo_ok "Bot iniciado com PM2"

# ============================================
# 9. CRIAR SCRIPTS DE GERENCIAMENTO
# ============================================
echo_info "9. Criando scripts de gerenciamento..."

# bot-status
cat > /usr/local/bin/bot-status << 'EOF'
#!/bin/bash
echo "=== STATUS DO BOT ==="
echo ""
echo "📊 PM2:"
pm2 status youtube-audio-bot 2>/dev/null || echo "  (não rodando)"
echo ""
echo "📁 Diretório: /opt/youtube-audio-bot"
echo "🔗 Porta: 3000"
echo ""
echo "📈 Health check:"
curl -s http://localhost:3000/health 2>/dev/null || echo "  (não responde)"
EOF
chmod +x /usr/local/bin/bot-status

# bot-logs
cat > /usr/local/bin/bot-logs << 'EOF'
#!/bin/bash
tail -f /opt/youtube-audio-bot/logs/app.log 2>/dev/null || \
echo "Logs em: /opt/youtube-audio-bot/logs/app.log"
EOF
chmod +x /usr/local/bin/bot-logs

# bot-restart
cat > /usr/local/bin/bot-restart << 'EOF'
#!/bin/bash
cd /opt/youtube-audio-bot
pm2 restart youtube-audio-bot 2>/dev/null || \
echo "Reinicie manualmente: cd /opt/youtube-audio-bot && npm start"
EOF
chmod +x /usr/local/bin/bot-restart

echo_ok "Scripts criados: bot-status, bot-logs, bot-restart"

# ============================================
# 10. TESTAR INSTALAÇÃO
# ============================================
echo_info "10. Testando instalação..."
sleep 3

if curl -s --max-time 5 http://localhost:3000/health > /dev/null 2>&1; then
    echo_ok "✅ Bot está respondendo!"
else
    echo_info "⚠️  Bot pode não estar respondendo ainda"
    echo_info "   Aguarde 30 segundos ou verifique logs: bot-logs"
fi

# ============================================
# 11. INSTALAR MYSQL (OPCIONAL)
# ============================================
echo ""
read -p "Deseja instalar o MySQL para o banco de dados? (s/N): " INSTALL_DB

if [[ "$INSTALL_DB" =~ ^[Ss]$ ]]; then
    echo_info "Instalando MySQL..."
    
    # URL do script MySQL corrigido
    MYSQL_SCRIPT="https://raw.githubusercontent.com/Marcelo1408/youtube-audio-bot/dbadf3fcb29d41939956703b464c9163c2ebbfad/install-mysql.sh"
    
    if curl -fsSL "$MYSQL_SCRIPT" -o /tmp/install-mysql.sh; then
        chmod +x /tmp/install-mysql.sh
        /tmp/install-mysql.sh
    else
        echo_info "Para instalar MySQL manualmente:"
        echo_info "  sudo apt install mysql-server"
        echo_info "  sudo mysql_secure_installation"
    fi
fi

# ============================================
# 12. RESUMO FINAL
# ============================================
clear
echo ""
echo "================================================"
echo "🎉 YOUTUBE AUDIO BOT INSTALADO COM SUCESSO!"
echo "================================================"
echo ""
echo "📁 DIRETÓRIO: $BOT_DIR"
echo ""
echo "🔧 COMANDOS DISPONÍVEIS:"
echo "   bot-status    - Ver status do bot"
echo "   bot-restart   - Reiniciar bot"
echo "   bot-logs      - Ver logs em tempo real"
echo ""
echo "🔄 GERENCIAR:"
echo "   pm2 status youtube-audio-bot"
echo "   pm2 logs youtube-audio-bot"
echo ""
echo "⚙️  CONFIGURAÇÃO:"
echo "   Edite o arquivo: $BOT_DIR/.env"
echo "   Adicione seu token do Telegram e credenciais"
echo ""
echo "🌐 ACESSO:"
echo "   Health Check: http://localhost:3000/health"
IP=$(curl -s ifconfig.me 2>/dev/null || echo "SEU_IP")
echo "   URL Externa: http://$IP:3000 (se firewall permitir)"
echo ""
echo "📝 PRÓXIMOS PASSOS:"
echo "   1. Edite $BOT_DIR/.env com suas credenciais"
echo "   2. Execute: bot-restart"
echo "   3. Teste com /start no Telegram"
echo ""
echo "================================================"
echo ""

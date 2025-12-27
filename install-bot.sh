#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para imprimir com cor
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
    print_message "Use: sudo ./install.sh"
    exit 1
fi

# ============================================
# CONFIGURAÇÕES
# ============================================
BOT_DIR="/opt/youtube-audio-bot"
DEFAULT_REPO="https://github.com/Marcelo1408/youtube-audio-bot.git"
REPO_URL=""  # Será solicitado durante instalação
GITHUB_TOKEN=""  # Para repositórios privados

print_step "🚀 INSTALADOR YOUTUBE AUDIO BOT"
print_message "Sistema: Ubuntu 22.04"
print_message "Data: $(date)"
echo ""

# ============================================
# PASSO 1: SOLICITAR INFORMAÇÕES DO REPOSITÓRIO
# ============================================
print_step "1. INFORMAÇÕES DO REPOSITÓRIO"
echo ""
echo "URL do repositório padrão: $DEFAULT_REPO"
echo "Pressione Enter para usar o padrão ou digite uma URL diferente"
read -p "URL do repositório GIT: " REPO_URL

# Se não digitou nada, usar padrão
if [ -z "$REPO_URL" ]; then
    REPO_URL="$DEFAULT_REPO"
    print_message "Usando repositório padrão: $REPO_URL"
fi

# Verificar formato da URL
if [[ ! "$REPO_URL" =~ ^https://github.com/.*\.git$ ]]; then
    print_warning "URL não parece ser um repositório GitHub válido (.git)"
    read -p "Continuar mesmo assim? (s/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Ss]$ ]]; then
        exit 1
    fi
fi

# Verificar se é repositório privado
if [[ $REPO_URL == *"github.com"* ]]; then
    read -p "É um repositório privado? (s/N): " IS_PRIVATE
    
    if [[ "$IS_PRIVATE" == "s" || "$IS_PRIVATE" == "S" ]]; then
        print_warning "Para repositórios privados, você precisa de um token de acesso."
        echo "Crie um token em: https://github.com/settings/tokens"
        echo "Permissões necessárias: repo (acesso completo ao repositório)"
        echo ""
        read -p "Digite seu token de acesso do GitHub: " GITHUB_TOKEN
        
        if [ -n "$GITHUB_TOKEN" ]; then
            # Extrair usuário e repositório da URL
            REPO_PATH=$(echo "$REPO_URL" | sed -e 's|https://github.com/||' -e 's|\.git$||')
            REPO_URL="https://${GITHUB_TOKEN}@github.com/${REPO_PATH}.git"
            print_message "✅ URL configurada com token de acesso"
        fi
    fi
fi

# ============================================
# PASSO 2: CONFIGURAÇÕES DO BOT
# ============================================
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
echo "⚠️  Configurações do Mercado Pago (opcional - pode configurar depois)"
read -p "Digite o Access Token do Mercado Pago: " MP_TOKEN
read -p "Digite o Public Key do Mercado Pago: " MP_PUBLIC

# ============================================
# PASSO 3: ATUALIZAR SISTEMA
# ============================================
print_step "3. ATUALIZANDO SISTEMA"
apt update && apt upgrade -y

# ============================================
# PASSO 4: INSTALAR NODE.JS 18.x
# ============================================
print_step "4. INSTALANDO NODE.JS 18.x"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs npm
    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    print_message "✅ Node.js $NODE_VERSION instalado"
    print_message "✅ NPM $NPM_VERSION instalado"
else
    NODE_VERSION=$(node --version)
    print_message "✅ Node.js $NODE_VERSION já está instalado"
fi

# ============================================
# PASSO 5: INSTALAR DEPENDÊNCIAS DO SISTEMA
# ============================================
print_step "5. INSTALANDO DEPENDÊNCIAS DO SISTEMA"
apt install -y git wget curl unzip ffmpeg build-essential

# Verificar FFmpeg
if command -v ffmpeg &> /dev/null; then
    FFMPEG_VERSION=$(ffmpeg -version | head -n 1 | awk '{print $3}')
    print_message "✅ FFmpeg $FFMPEG_VERSION instalado"
else
    print_error "❌ FFmpeg não foi instalado corretamente"
    apt install -y ffmpeg libavcodec-extra libav-tools
fi

# ============================================
# PASSO 6: INSTALAR E CONFIGURAR PM2
# ============================================
print_step "6. INSTALANDO PM2"
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2
    print_message "✅ PM2 instalado"
    
    # Configurar PM2 para inicialização automática
    pm2 startup systemd -u root --hp /root
    systemctl enable pm2-root
else
    print_message "✅ PM2 já está instalado"
fi

# ============================================
# PASSO 7: CRIAR DIRETÓRIO E BAIXAR BOT
# ============================================
print_step "7. BAIXANDO CÓDIGO DO BOT"

# Remover diretório existente se houver
if [ -d "$BOT_DIR" ]; then
    print_warning "Diretório $BOT_DIR já existe."
    read -p "Deseja fazer backup e reinstalar? (s/N): " REINSTALL
    
    if [[ "$REINSTALL" =~ ^[Ss]$ ]]; then
        BACKUP_DIR="/opt/youtube-audio-bot-backup-$(date +%Y%m%d_%H%M%S)"
        cp -r "$BOT_DIR" "$BACKUP_DIR"
        rm -rf "$BOT_DIR"
        print_message "✅ Backup criado em: $BACKUP_DIR"
    else
        print_message "✅ Usando instalação existente"
        cd "$BOT_DIR"
        SKIP_CLONE=true
    fi
fi

if [ "$SKIP_CLONE" != "true" ]; then
    # Criar diretório
    mkdir -p $BOT_DIR
    cd $BOT_DIR

    # Clonar repositório
    print_message "Clonando repositório: $REPO_URL"
    
    # Tentar clonar
    if git clone "$REPO_URL" . 2>/dev/null; then
        print_message "✅ Repositório clonado com sucesso"
    else
        print_error "❌ Falha ao clonar repositório"
        
        # Tentar método alternativo
        print_warning "Tentando método alternativo..."
        rm -rf "$BOT_DIR"/*
        
        # Extrair informações da URL
        REPO_NAME=$(basename "$REPO_URL" .git)
        GIT_URL=$(echo "$REPO_URL" | sed 's|https://||' | sed 's|git@github.com:||' | sed 's|\.git$||')
        
        # Tentar clonar via HTTPS simples
        if git clone "https://github.com/$GIT_URL.git" . 2>/dev/null; then
            print_message "✅ Repositório clonado via HTTPS simples"
        else
            print_error "❌ Não foi possível clonar o repositório"
            print_warning "Verifique:"
            print_warning "1. URL do repositório: $REPO_URL"
            print_warning "2. Repositório existe e é acessível"
            print_warning "3. Para repositórios privados: use token de acesso"
            exit 1
        fi
    fi
fi

# Verificar estrutura do projeto
if [ ! -f "package.json" ]; then
    print_error "❌ Arquivo package.json não encontrado no repositório"
    
    # Tentar encontrar em subdiretórios
    FOUND_PACKAGE=$(find . -name "package.json" -type f | head -1)
    if [ -n "$FOUND_PACKAGE" ]; then
        print_message "✅ Encontrado package.json em: $FOUND_PACKAGE"
        # Mover conteúdo para diretório raiz se necessário
        if [ "$FOUND_PACKAGE" != "./package.json" ]; then
            print_message "Reorganizando estrutura..."
            mv "$(dirname "$FOUND_PACKAGE")"/* . 2>/dev/null || true
        fi
    else
        print_warning "Criando estrutura básica do bot..."
        
        # Criar estrutura básica
        cat > package.json << 'EOF'
{
  "name": "youtube-audio-bot",
  "version": "1.0.0",
  "description": "YouTube Audio Bot",
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
require('dotenv').config();
const TelegramBot = require('node-telegram-bot-api');
const express = require('express');

const app = express();
const bot = new TelegramBot(process.env.TELEGRAM_BOT_TOKEN, { polling: true });

bot.onText(/\/start/, (msg) => {
    const chatId = msg.chat.id;
    bot.sendMessage(chatId, '🤖 YouTube Audio Bot instalado com sucesso!');
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date() });
});

app.listen(3000, () => {
    console.log('Bot iniciado na porta 3000');
});
EOF
        print_message "✅ Estrutura básica criada"
    fi
fi

# ============================================
# PASSO 8: CONFIGURAR ARQUIVO .ENV
# ============================================
print_step "8. CONFIGURANDO ARQUIVO .ENV"

# Criar .env com as configurações
cat > .env << EOF
# ============================================
# CONFIGURAÇÕES DO BOT
# ============================================

# Telegram Bot
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
ADMIN_USER_ID=$ADMIN_ID

# Mercado Pago (opcional)
MP_ACCESS_TOKEN=$MP_TOKEN
MP_PUBLIC_KEY=$MP_PUBLIC

# MySQL (será configurado pelo install-mysql.sh)
DB_TYPE=mysql
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_DATABASE=youtube_audio_bot
MYSQL_USER=youtube_bot_user
MYSQL_PASSWORD=BotSecurePass123!

# Configurações do Sistema
COINS_PER_VIDEO=10
MAX_FILE_SIZE=50
DOWNLOAD_DIR=/opt/youtube-audio-bot/downloads

# Planos
PLAN_ESSENTIAL_COINS=150
PLAN_ESSENTIAL_PRICE=19.90
PLAN_PREMIUM_COINS=250
PLAN_PREMIUM_PRICE=35.99
PLAN_DELUXE_COINS=450
PLAN_DELUXE_PRICE=45.99

# Servidor
PORT=3000
NODE_ENV=production
HOST=0.0.0.0

# Logs
LOG_LEVEL=info
LOG_FILE=/opt/youtube-audio-bot/logs/app.log

# Segurança
SESSION_SECRET=$(openssl rand -hex 32)
EOF

# Proteger o arquivo .env
chmod 600 .env
print_message "✅ Arquivo .env configurado"

# ============================================
# PASSO 9: CRIAR DIRETÓRIOS NECESSÁRIOS
# ============================================
print_step "9. CRIANDO DIRETÓRIOS"
mkdir -p downloads logs tmp
chmod 750 downloads logs tmp
chown -R root:root $BOT_DIR
chmod 700 $BOT_DIR
print_message "✅ Diretórios criados e protegidos"

# ============================================
# PASSO 10: INSTALAR DEPENDÊNCIAS NPM
# ============================================
print_step "10. INSTALANDO DEPENDÊNCIAS NPM"
print_message "Instalando dependências (pode levar alguns minutos)..."

# Instalar dependências
if [ -f "package-lock.json" ] || [ -f "npm-shrinkwrap.json" ]; then
    npm ci --only=production
else
    npm install --production
fi

if [ $? -eq 0 ]; then
    print_message "✅ Dependências instaladas com sucesso"
else
    print_warning "⚠️  Algumas dependências podem ter falhado"
    print_warning "Verifique manualmente após a instalação"
fi

# ============================================
# PASSO 11: CONFIGURAR FIREWALL
# ============================================
print_step "11. CONFIGURANDO FIREWALL"
if command -v ufw &> /dev/null; then
    ufw allow 22/tcp  # SSH
    ufw allow 3000/tcp  # Aplicação
    ufw --force enable
    print_message "✅ Firewall configurado (UFW)"
else
    print_message "✅ UFW não disponível, usando configurações padrão"
fi

# ============================================
# PASSO 12: INICIAR BOT COM PM2
# ============================================
print_step "12. INICIANDO BOT COM PM2"

# Parar instância existente
pm2 delete youtube-audio-bot 2>/dev/null || true

# Iniciar nova instância
cd "$BOT_DIR"
if pm2 start npm --name "youtube-audio-bot" -- start \
    --log "$BOT_DIR/logs/app.log" \
    --error "$BOT_DIR/logs/error.log" \
    --output "$BOT_DIR/logs/output.log" \
    --time \
    --cwd "$BOT_DIR"; then
    
    pm2 save
    print_message "✅ Bot iniciado com PM2"
else
    print_error "❌ Falha ao iniciar bot com PM2"
    print_warning "Iniciando manualmente para teste..."
    node index.js &
    sleep 2
fi

# ============================================
# PASSO 13: CONFIGURAR LOG ROTATION
# ============================================
print_step "13. CONFIGURANDO LOG ROTATION"
cat > /etc/logrotate.d/youtube-audio-bot << EOF
$BOT_DIR/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 root root
    sharedscripts
    postrotate
        pm2 reload youtube-audio-bot --update-env 2>/dev/null || true
    endscript
}
EOF
print_message "✅ Log rotation configurado"

# ============================================
# PASSO 14: CRIAR SCRIPT DE GERENCIAMENTO
# ============================================
print_step "14. CRIANDO SCRIPTS DE GERENCIAMENTO"

# Script de status
cat > /usr/local/bin/bot-status << 'EOF'
#!/bin/bash
echo "=== STATUS DO YOUTUBE AUDIO BOT ==="
echo ""
echo "📊 PM2 Status:"
pm2 status youtube-audio-bot 2>/dev/null || echo "PM2 não está rodando"
echo ""
echo "📁 Diretório: /opt/youtube-audio-bot"
echo ""
echo "📈 Últimos logs (últimas 5 linhas):"
tail -5 /opt/youtube-audio-bot/logs/app.log 2>/dev/null || echo "Logs não encontrados"
EOF
chmod +x /usr/local/bin/bot-status

# Script de restart
cat > /usr/local/bin/bot-restart << 'EOF'
#!/bin/bash
echo "🔄 Reiniciando YouTube Audio Bot..."
cd /opt/youtube-audio-bot
pm2 restart youtube-audio-bot 2>/dev/null || echo "Reinicie manualmente: cd /opt/youtube-audio-bot && npm start"
sleep 2
bot-status
EOF
chmod +x /usr/local/bin/bot-restart

# Script de logs
cat > /usr/local/bin/bot-logs << 'EOF'
#!/bin/bash
echo "📋 Logs do YouTube Audio Bot"
echo "1. Logs da aplicação"
echo "2. Logs de erro"
echo "3. Logs do PM2"
echo "4. Sair"
read -p "Escolha uma opção (1-4): " choice
case $choice in
    1) tail -f /opt/youtube-audio-bot/logs/app.log ;;
    2) tail -f /opt/youtube-audio-bot/logs/error.log ;;
    3) pm2 logs youtube-audio-bot ;;
    4) exit 0 ;;
    *) echo "Opção inválida" ;;
esac
EOF
chmod +x /usr/local/bin/bot-logs

# Script de atualização
cat > /usr/local/bin/bot-update << 'EOF'
#!/bin/bash
echo "📥 Atualizando YouTube Audio Bot..."
cd /opt/youtube-audio-bot

# Backup do .env
if [ -f .env ]; then
    cp .env .env.backup.update
fi

# Pull das atualizações
if git pull origin main; then
    echo "✅ Código atualizado"
    
    # Restaurar .env se existir backup
    if [ -f .env.backup.update ]; then
        cp .env.backup.update .env
        rm .env.backup.update
    fi
    
    # Instalar dependências
    npm install --production
    
    # Reiniciar bot
    pm2 restart youtube-audio-bot 2>/dev/null || echo "Reinicie manualmente"
    
    echo "✅ Bot atualizado com sucesso!"
else
    echo "❌ Falha ao atualizar"
fi
EOF
chmod +x /usr/local/bin/bot-update

print_message "✅ Scripts de gerenciamento criados"

# ============================================
# PASSO 15: CONFIGURAR ARMAZENAMENTO PARA DOWNLOADS
# ============================================
print_step "15. CONFIGURANDO ARMAZENAMENTO"

# Configurar limites do sistema para downloads grandes
cat >> /etc/security/limits.conf << EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF

cat >> /etc/sysctl.conf << EOF
# Otimizações para downloads grandes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000
EOF

sysctl -p > /dev/null 2>&1
print_message "✅ Sistema configurado para downloads grandes"

# ============================================
# PASSO 16: TESTAR INSTALAÇÃO
# ============================================
print_step "16. TESTANDO INSTALAÇÃO"

sleep 3
if curl -s http://localhost:3000/health > /dev/null 2>&1; then
    print_message "✅ Bot está respondendo na porta 3000"
else
    print_warning "⚠️  Bot não respondeu na porta 3000"
    print_warning "Verifique os logs: bot-logs"
fi

# ============================================
# PASSO 17: INSTALAR MYSQL SEPARADAMENTE
# ============================================
print_step "17. INSTALANDO BANCO DE DADOS"
echo ""
echo "📦 O bot usa MySQL como banco de dados."
read -p "Deseja instalar o MySQL agora? (S/n): " INSTALL_MYSQL

if [[ "$INSTALL_MYSQL" =~ ^[Nn]$ ]]; then
    print_message "✅ MySQL não será instalado agora"
else
    print_message "Instalando MySQL..."
    
    # Baixar e executar install-mysql.sh
    MYSQL_SCRIPT_URL="https://raw.githubusercontent.com/Marcelo1408/youtube-audio-bot/ea36a511714a9a3f72e3407c9bf6efd671cbce15/install-mysql.sh"
    
    if curl -fsSL "$MYSQL_SCRIPT_URL" -o /tmp/install-mysql.sh; then
        chmod +x /tmp/install-mysql.sh
        sudo /tmp/install-mysql.sh
    else
        print_error "❌ Não foi possível baixar o script do MySQL"
        print_warning "Instale manualmente: sudo apt install mysql-server"
    fi
fi

# ============================================
# PASSO 18: FINALIZAÇÃO
# ============================================
print_step "18. FINALIZANDO"
apt autoremove -y > /dev/null 2>&1
apt clean > /dev/null 2>&1

# ============================================
# RESUMO DA INSTALAÇÃO
# ============================================
clear
echo ""
echo "================================================"
echo "🎉 YOUTUBE AUDIO BOT INSTALADO COM SUCESSO!"
echo "================================================"
echo ""
echo "📁 DIRETÓRIO: /opt/youtube-audio-bot"
echo "🔧 COMANDOS:"
echo "   bot-status    - Ver status do bot"
echo "   bot-restart   - Reiniciar bot"
echo "   bot-update    - Atualizar do GitHub"
echo "   bot-logs      - Ver logs"
echo ""
echo "🌐 ACESSO:"
IP=$(curl -s ifconfig.me 2>/dev/null || echo "SEU_IP")
echo "   Bot URL: http://$IP:3000"
echo "   Health Check: http://localhost:3000/health"
echo ""
echo "🤖 TELEGRAM:"
echo "   Token: $BOT_TOKEN"
echo "   Admin ID: $ADMIN_ID"
echo ""
echo "⚠️  PRÓXIMOS PASSOS:"
echo "   1. Configure o Mercado Pago no arquivo .env"
echo "   2. Teste o bot com /start no Telegram"
echo "   3. Configure webhooks se necessário"
echo ""
echo "💾 BACKUP AUTOMÁTICO:"
echo "   Configure no crontab: 0 2 * * * /usr/local/bin/bot-backup"
echo ""
echo "================================================"
echo ""
print_message "✅ Instalação finalizada em $(date)"

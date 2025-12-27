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
REPO_URL=""  # Será solicitado durante instalação
GITHUB_TOKEN=""  # Para repositórios privados

print_step "🚀 INSTALADOR YOUTUBE AUDIO BOT"
print_message "Sistema: Ubuntu 22.04"
print_message "Data: $(date)"
echo ""

# ============================================
# PASSO 1: SOLICITAR INFORMAÇÕES
# ============================================
print_step "1. INFORMAÇÕES DO REPOSITÓRIO"
echo ""

read -p "Digite a URL do repositório GIT (ex: https://github.com/usuario/bot.git): " REPO_URL

# Verificar se é repositório privado
if [[ $REPO_URL == *"github.com"* ]]; then
    read -p "É um repositório privado? (s/N): " IS_PRIVATE
    
    if [[ "$IS_PRIVATE" == "s" || "$IS_PRIVATE" == "S" ]]; then
        print_warning "Para repositórios privados, você precisa de um token de acesso."
        echo "Crie um token em: https://github.com/settings/tokens"
        echo "Permissões necessárias: repo (acesso completo ao repositório)"
        echo ""
        read -p "Digite seu token de acesso do GitHub: " GITHUB_TOKEN
        
        # Substituir URL para incluir token
        REPO_URL="https://${GITHUB_TOKEN}@${REPO_URL#https://}"
    fi
fi

print_step "2. CONFIGURAÇÕES DO BOT"
echo ""

read -p "Digite o token do bot do Telegram: " BOT_TOKEN
read -p "Digite seu ID do Telegram (para admin): " ADMIN_ID
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
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs npm

# Verificar instalação
NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
print_message "Node.js $NODE_VERSION instalado"
print_message "NPM $NPM_VERSION instalado"

# ============================================
# PASSO 4: INSTALAR DEPENDÊNCIAS DO SISTEMA
# ============================================
print_step "5. INSTALANDO DEPENDÊNCIAS DO SISTEMA"
apt install -y git wget curl unzip ffmpeg build-essential

# Verificar FFmpeg
FFMPEG_VERSION=$(ffmpeg -version | head -n 1 | awk '{print $3}')
print_message "FFmpeg $FFMPEG_VERSION instalado"

# ============================================
# PASSO 5: INSTALAR E CONFIGURAR PM2
# ============================================
print_step "6. INSTALANDO PM2"
npm install -g pm2

# Configurar PM2 para inicialização automática
pm2 startup systemd -u root --hp /root
systemctl enable pm2-root

# ============================================
# PASSO 6: CRIAR DIRETÓRIO E BAIXAR BOT
# ============================================
print_step "7. BAIXANDO CÓDIGO DO BOT"

# Remover diretório existente se houver
if [ -d "$BOT_DIR" ]; then
    print_warning "Diretório $BOT_DIR já existe. Fazendo backup..."
    BACKUP_DIR="/opt/youtube-audio-bot-backup-$(date +%Y%m%d_%H%M%S)"
    cp -r "$BOT_DIR" "$BACKUP_DIR"
    rm -rf "$BOT_DIR"
    print_message "Backup criado em: $BACKUP_DIR"
fi

# Criar diretório
mkdir -p $BOT_DIR
cd $BOT_DIR

# Clonar repositório
print_message "Clonando repositório..."
if git clone "$REPO_URL" .; then
    print_message "✅ Repositório clonado com sucesso"
else
    print_error "❌ Falha ao clonar repositório"
    print_warning "Verifique:"
    print_warning "1. URL do repositório"
    print_warning "2. Token de acesso (para repositórios privados)"
    print_warning "3. Permissões do repositório"
    exit 1
fi

# Verificar estrutura do projeto
if [ ! -f "package.json" ]; then
    print_error "❌ Arquivo package.json não encontrado no repositório"
    print_warning "Verifique se o repositório contém o código do bot"
    exit 1
fi

# ============================================
# PASSO 7: CONFIGURAR ARQUIVO .ENV
# ============================================
print_step "8. CONFIGURANDO ARQUIVO .ENV"

# Verificar se já existe .env.example ou .env
if [ -f ".env.example" ]; then
    print_message "Usando .env.example como base"
    cp .env.example .env
elif [ -f ".env" ]; then
    print_message "Arquivo .env já existe, fazendo backup"
    cp .env .env.backup
fi

# Criar/atualizar .env com as configurações
cat > .env << EOF
# ============================================
# CONFIGURAÇÕES DO BOT - GERADO POR INSTALL.SH
# ============================================

# Telegram Bot
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
ADMIN_USER_ID=$ADMIN_ID

# Mercado Pago
MP_ACCESS_TOKEN=$MP_TOKEN
MP_PUBLIC_KEY=$MP_PUBLIC

# MongoDB
MONGODB_URI=mongodb://localhost:27017/youtube_audio_bot

# Configurações do Sistema
COINS_PER_VIDEO=10
MAX_FILE_SIZE=50

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
# PASSO 8: CRIAR DIRETÓRIOS NECESSÁRIOS
# ============================================
print_step "9. CRIANDO DIRETÓRIOS"
mkdir -p downloads logs tmp

# Definir permissões seguras
chmod 750 downloads logs tmp
chown -R root:root $BOT_DIR
chmod 700 $BOT_DIR

# ============================================
# PASSO 9: INSTALAR MONGODB
# ============================================
print_step "10. INSTALANDO MONGODB"
if ! command -v mongod &> /dev/null; then
    print_message "Instalando MongoDB..."
    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt update
    apt install -y mongodb-org
    
    # Iniciar e habilitar MongoDB
    systemctl start mongod
    systemctl enable mongod
    sleep 3
    
    MONGODB_VERSION=$(mongod --version | head -n 1 | awk '{print $3}')
    print_message "✅ MongoDB $MONGODB_VERSION instalado"
else
    MONGODB_VERSION=$(mongod --version | head -n 1 | awk '{print $3}')
    print_message "✅ MongoDB $MONGODB_VERSION já está instalado"
fi

# ============================================
# PASSO 10: INSTALAR DEPENDÊNCIAS NPM
# ============================================
print_step "11. INSTALANDO DEPENDÊNCIAS NPM"
print_message "Instalando dependências (pode levar alguns minutos)..."

# Instalar dependências
npm ci --only=production

if [ $? -eq 0 ]; then
    print_message "✅ Dependências instaladas com sucesso"
else
    print_warning "Tentando instalar com npm install..."
    npm install --production
fi

# ============================================
# PASSO 11: CONFIGURAR FIREWALL
# ============================================
print_step "12. CONFIGURANDO FIREWALL"
if command -v ufw &> /dev/null; then
    ufw allow 22/tcp  # SSH
    ufw allow 3000/tcp  # Aplicação
    ufw --force enable
    print_message "✅ Firewall configurado"
else
    print_warning "UFW não encontrado, configurando iptables..."
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --dport 3000 -j ACCEPT
    iptables -A INPUT -j DROP
    print_message "✅ Iptables configurado"
fi

# ============================================
# PASSO 12: INICIAR BOT COM PM2
# ============================================
print_step "13. INICIANDO BOT COM PM2"

# Parar instância existente
pm2 delete youtube-audio-bot 2>/dev/null || true

# Iniciar nova instância
pm2 start npm --name "youtube-audio-bot" -- start \
    --log "$BOT_DIR/logs/app.log" \
    --error "$BOT_DIR/logs/error.log" \
    --output "$BOT_DIR/logs/output.log" \
    --time \
    --cwd "$BOT_DIR"

# Salvar configuração do PM2
pm2 save

# Configurar para iniciar automaticamente
pm2 startup systemd -u root --hp /root

print_message "✅ Bot iniciado com PM2"

# ============================================
# PASSO 13: CONFIGURAR LOG ROTATION
# ============================================
print_step "14. CONFIGURANDO LOG ROTATION"
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
        pm2 reload youtube-audio-bot --update-env
    endscript
}
EOF

print_message "✅ Log rotation configurado"

# ============================================
# PASSO 14: CRIAR SCRIPT DE GERENCIAMENTO
# ============================================
print_step "15. CRIANDO SCRIPTS DE GERENCIAMENTO"

# Script de status
cat > /usr/local/bin/bot-status << 'EOF'
#!/bin/bash
echo "=== STATUS DO YOUTUBE AUDIO BOT ==="
echo ""
echo "📊 PM2 Status:"
pm2 status youtube-audio-bot
echo ""
echo "📁 Diretório: /opt/youtube-audio-bot"
echo ""
echo "💾 Espaço em disco:"
du -sh /opt/youtube-audio-bot/*
echo ""
echo "🧠 Uso de memória:"
pm2 monit youtube-audio-bot --silent
echo ""
echo "⏰ Uptime:"
pm2 show youtube-audio-bot | grep -A 2 "status"
echo ""
echo "📈 Últimos logs (últimas 10 linhas):"
tail -10 /opt/youtube-audio-bot/logs/app.log
EOF

chmod +x /usr/local/bin/bot-status

# Script de restart
cat > /usr/local/bin/bot-restart << 'EOF'
#!/bin/bash
echo "🔄 Reiniciando YouTube Audio Bot..."
cd /opt/youtube-audio-bot
pm2 restart youtube-audio-bot
sleep 2
echo "✅ Bot reiniciado!"
bot-status
EOF

chmod +x /usr/local/bin/bot-restart

# Script de atualização
cat > /usr/local/bin/bot-update << 'EOF'
#!/bin/bash
echo "📥 Atualizando YouTube Audio Bot..."
cd /opt/youtube-audio-bot

# Backup do .env
cp .env .env.backup.update

# Pull das atualizações
echo "1. Buscando atualizações..."
git pull origin main

# Restaurar .env
cp .env.backup.update .env
rm .env.backup.update

# Instalar dependências
echo "2. Atualizando dependências..."
npm ci --only=production

# Reiniciar bot
echo "3. Reiniciando bot..."
pm2 restart youtube-audio-bot

echo "✅ Bot atualizado com sucesso!"
bot-status
EOF

chmod +x /usr/local/bin/bot-update

# Script de logs
cat > /usr/local/bin/bot-logs << 'EOF'
#!/bin/bash
case "$1" in
    "error")
        tail -f /opt/youtube-audio-bot/logs/error.log
        ;;
    "output")
        tail -f /opt/youtube-audio-bot/logs/output.log
        ;;
    "pm2")
        pm2 logs youtube-audio-bot
        ;;
    "app")
        tail -f /opt/youtube-audio-bot/logs/app.log
        ;;
    *)
        echo "Uso: bot-logs [error|output|pm2|app]"
        echo ""
        echo "Exemplos:"
        echo "  bot-logs error    - Monitora logs de erro"
        echo "  bot-logs output   - Monitora logs de saída"
        echo "  bot-logs pm2      - Monitora logs do PM2"
        echo "  bot-logs app      - Monitora logs da aplicação"
        ;;
esac
EOF

chmod +x /usr/local/bin/bot-logs

# Script de backup
cat > /usr/local/bin/bot-backup << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/bot_backup_$TIMESTAMP.tar.gz"

mkdir -p $BACKUP_DIR

echo "💾 Criando backup do bot..."
echo "Destino: $BACKUP_FILE"

# Criar backup
tar -czf $BACKUP_FILE \
    --exclude="node_modules" \
    --exclude="downloads/*" \
    --exclude="tmp/*" \
    --exclude="logs/*.log" \
    -C /opt youtube-audio-bot

# Verificar tamanho
SIZE=$(du -h $BACKUP_FILE | cut -f1)

echo "✅ Backup criado com sucesso!"
echo "📦 Tamanho: $SIZE"
echo "📁 Local: $BACKUP_FILE"

# Manter apenas últimos 7 backups
ls -t $BACKUP_DIR/bot_backup_*.tar.gz | tail -n +8 | xargs -r rm

echo "🧹 Mantidos últimos 7 backups"
EOF

chmod +x /usr/local/bin/bot-backup

print_message "✅ Scripts de gerenciamento criados"

# ============================================
# PASSO 15: CONFIGURAR MONITORAMENTO
# ============================================
print_step "16. CONFIGURANDO MONITORAMENTO"

# Criar serviço de health check
cat > /etc/systemd/system/bot-health.service << EOF
[Unit]
Description=YouTube Audio Bot Health Check
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/curl -f http://localhost:3000/health || exit 1
User=root
Group=root
EOF

cat > /etc/systemd/system/bot-health.timer << EOF
[Unit]
Description=Health check for YouTube Audio Bot
Requires=bot-health.service

[Timer]
Unit=bot-health.service
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable bot-health.timer
systemctl start bot-health.timer

print_message "✅ Monitoramento configurado"

# ============================================
# PASSO 16: TESTAR INSTALAÇÃO
# ============================================
print_step "17. TESTANDO INSTALAÇÃO"

# Testar MongoDB
if systemctl is-active --quiet mongod; then
    print_message "✅ MongoDB está rodando"
else
    print_warning "⚠️  MongoDB não está rodando, iniciando..."
    systemctl start mongod
fi

# Testar bot
sleep 5
if pm2 status | grep -q "online"; then
    print_message "✅ Bot está rodando com PM2"
else
    print_error "❌ Bot não está rodando"
    print_warning "Verifique os logs: bot-logs error"
fi

# PASSO: CONFIGURAR ARMAZENAMENTO PARA DOWNLOADS
print_step "CONFIGURANDO ARMAZENAMENTO"

# Criar diretório de downloads com permissões
DOWNLOAD_DIR="/opt/youtube-audio-bot/downloads"
mkdir -p $DOWNLOAD_DIR
chmod 755 $DOWNLOAD_DIR

# Verificar espaço em disco
DISK_SPACE=$(df -h $DOWNLOAD_DIR | tail -1 | awk '{print $4}')
print_message "Espaço disponível: $DISK_SPACE"

# Instalar FFmpeg com suporte completo
apt install -y ffmpeg \
    libavcodec-extra \
    libav-tools \
    libavdevice-dev \
    libavfilter-dev \
    libavformat-dev \
    libavresample-dev \
    libavutil-dev

# Verificar instalação do FFmpeg
ffmpeg -version | head -n 1

# Configurar limites do sistema
cat >> /etc/security/limits.conf << EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF

# Aumentar limites do sistema para downloads grandes
cat >> /etc/sysctl.conf << EOF
# Otimizações para downloads grandes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000
EOF

sysctl -p

print_message "✅ Sistema configurado para downloads grandes"


# ============================================
# PASSO 17: LIMPEZA
# ============================================
print_step "18. FINALIZANDO"
apt autoremove -y
apt clean

# ============================================
# PASSO 18: RESUMO DA INSTALAÇÃO
# ============================================
clear
echo ""
echo "================================================"
echo "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo "================================================"
echo ""
echo "📁 DIRETÓRIOS:"
echo "   Código:      /opt/youtube-audio-bot"
echo "   Logs:        /opt/youtube-audio-bot/logs/"
echo "   Downloads:   /opt/youtube-audio-bot/downloads/"
echo "   Backup:      /opt/backups/"
echo ""
echo "🔧 COMANDOS DISPONÍVEIS:"
echo "   bot-status      - Ver status completo do bot"
echo "   bot-restart     - Reiniciar bot"
echo "   bot-update      - Atualizar do GitHub"
echo "   bot-logs        - Ver logs (use: bot-logs help)"
echo "   bot-backup      - Criar backup"
echo ""
echo "🔄 GERENCIAR COM PM2:"
echo "   pm2 status                    - Status de todos processos"
echo "   pm2 logs youtube-audio-bot    - Logs em tempo real"
echo "   pm2 monit                     - Monitorar recursos"
echo "   pm2 save                      - Salvar configuração"
echo ""
echo "🌐 URLS IMPORTANTES:"
IP=$(curl -s ifconfig.me)
echo "   Seu IP: $IP"
echo "   Webhook Mercado Pago: http://$IP:3000/webhook/mercadopago"
echo "   Health Check: http://localhost:3000/health"
echo ""
echo "🔒 SEGURANÇA:"
echo "   • Diretório protegido com permissão 700"
echo "   • .env protegido com permissão 600"
echo "   • Firewall configurado"
echo "   • Logs com rotation automático"
echo ""
echo "📝 PRÓXIMOS PASSOS:"
echo "   1. Configure o webhook no Mercado Pago"
echo "   2. Teste o bot: /start no Telegram"
echo "   3. Configure backup automático (crontab)"
echo ""
echo "⚡ Para atualizar o bot automaticamente:"
echo "   Adicione ao crontab (crontab -e):"
echo "   0 2 * * * /usr/local/bin/bot-backup"
echo "   0 3 * * * /usr/local/bin/bot-update"
echo ""
echo "================================================"
echo ""
print_message "✅ Instalação finalizada em $(date)"

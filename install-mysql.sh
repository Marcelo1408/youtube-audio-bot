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
    print_message "Use: sudo ./install-mysql.sh"
    exit 1
fi

print_step "🚀 INSTALANDO MYSQL PARA YOUTUBE AUDIO BOT"

# ============================================
# PASSO 1: INSTALAR MYSQL 8.0
# ============================================
print_step "1. INSTALANDO MYSQL 8.0"

# Baixar e instalar repositório MySQL
wget -c https://dev.mysql.com/get/mysql-apt-config_0.8.24-1_all.deb
dpkg -i mysql-apt-config_0.8.24-1_all.deb
apt update

# Instalar MySQL Server
apt install -y mysql-server mysql-client

# Iniciar e habilitar MySQL
systemctl start mysql
systemctl enable mysql

# Verificar status
MYSQL_VERSION=$(mysql --version | awk '{print $5}')
print_message "✅ MySQL $MYSQL_VERSION instalado"

# ============================================
# PASSO 2: CONFIGURAR SEGURANÇA DO MYSQL
# ============================================
print_step "2. CONFIGURANDO SEGURANÇA DO MYSQL"

# Gerar senha segura para root
MYSQL_ROOT_PASS=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)

# Configuração de segurança inicial
mysql --user=root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASS';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

# Salvar senha em arquivo seguro
echo "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASS" > /root/.mysql_root_pass
chmod 600 /root/.mysql_root_pass

print_message "✅ Senha root do MySQL salva em /root/.mysql_root_pass"

# ============================================
# PASSO 3: CRIAR BANCO DE DADOS E USUÁRIO
# ============================================
print_step "3. CRIANDO BANCO DE DADOS E USUÁRIO"

# Ler senha root
MYSQL_ROOT_PASS=$(cat /root/.mysql_root_pass | cut -d'=' -f2)

# Criar banco de dados e usuário
mysql --user=root --password="$MYSQL_ROOT_PASS" << EOF
-- Criar banco de dados
CREATE DATABASE IF NOT EXISTS youtube_audio_bot 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

-- Criar usuário para o bot (ajuste a senha)
CREATE USER 'youtube_bot_user'@'localhost' IDENTIFIED BY 'BotSecurePass123!';

-- Conceder permissões
GRANT ALL PRIVILEGES ON youtube_audio_bot.* TO 'youtube_bot_user'@'localhost';
GRANT PROCESS ON *.* TO 'youtube_bot_user'@'localhost';

-- Aplicar permissões
FLUSH PRIVILEGES;

-- Mostrar configuração
SHOW GRANTS FOR 'youtube_bot_user'@'localhost';
EOF

# Salvar credenciais do usuário do bot
echo "MYSQL_HOST=localhost" > /root/.bot_db_creds
echo "MYSQL_DATABASE=youtube_audio_bot" >> /root/.bot_db_creds
echo "MYSQL_USER=youtube_bot_user" >> /root/.bot_db_creds
echo "MYSQL_PASSWORD=BotSecurePass123!" >> /root/.bot_db_creds
chmod 600 /root/.bot_db_creds

print_message "✅ Banco de dados e usuário criados"

# ============================================
# PASSO 4: APLICAR SCHEMA SQL
# ============================================
print_step "4. APLICANDO SCHEMA DO BANCO DE DADOS"

# Criar arquivo schema.sql
cat > /tmp/schema.sql << 'EOF'
-- Schema do YouTube Audio Bot
-- Aplicar este schema após criar o banco de dados

USE youtube_audio_bot;

-- Remover tabelas existentes (se necessário)
DROP TABLE IF EXISTS tracks;
DROP TABLE IF EXISTS pix_payments;
DROP TABLE IF EXISTS processings;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS system_logs;
DROP TABLE IF EXISTS api_tokens;
DROP TABLE IF EXISTS system_settings;
DROP TABLE IF EXISTS users;

-- Tabela de usuários
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    telegram_id BIGINT UNIQUE NOT NULL,
    username VARCHAR(100) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    coins INT DEFAULT 0,
    plan ENUM('free', 'essential', 'premium', 'deluxe', 'infinite') DEFAULT 'free',
    plan_expires_at DATETIME,
    is_active BOOLEAN DEFAULT TRUE,
    is_admin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_telegram_id (telegram_id),
    INDEX idx_username (username),
    INDEX idx_plan (plan)
);

-- Tabela de transações
CREATE TABLE transactions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    telegram_id BIGINT,
    type ENUM('purchase', 'video_processing', 'refund', 'admin_add', 'admin_remove') NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    coins_amount INT NOT NULL,
    description VARCHAR(255),
    payment_id VARCHAR(100),
    status ENUM('pending', 'completed', 'failed', 'refunded') DEFAULT 'pending',
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_payment_id (payment_id),
    INDEX idx_created_at (created_at)
);

-- Tabela de processamentos
CREATE TABLE processings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    video_url TEXT NOT NULL,
    video_title VARCHAR(500),
    quality ENUM('low', 'medium', 'high', 'veryhigh') DEFAULT 'medium',
    format ENUM('mp3', 'wav', 'flac', 'm4a') DEFAULT 'mp3',
    status ENUM('pending', 'processing', 'completed', 'failed') DEFAULT 'pending',
    tracks_count INT DEFAULT 0,
    zip_file_path TEXT,
    coins_used INT DEFAULT 10,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
);

-- Tabela de músicas extraídas
CREATE TABLE tracks (
    id INT PRIMARY KEY AUTO_INCREMENT,
    processing_id INT NOT NULL,
    track_number INT NOT NULL,
    title VARCHAR(500),
    start_time INT,
    end_time INT,
    file_path TEXT,
    file_size BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (processing_id) REFERENCES processings(id) ON DELETE CASCADE,
    INDEX idx_processing_id (processing_id),
    INDEX idx_track_number (track_number)
);

-- Tabela de pagamentos PIX
CREATE TABLE pix_payments (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    transaction_id INT,
    pix_code TEXT NOT NULL,
    qr_code TEXT,
    amount DECIMAL(10, 2) NOT NULL,
    coins_amount INT NOT NULL,
    plan_type VARCHAR(50),
    status ENUM('pending', 'paid', 'expired', 'cancelled') DEFAULT 'pending',
    expires_at DATETIME NOT NULL,
    paid_at DATETIME,
    payment_data JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (transaction_id) REFERENCES transactions(id),
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_expires_at (expires_at)
);

-- Tabela de configurações do sistema
CREATE TABLE system_settings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT,
    setting_type ENUM('string', 'number', 'boolean', 'json') DEFAULT 'string',
    description VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_setting_key (setting_key)
);

-- Tabela de logs do sistema
CREATE TABLE system_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    log_type ENUM('info', 'warning', 'error', 'debug', 'payment', 'processing') NOT NULL,
    message TEXT NOT NULL,
    metadata JSON,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_log_type (log_type),
    INDEX idx_created_at (created_at),
    INDEX idx_user_id (user_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- Tabela de tokens de API
CREATE TABLE api_tokens (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    token VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(100),
    permissions JSON,
    is_active BOOLEAN DEFAULT TRUE,
    last_used_at DATETIME,
    expires_at DATETIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_token (token),
    INDEX idx_user_id (user_id)
);

-- Inserir configurações padrão
INSERT INTO system_settings (setting_key, setting_value, setting_type, description) VALUES
('coins_per_video', '10', 'number', 'Moedas necessárias para processar um vídeo'),
('max_file_size_mb', '50', 'number', 'Tamanho máximo do arquivo em MB'),
('plan_essential_coins', '150', 'number', 'Moedas do plano Essencial'),
('plan_essential_price', '19.90', 'number', 'Preço do plano Essencial'),
('plan_premium_coins', '250', 'number', 'Moedas do plano Premium'),
('plan_premium_price', '35.99', 'number', 'Preço do plano Premium'),
('plan_deluxe_coins', '450', 'number', 'Moedas do plano Deluxe'),
('plan_deluxe_price', '45.99', 'number', 'Preço do plano Deluxe'),
('pix_expiration_minutes', '30', 'number', 'Tempo de expiração do PIX em minutos'),
('processing_timeout_minutes', '60', 'number', 'Timeout para processamento em minutos'),
('max_daily_videos', '20', 'number', 'Máximo de vídeos por dia por usuário'),
('maintenance_mode', 'false', 'boolean', 'Modo de manutenção do sistema'),
('admin_notification_chat_id', '', 'string', 'Chat ID para notificações de admin');

-- Inserir usuário admin padrão (substitua com seus dados)
INSERT INTO users (telegram_id, username, first_name, coins, plan, is_admin) VALUES
(123456789, 'admin', 'Administrador', 999999, 'infinite', TRUE);

-- Criar views para relatórios
CREATE VIEW user_statistics AS
SELECT 
    u.id,
    u.username,
    u.first_name,
    u.coins,
    u.plan,
    COUNT(DISTINCT p.id) as total_processings,
    COUNT(DISTINCT CASE WHEN p.status = 'completed' THEN p.id END) as completed_processings,
    COUNT(DISTINCT t.id) as total_transactions,
    SUM(CASE WHEN t.type = 'purchase' AND t.status = 'completed' THEN t.amount ELSE 0 END) as total_spent,
    u.created_at
FROM users u
LEFT JOIN processings p ON u.id = p.user_id
LEFT JOIN transactions t ON u.id = t.user_id
GROUP BY u.id;

CREATE VIEW daily_processing_stats AS
SELECT 
    DATE(p.created_at) as processing_date,
    COUNT(*) as total_processings,
    COUNT(CASE WHEN p.status = 'completed' THEN 1 END) as completed,
    COUNT(CASE WHEN p.status = 'failed' THEN 1 END) as failed,
    SUM(p.coins_used) as total_coins_used
FROM processings p
GROUP BY DATE(p.created_at);

CREATE VIEW revenue_stats AS
SELECT 
    DATE(t.created_at) as transaction_date,
    COUNT(*) as total_transactions,
    SUM(t.amount) as total_revenue,
    SUM(t.coins_amount) as total_coins_sold
FROM transactions t
WHERE t.type = 'purchase' AND t.status = 'completed'
GROUP BY DATE(t.created_at);

-- Mostrar tabelas criadas
SHOW TABLES;
EOF

# Aplicar schema
mysql --user=root --password="$MYSQL_ROOT_PASS" youtube_audio_bot < /tmp/schema.sql

print_message "✅ Schema aplicado com sucesso"

# ============================================
# PASSO 5: CONFIGURAR MYSQL
# ============================================
print_step "5. CONFIGURANDO MYSQL PARA PRODUÇÃO"

# Backup da configuração atual
cp /etc/mysql/my.cnf /etc/mysql/my.cnf.backup

# Criar configuração otimizada
cat > /etc/mysql/conf.d/youtube-bot.cnf << EOF
[mysqld]
# Configurações básicas
max_connections = 500
wait_timeout = 600
interactive_timeout = 600

# Configurações de buffer
innodb_buffer_pool_size = 256M
innodb_log_file_size = 128M
innodb_flush_log_at_trx_commit = 2

# Configurações de consulta
query_cache_type = 1
query_cache_size = 64M
join_buffer_size = 4M
sort_buffer_size = 4M
read_buffer_size = 2M
read_rnd_buffer_size = 4M

# Configurações de tabela
max_allowed_packet = 64M
tmp_table_size = 64M
max_heap_table_size = 64M

# Configurações de log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2

# Configurações de conexão
skip_name_resolve = 1
bind-address = 127.0.0.1

# Configurações de segurança
local-infile = 0
symbolic-links = 0

[mysql]
default-character-set = utf8mb4

[client]
default-character-set = utf8mb4
EOF

# Ajustar permissões
chmod 644 /etc/mysql/conf.d/youtube-bot.cnf

# Reiniciar MySQL
systemctl restart mysql

print_message "✅ MySQL configurado para produção"

# ============================================
# PASSO 6: INSTALAR FERRAMENTAS DE BACKUP
# ============================================
print_step "6. INSTALANDO FERRAMENTAS DE BACKUP"

# Instalar ferramentas de backup
apt install -y automysqlbackup

# Configurar backup automático
cat > /etc/automysqlbackup/automysqlbackup.conf << EOF
# Configuração do AutoMySQLBackup para YouTube Audio Bot

# Usuário e senha do MySQL
USERNAME=root
PASSWORD=$MYSQL_ROOT_PASS
DBHOST=localhost

# Diretórios de backup
BACKUPDIR="/var/backups/mysql"
CONFIG_backup_dir="/var/backups/mysql"

# Opções de backup
DBNAMES="youtube_audio_bot"
DBEXCLUDE="information_schema performance_schema"
CREATE_DATABASE=yes
SEPDIR=yes
COMP=yes

# Agendamento
DOWEEKLY=6
COMMCOMP="gzip"

# Retenção
BACKUP_RETention_DAYS=30
EOF

# Criar diretório de backups
mkdir -p /var/backups/mysql
chmod 700 /var/backups/mysql

# Testar backup
automysqlbackup /etc/automysqlbackup/automysqlbackup.conf

print_message "✅ Ferramentas de backup instaladas"

# ============================================
# PASSO 7: CRIAR SCRIPT DE GERENCIAMENTO
# ============================================
print_step "7. CRIANDO SCRIPTS DE GERENCIAMENTO"

# Script para backup manual
cat > /usr/local/bin/db-backup << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/mysql/manual"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/youtube_audio_bot_$TIMESTAMP.sql.gz"

mkdir -p $BACKUP_DIR

echo "💾 Criando backup do banco de dados..."
mysqldump --single-transaction --quick --lock-tables=false \
    -u root -p$(cat /root/.mysql_root_pass | cut -d'=' -f2) \
    youtube_audio_bot | gzip > $BACKUP_FILE

SIZE=$(du -h $BACKUP_FILE | cut -f1)
echo "✅ Backup criado: $BACKUP_FILE ($SIZE)"

# Manter últimos 7 backups
ls -t $BACKUP_DIR/*.sql.gz | tail -n +8 | xargs -r rm
echo "🧹 Mantidos últimos 7 backups"
EOF

chmod +x /usr/local/bin/db-backup

# Script para restore
cat > /usr/local/bin/db-restore << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Uso: db-restore <arquivo_backup.sql.gz>"
    echo ""
    echo "Backups disponíveis:"
    ls -lh /var/backups/mysql/manual/*.sql.gz 2>/dev/null || echo "Nenhum backup encontrado"
    exit 1
fi

BACKUP_FILE="$1"
if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Arquivo não encontrado: $BACKUP_FILE"
    exit 1
fi

echo "⚠️  ATENÇÃO: Isso irá SOBRESCREVER o banco de dados atual!"
read -p "Tem certeza? (digite 'SIM' para confirmar): " CONFIRM

if [ "$CONFIRM" != "SIM" ]; then
    echo "❌ Restore cancelado"
    exit 1
fi

echo "🔄 Restaurando banco de dados..."
gunzip -c "$BACKUP_FILE" | mysql -u root -p$(cat /root/.mysql_root_pass | cut -d'=' -f2) youtube_audio_bot

echo "✅ Banco de dados restaurado de: $BACKUP_FILE"
EOF

chmod +x /usr/local/bin/db-restore

# Script para monitoramento
cat > /usr/local/bin/db-status << 'EOF'
#!/bin/bash
echo "=== STATUS DO MYSQL ==="
echo ""
echo "📊 Versão do MySQL:"
mysql --version
echo ""
echo "🔌 Conexões ativas:"
mysql -u root -p$(cat /root/.mysql_root_pass | cut -d'=' -f2) -e "SHOW STATUS LIKE 'Threads_connected';"
echo ""
echo "💾 Uso de storage:"
mysql -u root -p$(cat /root/.mysql_root_pass | cut -d'=' -f2) youtube_audio_bot -e "
SELECT 
    table_schema as 'Database',
    SUM(data_length + index_length) / 1024 / 1024 as 'Size (MB)'
FROM information_schema.tables
WHERE table_schema = 'youtube_audio_bot'
GROUP BY table_schema;
"
echo ""
echo "📈 Tabelas e registros:"
mysql -u root -p$(cat /root/.mysql_root_pass | cut -d'=' -f2) youtube_audio_bot -e "
SELECT 
    TABLE_NAME as 'Tabela',
    TABLE_ROWS as 'Registros',
    ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) as 'Tamanho (MB)'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'youtube_audio_bot'
ORDER BY TABLE_ROWS DESC;
"
echo ""
echo "📅 Último backup:"
ls -lt /var/backups/mysql/manual/*.sql.gz 2>/dev/null | head -5
EOF

chmod +x /usr/local/bin/db-status

print_message "✅ Scripts de gerenciamento criados"

# ============================================
# PASSO 8: CONFIGURAR CRONTAB PARA BACKUP
# ============================================
print_step "8. CONFIGURANDO BACKUP AUTOMÁTICO"

# Adicionar ao crontab
(crontab -l 2>/dev/null; echo "# Backup diário do banco de dados às 2 AM") | crontab -
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/db-backup") | crontab -
(crontab -l 2>/dev/null; echo "# Limpeza de backups antigos semanalmente") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * 0 find /var/backups/mysql -name '*.gz' -mtime +30 -delete") | crontab -

print_message "✅ Backup automático configurado"

# ============================================
# PASSO 9: FINALIZAÇÃO
# ============================================
print_step "9. FINALIZANDO INSTALAÇÃO"

# Testar conexão
if mysql -u youtube_bot_user -p'BotSecurePass123!' -e "USE youtube_audio_bot; SELECT '✅ Conexão OK' as status;" 2>/dev/null; then
    print_message "✅ Conexão com o banco de dados testada com sucesso"
else
    print_error "❌ Falha na conexão com o banco de dados"
    print_warning "Verifique as credenciais em /root/.bot_db_creds"
fi

# Resumo da instalação
echo ""
echo "================================================"
echo "🎉 MYSQL INSTALADO E CONFIGURADO COM SUCESSO!"
echo "================================================"
echo ""
echo "📊 INFORMAÇÕES DO BANCO DE DADOS:"
echo "   Host: localhost"
echo "   Banco: youtube_audio_bot"
echo "   Usuário: youtube_bot_user"
echo "   Senha: BotSecurePass123! (altere em produção)"
echo ""
echo "🔧 COMANDOS DISPONÍVEIS:"
echo "   db-status      - Ver status do banco"
echo "   db-backup      - Criar backup manual"
echo "   db-restore     - Restaurar de backup"
echo ""
echo "💾 BACKUP AUTOMÁTICO:"
echo "   Diariamente às 2:00 AM"
echo "   Diretório: /var/backups/mysql/"
echo ""
echo "🔒 CREDENCIAIS SALVAS EM:"
echo "   Root MySQL: /root/.mysql_root_pass"
echo "   Bot DB: /root/.bot_db_creds"
echo ""
echo "⚠️  IMPORTANTE:"
echo "   1. Altere a senha do usuário do bot em produção!"
echo "   2. Configure firewall para permitir apenas localhost"
echo "   3. Monitore os logs: /var/log/mysql/error.log"
echo ""
echo "================================================"
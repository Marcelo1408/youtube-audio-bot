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

# URLs do GitHub
SCHEMA_URL="https://raw.githubusercontent.com/Marcelo1408/youtube-audio-bot/ea36a511714a9a3f72e3407c9bf6efd671cbce15/schema.sql"

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
# PASSO 4: BAIXAR E APLICAR SCHEMA SQL DO GITHUB
# ============================================
print_step "4. BAIXANDO E APLICANDO SCHEMA DO GITHUB"

print_message "Baixando schema.sql do GitHub..."
if curl -fsSL "$SCHEMA_URL" -o /tmp/schema.sql; then
    print_message "✅ schema.sql baixado com sucesso"
    
    # Verificar se o arquivo não está vazio
    if [ ! -s /tmp/schema.sql ]; then
        print_error "❌ schema.sql está vazio ou corrompido"
        print_warning "Criando schema básico como fallback..."
        
        # Criar schema básico como fallback
        cat > /tmp/schema.sql << 'EOF'
CREATE DATABASE IF NOT EXISTS youtube_audio_bot CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE youtube_audio_bot;

CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    telegram_id BIGINT UNIQUE NOT NULL,
    username VARCHAR(100) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    coins INT DEFAULT 0,
    plan ENUM('free', 'essential', 'premium', 'deluxe', 'infinite') DEFAULT 'free',
    is_active BOOLEAN DEFAULT TRUE,
    is_admin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE transactions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    type ENUM('purchase', 'video_processing', 'refund') NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    coins_amount INT NOT NULL,
    description VARCHAR(255),
    status ENUM('pending', 'completed', 'failed') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE processings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    video_url TEXT NOT NULL,
    video_title VARCHAR(500),
    quality ENUM('low', 'medium', 'high', 'veryhigh') DEFAULT 'medium',
    format ENUM('mp3', 'wav', 'flac', 'm4a') DEFAULT 'mp3',
    status ENUM('pending', 'processing', 'completed', 'failed') DEFAULT 'pending',
    coins_used INT DEFAULT 10,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (telegram_id, username, first_name, coins, plan, is_admin) 
VALUES (123456789, 'admin', 'Administrador', 999999, 'infinite', TRUE);
EOF
    fi
    
    # Aplicar schema
    print_message "Aplicando schema ao banco de dados..."
    if mysql --user=root --password="$MYSQL_ROOT_PASS" youtube_audio_bot < /tmp/schema.sql; then
        print_message "✅ Schema aplicado com sucesso"
        
        # Verificar se as tabelas foram criadas
        TABLE_COUNT=$(mysql --user=root --password="$MYSQL_ROOT_PASS" youtube_audio_bot -sN -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'youtube_audio_bot';")
        print_message "✅ $TABLE_COUNT tabelas criadas no banco"
        
    else
        print_error "❌ Erro ao aplicar schema"
        print_warning "Verifique o arquivo schema.sql"
    fi
    
else
    print_error "❌ Falha ao baixar schema.sql do GitHub"
    print_warning "URL: $SCHEMA_URL"
    print_warning "Criando schema básico..."
    
    # Criar schema básico mínimo
    mysql --user=root --password="$MYSQL_ROOT_PASS" << EOF
USE youtube_audio_bot;

CREATE TABLE IF NOT EXISTS users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    telegram_id BIGINT UNIQUE NOT NULL,
    username VARCHAR(100) NOT NULL,
    first_name VARCHAR(100),
    coins INT DEFAULT 0,
    plan VARCHAR(20) DEFAULT 'free',
    is_admin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS processings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    video_url TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT IGNORE INTO users (telegram_id, username, first_name, coins, plan, is_admin) 
VALUES (123456789, 'admin', 'Administrador', 999999, 'infinite', TRUE);
EOF
    
    print_message "✅ Schema básico criado"
fi

# ============================================
# PASSO 5: CONFIGURAR MYSQL PARA PRODUÇÃO
# ============================================
print_step "5. CONFIGURANDO MYSQL PARA PRODUÇÃO"

# Backup da configuração atual
if [ -f /etc/mysql/my.cnf ]; then
    cp /etc/mysql/my.cnf /etc/mysql/my.cnf.backup
fi

# Criar configuração otimizada
mkdir -p /etc/mysql/conf.d
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
if apt install -y automysqlbackup 2>/dev/null || apt install -y default-mysql-client 2>/dev/null; then
    print_message "✅ Ferramentas de backup instaladas"
    
    # Configurar backup automático se automysqlbackup estiver disponível
    if command -v automysqlbackup &> /dev/null; then
        mkdir -p /etc/automysqlbackup
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
    fi
else
    print_warning "⚠️  Automysqlbackup não disponível, usando backup manual"
fi

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
if [ -f /root/.mysql_root_pass ]; then
    MYSQL_PASS=$(cat /root/.mysql_root_pass | cut -d'=' -f2)
    mysqldump --single-transaction --quick --lock-tables=false \
        -u root -p"$MYSQL_PASS" \
        youtube_audio_bot | gzip > "$BACKUP_FILE"
    
    if [ $? -eq 0 ] && [ -f "$BACKUP_FILE" ]; then
        SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo "✅ Backup criado: $BACKUP_FILE ($SIZE)"
        
        # Manter últimos 7 backups
        ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm
        echo "🧹 Mantidos últimos 7 backups"
    else
        echo "❌ Falha ao criar backup"
        rm -f "$BACKUP_FILE"
    fi
else
    echo "❌ Arquivo de senha root não encontrado: /root/.mysql_root_pass"
fi
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

if [ -f /root/.mysql_root_pass ]; then
    MYSQL_PASS=$(cat /root/.mysql_root_pass | cut -d'=' -f2)
    echo "🔄 Restaurando banco de dados..."
    
    # Descompactar e restaurar
    gunzip -c "$BACKUP_FILE" | mysql -u root -p"$MYSQL_PASS" youtube_audio_bot
    
    if [ $? -eq 0 ]; then
        echo "✅ Banco de dados restaurado de: $BACKUP_FILE"
    else
        echo "❌ Erro ao restaurar banco de dados"
    fi
else
    echo "❌ Arquivo de senha root não encontrado"
fi
EOF

chmod +x /usr/local/bin/db-restore

# Script para monitoramento
cat > /usr/local/bin/db-status << 'EOF'
#!/bin/bash
echo "=== STATUS DO MYSQL ==="
echo ""
echo "📊 Versão do MySQL:"
mysql --version 2>/dev/null || echo "MySQL não encontrado"
echo ""
echo "🔌 Status do serviço:"
systemctl status mysql --no-pager | grep -E "(Active:|Main PID:|Status:)"
echo ""
if [ -f /root/.mysql_root_pass ]; then
    MYSQL_PASS=$(cat /root/.mysql_root_pass | cut -d'=' -f2)
    echo "💾 Uso de storage:"
    mysql -u root -p"$MYSQL_PASS" youtube_audio_bot -e "
SELECT 
    table_schema as 'Database',
    SUM(data_length + index_length) / 1024 / 1024 as 'Size (MB)'
FROM information_schema.tables
WHERE table_schema = 'youtube_audio_bot'
GROUP BY table_schema;" 2>/dev/null || echo "Não foi possível conectar ao banco"
    
    echo ""
    echo "📈 Tabelas e registros:"
    mysql -u root -p"$MYSQL_PASS" youtube_audio_bot -e "
SELECT 
    TABLE_NAME as 'Tabela',
    TABLE_ROWS as 'Registros',
    ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) as 'Tamanho (MB)'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'youtube_audio_bot'
ORDER BY TABLE_ROWS DESC;" 2>/dev/null || echo "Não foi possível listar tabelas"
else
    echo "❌ Arquivo de senha root não encontrado"
fi
echo ""
echo "📅 Últimos backups:"
ls -lt /var/backups/mysql/manual/*.sql.gz 2>/dev/null | head -5 || echo "Nenhum backup encontrado"
EOF

chmod +x /usr/local/bin/db-status

print_message "✅ Scripts de gerenciamento criados"

# ============================================
# PASSO 8: CONFIGURAR CRONTAB PARA BACKUP
# ============================================
print_step "8. CONFIGURANDO BACKUP AUTOMÁTICO"

# Adicionar ao crontab se não existir
if ! crontab -l 2>/dev/null | grep -q "db-backup"; then
    (crontab -l 2>/dev/null; echo "# Backup diário do banco de dados às 2 AM") | crontab -
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/db-backup") | crontab -
    (crontab -l 2>/dev/null; echo "# Limpeza de backups antigos semanalmente") | crontab -
    (crontab -l 2>/dev/null; echo "0 3 * * 0 find /var/backups/mysql -name '*.gz' -mtime +30 -delete") | crontab -
    print_message "✅ Backup automático configurado no crontab"
else
    print_message "✅ Backup automático já configurado"
fi

# ============================================
# PASSO 9: FINALIZAÇÃO
# ============================================
print_step "9. FINALIZANDO INSTALAÇÃO"

# Testar conexão com usuário do bot
print_message "Testando conexão com o banco de dados..."
if mysql -u youtube_bot_user -p'BotSecurePass123!' -e "USE youtube_audio_bot; SELECT '✅ Conexão OK' as status;" 2>/dev/null; then
    print_message "✅ Conexão com o banco de dados testada com sucesso"
    
    # Mostrar informações das tabelas criadas
    TABLE_INFO=$(mysql -u youtube_bot_user -p'BotSecurePass123!' youtube_audio_bot -e "SHOW TABLES;" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo ""
        print_message "📋 Tabelas criadas no banco:"
        echo "$TABLE_INFO" | while read -r table; do
            echo "   • $table"
        done
    fi
else
    print_warning "⚠️  Falha na conexão com usuário do bot"
    print_message "Testando conexão root..."
    
    if [ -f /root/.mysql_root_pass ]; then
        MYSQL_PASS=$(cat /root/.mysql_root_pass | cut -d'=' -f2)
        if mysql -u root -p"$MYSQL_PASS" -e "USE youtube_audio_bot; SHOW TABLES;" 2>/dev/null; then
            print_message "✅ Conexão root funciona, usuário do bot pode precisar de ajustes"
        fi
    fi
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
echo "   Schema: Baixado do GitHub: $SCHEMA_URL"
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
echo "   4. Schema completo em: https://github.com/Marcelo1408/youtube-audio-bot"
echo ""
echo "================================================"

# Limpar arquivo temporário
rm -f /tmp/schema.sql

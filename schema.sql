-- Banco de dados: youtube_audio_bot
CREATE DATABASE IF NOT EXISTS youtube_audio_bot;
USE youtube_audio_bot;

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
    start_time INT, -- em segundos
    end_time INT, -- em segundos
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

-- Stored procedures
DELIMITER //

CREATE PROCEDURE sp_add_coins_to_user(
    IN p_user_id INT,
    IN p_coins_amount INT,
    IN p_reason VARCHAR(255),
    IN p_admin_id INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Adicionar moedas ao usuário
    UPDATE users 
    SET coins = coins + p_coins_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_user_id;
    
    -- Registrar transação
    INSERT INTO transactions (
        user_id,
        telegram_id,
        type,
        amount,
        coins_amount,
        description,
        status,
        created_at
    )
    SELECT 
        p_user_id,
        u.telegram_id,
        'admin_add',
        0.00,
        p_coins_amount,
        CONCAT('Adição manual por admin #', p_admin_id, ': ', p_reason),
        'completed',
        CURRENT_TIMESTAMP
    FROM users u
    WHERE u.id = p_user_id;
    
    -- Log
    INSERT INTO system_logs (user_id, log_type, message, metadata)
    VALUES (
        p_admin_id,
        'info',
        CONCAT('Admin adicionou ', p_coins_amount, ' moedas ao usuário ID:', p_user_id),
        JSON_OBJECT('user_id', p_user_id, 'coins', p_coins_amount, 'reason', p_reason)
    );
    
    COMMIT;
END //

CREATE PROCEDURE sp_process_video_payment(
    IN p_user_id INT,
    IN p_video_url TEXT,
    IN p_video_title VARCHAR(500),
    IN p_quality ENUM('low', 'medium', 'high', 'veryhigh'),
    IN p_format ENUM('mp3', 'wav', 'flac', 'm4a')
)
BEGIN
    DECLARE v_user_coins INT;
    DECLARE v_coins_per_video INT;
    DECLARE v_processing_id INT;
    DECLARE v_user_plan VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Obter informações do usuário
    SELECT coins, plan INTO v_user_coins, v_user_plan
    FROM users 
    WHERE id = p_user_id
    FOR UPDATE;
    
    -- Obter configuração do sistema
    SELECT CAST(setting_value AS UNSIGNED) INTO v_coins_per_video
    FROM system_settings
    WHERE setting_key = 'coins_per_video';
    
    -- Verificar se tem moedas suficientes (exceto plano infinito)
    IF v_user_plan != 'infinite' AND v_user_coins < v_coins_per_video THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Moedas insuficientes';
    END IF;
    
    -- Criar registro de processamento
    INSERT INTO processings (
        user_id,
        video_url,
        video_title,
        quality,
        format,
        status,
        coins_used,
        created_at
    ) VALUES (
        p_user_id,
        p_video_url,
        p_video_title,
        p_quality,
        p_format,
        'pending',
        CASE WHEN v_user_plan = 'infinite' THEN 0 ELSE v_coins_per_video END,
        CURRENT_TIMESTAMP
    );
    
    SET v_processing_id = LAST_INSERT_ID();
    
    -- Debitar moedas (exceto plano infinito)
    IF v_user_plan != 'infinite' THEN
        UPDATE users 
        SET coins = coins - v_coins_per_video,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_user_id;
        
        -- Registrar transação
        INSERT INTO transactions (
            user_id,
            telegram_id,
            type,
            amount,
            coins_amount,
            description,
            status,
            created_at
        )
        SELECT 
            p_user_id,
            u.telegram_id,
            'video_processing',
            0.00,
            v_coins_per_video * -1,
            CONCAT('Processamento de vídeo: ', LEFT(p_video_title, 100)),
            'completed',
            CURRENT_TIMESTAMP
        FROM users u
        WHERE u.id = p_user_id;
    END IF;
    
    COMMIT;
    
    -- Retornar ID do processamento
    SELECT v_processing_id as processing_id;
END //

CREATE PROCEDURE sp_create_pix_payment(
    IN p_user_id INT,
    IN p_amount DECIMAL(10,2),
    IN p_coins_amount INT,
    IN p_plan_type VARCHAR(50)
)
BEGIN
    DECLARE v_pix_code VARCHAR(512);
    DECLARE v_expires_at DATETIME;
    DECLARE v_payment_id INT;
    DECLARE v_expiration_minutes INT;
    
    -- Obter tempo de expiração
    SELECT CAST(setting_value AS UNSIGNED) INTO v_expiration_minutes
    FROM system_settings
    WHERE setting_key = 'pix_expiration_minutes';
    
    SET v_expires_at = DATE_ADD(NOW(), INTERVAL v_expiration_minutes MINUTE);
    
    -- Gerar código PIX (simulação - em produção use API do Mercado Pago)
    SET v_pix_code = CONCAT(
        '00020126580014BR.GOV.BCB.PIX0136',
        UUID(),
        '520400005303986540',
        LPAD(ROUND(p_amount * 100), 13, '0'),
        '5802BR5925',
        (SELECT username FROM users WHERE id = p_user_id),
        '6009SAO PAULO62070503***6304'
    );
    
    -- Criar transação
    INSERT INTO transactions (
        user_id,
        telegram_id,
        type,
        amount,
        coins_amount,
        description,
        status,
        created_at
    )
    SELECT 
        p_user_id,
        u.telegram_id,
        'purchase',
        p_amount,
        p_coins_amount,
        CONCAT('Compra de ', p_coins_amount, ' moedas - Plano ', p_plan_type),
        'pending',
        CURRENT_TIMESTAMP
    FROM users u
    WHERE u.id = p_user_id;
    
    SET v_payment_id = LAST_INSERT_ID();
    
    -- Criar registro PIX
    INSERT INTO pix_payments (
        user_id,
        transaction_id,
        pix_code,
        amount,
        coins_amount,
        plan_type,
        status,
        expires_at,
        created_at
    ) VALUES (
        p_user_id,
        v_payment_id,
        v_pix_code,
        p_amount,
        p_coins_amount,
        p_plan_type,
        'pending',
        v_expires_at,
        CURRENT_TIMESTAMP
    );
    
    -- Retornar dados do PIX
    SELECT 
        pp.id as pix_id,
        pp.pix_code,
        pp.amount,
        pp.coins_amount,
        pp.expires_at,
        pp.created_at,
        u.telegram_id,
        u.username
    FROM pix_payments pp
    JOIN users u ON pp.user_id = u.id
    WHERE pp.id = LAST_INSERT_ID();
END //

CREATE PROCEDURE sp_confirm_pix_payment(
    IN p_pix_id INT,
    IN p_payment_data JSON
)
BEGIN
    DECLARE v_user_id INT;
    DECLARE v_coins_amount INT;
    DECLARE v_transaction_id INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Verificar se o PIX ainda está pendente e não expirado
    SELECT user_id, coins_amount, transaction_id 
    INTO v_user_id, v_coins_amount, v_transaction_id
    FROM pix_payments 
    WHERE id = p_pix_id 
      AND status = 'pending'
      AND expires_at > NOW()
    FOR UPDATE;
    
    IF v_user_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pagamento não encontrado, expirado ou já processado';
    END IF;
    
    -- Atualizar status do PIX
    UPDATE pix_payments 
    SET 
        status = 'paid',
        paid_at = NOW(),
        payment_data = p_payment_data
    WHERE id = p_pix_id;
    
    -- Atualizar status da transação
    UPDATE transactions 
    SET 
        status = 'completed',
        payment_id = JSON_UNQUOTE(JSON_EXTRACT(p_payment_data, '$.id'))
    WHERE id = v_transaction_id;
    
    -- Adicionar moedas ao usuário
    UPDATE users 
    SET coins = coins + v_coins_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_user_id;
    
    -- Registrar log
    INSERT INTO system_logs (user_id, log_type, message, metadata)
    VALUES (
        v_user_id,
        'payment',
        CONCAT('Pagamento PIX confirmado: ', v_coins_amount, ' moedas'),
        JSON_OBJECT('pix_id', p_pix_id, 'coins', v_coins_amount, 'payment_data', p_payment_data)
    );
    
    COMMIT;
    
    -- Retornar dados atualizados
    SELECT 
        'success' as result,
        v_coins_amount as coins_added,
        (SELECT coins FROM users WHERE id = v_user_id) as new_balance;
END //

DELIMITER ;

-- Triggers
DELIMITER //

CREATE TRIGGER trg_check_daily_limit
BEFORE INSERT ON processings
FOR EACH ROW
BEGIN
    DECLARE v_daily_count INT;
    DECLARE v_max_daily INT;
    DECLARE v_user_plan VARCHAR(20);
    
    -- Obter plano do usuário
    SELECT plan INTO v_user_plan
    FROM users 
    WHERE id = NEW.user_id;
    
    -- Se for plano infinito, não aplicar limite
    IF v_user_plan != 'infinite' THEN
        -- Obter limite diário
        SELECT CAST(setting_value AS UNSIGNED) INTO v_max_daily
        FROM system_settings
        WHERE setting_key = 'max_daily_videos';
        
        -- Contar processamentos do dia
        SELECT COUNT(*) INTO v_daily_count
        FROM processings
        WHERE user_id = NEW.user_id
          AND DATE(created_at) = CURDATE();
        
        -- Verificar limite
        IF v_daily_count >= v_max_daily THEN
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = CONCAT('Limite diário de ', v_max_daily, ' vídeos atingido');
        END IF;
    END IF;
END //

CREATE TRIGGER trg_update_user_plan_on_purchase
AFTER UPDATE ON transactions
FOR EACH ROW
BEGIN
    DECLARE v_total_purchased DECIMAL(10,2);
    
    -- Se for uma compra concluída
    IF NEW.type = 'purchase' AND NEW.status = 'completed' AND OLD.status != 'completed' THEN
        -- Calcular total gasto pelo usuário
        SELECT SUM(amount) INTO v_total_purchased
        FROM transactions
        WHERE user_id = NEW.user_id
          AND type = 'purchase'
          AND status = 'completed';
        
        -- Atualizar plano baseado no total gasto
        IF v_total_purchased >= 100.00 THEN
            UPDATE users 
            SET plan = 'deluxe',
                updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.user_id
              AND plan != 'infinite';
        ELSEIF v_total_purchased >= 50.00 THEN
            UPDATE users 
            SET plan = 'premium',
                updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.user_id
              AND plan != 'infinite';
        ELSEIF v_total_purchased >= 20.00 THEN
            UPDATE users 
            SET plan = 'essential',
                updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.user_id
              AND plan != 'infinite';
        END IF;
    END IF;
END //

DELIMITER ;

-- Criar usuário para o bot (ajuste a senha)
CREATE USER 'youtube_bot_user'@'localhost' IDENTIFIED BY 'SuaSenhaSegura123!';
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON youtube_audio_bot.* TO 'youtube_bot_user'@'localhost';
FLUSH PRIVILEGES;
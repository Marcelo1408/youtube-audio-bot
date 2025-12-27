require('dotenv').config();
const TelegramBot = require('node-telegram-bot-api');
const express = require('express');
const db = require('./config/database');
const DownloadService = require('./services/downloadService');
const ProcessingWorker = require('./workers/processingWorker');

const app = express();
const PORT = process.env.PORT || 3000;

// Inicializar bot
const bot = new TelegramBot(process.env.TELEGRAM_BOT_TOKEN, { 
    polling: true,
    filepath: false // Não baixar arquivos localmente
});

// Inicializar worker de processamento
const processingWorker = new ProcessingWorker(bot);

// Configurar endpoints para download
DownloadService.createDirectDownloadEndpoint(app, bot);

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({
        status: 'OK',
        timestamp: new Date(),
        queue: processingWorker.getQueueStatus(),
        storage: {
            downloadsDir: process.env.DOWNLOAD_DIR,
            freeSpace: require('check-disk-space').sync(process.env.DOWNLOAD_DIR).free
        }
    });
});

// Status endpoint para admin
app.get('/admin/status', async (req, res) => {
    // Verificar autenticação (implementar)
    const stats = {
        bot: {
            isRunning: true,
            uptime: process.uptime()
        },
        database: await db.ping(),
        processing: processingWorker.getQueueStatus(),
        system: {
            memory: process.memoryUsage(),
            uptime: os.uptime()
        }
    };
    res.json(stats);
});

// Iniciar servidor
app.listen(PORT, () => {
    console.log(`🚀 Servidor rodando na porta ${PORT}`);
    console.log(`📁 Downloads em: ${process.env.DOWNLOAD_DIR}`);
    console.log(`🤖 Bot iniciado!`);
});

// Comando para status do sistema (admin)
bot.onText(/\/status/, async (msg) => {
    const user = await User.findByTelegramId(msg.from.id);
    
    if (user && user.is_admin) {
        const queueStatus = processingWorker.getQueueStatus();
        
        bot.sendMessage(msg.chat.id,
            `⚙️ *Status do Sistema*\n\n` +
            `📊 **Fila de Processamento:**\n` +
            `• Em processamento: ${queueStatus.isProcessing ? 'Sim' : 'Não'}\n` +
            `• Tamanho da fila: ${queueStatus.queueLength}\n\n` +
            `💾 **Armazenamento:**\n` +
            `• Diretório: ${process.env.DOWNLOAD_DIR}\n` +
            `• Uso: ${await getStorageUsage()}\n\n` +
            `🔄 **Bot:**\n` +
            `• Status: Online\n` +
            `• Uptime: ${formatUptime(process.uptime())}`,
            { parse_mode: 'Markdown' }
        );
    }
});

// Limpeza automática de arquivos antigos
setInterval(async () => {
    const dir = process.env.DOWNLOAD_DIR;
    const files = fs.readdirSync(dir);
    const now = Date.now();
    const maxAge = 24 * 60 * 60 * 1000; // 24 horas
    
    for (const file of files) {
        const filePath = path.join(dir, file);
        const stat = fs.statSync(filePath);
        
        if (now - stat.mtime.getTime() > maxAge) {
            try {
                if (fs.lstatSync(filePath).isDirectory()) {
                    fs.rmSync(filePath, { recursive: true });
                } else {
                    fs.unlinkSync(filePath);
                }
                console.log(`🧹 Limpado: ${file}`);
            } catch (error) {
                console.error(`Erro ao limpar ${file}:`, error.message);
            }
        }
    }
}, 60 * 60 * 1000); // A cada hora

// Funções auxiliares
async function getStorageUsage() {
    const disk = require('check-disk-space').sync(process.env.DOWNLOAD_DIR);
    const used = disk.size - disk.free;
    const usedPercent = ((used / disk.size) * 100).toFixed(1);
    return `${(used / 1024 / 1024 / 1024).toFixed(2)}GB/${(disk.size / 1024 / 1024 / 1024).toFixed(2)}GB (${usedPercent}%)`;
}

function formatUptime(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    return `${hours}h ${minutes}m`;
}
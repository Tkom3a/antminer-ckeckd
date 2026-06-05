#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}antminer-checkd Installation Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}⚠️  Запуск с sudo для установки Docker...${NC}"
    exec sudo "$0" "$@"
fi

# --- КОНФИГУРАЦИЯ ---
REPO_URL="https://github.com/Tkom3a/antminer-ckeckd.git"
INSTALL_DIR="/opt/antminer-checkd"
# -------------------

# Функция для запроса данных у пользователя
ask_config() {
    echo -e "${CYAN}📝 Настройка мониторинга ASIC${NC}"
    echo -e "${YELLOW}Пожалуйста, введите следующие данные:${NC}"
    echo ""
    
    # ASIC IP
    read -p "$(echo -e ${BLUE}IP адрес ASIC: ${NC})" ASIC_IP
    while [ -z "$ASIC_IP" ]; do
        echo -e "${RED}IP адрес не может быть пустым${NC}"
        read -p "$(echo -e ${BLUE}IP адрес ASIC: ${NC})" ASIC_IP
    done
    
    # ASIC Port
    read -p "$(echo -e ${BLUE}Порт веб-интерфейса ASIC [80]: ${NC})" ASIC_PORT
    ASIC_PORT=${ASIC_PORT:-80}
    
    # ASIC Username
    read -p "$(echo -e ${BLUE}Имя пользователя ASIC [root]: ${NC})" ASIC_USER
    ASIC_USER=${ASIC_USER:-root}
    
    # ASIC Password
    read -s -p "$(echo -e ${BLUE}Пароль ASIC: ${NC})" ASIC_PASSWORD
    echo ""
    while [ -z "$ASIC_PASSWORD" ]; do
        echo -e "${RED}Пароль не может быть пустым${NC}"
        read -s -p "$(echo -e ${BLUE}Пароль ASIC: ${NC})" ASIC_PASSWORD
        echo ""
    done
    
    echo ""
    
    # Telegram Token
    read -p "$(echo -e ${BLUE}Telegram Bot Token: ${NC})" TELEGRAM_TOKEN
    while [ -z "$TELEGRAM_TOKEN" ]; do
        echo -e "${RED}Telegram Token не может быть пустым${NC}"
        read -p "$(echo -e ${BLUE}Telegram Bot Token: ${NC})" TELEGRAM_TOKEN
    done
    
    # Telegram Chat ID
    read -p "$(echo -e ${BLUE}Telegram Chat ID: ${NC})" TELEGRAM_CHAT_ID
    while [ -z "$TELEGRAM_CHAT_ID" ]; do
        echo -e "${RED}Telegram Chat ID не может быть пустым${NC}"
        read -p "$(echo -e ${BLUE}Telegram Chat ID: ${NC})" TELEGRAM_CHAT_ID
    done
    
    # Min Hashrate
    read -p "$(echo -e ${BLUE}Минимальный хэшрейт в TH/s [80]: ${NC})" MIN_HASHRATE
    MIN_HASHRATE=${MIN_HASHRATE:-80}
    
    # Check Interval
    read -p "$(echo -e ${BLUE}Интервал проверки в секундах [300]: ${NC})" CHECK_INTERVAL
    CHECK_INTERVAL=${CHECK_INTERVAL:-300}
    
    echo ""
    echo -e "${GREEN}✅ Данные сохранены${NC}"
    echo ""
}

# Функция проверки подключения к ASIC
test_connection() {
    echo -e "${CYAN}🔍 Проверка подключения к ASIC...${NC}"
    
    # Пробуем подключиться через digest auth
    if curl -s --digest -u "${ASIC_USER}:${ASIC_PASSWORD}" \
        --connect-timeout 5 \
        "http://${ASIC_IP}:${ASIC_PORT}/cgi-bin/stats.cgi" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Подключение к ASIC успешно${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Не удалось подключиться к ASIC${NC}"
        echo -e "${YELLOW}   Проверьте IP, порт и пароль${NC}"
        read -p "Продолжить установку? (yes/no): " continue_anyway
        if [ "$continue_anyway" != "yes" ]; then
            exit 1
        fi
        return 1
    fi
}

# Функция проверки Telegram бота
test_telegram() {
    echo -e "${CYAN}📱 Проверка Telegram бота...${NC}"
    
    # Отправляем тестовое сообщение
    local test_message="🟢 <b>antminer-checkd</b> установка начата!"
    
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${test_message}" \
        -d "parse_mode=HTML" \
        --connect-timeout 10 > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Telegram бот работает${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Не удалось отправить сообщение в Telegram${NC}"
        echo -e "${YELLOW}   Проверьте Token и Chat ID${NC}"
        read -p "Продолжить установку? (yes/no): " continue_anyway
        if [ "$continue_anyway" != "yes" ]; then
            exit 1
        fi
        return 1
    fi
}

# Функция проверки и установки Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}🐳 Docker не установлен. Устанавливаем...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        echo -e "${GREEN}✓ Docker установлен${NC}"
    else
        echo -e "${GREEN}✓ Docker уже установлен${NC}"
    fi

    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}🐳 Docker Compose не установлен. Устанавливаем...${NC}"
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}✓ Docker Compose установлен${NC}"
    else
        echo -e "${GREEN}✓ Docker Compose уже установлен${NC}"
    fi
}

# Функция создания .env файла
create_env_file() {
    cat > "$INSTALL_DIR/.env" << EOF
# ASIC Configuration
ASIC_IP=${ASIC_IP}
ASIC_PORT=${ASIC_PORT}
ASIC_USER=${ASIC_USER}
ASIC_PASSWORD=${ASIC_PASSWORD}

# Telegram Configuration
TELEGRAM_TOKEN=${TELEGRAM_TOKEN}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}

# Monitoring Configuration
MIN_HASHRATE=${MIN_HASHRATE}
CHECK_INTERVAL=${CHECK_INTERVAL}
EOF
    
    echo -e "${GREEN}✓ Файл .env создан в $INSTALL_DIR/.env${NC}"
}

# Функция отправки финального сообщения в Telegram
send_final_notification() {
    local message="🟢 <b>antminer-checkd</b> установлен и запущен!\\n"
    message+="📊 Мониторинг ASIC ${ASIC_IP}:${ASIC_PORT}\\n"
    message+="🎯 Минимальный хэшрейт: ${MIN_HASHRATE} TH/s\\n"
    message+="⏱️  Интервал проверки: ${CHECK_INTERVAL} сек"
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" \
        --connect-timeout 10 > /dev/null 2>&1 || true
}

# ============= ОСНОВНАЯ ЛОГИКА =============

# 1. Проверка существующей установки
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}⚠️  Установка уже найдена в $INSTALL_DIR${NC}"
    echo ""
    echo -e "${BLUE}Выберите действие:${NC}"
    echo "  1) Обновить (сохранить настройки)"
    echo "  2) Переустановить (с очисткой)"
    echo "  3) Выход"
    read -p "Ваш выбор (1-3): " choice
    
    case $choice in
        1)
            echo -e "${BLUE}Обновляем antminer-checkd...${NC}"
            cd "$INSTALL_DIR"
            git pull
            docker-compose down
            docker-compose up -d --build
            echo -e "${GREEN}✅ Обновление завершено!${NC}"
            
            # Отправляем уведомление об обновлении
            if [ -f "$INSTALL_DIR/.env" ]; then
                source "$INSTALL_DIR/.env"
                send_final_notification
            fi
            exit 0
            ;;
        2)
            echo -e "${BLUE}Запускаем переустановку...${NC}"
            cd "$INSTALL_DIR"
            docker-compose down 2>/dev/null || true
            cd /
            rm -rf "$INSTALL_DIR"
            docker rmi antminer-checkd_antminer-checkd 2>/dev/null || true
            echo -e "${GREEN}✓ Старая установка удалена${NC}"
            echo ""
            ;;
        3)
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            exit 1
            ;;
    esac
fi

# 2. Запрос конфигурации
ask_config

# 3. Тестирование подключений
test_connection
test_telegram

# 4. Установка Docker (если нужно)
echo ""
install_docker

# 5. Клонирование репозитория
echo ""
echo -e "${BLUE}📦 Клонирование репозитория...${NC}"
git clone "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 6. Создание .env файла
create_env_file

# 7. Запуск контейнера
echo ""
echo -e "${BLUE}🚀 Запуск контейнера...${NC}"
mkdir -p logs
docker-compose up -d --build

# 8. Проверка статуса
sleep 5
if docker-compose ps | grep -q "Up"; then
    # Отправляем финальное уведомление
    send_final_notification
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ antminer-checkd успешно установлен!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}📊 Информация:${NC}"
    echo -e "  📁 Установлен в: $INSTALL_DIR"
    echo -e "  🐳 Контейнер: antminer-checkd"
    echo -e "  📝 Логи: docker-compose logs -f"
    echo -e "  🔄 Статус: docker-compose ps"
    echo ""
    echo -e "${BLUE}🔧 Управление:${NC}"
    echo -e "  cd $INSTALL_DIR"
    echo -e "  docker-compose restart  # Перезапуск"
    echo -e "  docker-compose stop     # Остановка"
    echo -e "  docker-compose logs -f  # Логи в реальном времени"
    echo ""
    echo -e "${BLUE}📝 Изменить настройки:${NC}"
    echo -e "  nano $INSTALL_DIR/.env"
    echo -e "  cd $INSTALL_DIR && docker-compose restart"
    echo ""
    echo -e "${BLUE}🗑️  Удаление:${NC}"
    echo -e "  sudo bash $INSTALL_DIR/uninstall.sh"
    echo ""
    echo -e "${GREEN}🔄 Контейнер будет автоматически запускаться после перезагрузки сервера!${NC}"
    echo -e "${GREEN}📱 Проверьте Telegram - должно прийти уведомление о запуске!${NC}"
else
    echo -e "${RED}❌ Ошибка при запуске контейнера${NC}"
    echo -e "${YELLOW}Логи ошибки:${NC}"
    docker-compose logs --tail=50
    exit 1
fi

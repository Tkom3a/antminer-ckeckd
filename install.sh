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
    echo -e "${YELLOW}⚠️  Запуск с sudo...${NC}"
    exec sudo "$0" "$@"
fi

REPO_URL="https://github.com/Tkom3a/antminer-ckeckd.git"
INSTALL_DIR="/opt/antminer-checkd"
ENV_FILE="$INSTALL_DIR/.env"

# Функция проверки заполненности .env файла
is_env_valid() {
    if [ ! -f "$ENV_FILE" ]; then
        return 1
    fi
    
    # Проверяем наличие и непустоту ключевых переменных
    source "$ENV_FILE" 2>/dev/null || return 1
    
    if [ -z "$ASIC_IP" ] || [ -z "$ASIC_PASSWORD" ] || [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return 1
    fi
    
    # Дополнительная проверка: пробуем подключиться к ASIC
    if ! curl -s --digest -u "${ASIC_USER:-root}:${ASIC_PASSWORD}" \
        --connect-timeout 5 \
        "http://${ASIC_IP}:${ASIC_PORT:-80}/cgi-bin/stats.cgi" > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  В .env файле указаны неверные данные для подключения к ASIC${NC}"
        return 1
    fi
    
    # Проверка Telegram
    if ! curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=🟢 antminer-checkd проверка подключения" \
        --connect-timeout 10 > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  В .env файле указаны неверные Telegram данные${NC}"
        return 1
    fi
    
    return 0
}

# Функция запроса данных у пользователя
ask_config() {
    echo -e "${CYAN}📝 Настройка мониторинга ASIC${NC}"
    echo -e "${YELLOW}Пожалуйста, введите следующие данные:${NC}"
    echo ""
    
    # IP адрес
    while true; do
        read -p "$(echo -e ${BLUE}IP адрес ASIC: ${NC})" ASIC_IP
        if [ -n "$ASIC_IP" ]; then
            break
        fi
        echo -e "${RED}IP адрес не может быть пустым${NC}"
    done
    
    # Порт
    read -p "$(echo -e ${BLUE}Порт веб-интерфейса ASIC [80]: ${NC})" ASIC_PORT
    ASIC_PORT=${ASIC_PORT:-80}
    
    # Имя пользователя
    read -p "$(echo -e ${BLUE}Имя пользователя ASIC [root]: ${NC})" ASIC_USER
    ASIC_USER=${ASIC_USER:-root}
    
    # Пароль
    while true; do
        read -s -p "$(echo -e ${BLUE}Пароль ASIC: ${NC})" ASIC_PASSWORD
        echo ""
        if [ -n "$ASIC_PASSWORD" ]; then
            break
        fi
        echo -e "${RED}Пароль не может быть пустым${NC}"
    done
    
    echo ""
    
    # Telegram Token
    while true; do
        read -p "$(echo -e ${BLUE}Telegram Bot Token: ${NC})" TELEGRAM_TOKEN
        if [ -n "$TELEGRAM_TOKEN" ]; then
            break
        fi
        echo -e "${RED}Telegram Token не может быть пустым${NC}"
    done
    
    # Telegram Chat ID
    while true; do
        read -p "$(echo -e ${BLUE}Telegram Chat ID: ${NC})" TELEGRAM_CHAT_ID
        if [ -n "$TELEGRAM_CHAT_ID" ]; then
            break
        fi
        echo -e "${RED}Telegram Chat ID не может быть пустым${NC}"
    done
    
    # Минимальный хэшрейт
    read -p "$(echo -e ${BLUE}Минимальный хэшрейт в TH/s [80]: ${NC})" MIN_HASHRATE
    MIN_HASHRATE=${MIN_HASHRATE:-80}
    
    # Интервал проверки
    read -p "$(echo -e ${BLUE}Интервал проверки в секундах [300]: ${NC})" CHECK_INTERVAL
    CHECK_INTERVAL=${CHECK_INTERVAL:-300}
    
    echo ""
    echo -e "${GREEN}✅ Данные сохранены${NC}"
    echo ""
}

# Функция создания/обновления .env файла
create_env_file() {
    # Создаем директорию если её нет
    mkdir -p "$INSTALL_DIR"
    
    cat > "$ENV_FILE" << EOF
ASIC_IP=${ASIC_IP}
ASIC_PORT=${ASIC_PORT}
ASIC_USER=${ASIC_USER}
ASIC_PASSWORD=${ASIC_PASSWORD}
TELEGRAM_TOKEN=${TELEGRAM_TOKEN}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
MIN_HASHRATE=${MIN_HASHRATE}
CHECK_INTERVAL=${CHECK_INTERVAL}
EOF
    
    echo -e "${GREEN}✓ Файл .env создан/обновлен в $ENV_FILE${NC}"
}

# Функция проверки подключения к ASIC
test_connection() {
    echo -e "${CYAN}🔍 Проверка подключения к ASIC...${NC}"
    
    if curl -s --digest -u "${ASIC_USER}:${ASIC_PASSWORD}" \
        --connect-timeout 5 \
        "http://${ASIC_IP}:${ASIC_PORT}/cgi-bin/stats.cgi" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Подключение к ASIC успешно${NC}"
        return 0
    else
        echo -e "${RED}✗ Не удалось подключиться к ASIC${NC}"
        echo -e "${YELLOW}   Проверьте IP: ${ASIC_IP}, порт: ${ASIC_PORT}, пароль${NC}"
        return 1
    fi
}

# Функция проверки Telegram
test_telegram() {
    echo -e "${CYAN}📱 Проверка Telegram бота...${NC}"
    
    local test_message="🟢 <b>antminer-checkd</b> установка завершена успешно!"
    
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${test_message}" \
        -d "parse_mode=HTML" \
        --connect-timeout 10 > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Telegram бот работает, отправлено тестовое сообщение${NC}"
        return 0
    else
        echo -e "${RED}✗ Не удалось отправить сообщение в Telegram${NC}"
        echo -e "${YELLOW}   Проверьте Token и Chat ID${NC}"
        return 1
    fi
}

# Функция установки Docker
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

    # Удаляем старый Docker Compose если есть
    if command -v docker-compose &> /dev/null; then
        OLD_VERSION=$(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [[ "$OLD_VERSION" == 1.* ]]; then
            echo -e "${YELLOW}⚠️  Обнаружена старая версия Docker Compose v${OLD_VERSION}. Обновляем...${NC}"
            sudo rm -f /usr/local/bin/docker-compose
            sudo apt-get remove docker-compose -y 2>/dev/null || true
        fi
    fi

    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}🐳 Устанавливаем Docker Compose v2...${NC}"
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}✓ Docker Compose v2 установлен${NC}"
    else
        echo -e "${GREEN}✓ Docker Compose уже установлен${NC}"
    fi
}

# Функция запуска контейнера
start_container() {
    echo ""
    echo -e "${BLUE}🚀 Запуск контейнера...${NC}"
    cd "$INSTALL_DIR"
    mkdir -p logs
    
    # Собираем и запускаем
    docker-compose down 2>/dev/null || true
    docker-compose up -d --build
    
    sleep 5
    if docker-compose ps | grep -q "Up"; then
        echo -e "${GREEN}✓ Контейнер успешно запущен${NC}"
        return 0
    else
        echo -e "${RED}✗ Ошибка запуска контейнера${NC}"
        docker-compose logs --tail=30
        return 1
    fi
}

# ============================================
# ОСНОВНАЯ ЛОГИКА
# ============================================

# 1. Проверяем существование и валидность .env файла
NEEDS_CONFIG=false

if [ -f "$ENV_FILE" ]; then
    echo -e "${CYAN}📄 Найден существующий файл .env${NC}"
    
    if is_env_valid; then
        echo -e "${GREEN}✓ Файл .env валиден и заполнен корректно${NC}"
        echo ""
        
        # Загружаем существующие настройки
        source "$ENV_FILE"
        
        echo -e "${BLUE}Текущие настройки:${NC}"
        echo -e "  ASIC IP: ${ASIC_IP}"
        echo -e "  ASIC Port: ${ASIC_PORT:-80}"
        echo -e "  Min Hashrate: ${MIN_HASHRATE:-80} TH/s"
        echo -e "  Check Interval: ${CHECK_INTERVAL:-300} сек"
        echo ""
        
        read -p "Использовать существующие настройки? (Y/n): " use_existing
        if [[ "$use_existing" =~ ^[Nn]$ ]]; then
            NEEDS_CONFIG=true
        fi
    else
        echo -e "${YELLOW}⚠️  Файл .env существует, но содержит неверные данные${NC}"
        NEEDS_CONFIG=true
    fi
else
    echo -e "${CYAN}📄 Файл .env не найден${NC}"
    NEEDS_CONFIG=true
fi

# 2. Если нужна конфигурация - запрашиваем данные
if [ "$NEEDS_CONFIG" = true ]; then
    ask_config
    create_env_file
else
    # Загружаем существующие настройки для проверки
    source "$ENV_FILE"
fi

# 3. Проверяем подключения
echo ""
test_connection || {
    echo -e "${RED}❌ Ошибка подключения к ASIC. Проверьте настройки в $ENV_FILE${NC}"
    exit 1
}

test_telegram || {
    echo -e "${RED}❌ Ошибка подключения к Telegram. Проверьте настройки в $ENV_FILE${NC}"
    exit 1
}

# 4. Устанавливаем Docker
install_docker

# 5. Клонируем или обновляем репозиторий
echo ""
if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${BLUE}📦 Обновление репозитория...${NC}"
    cd "$INSTALL_DIR"
    git pull
else
    echo -e "${BLUE}📦 Клонирование репозитория...${NC}"
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# 6. Обновляем .env файл в директории установки
create_env_file

# 7. Запускаем контейнер
start_container || exit 1

# 8. Финальное сообщение
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ antminer-checkd успешно установлен!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}📊 Информация:${NC}"
echo -e "  📁 Установлен в: $INSTALL_DIR"
echo -e "  🐳 Контейнер: antminer-checkd"
echo -e "  📝 Логи: cd $INSTALL_DIR && docker-compose logs -f"
echo ""
echo -e "${BLUE}🔧 Управление:${NC}"
echo -e "  cd $INSTALL_DIR"
echo -e "  docker-compose logs -f     # Просмотр логов"
echo -e "  docker-compose restart     # Перезапуск"
echo -e "  docker-compose stop        # Остановка"
echo ""
echo -e "${BLUE}📝 Изменить настройки:${NC}"
echo -e "  nano $ENV_FILE && cd $INSTALL_DIR && docker-compose restart"
echo ""
echo -e "${GREEN}📱 Telegram бот оповещает о работе монитора!${NC}"
echo -e "${GREEN}🔄 Контейнер будет автоматически запускаться после перезагрузки сервера!${NC}"

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

# Определяем директорию установки - текущая папка где запущен скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$SCRIPT_DIR" = "/" ] || [ -z "$SCRIPT_DIR" ]; then
    # Если скрипт запущен через pipe, используем текущую рабочую директорию
    INSTALL_DIR="$(pwd)/antminer-checkd"
else
    INSTALL_DIR="$SCRIPT_DIR"
fi

ENV_FILE="$INSTALL_DIR/.env"

echo -e "${BLUE}📁 Директория установки: $INSTALL_DIR${NC}"
echo ""

# Функция проверки валидности .env
is_env_valid() {
    if [ ! -f "$ENV_FILE" ]; then
        return 1
    fi
    
    source "$ENV_FILE" 2>/dev/null || return 1
    
    if [ -z "$ASIC_IP" ] || [ -z "$ASIC_PASSWORD" ] || [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return 1
    fi
    
    return 0
}

# Функция запроса данных
ask_config() {
    echo -e "${CYAN}📝 Настройка мониторинга ASIC${NC}"
    echo -e "${YELLOW}Пожалуйста, введите следующие данные:${NC}"
    echo ""
    
    # IP адрес
    while true; do
        printf "${BLUE}IP адрес ASIC: ${NC}"
        read ASIC_IP
        if [ -n "$ASIC_IP" ]; then
            break
        fi
        echo -e "${RED}IP адрес не может быть пустым${NC}"
    done
    
    # Порт
    printf "${BLUE}Порт ASIC [80]: ${NC}"
    read ASIC_PORT
    ASIC_PORT=${ASIC_PORT:-80}
    
    # Имя пользователя
    printf "${BLUE}Имя пользователя [root]: ${NC}"
    read ASIC_USER
    ASIC_USER=${ASIC_USER:-root}
    
    # Пароль
    while true; do
        printf "${BLUE}Пароль ASIC: ${NC}"
        read -s ASIC_PASSWORD
        echo ""
        if [ -n "$ASIC_PASSWORD" ]; then
            break
        fi
        echo -e "${RED}Пароль не может быть пустым${NC}"
    done
    
    echo ""
    
    # Telegram Token
    while true; do
        printf "${BLUE}Telegram Bot Token: ${NC}"
        read TELEGRAM_TOKEN
        if [ -n "$TELEGRAM_TOKEN" ]; then
            break
        fi
        echo -e "${RED}Token не может быть пустым${NC}"
    done
    
    # Telegram Chat ID
    while true; do
        printf "${BLUE}Telegram Chat ID: ${NC}"
        read TELEGRAM_CHAT_ID
        if [ -n "$TELEGRAM_CHAT_ID" ]; then
            break
        fi
        echo -e "${RED}Chat ID не может быть пустым${NC}"
    done
    
    # Минимальный хэшрейт
    printf "${BLUE}Мин. хэшрейт TH/s [80]: ${NC}"
    read MIN_HASHRATE
    MIN_HASHRATE=${MIN_HASHRATE:-80}
    
    # Интервал проверки
    printf "${BLUE}Интервал проверки сек [300]: ${NC}"
    read CHECK_INTERVAL
    CHECK_INTERVAL=${CHECK_INTERVAL:-300}
    
    echo ""
    echo -e "${GREEN}✅ Данные сохранены${NC}"
    echo ""
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
        echo -e "${YELLOW}⚠️  Не удалось подключиться к ASIC${NC}"
        read -p "Продолжить установку? (y/n): " continue_anyway
        [[ "$continue_anyway" =~ ^[Yy]$ ]]
        return $?
    fi
}

# Функция проверки Telegram
test_telegram() {
    echo -e "${CYAN}📱 Проверка Telegram бота...${NC}"
    
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
        read -p "Продолжить установку? (y/n): " continue_anyway
        [[ "$continue_anyway" =~ ^[Yy]$ ]]
        return $?
    fi
}

# Функция установки Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}🐳 Установка Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        echo -e "${GREEN}✓ Docker установлен${NC}"
    else
        echo -e "${GREEN}✓ Docker уже установлен${NC}"
    fi

    if command -v docker-compose &> /dev/null; then
        OLD_VERSION=$(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [[ "$OLD_VERSION" == 1.* ]]; then
            echo -e "${YELLOW}⚠️  Обновляем Docker Compose...${NC}"
            sudo rm -f /usr/local/bin/docker-compose
            sudo apt-get remove docker-compose -y 2>/dev/null || true
        fi
    fi

    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}🐳 Установка Docker Compose v2...${NC}"
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}✓ Docker Compose v2 установлен${NC}"
    else
        echo -e "${GREEN}✓ Docker Compose уже установлен${NC}"
    fi
}

# Функция создания .env
create_env_file() {
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
    echo -e "${GREEN}✓ Файл .env создан в $ENV_FILE${NC}"
}

# ============================================
# ОСНОВНАЯ ЛОГИКА
# ============================================

# Проверяем существующую установку в текущей директории
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    echo -e "${YELLOW}⚠️  Установка уже найдена в $INSTALL_DIR${NC}"
    
    if is_env_valid; then
        source "$ENV_FILE"
        echo -e "${GREEN}✓ Найдены рабочие настройки для ASIC ${ASIC_IP}${NC}"
        echo ""
        read -p "Переустановить с сохранением настроек? (Y/n): " reinstall
        if [[ ! "$reinstall" =~ ^[Nn]$ ]]; then
            cd "$INSTALL_DIR"
            git pull
            docker-compose down 2>/dev/null || true
            docker-compose up -d --build
            echo -e "${GREEN}✅ Обновление завершено!${NC}"
            exit 0
        fi
    fi
    
    echo ""
    echo -e "${BLUE}Выберите действие:${NC}"
    echo "  1) Удалить и установить заново (с новыми настройками)"
    echo "  2) Выход"
    read -p "Выбор (1-2): " choice
    
    case $choice in
        1)
            cd "$INSTALL_DIR" 2>/dev/null && docker-compose down 2>/dev/null || true
            rm -rf "$INSTALL_DIR"
            docker rm -f antminer-checkd 2>/dev/null || true
            docker rmi antminer-checkd_antminer-checkd 2>/dev/null || true
            echo -e "${GREEN}✓ Старая установка удалена${NC}"
            ;;
        2)
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            exit 1
            ;;
    esac
fi

# Запрашиваем конфигурацию
ask_config

# Проверяем подключения
test_connection || exit 1
test_telegram || exit 1

# Устанавливаем Docker
install_docker

# Клонируем репозиторий в текущую директорию
echo -e "${BLUE}📦 Клонирование репозитория в $INSTALL_DIR...${NC}"
git clone "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Создаем .env
create_env_file

# Запускаем контейнер
echo -e "${BLUE}🚀 Запуск контейнера...${NC}"
mkdir -p logs
docker-compose up -d --build

sleep 5
if docker-compose ps | grep -q "Up"; then
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
    echo -e "${GREEN}🔄 Контейнер будет автоматически запускаться после перезагрузки сервера!${NC}"
    echo -e "${GREEN}📁 Для удаления: rm -rf $INSTALL_DIR${NC}"
else
    echo -e "${RED}❌ Ошибка запуска контейнера${NC}"
    docker-compose logs --tail=30
    exit 1
fi

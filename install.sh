#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Проверяем, что скрипт запущен не через pipe
if [ ! -t 0 ]; then
    echo -e "${YELLOW}⚠️  Скрипт запущен через pipe. Перезапускаем для интерактивного режима...${NC}"
    # Скачиваем и запускаем заново в интерактивном режиме
    curl -sSL https://raw.githubusercontent.com/Tkom3a/antminer-ckeckd/main/install.sh -o /tmp/antminer_install.sh
    chmod +x /tmp/antminer_install.sh
    exec /tmp/antminer_install.sh
    exit 0
fi

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
    
    while true; do
        read -p "$(echo -e ${BLUE}IP адрес ASIC: ${NC})" ASIC_IP
        if [ -n "$ASIC_IP" ]; then
            break
        fi
        echo -e "${RED}IP адрес не может быть пустым${NC}"
    done
    
    read -p "$(echo -e ${BLUE}Порт ASIC [80]: ${NC})" ASIC_PORT
    ASIC_PORT=${ASIC_PORT:-80}
    
    read -p "$(echo -e ${BLUE}Имя пользователя [root]: ${NC})" ASIC_USER
    ASIC_USER=${ASIC_USER:-root}
    
    while true; do
        read -s -p "$(echo -e ${BLUE}Пароль ASIC: ${NC})" ASIC_PASSWORD
        echo ""
        if [ -n "$ASIC_PASSWORD" ]; then
            break
        fi
        echo -e "${RED}Пароль не может быть пустым${NC}"
    done
    
    echo ""
    
    while true; do
        read -p "$(echo -e ${BLUE}Telegram Bot Token: ${NC})" TELEGRAM_TOKEN
        if [ -n "$TELEGRAM_TOKEN" ]; then
            break
        fi
        echo -e "${RED}Token не может быть пустым${NC}"
    done
    
    while true; do
        read -p "$(echo -e ${BLUE}Telegram Chat ID: ${NC})" TELEGRAM_CHAT_ID
        if [ -n "$TELEGRAM_CHAT_ID" ]; then
            break
        fi
        echo -e "${RED}Chat ID не может быть пустым${NC}"
    done
    
    read -p "$(echo -e ${BLUE}Мин. хэшрейт TH/s [80]: ${NC})" MIN_HASHRATE
    MIN_HASHRATE=${MIN_HASHRATE:-80}
    
    read -p "$(echo -e ${BLUE}Интервал проверки сек [300]: ${NC})" CHECK_INTERVAL
    CHECK_INTERVAL=${CHECK_INTERVAL:-300}
    
    echo ""
    echo -e "${GREEN}✅ Данные сохранены${NC}"
    echo ""
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
    echo -e "${GREEN}✓ Файл .env создан${NC}"
}

# Функция установки Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}🐳 Установка Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
    fi

    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}🐳 Установка Docker Compose...${NC}"
        curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi

    echo -e "${GREEN}✓ Docker готов${NC}"
}

# ============================================
# ОСНОВНАЯ ЛОГИКА
# ============================================

# Проверяем существующую установку
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}⚠️  Установка найдена в $INSTALL_DIR${NC}"
    echo ""
    
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
    
    echo -e "${BLUE}Выберите действие:${NC}"
    echo "  1) Удалить и установить заново (с новыми настройками)"
    echo "  2) Выход"
    read -p "Выбор (1-2): " choice
    
    case $choice in
        1)
            cd "$INSTALL_DIR" 2>/dev/null && docker-compose down 2>/dev/null || true
            cd /
            rm -rf "$INSTALL_DIR"
            docker rm -f antminer-checkd 2>/dev/null || true
            docker rmi antminer-checkd_antminer-checkd 2>/dev/null || true
            echo -e "${GREEN}✓ Старая установка удалена${NC}"
            ;;
        2)
            exit 0
            ;;
    esac
fi

# Запрашиваем конфигурацию
ask_config

# Устанавливаем Docker
install_docker

# Клонируем репозиторий
echo -e "${BLUE}📦 Клонирование репозитория...${NC}"
git clone "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Создаем .env
create_env_file

# Запускаем контейнер
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
    echo -e "${GREEN}🔄 Контейнер будет автоматически запускаться после перезагрузки сервера!${NC}"
else
    echo -e "${RED}❌ Ошибка запуска контейнера${NC}"
    docker-compose logs --tail=30
    exit 1
fi

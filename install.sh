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

# Функция запроса данных
ask_config() {
    echo -e "${CYAN}📝 Настройка мониторинга ASIC${NC}"
    echo -e "${YELLOW}Введите данные (или нажмите Enter для значений по умолчанию):${NC}"
    echo ""
    
    read -p "$(echo -e ${BLUE}IP адрес ASIC: ${NC})" ASIC_IP
    while [ -z "$ASIC_IP" ]; do
        echo -e "${RED}IP адрес не может быть пустым${NC}"
        read -p "$(echo -e ${BLUE}IP адрес ASIC: ${NC})" ASIC_IP
    done
    
    read -p "$(echo -e ${BLUE}Порт ASIC [80]: ${NC})" ASIC_PORT
    ASIC_PORT=${ASIC_PORT:-80}
    
    read -p "$(echo -e ${BLUE}Имя пользователя [root]: ${NC})" ASIC_USER
    ASIC_USER=${ASIC_USER:-root}
    
    read -s -p "$(echo -e ${BLUE}Пароль ASIC: ${NC})" ASIC_PASSWORD
    echo ""
    while [ -z "$ASIC_PASSWORD" ]; do
        echo -e "${RED}Пароль не может быть пустым${NC}"
        read -s -p "$(echo -e ${BLUE}Пароль ASIC: ${NC})" ASIC_PASSWORD
        echo ""
    done
    
    echo ""
    read -p "$(echo -e ${BLUE}Telegram Bot Token: ${NC})" TELEGRAM_TOKEN
    while [ -z "$TELEGRAM_TOKEN" ]; do
        echo -e "${RED}Token не может быть пустым${NC}"
        read -p "$(echo -e ${BLUE}Telegram Bot Token: ${NC})" TELEGRAM_TOKEN
    done
    
    read -p "$(echo -e ${BLUE}Telegram Chat ID: ${NC})" TELEGRAM_CHAT_ID
    while [ -z "$TELEGRAM_CHAT_ID" ]; do
        echo -e "${RED}Chat ID не может быть пустым${NC}"
        read -p "$(echo -e ${BLUE}Telegram Chat ID: ${NC})" TELEGRAM_CHAT_ID
    done
    
    read -p "$(echo -e ${BLUE}Мин. хэшрейт TH/s [80]: ${NC})" MIN_HASHRATE
    MIN_HASHRATE=${MIN_HASHRATE:-80}
    
    read -p "$(echo -e ${BLUE}Интервал проверки сек [300]: ${NC})" CHECK_INTERVAL
    CHECK_INTERVAL=${CHECK_INTERVAL:-300}
    
    echo ""
    echo -e "${GREEN}✅ Данные сохранены${NC}"
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

# Проверка существующей установки
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}⚠️  Установка найдена в $INSTALL_DIR${NC}"
    echo ""
    echo -e "${BLUE}Выберите действие:${NC}"
    echo "  1) Обновить"
    echo "  2) Переустановить"
    echo "  3) Выход"
    read -p "Выбор (1-3): " choice
    
    case $choice in
        1)
            cd "$INSTALL_DIR"
            git pull
            docker-compose down 2>/dev/null || true
            docker-compose up -d --build
            echo -e "${GREEN}✅ Обновлено!${NC}"
            exit 0
            ;;
        2)
            cd "$INSTALL_DIR" 2>/dev/null && docker-compose down 2>/dev/null || true
            cd /
            rm -rf "$INSTALL_DIR"
            docker rm -f antminer-checkd 2>/dev/null || true
            docker rmi antminer-checkd_antminer-checkd 2>/dev/null || true
            ;;
        3)
            exit 0
            ;;
    esac
fi

# Основная установка
ask_config
install_docker

echo -e "${BLUE}📦 Клонирование репозитория...${NC}"
git clone "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Создание .env
cat > "$INSTALL_DIR/.env" << EOF
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

# Запуск
mkdir -p logs
docker-compose up -d --build

sleep 5
if docker-compose ps | grep -q "Up"; then
    echo -e "${GREEN}✅ antminer-checkd установлен и запущен!${NC}"
    echo -e "📝 Логи: docker-compose logs -f"
else
    echo -e "${RED}❌ Ошибка запуска${NC}"
    docker-compose logs --tail=30
    exit 1
fi

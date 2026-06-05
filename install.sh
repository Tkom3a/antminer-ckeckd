#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Функция проверки и установки Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}🐳 Docker не установлен. Устанавливаем...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        echo -e "${GREEN}✓ Docker установлен${NC}"
    fi

    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}🐳 Docker Compose не установлен. Устанавливаем...${NC}"
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}✓ Docker Compose установлен${NC}"
    fi
}

# 1. Проверка существующей установки
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}⚠️  Установка уже найдена в $INSTALL_DIR${NC}"
    echo ""
    echo -e "${BLUE}Выберите действие:${NC}"
    echo "  1) Обновить (git pull + пересобрать контейнер)"
    echo "  2) Удалить и установить заново"
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
            exit 0
            ;;
        2)
            echo -e "${BLUE}Запускаем удаление...${NC}"
            if [ -f "$INSTALL_DIR/uninstall.sh" ]; then
                bash "$INSTALL_DIR/uninstall.sh"
            else
                rm -rf "$INSTALL_DIR"
                docker rm -f antminer-checkd 2>/dev/null || true
                docker rmi antminer-checkd_antminer-checkd 2>/dev/null || true
            fi
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

# 2. Установка Docker (если нужно)
install_docker

# 3. Клонирование репозитория
echo -e "${BLUE}📦 Клонирование репозитория...${NC}"
git clone "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 4. Создание .env файла
if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "${YELLOW}⚠️  Создан файл .env${NC}"
    echo -e "${YELLOW}📝 Пожалуйста, отредактируйте его с вашими настройками:${NC}"
    echo -e "   nano $INSTALL_DIR/.env"
    echo ""
    read -p "Настроить сейчас? (yes/no): " configure_now
    
    if [ "$configure_now" == "yes" ]; then
        nano "$INSTALL_DIR/.env"
    else
        echo -e "${RED}❌ Установка прервана. Запустите install.sh снова после настройки .env${NC}"
        exit 1
    fi
fi

# 5. Запуск контейнера
mkdir -p logs
docker-compose down 2>/dev/null || true
docker-compose up -d --build

# 6. Проверка статуса
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
    echo -e "  📝 Логи: docker-compose logs -f"
    echo -e "  🔄 Статус: docker-compose ps"
    echo ""
    echo -e "${BLUE}🔧 Управление:${NC}"
    echo -e "  cd $INSTALL_DIR"
    echo -e "  docker-compose restart  # Перезапуск"
    echo -e "  docker-compose stop     # Остановка"
    echo -e "  docker-compose logs -f  # Логи в реальном времени"
    echo ""
    echo -e "${BLUE}🗑️  Удаление:${NC}"
    echo -e "  sudo bash $INSTALL_DIR/uninstall.sh"
    echo ""
    echo -e "${GREEN}🔄 Контейнер будет автоматически запускаться после перезагрузки сервера!${NC}"
else
    echo -e "${RED}❌ Ошибка при запуске контейнера${NC}"
    docker-compose logs --tail=50
    exit 1
fi

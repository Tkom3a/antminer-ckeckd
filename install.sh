#!/bin/bash

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Antminer-checkd Installation Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Проверка запуска от root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}⚠️  Запуск с sudo для установки Docker...${NC}"
    exec sudo "$0" "$@"
fi

# Проверка существующей установки
if [ -d "/opt/asic-monitor" ]; then
    echo -e "${YELLOW}⚠️  Antminer-checkd уже установлен в /opt/asic-monitor${NC}"
    echo ""
    echo -e "${BLUE}Выберите действие:${NC}"
    echo "  1) Обновить существующую установку"
    echo "  2) Полностью удалить и установить заново"
    echo "  3) Выход"
    read -p "Ваш выбор (1-3): " -r choice
    
    case $choice in
        1)
            echo -e "${BLUE}Обновляем Antminer-checkd...${NC}"
            cd /opt/asic-monitor
            git pull
            docker-compose down
            docker-compose up -d --build
            echo -e "${GREEN}✅ Обновление завершено!${NC}"
            exit 0
            ;;
        2)
            echo -e "${BLUE}Запускаем удаление...${NC}"
            if [ -f "/opt/antminer-checkd/uninstall.sh" ]; then
                bash /opt/asic-monitor/uninstall.sh
            else
                rm -rf /opt/asic-monitor
                docker rm -f asic-monitor 2>/dev/null || true
                docker rmi asic-monitor_asic-monitor 2>/dev/null || true
            fi
            ;;
        3)
            echo -e "${RED}Выход${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            exit 1
            ;;
    esac
fi

# Проверка наличия Docker
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}🐳 Docker не установлен. Устанавливаем...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    echo -e "${GREEN}✓ Docker установлен${NC}"
fi

# Проверка Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}🐳 Docker Compose не установлен. Устанавливаем...${NC}"
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}✓ Docker Compose установлен${NC}"
fi

# Определяем репозиторий (можно переопределить через переменную)
REPO_URL="${REPO_URL:-https://github.com/yourusername/asic-monitor.git}"
INSTALL_DIR="/opt/antminer-checkd"

# Клонируем репозиторий
echo -e "${BLUE}📦 Клонирование репозитория...${NC}"
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}Директория уже существует, обновляем...${NC}"
    cd "$INSTALL_DIR"
    git pull
else
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# Создаем .env файл если его нет
if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "${YELLOW}⚠️  Создан файл .env${NC}"
    echo -e "${YELLOW}📝 Пожалуйста, отредактируйте его с вашими настройками:${NC}"
    echo -e "   nano $INSTALL_DIR/.env"
    echo ""
    read -p "Настроить сейчас? (yes/no): " -r configure_now
    
    if [ "$configure_now" == "yes" ]; then
        nano "$INSTALL_DIR/.env"
    else
        echo -e "${RED}❌ Установка прервана. Настройте .env и запустите install.sh снова${NC}"
        exit 1
    fi
fi

# Создаем директорию для логов
mkdir -p logs

# Останавливаем старый контейнер если есть
docker-compose down 2>/dev/null || true

# Собираем и запускаем
echo -e "${BLUE}🏗️  Сборка Docker образа...${NC}"
docker-compose build

echo -e "${BLUE}🚀 Запуск контейнера...${NC}"
docker-compose up -d

# Проверяем статус
sleep 5
if docker-compose ps | grep -q "Up"; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ Antminer-checkd успешно установлен!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}📊 Информация:${NC}"
    echo -e "  📁 Установлен в: $INSTALL_DIR"
    echo -e "  🐳 Контейнер: antminer-check"
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
    echo -e "${GREEN}🔄 Монитор будет автоматически запускаться после перезагрузки сервера!${NC}"
else
    echo -e "${RED}❌ Ошибка при запуске контейнера${NC}"
    echo -e "${YELLOW}Логи ошибки:${NC}"
    docker-compose logs --tail=50
    exit 1
fi

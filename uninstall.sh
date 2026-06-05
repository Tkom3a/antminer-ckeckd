#!/bin/bash

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}Antminer-checkd - COMPLETE UNINSTALL${NC}"
echo -e "${RED}========================================${NC}"
echo ""

# Проверка запуска от root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Пожалуйста, запустите с sudo: sudo ./uninstall.sh${NC}"
    exit 1
fi

# Предупреждение
echo -e "${YELLOW}⚠️  ВНИМАНИЕ! Это действие полностью удалит:${NC}"
echo -e "  • Docker контейнер antminer-check"
echo -e "  • Docker образ antminer-check"
echo -e "  • Все файлы конфигурации (/opt/antminer-check)"
echo -e "  • Логи монитора"
echo -e "  • Docker volumes (если есть)"
echo ""
read -p "Вы уверены, что хотите продолжить? (yes/no): " -r confirmation

if [ "$confirmation" != "yes" ]; then
    echo -e "${GREEN}❌ Удаление отменено${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Начинаем удаление...${NC}"

# 1. Останавливаем и удаляем контейнер
if [ -d "/opt/asic-monitor" ]; then
    cd /opt/antminer-check
    if command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}📦 Останавливаем и удаляем контейнер...${NC}"
        docker-compose down -v 2>/dev/null || true
    fi
fi

# 2. Удаляем Docker образ
echo -e "${YELLOW}🗑️  Удаляем Docker образ...${NC}"
docker rmi antminer-checkd 2>/dev/null || true
docker rmi antminer-checkd 2>/dev/null || true

# 3. Очищаем неиспользуемые Docker ресурсы
echo -e "${YELLOW}🧹 Очищаем неиспользуемые Docker ресурсы...${NC}"
docker system prune -f 2>/dev/null || true

# 4. Удаляем директорию с файлами
echo -e "${YELLOW}📁 Удаляем директорию /opt/asic-monitor...${NC}"
rm -rf /opt/antminer-check

# 5. Удаляем логи (если остались где-то еще)
echo -e "${YELLOW}📝 Удаляем файлы логов...${NC}"
rm -rf /var/log/antminer-check 2>/dev/null || true
rm -rf /var/log/antminer-check/ 2>/dev/null || true

fi


# Итог
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Antminer-checkd полностью удален!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}💡 Чтобы установить заново:${NC}"
echo -e "  curl -sSL https://raw.githubusercontent.com/yourusername/asic-monitor/main/install.sh | bash"

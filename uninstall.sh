#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}antminer-checkd - COMPLETE UNINSTALL${NC}"
echo -e "${RED}========================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Пожалуйста, запустите с sudo: sudo ./uninstall.sh${NC}"
    exit 1
fi

INSTALL_DIR="/opt/antminer-checkd"

echo -e "${YELLOW}⚠️  ВНИМАНИЕ! Это действие полностью удалит:${NC}"
echo -e "  • Docker контейнер antminer-checkd"
echo -e "  • Docker образ antminer-checkd"
echo -e "  • Все файлы конфигурации ($INSTALL_DIR)"
echo ""
read -p "Вы уверены, что хотите продолжить? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo -e "${GREEN}❌ Удаление отменено${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Начинаем удаление...${NC}"

# 1. Остановка и удаление контейнера
if [ -d "$INSTALL_DIR" ]; then
    cd "$INSTALL_DIR"
    docker-compose down -v 2>/dev/null || true
fi

# 2. Удаление Docker образа
docker rmi antminer-checkd_antminer-checkd 2>/dev/null || true
docker rmi antminer-checkd 2>/dev/null || true

# 3. Очистка Docker
docker system prune -f 2>/dev/null || true

# 4. Удаление директории
rm -rf "$INSTALL_DIR"

# 5. Удаление логов
rm -rf /var/log/antminer-checkd.log 2>/dev/null || true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ antminer-checkd полностью удален!${NC}"
echo -e "${GREEN}========================================${NC}"

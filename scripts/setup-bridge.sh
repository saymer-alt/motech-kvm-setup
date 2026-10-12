#!/bin/bash
set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========== 1. Только root ==========
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ОШИБКА: Запускай из-под root: sudo bash setup-bridge.sh${NC}"
    exit 1
fi

# ========== 2. Проверяем NetworkManager ==========
if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
    echo -e "${RED}ОШИБКА: NetworkManager не запущен.${NC}"
    exit 1
fi

# ========== 3. Если br0 уже есть — спросим ==========
if ip link show br0 &>/dev/null; then
    echo -e "${YELLOW}>>> Мост br0 уже существует.${NC}"
    ip -4 addr show br0 2>/dev/null | grep "inet " | awk '{print "    Текущий IP: " $2}' || true
    echo ""
    read -rp "Удалить текущий br0 и пересоздать? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        echo ">>> Удаляю старый br0..."
        nmcli connection down br0 2>/dev/null || true
        nmcli connection delete br0 2>/dev/null || true
        nmcli connection delete br0-slave 2>/dev/null || true
        ip link delete br0 2>/dev/null || true
        sleep 1
    else
        echo "Отмена. br0 оставлен как есть."
        exit 0
    fi
fi

# ========== 4. Ищем проводные Ethernet-интерфейсы ==========
echo ">>> Ищу проводные сетевые интерфейсы..."

mapfile -t ifaces < <(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | \
    awk -F: '$2=="ethernet" {print $1}' | \
    grep -vE '^lo$|^virbr|^vnet|^docker|^br|^wlan|^wlp|^wlx' | sort -u)

if [ ${#ifaces[@]} -eq 0 ]; then
    echo -e "${RED}ОШИБКА: Проводные Ethernet-интерфейсы не найдены.${NC}"
    echo "    Возможно, у тебя Wi-Fi или интерфейс уже в другом мосте."
    exit 1
fi

# ========== 5. Выбираем интерфейс ==========
TARGET_IFACE=""

if [ ${#ifaces[@]} -eq 1 ]; then
    only_one="${ifaces[0]}"
    echo "    Найден: $only_one"
    read -rp "Использовать его для моста? [Y/n]: " ans
    if [[ "$ans" =~ ^[Nn]$ ]]; then
        read -rp "Введите имя интерфейса вручную: " TARGET_IFACE
    else
        TARGET_IFACE="$only_one"
    fi
else
    echo ""
    echo "Найдены интерфейсы (выберите номер):"
    for i in "${!ifaces[@]}"; do
        echo "  $((i+1)). ${ifaces[$i]}"
    done
    echo "  0. Ввести имя вручную"
    read -rp "Ваш выбор: " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#ifaces[@]} ]; then
        TARGET_IFACE="${ifaces[$((choice-1))]}"
    else
        read -rp "Введите имя интерфейса вручную: " TARGET_IFACE
    fi
fi

if [ -z "$TARGET_IFACE" ]; then
    echo -e "${RED}ОШИБКА: Интерфейс не выбран.${NC}"
    exit 1
fi

if ! ip link show "$TARGET_IFACE" &>/dev/null; then
    echo -e "${RED}ОШИБКА: Интерфейс '$TARGET_IFACE' не существует!${NC}"
    exit 1
fi

# Проверим, не в мосте ли уже
CURRENT_MASTER=$(ip link show "$TARGET_IFACE" 2>/dev/null | grep -oP 'master \K\w+' || true)
if [ -n "$CURRENT_MASTER" ] && [ "$CURRENT_MASTER" != "br0" ]; then
    echo -e "${RED}ОШИБКА: $TARGET_IFACE уже подключён к мосту $CURRENT_MASTER!${NC}"
    exit 1
fi

echo -e "${BLUE}>>> Выбран интерфейс: $TARGET_IFACE${NC}"

# ========== 6. Узнаём текущее подключение ==========
OLD_CONN=$(nmcli -g GENERAL.CONNECTION device show "$TARGET_IFACE" 2>/dev/null | head -n1)

if [ -z "$OLD_CONN" ]; then
    echo -e "${YELLOW}    Не удалось определить имя подключения, попробую 'Wired connection 1'${NC}"
    OLD_CONN="Wired connection 1"
else
    echo "    Текущее подключение: '$OLD_CONN'"
fi

# ========== 7. Подтверждение ==========
echo ""
echo -e "${YELLOW}==========================================${NC}"
echo "Будет создан мост:"
echo "  Физический интерфейс: $TARGET_IFACE"
echo "  Старое подключение '$OLD_CONN' → ОТКЛЮЧИТСЯ"
echo "  Мост br0 → ПОЛУЧИТ IP из сети (DHCP)"
echo -e "${YELLOW}==========================================${NC}"
read -rp "Продолжить? [Y/n]: " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Отменено."
    exit 0
fi

# ========== 8. Создаём мост ==========
echo ">>> Создаю мост br0..."
nmcli connection add type bridge ifname br0 con-name br0 autoconnect yes 2>/dev/null || {
    echo -e "${RED}ОШИБКА: не удалось создать мост${NC}"
    exit 1
}

echo ">>> Подключаю $TARGET_IFACE к мосту..."
nmcli connection add type ethernet ifname "$TARGET_IFACE" master br0 con-name br0-slave autoconnect yes 2>/dev/null || {
    echo -e "${RED}ОШИБКА: не удалось добавить интерфейс в мост${NC}"
    echo ">>> Откат: удаляю br0..."
    nmcli connection delete br0 2>/dev/null || true
    exit 1
}

echo ">>> Отключаю старое подключение '$OLD_CONN'..."
nmcli connection down "$OLD_CONN" 2>/dev/null || true

echo ">>> Поднимаю мост br0..."
nmcli connection up br0 2>/dev/null || {
    echo -e "${RED}ОШИБКА: мост не поднялся${NC}"
    echo ">>> Пытаюсь вернуть старое подключение..."
    nmcli connection up "$OLD_CONN" 2>/dev/null || true
    exit 1
}

# ========== 9. Ждём IP ==========
echo ">>> Жду IP-адрес (до 30 сек)..."
ip_ok=false
for i in {1..30}; do
    if ip -4 addr show br0 2>/dev/null | grep -q "inet "; then
        ip_ok=true
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# ========== 10. Результат ==========
echo ""
echo -e "${GREEN}==========================================${NC}"

if [ "$ip_ok" = true ]; then
    echo -e "${GREEN}Мост br0 работает!${NC}"
    echo ""
    ip -4 addr show br0 | grep "inet " | awk '{print "  IP-адрес: " $2}'
    echo ""
    echo "  Проверь интернет:  ping -c 3 8.8.8.8"
    echo ""
    echo "  В virt-manager укажи:"
    echo "    Network source: Bridge br0"
    echo "    Device model:   virtio"
else
    echo -e "${YELLOW}Мост создан, но IP не получен.${NC}"
    echo "  Возможно, в сети нет DHCP (нужна ручная настройка)."
    echo ""
    echo "  Статус br0:"
    ip addr show br0 || true
fi

echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${BLUE}Команды отката (если нужно всё вернуть):${NC}"
echo "  nmcli connection down br0"
echo "  nmcli connection delete br0"
echo "  nmcli connection delete br0-slave"
echo "  nmcli connection up \"$OLD_CONN\""
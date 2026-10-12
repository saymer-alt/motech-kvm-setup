#!/bin/bash
set -e

# ========== 1. Проверяем root ==========
if [ "$EUID" -ne 0 ]; then
    echo "ОШИБКА: Запускай из-под root: sudo bash setup-kvm-motech.sh"
    exit 1
fi

# ========== 2. Определяем целевого пользователя ==========
TARGET_USER=""

# --- Вариант А: если скрипт вызван через sudo от доменного пользователя ---
if [ -n "$SUDO_USER" ] && [[ "$SUDO_USER" != "root" ]] && \
   [[ "$SUDO_USER" != "lroot" ]] && [[ "$SUDO_USER" != "leaderpc" ]]; then
    echo ">>> Обнаружен вызов sudo от: $SUDO_USER"
    read -rp "Настроить virt-manager для $SUDO_USER? [Y/n]: " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        TARGET_USER="$SUDO_USER"
    fi
fi

# --- Вариант Б: ищем вручную, но без доменной свалки ---
if [ -z "$TARGET_USER" ]; then
    echo ">>> Ищу пользователей на этой машине..."

    # Собираем кандидатов из НЕСКОЛЬКИХ источников
    # Важно: каждая команда обёрнута так, чтобы не выдавать пустые строки
    raw_list=""

    # Источник 1: кто сейчас залогинен (GUI, терминал)
    active=$(who | awk '{print $1}' | sort -u | grep -v '^$')
    if [ -n "$active" ]; then
        raw_list="$raw_list"$'\n'"$active"
        echo "    [who] Найдены: $(echo "$active" | tr '\n' ' ')"
    fi

    # Источник 2: активные пользователи через loginctl (реальные имена, без обрезки!)
    loginctl_users=$(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}' | grep -v '^$')
    if [ -n "$loginctl_users" ]; then
        raw_list="$raw_list"$'\n'"$loginctl_users"
        echo "    [loginctl] Найдены: $(echo "$loginctl_users" | tr '\n' ' ')"
    fi

    # Источник 3: кто логинился за последние 30 дней (только реальные имена)
    # ВНИМАНИЕ: last обрезает имена до 8 символов в wtmp/utmp!
    recent=$(last -s -30days 2>/dev/null | awk '{print $1}' | \
             grep -vE '^wtmp$|^$|^reboot$|^shutdown$' | sort -u)
    if [ -n "$recent" ]; then
        raw_list="$raw_list"$'\n'"$recent"
        echo "    [last] Найдены: $(echo "$recent" | tr '\n' ' ')"
    fi

    # Источник 4: ТОЛЬКО локальные пользователи из /etc/passwd (без SSSD!)
    # Это надёжно: берём только тех, кто прописан локально
    local_passwd=$(awk -F: '$3 >= 1000 && $3 < 65534 && $1 != "root" {print $1}' /etc/passwd)
    if [ -n "$local_passwd" ]; then
        raw_list="$raw_list"$'\n'"$local_passwd"
        echo "    [passwd] Найдены: $(echo "$local_passwd" | tr '\n' ' ')"
    fi

    # --- Очистка: убираем пустые строки, дубли, root, служебных ---
    # Здесь ключевой момент: grep -v '^$' удаляет ВСЕ пустые строки
    mapfile -t candidates < <(echo "$raw_list" | grep -v '^$' | grep -vE '^(root|lroot|leaderpc|reboot|shutdown)$' | sort -u)

    # Убираем тех, кого реально нет в системе (на всякий случай)
    # + восстанавливаем обрезанные имена из last (обрезка до 8 символов в wtmp)
    valid_candidates=()
    for u in "${candidates[@]}"; do
        # Строгая проверка: не пусто, не пробелы, и id существует
        u_clean=$(echo "$u" | xargs)  # убираем пробелы по краям
        [ -z "$u_clean" ] && continue

        if id "$u_clean" &>/dev/null; then
            # Имя найдено как есть — отлично
            valid_candidates+=("$u_clean")
        elif [ ${#u_clean} -le 8 ]; then
            # Имя короткое, но id не нашёл — возможно, обрезанное из last.
            # Пробуем найти по префиксу среди ВСЕХ пользователей системы.
            matched=$(getent passwd | awk -F: '$1 ~ /^'"$u_clean"'/ {print $1}' | head -1)
            if [ -n "$matched" ] && id "$matched" &>/dev/null; then
                echo "    [fix] Восстановлено имя '$u_clean' -> '$matched' (обрезка last/wtmp)"
                valid_candidates+=("$matched")
            fi
        fi
        # Если имя длиннее 8 символов и id не нашёл — пропускаем (странный случай)
    done

    # Убираем дубли ещё раз (на всякий случай)
    mapfile -t valid_candidates < <(printf "%s\n" "${valid_candidates[@]}" | sort -u)

    echo ">>> Итого уникальных кандидатов: ${#valid_candidates[@]}"

    # --- Выбор ---
    if [ ${#valid_candidates[@]} -eq 0 ]; then
        echo "Автоматически пользователей не найдено."
        read -rp "Введите имя пользователя вручную: " TARGET_USER

    elif [ ${#valid_candidates[@]} -eq 1 ]; then
        # Защита от пустой строки: проверяем, что внутри что-то есть
        only_one="${valid_candidates[0]}"
        if [ -z "$only_one" ]; then
            echo "Автопоиск дал пустой результат."
            read -rp "Введите имя пользователя вручную: " TARGET_USER
        else
            echo "Найден пользователь: $only_one"
            read -rp "Использовать его? [Y/n]: " ans
            if [[ "$ans" =~ ^[Nn]$ ]]; then
                read -rp "Введите имя пользователя вручную: " TARGET_USER
            else
                TARGET_USER="$only_one"
            fi
        fi

    else
        echo ""
        echo "Найдены пользователи (выберите номер):"
        max_show=10
        count=${#valid_candidates[@]}
        [ $count -gt $max_show ] && show=$max_show || show=$count

        for i in $(seq 0 $((show-1))); do
            echo "  $((i+1)). ${valid_candidates[$i]}"
        done
        [ $count -gt $max_show ] && echo "  ...и ещё $((count - max_show))"
        echo "  0. Ввести имя вручную"

        read -rp "Ваш выбор: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $show ]; then
            TARGET_USER="${valid_candidates[$((choice-1))]}"
        else
            read -rp "Введите имя пользователя вручную: " TARGET_USER
        fi
    fi
fi

# ========== 3. Проверка ==========
if [ -z "$TARGET_USER" ]; then
    echo "ОШИБКА: Имя пользователя не указано."
    exit 1
fi

if ! id "$TARGET_USER" &>/dev/null; then
    echo "ОШИБКА: Пользователь '$TARGET_USER' не найден в системе!"
    exit 1
fi

echo ">>> Выбран пользователь: '$TARGET_USER'"
sleep 1

# ========== 4. VT-x ==========
echo ">>> Проверка виртуализации..."
VIRT_COUNT=$(egrep -c '(vmx|svm)' /proc/cpuinfo)
if [ "$VIRT_COUNT" -eq 0 ]; then
    echo "ВНИМАНИЕ: VT-x/AMD-V не обнаружены!"
    read -rp "Продолжить? (y/N): " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
else
    echo "OK: $VIRT_COUNT ядер с виртуализацией."
fi

# ========== 5. Пакеты ==========
echo ">>> Установка KVM и зависимостей..."
dnf install -y qemu-kvm libvirt virt-install virt-manager
dnf install -y lib64gst-gir1.0 lib64gstreamer-plugins-base-gir1.0 \
    lib64spice-client-glib-gir2.0 lib64spice-client-gtk-gir3.0

# ========== 6. Служба ==========
echo ">>> Запуск libvirtd..."
systemctl enable --now libvirtd

# ========== 7. Настройка libvirtd.conf ==========
echo ">>> Настройка сокета libvirtd..."

set_conf() {
    local file="$1" key="$2" val="$3"
    if grep -qE "^#?\s*${key}\s*=" "$file"; then
        sed -i "s|^#\?\s*${key}\s*=.*|${key} = ${val}|" "$file"
    else
        echo "${key} = ${val}" >> "$file"
    fi
}

set_conf /etc/libvirt/libvirtd.conf "unix_sock_group" '"libvirt"'
set_conf /etc/libvirt/libvirtd.conf "unix_sock_rw_perms" '"0770"'
set_conf /etc/libvirt/libvirtd.conf "auth_unix_rw" '"polkit"'

# ========== 8. Группа ==========
echo ">>> Добавление '$TARGET_USER' в группу libvirt..."
gpasswd -a "$TARGET_USER" libvirt

# ========== 9. Polkit ==========
echo ">>> Создание правила Polkit..."
tee /etc/polkit-1/rules.d/49-libvirt-motech.rules > /dev/null <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" &&
        subject.isInGroup("libvirt")) {
            return polkit.Result.YES;
    }
});
EOF

# ========== 10. Перезапуск ==========
echo ">>> Перезапуск служб..."
systemctl restart polkit
systemctl restart libvirtd

# ========== Готово ==========
echo ""
echo "=========================================="
echo "ГОТОВО! Пользователь '$TARGET_USER' настроен."
echo ""
echo "ДЕЙСТВИЯ:"
echo "1. Выйди из сеанса root"
echo "2. Зайди под пользователем '$TARGET_USER'"
echo "3. Запусти: virt-manager"
echo "=========================================="
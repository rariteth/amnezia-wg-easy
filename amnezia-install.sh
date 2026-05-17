#!/bin/bash
# Переменные
CONTAINER_NAME="amnezia-wg-easy"
CONFIG_DIR="$HOME/.amnezia-wg-easy"

# Пытаемся определить публичный IP через внешний сервис,
# fallback на локальный адрес интерфейса
DEFAULT_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
if [ -z "$DEFAULT_IP" ]; then
    DEFAULT_IP=$(curl -4 -s --max-time 5 api.ipify.org 2>/dev/null)
fi
if [ -z "$DEFAULT_IP" ]; then
    DEFAULT_IP=$(hostname -I | awk '{print $1}')
fi

# Функция проверки и установки зависимостей
check_dependencies() {
    echo "Проверка зависимостей..."
    if ! command -v podman &> /dev/null; then
        echo "Podman не найден. Установка..."
        if [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y podman curl
        elif [ -f /etc/redhat-release ]; then
            dnf install -y podman curl
        else
            echo "Неизвестная ОС. Установите podman вручную."
            exit 1
        fi
    fi
    if ! command -v curl &> /dev/null; then
        if [ -f /etc/debian_version ]; then
            apt-get install -y curl
        elif [ -f /etc/redhat-release ]; then
            dnf install -y curl
        fi
    fi
}

case "$1" in
    install)
        check_dependencies
        echo "--- Настройка AmneziaWG ---"

        read -p "Введите публичный IP сервера [$DEFAULT_IP]: " WG_HOST
        WG_HOST=${WG_HOST:-$DEFAULT_IP}

        read -s -p "Введите пароль для веб-панели: " PASSWORD
        echo
        if [ -z "$PASSWORD" ]; then
            echo "Ошибка: нужен пароль"
            exit 1
        fi

        mkdir -p "$CONFIG_DIR"
        modprobe wireguard 2>/dev/null || true
        systemctl enable --now podman-restart.service 2>/dev/null || true

        # Удаляем старый контейнер, если был
        podman rm -f "$CONTAINER_NAME" 2>/dev/null

        podman run -d \
          --name="$CONTAINER_NAME" \
          --privileged \
          --sysctl="net.ipv4.ip_forward=1" \
          --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
          -e WG_HOST="$WG_HOST" \
          -e PASSWORD="$PASSWORD" \
          -e WG_DEFAULT_KEEPALIVE=25 \
          -v "$CONFIG_DIR:/etc/wireguard" \
          -v /lib/modules:/lib/modules:ro \
          -p 51820:51820/udp \
          -p 51821:51821/tcp \
          --restart unless-stopped \
          ghcr.io/spcfox/amnezia-wg-easy

        if [ $? -ne 0 ]; then
            echo "Ошибка запуска контейнера. Смотри: podman logs $CONTAINER_NAME"
            exit 1
        fi

        echo ""
        echo "Установка завершена! Панель: http://$WG_HOST:51821"

        # Ждём, пока контейнер создаст wg0.conf
        echo "--- Команда для настройки Keenetic ---"
        for i in $(seq 1 15); do
            [ -f "$CONFIG_DIR/wg0.conf" ] && break
            sleep 1
        done

        if [ -f "$CONFIG_DIR/wg0.conf" ]; then
            VALUES=$(grep -E '^(Jc|Jmin|Jmax|S1|S2|H1|H2|H3|H4)' "$CONFIG_DIR/wg0.conf" | awk '{printf "%s ", $3}')
            echo "Скопируйте и вставьте это в консоль роутера:"
            echo "interface Wireguard0 wireguard asc $VALUES"
            echo "system configuration save"
        else
            echo "Файл wg0.conf пока не создан — создайте клиента в веб-панели,"
            echo "затем выполните вручную:"
            echo "  grep -E '^(Jc|Jmin|Jmax|S1|S2|H1|H2|H3|H4)' $CONFIG_DIR/wg0.conf | awk '{printf \"%s \", \$3}'"
        fi

        # Проверка ключевых настроек
        echo ""
        echo "--- Проверка ---"
        sleep 2
        if podman exec "$CONTAINER_NAME" sysctl -n net.ipv4.ip_forward 2>/dev/null | grep -q 1; then
            echo "✓ IP forwarding включён в контейнере"
        else
            echo "✗ ВНИМАНИЕ: net.ipv4.ip_forward не = 1 в контейнере — VPN не будет пропускать трафик!"
        fi
        if podman port "$CONTAINER_NAME" 51820/udp 2>/dev/null | grep -q 51820; then
            echo "✓ Порт 51820/udp проброшен"
        else
            echo "✗ Порт 51820/udp не проброшен"
        fi
        ;;
    uninstall)
        podman stop "$CONTAINER_NAME" 2>/dev/null
        podman rm "$CONTAINER_NAME" 2>/dev/null
        rm -rf "$CONFIG_DIR"
        echo "Удалено."
        ;;
    *)
        echo "Использование: $0 {install|uninstall}"
        exit 1
        ;;
esac

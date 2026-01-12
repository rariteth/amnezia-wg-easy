#!/bin/bash

# Переменные
CONTAINER_NAME="amnezia-wg-easy"
CONFIG_DIR="$HOME/.amnezia-wg-easy"
DEFAULT_IP=$(hostname -I | awk '{print $1}')

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
}

case "$1" in
    install)
        check_dependencies
        echo "--- Настройка AmneziaWG ---"
        
        read -p "Введите публичный IP сервера [$DEFAULT_IP]: " WG_HOST
        WG_HOST=${WG_HOST:-$DEFAULT_IP}
        
        read -p "Введите пароль для веб-панели: " PASSWORD
        if [ -z "$PASSWORD" ]; then echo "Ошибка: нужен пароль"; exit 1; fi

        mkdir -p "$CONFIG_DIR"
        modprobe wireguard
        systemctl enable --now podman-restart.service
        
        podman run -d \
          --name=$CONTAINER_NAME \
          --privileged \
          -e WG_HOST=$WG_HOST \
          -e PASSWORD=$PASSWORD \
          -v "$CONFIG_DIR:/etc/wireguard" \
          -v /lib/modules:/lib/modules:ro \
          -p 51820:51820/udp \
          -p 51821:51821/tcp \
          --restart unless-stopped \
          ghcr.io/spcfox/amnezia-wg-easy

        echo "Установка завершена! Панель: http://$WG_HOST:51821"
        ;;
    uninstall)
        podman stop $CONTAINER_NAME && podman rm $CONTAINER_NAME
        rm -rf "$CONFIG_DIR"
        echo "Удалено."
        ;;
    *)
        echo "Использование: $0 {install|uninstall}"
        exit 1
esac

#!/bin/bash
# Новая версия скрипта установки SoftEther VPN Server
# SoftEther VPN Server (Ver 4.42, Build 9798, rtm)
# Скачивается по ссылке:
# https://www.softether-download.com/files/softether/v4.42-9798-rtm-2023.06.30-tree/Linux/SoftEther_VPN_Server/64bit_-_Intel_x64_or_AMD64/softether-vpnserver-v4.42-9798-rtm-2023.06.30-linux-x64-64bit.tar.gz
#
# Copyleft (C) 2023. Все права защищены.
#
# Скрипт разделён на функции для повышения надежности, читабельности и удобства сопровождения.

set -euo pipefail

###########################
# Функции для логирования #
###########################
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

###########################
# Глобальные переменные   #
###########################
SOFTETHER_URL="https://www.softether-download.com/files/softether/v4.42-9798-rtm-2023.06.30-tree/Linux/SoftEther_VPN_Server/64bit_-_Intel_x64_or_AMD64/softether-vpnserver-v4.42-9798-rtm-2023.06.30-linux-x64-64bit.tar.gz"
SOFTETHER_ARCHIVE_NAME="softether-vpnserver-v4.42-9798-rtm-2023.06.30-linux-x64-64bit.tar.gz"
VPN_SERVER_PASSWORD="softethervpn"  # Дефолтный пароль

#############################
# Установка зависимостей   #
#############################
install_dependencies() {
    log_info "Определение пакетного менеджера и установка необходимых зависимостей..."
    if command -v yum &>/dev/null; then
        log_info "Используется менеджер пакетов yum"
        yum update -y && yum upgrade -y
        yum groupinstall -y "Development Tools"
        yum install -y epel-release htop atop curl wget dnsmasq nano net-tools jq
        # Настройка firewall-cmd для открытия нужных портов
        local ZONE
        ZONE=$(firewall-cmd --get-default-zone)
        firewall-cmd --zone="${ZONE}" --add-service=openvpn --permanent
        firewall-cmd --zone="${ZONE}" --add-service=ipsec --permanent
        firewall-cmd --zone="${ZONE}" --add-service=https --permanent
        firewall-cmd --zone="${ZONE}" --add-port=992/tcp --permanent
        firewall-cmd --zone="${ZONE}" --add-port=1194/udp --permanent
        firewall-cmd --zone="${ZONE}" --add-port=500/udp --permanent
        firewall-cmd --zone="${ZONE}" --add-port=1701/udp --permanent
        firewall-cmd --zone="${ZONE}" --add-port=4500/udp --permanent
        firewall-cmd --zone="${ZONE}" --add-port=5555/tcp --permanent
        firewall-cmd --zone="${ZONE}" --add-port=40000-44999/udp --permanent
        firewall-cmd --reload
        touch /var/log/dnsmasq.log
        restorecon /var/log/dnsmasq.log || true
    elif command -v apt-get &>/dev/null; then
        log_info "Используется менеджер пакетов apt-get"
        apt-get update -y && apt-get upgrade -y
        apt-get install -y dnsmasq net-tools htop atop python3-simplejson python3-minimal curl wget jq libpam-radius-auth traceroute whois build-essential gnupg2 gcc make
        # Отключение UFW для избежания конфликтов
        ufw disable || true; service ufw stop || true;
    else
        log_error "Не найден пакетный менеджер (не обнаружены ни yum, ни apt-get). Завершение работы."
        exit 1
    fi
}

###############################################
# Резервное копирование конфигурации и очистка#
###############################################
backup_and_flush() {
    log_info "Создание резервной копии /etc/dnsmasq.conf и очистка iptables..."
    if [ -f /etc/dnsmasq.conf ]; then
        mv /etc/dnsmasq.conf /etc/dnsmasq.conf-bak || log_error "Не удалось создать резервную копию /etc/dnsmasq.conf"
    fi
    iptables -F && iptables -X
}

###############################################
# Скачивание SoftEther VPN Server версии 4.42#
###############################################
download_softether() {
    log_info "Скачивание SoftEther VPN Server версии 4.42 (Build 9798, rtm)..."
    wget -O "${SOFTETHER_ARCHIVE_NAME}" "${SOFTETHER_URL}"
}

##############################################
# Распаковка архива и компиляция vpnserver  #
##############################################
compile_softether() {
    log_info "Распаковка архива и компиляция SoftEther VPN Server..."
    tar xvf "${SOFTETHER_ARCHIVE_NAME}"
    cd vpnserver || { log_error "Папка vpnserver не найдена после распаковки"; exit 1; }
    # Автоматически принимаем лицензионное соглашение при компиляции
    printf '1\n1\n1\n' | make
    cd ..
}

####################################################
# Перемещение скомпилированного vpnserver и права  #
####################################################
install_softether() {
    log_info "Перемещение папки vpnserver в /usr/local и установка прав..."
    mv vpnserver /usr/local/
    cd /usr/local/vpnserver/ || { log_error "Не удалось перейти в /usr/local/vpnserver/"; exit 1; }
    chmod 600 *
    chmod 700 vpncmd vpnserver
}

###############################################
# Настройка конфигурации vpn_server.config   #
###############################################
configure_vpn_config() {
    log_info "Скачивание и настройка файла конфигурации vpn_server.config..."
    wget -O /usr/local/vpnserver/vpn_server.config https://raw.githubusercontent.com/Axino86/vpn-soft-ether/main/vpn_server.config
    # Генерация случайного MAC-адреса для TAP адаптера
    local MAC
    MAC=$(printf '%.2x\n' "$(shuf -i 0-281474976710655 -n 1)" | sed -r 's/(..)/\1:/g' | cut -d: -f -6 | tr '[:lower:]' '[:upper:]')
    log_info "Сгенерирован MAC для TAP адаптера: ${MAC}"
    sed -i "s/5E-BD-34-92-20-30/${MAC}/g" /usr/local/vpnserver/vpn_server.config
}

###########################################
# Настройка systemd unit для vpnserver   #
###########################################
configure_systemd_service() {
    log_info "Скачивание unit файла systemd для vpnserver..."
    wget -O /lib/systemd/system/vpnserver.service https://raw.githubusercontent.com/Axino86/vpn-soft-ether/main/vpnserver.service
}

##########################################
# Настройка DNSMasq и ad-blocking        #
##########################################
configure_dnsmasq() {
    log_info "Скачивание и настройка конфигурации DNSMasq..."
    wget -O /etc/dnsmasq.conf https://raw.githubusercontent.com/Axino86/vpn-soft-ether/main/dnsmasq.conf
    mkdir -p /etc/systemd/system/dnsmasq.service.d
    wget -O /etc/systemd/system/dnsmasq.service.d/clearlease.conf https://raw.githubusercontent.com/Axino86/vpn-soft-ether/main/dnsmasq.service_clearlease.conf
    # Определение текущего сетевого интерфейса
    local NET_INTERFACE
    NET_INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    log_info "Обнаружен сетевой интерфейс: ${NET_INTERFACE}"
    sed -i "s/ens3/${NET_INTERFACE}/g" /etc/dnsmasq.conf
    # Настройка ad-blocking: скачиваем и выполняем скрипт обновления hosts
    wget -O /root/updateHosts.sh https://raw.githubusercontent.com/Axino86/vpn-soft-ether/main/updateHosts.sh
    chmod a+x /root/updateHosts.sh
    bash /root/updateHosts.sh
}

##########################################
# Настройка cron задач для ad-blocking и  #
# очистки логов                          #
##########################################
configure_cron_jobs() {
    log_info "Настройка cron задач для обновления hosts и очистки логов..."
    # Cron для ad-blocking
    local cmd_adblock="/root/updateHosts.sh >/dev/null 2>&1"
    local job_adblock="0 0 * * * ${cmd_adblock}"
    (crontab -l 2>/dev/null | grep -v -F "${cmd_adblock}" ; echo "${job_adblock}") | crontab -

    # Cron для очистки логов
    wget -O /root/softetherlogpurge.sh https://raw.githubusercontent.com/Axino86/vpn-soft-ether/main/softetherlogpurge.sh
    chmod a+x /root/softetherlogpurge.sh
    local cmd_logpurge="/root/softetherlogpurge.sh >/dev/null 2>&1"
    local job_logpurge="0 0 * * * ${cmd_logpurge}"
    (crontab -l 2>/dev/null | grep -v -F "${cmd_logpurge}" ; echo "${job_logpurge}") | crontab -
}

###########################################
# Настройка параметров ядра (sysctl.conf) #
###########################################
configure_sysctl() {
    log_info "Настройка параметров ядра для IP forwarding и других сетевых параметров..."
    cat >> /etc/sysctl.conf <<'EOL'
net.core.somaxconn = 4096
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.send_redirects = 1
net.ipv4.conf.default.proxy_arp = 0
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.tap_soft.accept_ra = 2
net.ipv6.conf.all.accept_ra = 1
net.ipv6.conf.all.accept_source_route = 1
net.ipv6.conf.all.accept_redirects = 1
net.ipv6.conf.all.proxy_ndp = 1
EOL
    sysctl -f
}

###########################################
# Скачивание вспомогательных скриптов     #
# для iptables и статической привязки     #
###########################################
download_iptables_scripts() {
    log_info "Скачивание скриптов для управления iptables..."
    wget -O /root/softether-iptables.sh https://raw.githubusercontent.com/Axino86/vpn-soft-ether/main/softether-iptables.sh
    chmod +x /root/softether-iptables.sh
    wget -O /root/client_ports_iptables_conf.sh https://raw.githubusercontent.com/Axino86/vpn-soft-ether/main/client_ports_iptables_conf.sh
    chmod +x /root/client_ports_iptables_conf.sh
    # Создание файла для статической привязки MAC адресов
    touch /etc/ethers
}

###########################################
# Включение и перезапуск сервисов         #
###########################################
enable_and_start_services() {
    log_info "Включение сервисов vpnserver и dnsmasq..."
    systemctl enable vpnserver dnsmasq
    systemctl daemon-reload
    systemctl stop dnsmasq.service || true
    systemctl restart vpnserver
    systemctl status vpnserver dnsmasq || true
}

###########################################
# Генерация самоподписанного сертификата   #
###########################################
generate_certificate() {
    log_info "Генерация самоподписанного сертификата для vpn server..."
    /usr/local/vpnserver/vpncmd /server localhost /password:"${VPN_SERVER_PASSWORD}" /cmd ServerCertRegenerate US
}

##############################
# Очистка временных файлов    #
##############################
cleanup() {
    log_info "Удаление временного архива..."
    rm -f "${SOFTETHER_ARCHIVE_NAME}"
}

##############################
# Итоговые инструкции        #
##############################
final_instructions() {
    log_info "==============================="
    echo "Конфигурационные файлы:"
    echo "  - DNSMasq: /etc/dnsmasq.conf"
    echo "  - Iptables: /root/softether-iptables.sh"
    echo "  - SoftEther VPN: /usr/local/vpnserver/vpn_server.config"
    echo "  - Systemd unit: /lib/systemd/system/vpnserver.service"
    echo "==============================="
    echo "Управление сервисом SoftEther VPN:"
    echo "  systemctl start vpnserver"
    echo "  systemctl stop vpnserver"
    echo "  systemctl restart vpnserver"
    echo "  systemctl status vpnserver"
    echo "==============================="
    echo "Управление сервисом DNSMasq:"
    echo "  systemctl start dnsmasq"
    echo "  systemctl stop dnsmasq"
    echo "  systemctl restart dnsmasq"
    echo "  systemctl status dnsmasq"
    echo "==============================="
    echo "Дефолтный VPN-пользователь: test"
    echo "Пароль для VPN и администратора: ${VPN_SERVER_PASSWORD}"
    local VPNEXTERNALIP
    VPNEXTERNALIP=$(wget -qO- -t1 -T2 ipv4.icanhazip.com || echo "IP не определен")
    echo "Подключайтесь к ${VPNEXTERNALIP}:443"
    echo "Для подключения клиента скачайте SoftEther VPN Client с:"
    echo "https://www.softether-download.com/en.aspx?product=softether"
}

##############################
# Главная функция            #
##############################
main() {
    install_dependencies
    backup_and_flush
    download_softether
    compile_softether
    install_softether
    configure_vpn_config
    configure_systemd_service
    configure_dnsmasq
    download_iptables_scripts
    configure_sysctl
    configure_cron_jobs
    enable_and_start_services
    generate_certificate
    cleanup
    final_instructions
}

# Запуск основного процесса
main "$@"

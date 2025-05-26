#!/usr/bin/env bash
# updateHosts.sh — генератор ~/hosts.supp для ad-blocking через DNSMasq
# Алгоритм из Скрипта 1, генерация итогового файла и пути как в Скрипте 3
# Автор: Александр / 2025

set -euo pipefail
IFS=$'\n\t'

##############################
# Проверка прав суперпользователя
##############################
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Запуск скрипта возможен только от root." >&2
  exit 1
fi

##############################
# Подготовка временных файлов
##############################
temphosts1=$(mktemp)
temphosts2=$(mktemp)
suppfile=~/hosts.supp

cleanup() {
  rm -f "$temphosts1" "$temphosts2" "${suppfile}.tmp"
}
trap cleanup EXIT

##############################
# Источники блокировки рекламы и трекеров
##############################
sources=(
  # Основные глобальные списки
  "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
  "https://blocklistproject.github.io/Lists/ads.txt"
  "https://raw.githubusercontent.com/notracking/hosts-blocklists/master/hostnames.txt"
  "https://raw.githubusercontent.com/jerryn70/GoodbyeAds/master/Hosts/GoodbyeAds.txt"
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.txt"
  "https://raw.githubusercontent.com/lightswitch05/hosts/master/ads-and-tracking-extended.txt"

  # Дополнительные источники для РФ/СНГ
  "https://someonewhocares.org/hosts/zero/hosts"
  "https://raw.githubusercontent.com/nomadturk/vpn-adblock/master/hosts-sources/nomad/hosts"
  "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/android-tracking.txt"
  "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV.txt"
  "https://raw.githubusercontent.com/ookangzheng/dbl-oisd-nl/master/dbl.txt"
)

echo "[INFO] Скачивание списков блокировки..."
for url in "${sources[@]}"; do
  echo "→ $url"
  if ! curl --fail --silent --show-error "$url" >> "$temphosts1"; then
    echo "[WARN] Не удалось получить $url" >&2
  fi
done

##############################
# Очистка, нормализация, сортировка
##############################
echo "[INFO] Очистка и фильтрация..."
sed -e 's/\r//' \
    -e '/^127\.0\.0\.1\|^0\.0\.0\.0/!d' \
    -e '/localhost/d' \
    -e 's/^127\.0\.0\.1/0.0.0.0/' \
    -e 's/[[:space:]]\+/\t/' \
    -e 's/#.*$//' \
    -e 's/[[:space:]]*$//' \
    -e '/^0\.0\.0\.0/!d' \
    "$temphosts1" | sort -u > "$temphosts2"

# Удаление самоссылок
sed -i 's/^0\.0\.0\.0\t0\.0\.0\.0/0.0.0.0/' "$temphosts2"

##############################
# Генерация итогового файла
##############################
echo "[INFO] Создание итогового файла: $suppfile"
echo -e "#<local-data>" > "$suppfile"
echo -e "\n# Ad blocking hosts generated $(date)" >> "$suppfile"

# Временный файл для подсчёта строк
cat "$temphosts2" > "${suppfile}.tmp"
total=$(grep --regexp="\$" --count "${suppfile}.tmp")

echo -e "# Total number of blocked hosts are: $total" >> "$suppfile"
cat "$temphosts2" >> "$suppfile"
echo -e "#</local-data>" >> "$suppfile"

##############################
# Копирование в /etc и завершение
##############################
echo "[INFO] Копирование $suppfile → /etc/hosts.supp"
cp "$suppfile" /etc/hosts.supp

echo "[OK] Файл создан: /etc/hosts.supp"
echo "Перезапустите DNSMasq: systemctl restart dnsmasq"

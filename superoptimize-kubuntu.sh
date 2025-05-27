#!/bin/bash
set -e

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запускайте от root"
  exit 1
fi

echo "[*] Подготовка: установка необходимых утилит..."
apt update
apt install -y preload zram-tools irqbalance cpufrequtils build-essential linux-tools-$(uname -r) tuned

#########################################
## 1. CPU/NUMA: Ryzen-оптимизации
#########################################

echo "[*] Оптимизация CPU и NUMA для Ryzen"
cpufreq-set -g performance

# Отключение SMT, если требуется производительность одного потока
# echo off > /sys/devices/system/cpu/smt/control

# NUMA-aware настройки
sysctl -w kernel.numa_balancing=0
echo never > /sys/kernel/mm/transparent_hugepage/enabled

# IRQ балансировка
systemctl enable irqbalance
systemctl start irqbalance

#########################################
## 2. Отключаем systemd-journald и заменяем на busybox syslog
#########################################

echo "[*] Замена systemd-journald на busybox-syslogd"
systemctl stop systemd-journald
systemctl disable systemd-journald
systemctl mask systemd-journald

apt install -y busybox-syslogd
systemctl enable busybox-syslogd
systemctl start busybox-syslogd

#########################################
## 3. Поддержка hugepages и NUMA-узлов
#########################################

echo "[*] Настройка hugepages"
echo "vm.nr_hugepages=128" >> /etc/sysctl.conf
sysctl -p

#########################################
## 4. Флаги компиляции для всей системы
#########################################

echo "[*] Применение флагов -O3, -march=native, LTO"
cat <<EOF > /etc/environment
CFLAGS="-O3 -march=native -pipe"
CXXFLAGS="-O3 -march=native -pipe"
LDFLAGS="-fuse-linker-plugin -flto"
MAKEFLAGS="-j$(nproc)"
EOF

#########################################
## 5. I/O и память
#########################################

echo "[*] Установка параметров памяти и I/O"
cat <<EOF >> /etc/sysctl.d/99-performance.conf
vm.dirty_ratio = 8
vm.dirty_background_ratio = 4
vm.swappiness = 1
vm.vfs_cache_pressure = 50
vm.dirty_expire_centisecs = 200
vm.dirty_writeback_centisecs = 100
kernel.sched_autogroup_enabled = 0
EOF

sysctl --system

# Безопасный I/O scheduler
for dev in /sys/block/nvme*/queue/scheduler; do
  echo none > "$dev"
done

#########################################
## 6. Оптимизация сети (BBR + max buf)
#########################################

echo "[*] Настройка сети"
modprobe tcp_bbr
sysctl -w net.ipv4.tcp_congestion_control=bbr
sysctl -w net.core.rmem_max=67108864
sysctl -w net.core.wmem_max=67108864
sysctl -w net.ipv4.tcp_rmem="4096 87380 67108864"
sysctl -w net.ipv4.tcp_wmem="4096 65536 67108864"
sysctl -w net.core.netdev_max_backlog=16384

#########################################
## 7. Подключение tuned профиля
#########################################

echo "[*] Включение tuned профиля для производительности"
tuned-adm profile latency-performance

#########################################
## 8. Кастомное ядро Async Direct I/O
#########################################

echo "[*] Подготовка к установке кастомного ядра (опционально)"
echo "!!! Убедись, что у тебя исходники ядра с патчами и включен Async Direct I/O"

# Пример клонирования и сборки:
# git clone --depth=1 https://github.com/torvalds/linux.git /usr/src/linux-custom
# cd /usr/src/linux-custom
# patch -p1 < ~/aio-direct.patch
# make -j$(nproc) deb-pkg

#########################################
## 9. Финальное
#########################################

echo "[✔] Система готова. Перезагрузи, чтобы применить все параметры."

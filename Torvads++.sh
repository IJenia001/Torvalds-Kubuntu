#!/bin/bash

# Должен запускаться от root
if [[ $EUID -ne 0 ]]; then
   echo "Запусти этот скрипт от root"
   exit 1
fi

echo "[*] Начинаем темную оптимизацию ядра Kubuntu 25.04..."

############################################
## 1. CPU: Отключаем всё лишнее и турбируем ##
############################################

echo "[*] Отключаем энергосбережение и включаем максимальную производительность"

# Ставим производительный governor
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
  echo performance > "$cpu/cpufreq/scaling_governor"
done

# Turbo Boost ON (если нужно – можно и OFF, если стабильность важнее)
echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true

# Disable CPU C-States (не рекомендуется на ноутбуках)
echo 1 > /dev/cpu_dma_latency

##############################################
## 2. I/O: Async Direct I/O, dirty-tweaks    ##
##############################################

echo "[*] Настройка дискового ввода-вывода"

# Подходят для NVMe
sysctl -w vm.dirty_ratio=8
sysctl -w vm.dirty_background_ratio=4
sysctl -w vm.dirty_expire_centisecs=200
sysctl -w vm.dirty_writeback_centisecs=100
sysctl -w vm.vfs_cache_pressure=50

# Async Direct I/O патч предположим уже внедрён (воображаем)
# Преднастройка I/O scheduler
for dev in /sys/block/nvme*/queue/scheduler; do
  echo none > "$dev"
done

############################################
## 3. Сетевые ускорения (если используется) ##
############################################

echo "[*] Ускоряем сетевую подсистему"

sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216'
sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216'
sysctl -w net.core.netdev_max_backlog=5000
sysctl -w net.ipv4.tcp_congestion_control=bbr

############################################
## 4. Swap и кэширование                   ##
############################################

echo "[*] Работа со swap и swappiness"

sysctl -w vm.swappiness=1
sysctl -w vm.page-cluster=0
sysctl -w vm.min_free_kbytes=65536

############################################
## 5. Отключение ненужных служб и логов     ##
############################################

echo "[*] Отключаем логирование, чтоб не тратить SSD"

systemctl disable systemd-journald-audit.socket
systemctl stop systemd-journald
systemctl mask systemd-journald

# logrotate скидываем на /tmp
sed -i 's|/var/log|/tmp|g' /etc/logrotate.conf

############################################
## 6. Preload, ZRAM и прочее                ##
############################################

echo "[*] Включаем preload и zram"

apt install -y preload zram-tools
systemctl enable preload

# zram на 2GB
echo "zram_enabled=1" > /etc/default/zramswap
echo "zram_size_mb=2048" >> /etc/default/zramswap
systemctl restart zramswap

############################################
## 7. Грубые патчи в /etc/sysctl.conf       ##
############################################

cat <<EOF >> /etc/sysctl.conf

# Hardcore tweaks от Торвальдса++
vm.overcommit_memory = 1
vm.overcommit_ratio = 100
kernel.sched_autogroup_enabled = 0
kernel.numa_balancing = 0
kernel.randomize_va_space = 0
EOF

############################################
## 8. Файловая система (если ext4)         ##
############################################

echo "[*] Настройка ext4..."

mount -o remount,noatime,nodiratime,commit=60 /
tune2fs -o journal_data_writeback /dev/nvme0n1p2  # ПРИМЕНЯЙ С УМОМ!

############################################
## 9. Удаление Snap и мусора               ##
############################################

echo "[*] Удаляем Snap"

systemctl stop snapd.service
systemctl disable snapd.service
apt purge -y snapd

############################################
## 10. Финальное сообщение                 ##
############################################

echo "[✔] Оптимизация завершена. Перезагрузи систему."


#!/usr/bin/env bash
# sysinfo.sh — сбор системной информации
# Запуск: sudo ./sysinfo.sh [--save filename]
# Если не указан --save, вывод будет в stdout.

set -u
OUTFILE=""
if [[ "${1-}" == "--save" && -n "${2-}" ]]; then
  OUTFILE="$2"
fi

# helper: write either to stdout or file
write() {
  if [[ -n "$OUTFILE" ]]; then
    echo -e "$@" | tee -a "$OUTFILE"
  else
    echo -e "$@"
  fi
}

sep() { write "\n========== $1 ==========\n"; }

# проверка доступности команды
have() { command -v "$1" >/dev/null 2>&1; }

# ===============================
# Собираем информацию
# ===============================
sep "GENERAL"
write "Дата: $(date)"
write "Хостнейм: $(hostname --fqdn 2>/dev/null || hostname)"
write "Uptime: $(uptime -p)"
write "Kernel: $(uname -r) ($(uname -m))"
if have lsb_release; then
  write "Distro: $(lsb_release -d -s)"
else
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    write "Distro: $PRETTY_NAME"
  fi
fi

sep "HARDWARE: CPU / MEMORY"
if have lscpu; then
  lscpu | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
else
  write "lscpu отсутствует, fallback /proc/cpuinfo:"
  sed -n '1,12p' /proc/cpuinfo | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi

write ""
write "Memory:"
free -h | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done

sep "DISKS / FILESYSTEMS"
if have lsblk; then
  write "Block devices (lsblk):"
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
else
  write "lsblk отсутствует"
fi

write ""
write "Монтированные файловые системы (df -h):"
df -hT --total | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done

if have blkid; then
  write ""
  write "UUID/FILESYSTEMs (blkid):"
  blkid | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi

if have smartctl; then
  write ""
  write "SMART: краткий статус дисков (требует прав root):"
  for dev in $(lsblk -dn -o NAME | grep -E '^(nvme|sd)'); do
    d="/dev/$dev"
    write "  $d:"
    smartctl -H "$d" 2>&1 | sed 's/^/    /' | while IFS= read -r l; do write "$l"; done
  done
else
  write "smartctl не найден (установите smartmontools для SMART-проверки)."
fi

sep "NETWORK: interfaces / routes"
if have ip; then
  write "IP (короткий):"
  ip -br a | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
  write ""
  write "Маршруты:"
  ip route show | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
else
  write "Команда ip не найдена"
fi

write ""
write "DNS:"
resolvectl status 2>/dev/null | sed 's/^/  /' | head -n 20 | while IFS= read -r l; do write "$l"; done || \
  (grep -E 'nameserver' /etc/resolv.conf 2>/dev/null | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done)

sep "OPEN PORTS / SERVICES"
write "Active listening sockets (ss -tulwn):"
if have ss; then
  ss -tulwn | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
else
  write "ss отсутствует, fallback netstat:"
  if have netstat; then
    netstat -tuln | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
  else
    write "netstat тоже отсутствует"
  fi
fi

write ""
write "Процессы использующие порты (top 30):"
if have lsof; then
  lsof -i -P -n | sed -n '1,60p' | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
else
  write "lsof не найден (установите lsof для подробного списка)."
fi

sep "FIREWALL / RULES"
if have iptables; then
  write "iptables -L -n -v:"
  iptables -L -n -v 2>/dev/null | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi
if have nft; then
  write ""
  write "nft ruleset:"
  nft list ruleset 2>/dev/null | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi
if have ufw; then
  write ""
  write "ufw status:"
  ufw status verbose 2>/dev/null | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi
if systemctl is-active --quiet firewalld 2>/dev/null; then
  write ""
  write "firewalld is active:"
  firewall-cmd --list-all --zone=public 2>/dev/null | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi

sep "USERS / SESSIONS"
write "Текущие авторизованные пользователи (who):"
who | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done

write ""
write "Последние логины (last -n 10):"
if have last; then
  last -n 10 | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi

write ""
write "Список системных пользователей (getent passwd):"
getent passwd | awk -F: '{printf "  %-20s UID:%-6s GID:%-6s Home:%-20s Shell:%s\n",$1,$3,$4,$6,$7}' | while IFS= read -r l; do write "$l"; done

sep "CRON / TIMER / SYSTEMD UNITS"
write "cron jobs: /etc/cron*, crontab -l (для текущего пользователя):"
if [[ -d /etc/cron.* ]]; then
  for f in /etc/cron.*/*; do [[ -e $f ]] && echo "  $f"; done | while IFS= read -r l; do write "$l"; done
fi
if have crontab; then
  write ""
  write "crontab -l (root):"
  sudo crontab -l 2>/dev/null | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done || write "  пусто или нет прав"
fi

write ""
write "Top systemd units (active):"
systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print "  "$1" "$2" "$3}' | while IFS= read -r l; do write "$l"; done

sep "KERNEL MODULES / HARDWARE BUS"
if have lsmod; then
  write "lsmod (kernel modules):"
  lsmod | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi
if have lspci; then
  write ""
  write "lspci:"
  lspci -vnn | sed 's/^/  /' | sed -n '1,60p' | while IFS= read -r l; do write "$l"; done
fi
if have lsusb; then
  write ""
  write "lsusb:"
  lsusb 2>/dev/null | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi

sep "SOFTWARE / PACKAGES"
if have dpkg; then
  write "Debian/Ubuntu packages (top 30 by size):"
  dpkg-query -Wf='${Installed-Size}\t${Package}\n' 2>/dev/null | sort -nr | head -n 30 | awk '{printf "  %-8s %s\n",$1,$2}' | while IFS= read -r l; do write "$l"; done
elif have rpm; then
  write "RPM packages (some):"
  rpm -qa --last | sed 's/^/  /' | head -n 30 | while IFS= read -r l; do write "$l"; done
else
  write "Неизвестный пакетный менеджер"
fi

sep "LOGS: CRITICAL (journalctl + files)"
write "journalctl -n 200 --no-pager (system):"
journalctl -n 200 --no-pager 2>/dev/null | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done

write ""
if [[ -f /var/log/syslog ]]; then
  write "/var/log/syslog (last 150 lines):"
  tail -n 150 /var/log/syslog | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi
if [[ -f /var/log/messages ]]; then
  write "/var/log/messages (last 150 lines):"
  tail -n 150 /var/log/messages | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi
if [[ -f /var/log/auth.log ]]; then
  write "/var/log/auth.log (last 200 lines):"
  tail -n 200 /var/log/auth.log | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi

sep "MISC: processes / top / io"
write "Top CPU consuming (ps):"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 15 | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done

write ""
write "Top Memory consuming (ps):"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 15 | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done

write ""
if have iotop; then
  write "iotop (top I/O):"
  iotop -boqqt 2>/dev/null | head -n 20 | sed 's/^/  /' | while IFS= read -r l; do write "$l"; done
fi

sep "END"
write "Готово. $(date)"
if [[ -n "$OUTFILE" ]]; then
  write ""
  write "Отчёт сохранён в: $OUTFILE"
fi

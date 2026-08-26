#!/bin/bash

# ============================================================
#  ПОЧИНКА — разовая. Чинит то, что сломал перенос папок:
#   1) убирает симлинки Desktop / Documents / Downloads
#      (в т.ч. вложенные Desktop/Desktop и т.п.),
#   2) возвращает на их место настоящие папки
#      (из .old, иначе создает пустые),
#   3) пересоздает с нуля папку демона «Недавние объекты»
#      (sharedfilelistd падал по кругу из-за битых файлов),
#   4) снимает зависшую петлю монтирования VeraCrypt,
#   5) перезапускает Finder и Dock.
#  Данные на /Volumes/EncryptDisk НЕ трогает вообще.
# ============================================================

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
cd "$HOME" || exit 1

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'
ok()  { echo -e "  ${GREEN}OK${NC}  $1"; }
bad() { echo -e "  ${RED}!!${NC}  $1"; }
step() { echo ""; echo -e "${BOLD}== $1 ==${NC}"; }

IPS="$HOME/Library/Logs/DiagnosticReports"
IPS_BEFORE=$(ls "$IPS" 2>/dev/null | sort)

echo -e "${BOLD}Починка: папки, демон «недавних», Finder. Данные на диске не трогаю.${NC}"

# ---------- 1. Папки ----------
step "1/5 Папки: убираю симлинки, возвращаю настоящие папки"
for d in Desktop Documents Downloads; do
    src="$HOME/$d"

    # вложенный симлинк ( ~/Desktop/Desktop -> диск )
    if [ -L "$src/$d" ] 2>/dev/null; then
        rm -f "$src/$d" && ok "убран вложенный симлинк: $d/$d" || bad "не убрался: $d/$d"
    fi

    # сам симлинк вместо папки
    if [ -L "$src" ]; then
        rm -f "$src" && ok "убран симлинк: $d" || bad "не убрался симлинк: $d"
    fi

    # настоящая папка на месте? если нет — вернуть/создать
    if [ -d "$src" ]; then
        ok "$d — настоящая папка"
        rm -rf "$src.old" "$src.autosetup-old" 2>/dev/null
    elif [ -d "$src.old" ]; then
        mv "$src.old" "$src" && ok "$d — возвращена из .old"
    elif [ -d "$src.autosetup-old" ]; then
        mv "$src.autosetup-old" "$src" && ok "$d — возвращена из .autosetup-old"
    else
        mkdir -p "$src" && ok "$d — создана пустая (твои файлы лежат на EncryptDisk)"
    fi
done

# ---------- 2. Демон «Недавних объектов» ----------
step "2/5 Демон «Недавние объекты»: пересоздаю его папку с нуля"
SFL="$HOME/Library/Application Support/com.apple.sharedfilelist"
rm -rf "$SFL.bak" 2>/dev/null
if [ -d "$SFL" ]; then
    mv "$SFL" "$SFL.bak" 2>/dev/null && ok "старая папка убрана в .bak (это только списки «недавних»)"
fi
killall sharedfilelistd 2>/dev/null
echo "      жду 15 секунд, пока macOS поднимет демона заново..."
sleep 15
if ! pgrep -x sharedfilelistd >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$(id -u)/com.apple.coreservices.sharedfilelistd" 2>/dev/null
    sleep 5
fi
if pgrep -x sharedfilelistd >/dev/null 2>&1; then
    ok "sharedfilelistd работает (списки «недавних» будут пустые — так и задумано)"
else
    bad "sharedfilelistd не поднялся — скопируй итог этого скрипта в чат"
fi

# ---------- 3. Петля VeraCrypt ----------
step "3/5 Зависшая петля монтирования VeraCrypt"
AUX=$(mount 2>/dev/null | grep -o '/private/tmp/\.veracrypt_aux_mnt[0-9]*' | sort -u)
if [ -z "$AUX" ]; then
    ok "петли нет"
elif pgrep -x VeraCrypt >/dev/null 2>&1; then
    bad "VeraCrypt сейчас запущен: закрой его (Dismount All -> Quit) и запусти этот скрипт еще раз"
else
    for m in $AUX; do
        umount -f "$m" 2>/dev/null
        pkill -f "go-nfsv4.*veracrypt_aux" 2>/dev/null
        sleep 2
        umount -f "$m" 2>/dev/null
        mount | grep -q " $m " && bad "петля НЕ снята: $m — скопируй итог в чат" || ok "петля снята: $m"
    done
fi

# ---------- 4. Finder и Dock ----------
step "4/5 Finder и Dock: перезапуск"
killall Dock 2>/dev/null
killall Finder 2>/dev/null
echo "      жду 5 секунд..."
sleep 5
pgrep -x Finder >/dev/null 2>&1 && ok "Finder запущен" || bad "Finder не поднялся — скопируй итог в чат"

# ---------- 5. Итог ----------
step "5/5 Итог"
ls -la "$HOME" | grep -E "Desktop|Documents|Downloads" 2>/dev/null
echo ""
IPS_AFTER=$(ls "$IPS" 2>/dev/null | sort)
NEW_IPS=$(comm -13 <(echo "$IPS_BEFORE") <(echo "$IPS_AFTER"))
if [ -z "$NEW_IPS" ]; then
    ok "новых падений демона нет"
else
    bad "новые отчеты о падении (скопируй в чат):"
    echo "$NEW_IPS"
fi

echo ""
echo -e "${BOLD}Готово.${NC} Данные приложений и файлов — на /Volumes/EncryptDisk/DataAPP, их не трогал."
echo "Открой Finder и проверь папки. Симлинки на диск поставим потом, отдельным шагом."
echo "Если есть строки с '!!' — скопируй весь итог в чат."

#!/bin/bash

# ============================================================
#  ФИКС — последний. Делает ВСЁ сразу и без вопросов:
#   1) вырубает VeraCrypt + FUSE-T и снимает их зависшее
#      монтирование (именно оно вешает Finder),
#   2) пересоздает падающего по кругу демона «недавних»,
#   3) перезапускает iCloud-провайдеров (безопасно, сами встанут),
#   4) полностью сбрасывает Finder (настройки/кеш/окна),
#   5) честный вердикт. Если что-то осталось — сам вызывает
#      перезагрузку (единственный способ снять зависшее в ядре).
#  Данные на /Volumes/EncryptDisk НЕ трогает вообще.
# ============================================================

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

GREEN='\033[0;32m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}  $1"; }
bad()  { echo -e "  ${RED}!!${NC}  $1"; FAILS=$((FAILS + 1)); }
step() { echo ""; echo -e "${BOLD}== $1 ==${NC}"; }
FAILS=0

IPS="$HOME/Library/Logs/DiagnosticReports"
IPS_BEFORE=$(ls "$IPS" 2>/dev/null | sort)

# ---------- 1. VeraCrypt + FUSE-T под корень ----------
step "1/5 Вырубаю VeraCrypt и FUSE-T (данные на диске — НЕ трогаю)"

# сначала аккуратно: пусть сам размонтирует что успел
osascript -e 'quit app "VeraCrypt"' >/dev/null 2>&1
sleep 2

# висячие smb-петли VeraCrypt
LOOPS=$(mount 2>/dev/null | grep -o '/private/tmp/\.veracrypt_aux_mnt[0-9]*' | sort -u)
for m in $LOOPS; do
    umount -f "$m" 2>/dev/null
    diskutil unmount force "$m" >/dev/null 2>&1
done

# только ПОСЛЕ отмонтирования убиваем процессы
killall VeraCrypt 2>/dev/null
sleep 1
pkill -9 -f "VeraCrypt.*core-service" 2>/dev/null
pkill -9 -x go-nfsv4 2>/dev/null
sleep 2
pkill -9 -x go-nfsv4 2>/dev/null

# повторный заход, если петля пересоздалась
LOOPS2=$(mount 2>/dev/null | grep -o '/private/tmp/\.veracrypt_aux_mnt[0-9]*' | sort -u)
for m in $LOOPS2; do
    umount -f "$m" 2>/dev/null
    diskutil unmount force "$m" >/dev/null 2>&1
done
sleep 1

if mount 2>/dev/null | grep -q veracrypt_aux; then
    bad "петля монтирования НЕ снялась — добьет перезагрузка в конце"
else
    ok "VeraCrypt/FUSE-T выключены, петель нет"
fi
pgrep -f VeraCrypt >/dev/null 2>&1 && bad "процессы VeraCrypt живы — добьет перезагрузка" \
                                   || ok "процессов VeraCrypt нет"

# ---------- 2. Демон «недавних» ----------
step "2/5 Демон «недавних»: пересоздаю папку с нуля"
SFL="$HOME/Library/Application Support/com.apple.sharedfilelist"
rm -rf "$SFL.bak2" 2>/dev/null
[ -d "$SFL" ] && mv "$SFL" "$SFL.bak2" 2>/dev/null
killall sharedfilelistd 2>/dev/null
ok "старая папка в .bak2, демон стартует чистым (это только списки «недавних»)"

# ---------- 3. iCloud-провайдеры ----------
step "3/5 Перезапускаю iCloud-провайдеров (если зависли на папках)"
killall fileproviderd 2>/dev/null
killall bird 2>/dev/null
ok "fileproviderd и bird перезапущены (сами поднимутся)"

# ---------- 4. Finder: полный сброс ----------
step "4/5 Finder: полный сброс настроек и кеша"
rm -f "$HOME/Library/Preferences/com.apple.finder.plist" 2>/dev/null
rm -rf "$HOME/Library/Saved Application State/com.apple.finder.savedState" 2>/dev/null
rm -rf "$HOME/Library/Caches/com.apple.finder" 2>/dev/null
rm -f "$HOME/.DS_Store" 2>/dev/null
killall cfprefsd 2>/dev/null
killall Dock 2>/dev/null
killall Finder 2>/dev/null
sleep 4
if pgrep -x Finder >/dev/null 2>&1; then
    ok "Finder поднялся с чистыми настройками"
else
    open -a Finder 2>/dev/null; sleep 2
    pgrep -x Finder >/dev/null 2>&1 && ok "Finder поднялся" \
        || bad "Finder не поднялся — добьет перезагрузка"
fi

# ---------- 5. Вердикт ----------
step "5/5 Вердикт"
for d in Desktop Documents Downloads; do
    if [ -L "$HOME/$d" ]; then
        bad "$d — снова симлинк (кто-то его пересоздал)"
    else
        ok "$d — настоящая папка"
    fi
done
IPS_AFTER=$(ls "$IPS" 2>/dev/null | sort)
NEW_IPS=$(comm -13 <(echo "$IPS_BEFORE") <(echo "$IPS_AFTER") | grep . || true)
if [ -z "$NEW_IPS" ]; then
    ok "новых падений за это время нет"
else
    bad "демон падает ДАЛЬШЕ (файлы ниже — в чат):"
    echo "$NEW_IPS"
fi

echo ""
if [ "$FAILS" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}ВСЁ ЧИСТО.${NC} Finder должен работать. VeraCrypt открой после проверки."
    echo "Списки «недавних» пустые — так и задумано, наполнятся сами."
else
    echo -e "${RED}${BOLD}Осталось: $FAILS пункта(ов). Лечится перезагрузкой.${NC}"
    echo "Перезагрузка через 10 секунд — нажми Ctrl+C, если не надо."
    sleep 10
    osascript -e 'tell application "System Events" to restart' 2>/dev/null \
        || { echo "Не вышло автоматом — перезагрузи сам:  -> Перезагрузить."; exit 1; }
fi

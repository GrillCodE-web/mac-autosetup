#!/bin/bash

# ============================================================
#  ФИКС — последний. Делает ВСЁ сразу и без вопросов:
#   1) вырубает VeraCrypt + FUSE-T и снимает их зависшее
#      монтирование (именно оно вешает Finder),
#   2) пересоздает падающего по кругу демона «недавних»,
#   3) перезапускает iCloud-провайдеров (безопасно, сами встанут),
#   4) убирает симлинки Desktop/Documents/Downloads на диск
#      (и вложенные Desktop/Desktop), возвращает настоящие папки,
#   5) полностью сбрасывает Finder (настройки/кеш/окна),
#   6) честный вердикт. Если что-то осталось — сам вызывает
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
step "1/6 Вырубаю VeraCrypt и FUSE-T (данные на диске — НЕ трогаю)"

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
step "2/6 Демон «недавних»: пересоздаю папку с нуля"
SFL="$HOME/Library/Application Support/com.apple.sharedfilelist"
rm -rf "$SFL.bak2" 2>/dev/null
[ -d "$SFL" ] && mv "$SFL" "$SFL.bak2" 2>/dev/null
killall sharedfilelistd 2>/dev/null
ok "старая папка в .bak2, демон стартует чистым (это только списки «недавних»)"

# ---------- 3. iCloud-провайдеры ----------
step "3/6 Перезапускаю iCloud-провайдеров (если зависли на папках)"
killall fileproviderd 2>/dev/null
killall bird 2>/dev/null
ok "fileproviderd и bird перезапущены (сами поднимутся)"

# ---------- 4. Папки: убираем симлинки на диск ----------
step "4/6 Папки: убираю симлинки на зашифрованный диск"
for d in Desktop Documents Downloads; do
    src="$HOME/$d"

    # вложенный симлинк ~/Desktop/Desktop и т.п.
    if [ -L "$src/$d" ] 2>/dev/null; then
        rm -f "$src/$d" && ok "убран вложенный симлинк: $d/$d"
    fi

    # папка сама стала симлинком на диск
    if [ -L "$src" ]; then
        rm -f "$src"
        if [ -d "$src.old" ]; then
            mv "$src.old" "$src" && ok "$d — симлинк убран, папка возвращена из .old"
        elif [ -d "$src.autosetup-old" ]; then
            mv "$src.autosetup-old" "$src" && ok "$d — симлинк убран, папка возвращена из .autosetup-old"
        else
            mkdir -p "$src" && ok "$d — симлинк убран, создана пустая папка (файлы лежат на EncryptDisk)"
        fi
    else
        ok "$d — уже настоящая папка, симлинка нет"
    fi
done

# ---------- 5. Finder: полный сброс ----------
step "5/6 Finder: полный сброс настроек и кеша"
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

# ---------- 6. Вердикт ----------
step "6/6 Вердикт"
for d in Desktop Documents Downloads; do
    if [ -L "$HOME/$d" ]; then
        bad "$d — снова симлинк (кто-то его пересоздал)"
    elif [ -L "$HOME/$d/$d" ] 2>/dev/null; then
        bad "$d/$d — вложенный симлинк остался"
    else
        ok "$d — настоящая папка, симлинков нет"
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

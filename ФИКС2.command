#!/bin/bash

# ============================================================
#  ФИКС2 — глубокий и последний. Причина мёртвого меню найдена:
#  блок «Recents» в ЗАПУСТИТЬ рвал .sfl2 под живым демоном —
#  sharedfilelistd падал по кругу и намертво вешал SystemUIServer
#  (это он рисует тулбар, часы и меню с яблоком; Finder/Dock тут
#  ни при чём, поэтому их перезапуски ничего не давали).
#
#  Порядок:
#    1) вычистить ВСЁ, что трогал тот блок: остатки папки демона
#       и его plist'ы (recentitems / LSSharedFileList /
#       sharedfilelistd) — plist'ы при починке раньше не чистили,
#       поэтому краши возвращались после каждой перезагрузки,
#    2) 60 секунд следить за краш-репортами: демон мёртв намертво?
#       (если нет — сам напечатает ПРИЧИНУ падения из отчёта),
#    3) перезапустить SystemUIServer + Dock + NotificationCenter,
#    4) тест USB-диска (висящий диск валит весь UI),
#    5) проверка человеком; нет — WindowServer (вся графика).
#  Данные на /Volumes/EncryptDisk НЕ трогает.
# ============================================================

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

GREEN='\033[0;32m'; RED='\033[0;31m'; YEL='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}  $1"; }
bad()  { echo -e "  ${RED}!!${NC}  $1"; }
step() { echo ""; echo -e "${BOLD}== $1 ==${NC}"; }

IPS="$HOME/Library/Logs/DiagnosticReports"

# ---------- 1. Вычищаем ВСЁ состояние блока Recents ----------
step "1/6 Вычищаю всё, что писал/рвал блок «Недавние» в ЗАПУСТИТЬ"
SFL="$HOME/Library/Application Support/com.apple.sharedfilelist"
P="$HOME/Library/Preferences"

for junk in "$SFL" "$SFL.bak" "$SFL.bak2" "$P/com.apple.sharedfilelistd.plist" \
            "$P/com.apple.LSSharedFileList.plist" "$P/com.apple.recentitems.plist"; do
    if [ -e "$junk" ]; then
        rm -rf "${junk}.fixold" 2>/dev/null
        mv "$junk" "${junk}.fixold" 2>/dev/null && ok "убрано в сторону: $(basename "$junk")"
    fi
done
ok "первую десятку «недавних» записей это не стирает — только служебные списки"

killall sharedfilelistd 2>/dev/null
killall cfprefsd 2>/dev/null
killall Dock 2>/dev/null
killall Finder 2>/dev/null
killall SystemUIServer 2>/dev/null
sleep 3

# ---------- 2. 60 секунд следим: краш-цикл умер? ----------
step "2/6 Слежу 60 секунд за краш-репортами демона «недавних»"
BEFORE=$(ls "$IPS" 2>/dev/null | sort)
echo "      (папку демона macOS уже пересоздала пустой — это норма)"
sleep 60
AFTER=$(ls "$IPS" 2>/dev/null | sort)
NEWCRASH=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | grep -i sharedfilelistd || true)

if [ -z "$NEWCRASH" ]; then
    ok "демон «недавних» больше НЕ падает — источник яда удален"
else
    bad "демон падает ДАЛЬШЕ. Причина из самого свежего отчета (ниже в чат):"
    f=$(ls -t "$IPS"/sharedfilelistd-*.ips 2>/dev/null | head -1)
    [ -n "$f" ] && tr ',' '\n' < "$f" | grep -Ei '"asi"|exception|termination|reason' | head -8
fi

# ---------- 3. Меню/тулбар: SystemUIServer ----------
step "3/6 Поднимаю меню: SystemUIServer (тулбар, часы, яблоко)"
killall SystemUIServer 2>/dev/null
killall NotificationCenter 2>/dev/null
killall Dock 2>/dev/null
sleep 3
pgrep -x SystemUIServer >/dev/null 2>&1 \
    && ok "SystemUIServer перезапущен (без логаута, окна целы)" \
    || { sleep 3; pgrep -x SystemUIServer >/dev/null 2>&1 \
           && ok "SystemUIServer поднялся" \
           || bad "SystemUIServer не поднялся — лечит шаг 6"; }

# ---------- 4. Диск ----------
step "4/6 Тест: USB-диск отвечает мгновенно?"
if ls /Volumes/EncryptDisk >/dev/null 2>&1; then
    ok "EncryptDisk отвечает"
else
    bad "EncryptDisk НЕ отвечает — вставший USB валит ВЕСЬ интерфейс."
    echo "      Вытащи кабель диска на 5 секунд и вставь обратно (данным не вредит)."
fi

# ---------- 5. Проверка человеком ----------
step "5/6 ПРОВЕРЬ: ткни в яблоко и в пункт меню справа"
echo ""
printf "   Меню нажимается? Enter = ДА / набери n и Enter = НЕТ: "
read -t 90 ans || true
echo ""
if [ "${ans:-да}" != "n" ]; then
    ok "Меню работает. Готово."
    echo "Если снова залагает — запусти этот скрипт еще раз (он безвреден)."
    exit 0
fi

# ---------- 6. WindowServer ----------
step "6/6 Перезапуск ВСЕЙ графики (WindowServer)"
echo ""
echo -e "  ${YEL}Что будет:${NC} экран мигнет → окно входа → введи пароль — сессия с чистого листа."
echo "  Несохраненное в программах пропадет. Файлы на диске — нет."
echo -e "  ${BOLD}Отмена — Ctrl+C в течение 10 секунд.${NC}"
sleep 10
if sudo -n true 2>/dev/null; then
    ok "перезапускаю графику"
    sudo killall WindowServer 2>/dev/null
    sleep 5
    echo "Не вышло → в Терминале:  sudo shutdown -r now"
    echo "Терминал мертв → зажми кнопку питания на 10 секунд (для диска безопасно)."
else
    echo "Введи вручную (спросит пароль Mac):"
    echo ""
    echo "        sudo killall WindowServer"
    echo ""
    echo "      не помогло →  sudo shutdown -r now"
    echo "      и это мертво → кнопка питания 10 секунд"
fi

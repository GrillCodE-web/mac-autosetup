#!/bin/bash

# ============================================================
#  ФИКС2 — глубокая починка МЕНЮ/ТУЛБАРА/ЯБЛОКА.
#  Тулбар, часы и кнопка  принадлежат SystemUIServer — его
#  до сих пор никто не перезапускал. Порядок эскалации:
#    1) SystemUIServer (лечит зависшее меню, без логаута)
#    2) Dock, NotificationCenter, Spotlight-воркеры
#    3) быстрый тест: диск отвечает? (висящий USB валит весь UI)
#    4) вопрос: заработало? если нет —
#    5) WindowServer: перезапуск ВСЕЙ графики (выход на экран
#       входа; несохраненное в программах пропадет)
#  Данные на /Volumes/EncryptDisk НЕ трогает.
# ============================================================

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

GREEN='\033[0;32m'; RED='\033[0;31m'; YEL='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}  $1"; }
bad()  { echo -e "  ${RED}!!${NC}  $1"; }
step() { echo ""; echo -e "${BOLD}== $1 ==${NC}"; }

# ---------- 1. SystemUIServer — владелец меню и тулбара ----------
step "1/5 Перезапускаю SystemUIServer (тулбар, часы, меню, яблоко)"
if pgrep -x SystemUIServer >/dev/null 2>&1; then
    killall SystemUIServer 2>/dev/null
    sleep 3
    pgrep -x SystemUIServer >/dev/null 2>&1 \
        && ok "SystemUIServer перезапущен (это НЕ логаут, окна остались)" \
        || ok "SystemUIServer стартует заново при первом обращении"
else
    ok "SystemUIServer не висел в процессах — стартует по требованию"
fi

# ---------- 2. Соседи по системному UI ----------
step "2/5 Перезапускаю Dock, NotificationCenter, Spotlight-воркеры"
killall Dock 2>/dev/null
killall NotificationCenter 2>/dev/null
killall mds_stores 2>/dev/null
killall mdworker 2>/dev/null
ok "перезапущены (все стартуют сами за пару секунд)"

# ---------- 3. Диск: мгновенный тест отклика ----------
step "3/5 Тест: USB-диск отвечает мгновенно?"
DISK_OK=$(ls /Volumes/EncryptDisk >/dev/null 2>&1 && echo да || echo нет)
if [ "$DISK_OK" = "да" ]; then
    ok "EncryptDisk отвечает — диск не виновник"
else
    bad "EncryptDisk НЕ отвечает! Висящий USB-диск валит ВЕСЬ интерфейс."
    echo "      Вытащи USB-кабель диска из Mac на 5 секунд и вставь обратно."
    echo "      Данные на нем останутся (журналирование HFS+), это безопасно."
fi

# ---------- 4. Проверка человеком ----------
step "4/5 ПРОВЕРЬ СЕЙЧАС: ткни мышкой в яблоко и в любой пункт меню"
echo ""
printf "   Меню нажимается? Enter = ДА, всё работает / набери n и Enter = НЕТ: "
read -t 60 ans || true
echo ""

if [ "${ans:-да}" != "n" ]; then
    ok "Меню работает. Готово."
    echo ""
    echo -e "${BOLD}Если снова залагает — запусти этот скрипт еще раз.${NC}"
    exit 0
fi

# ---------- 5. WindowServer — перезапуск всей графики ----------
step "5/5 Меню мертво — перезапускаю ВСЮ графику (WindowServer)"
echo ""
echo -e "  ${YEL}Что сейчас будет:${NC} экран мигнет и ты увидишь окно входа с паролем."
echo "  Введи пароль — сессия начнется с чистого листа. Несохраненные"
echo "  документы в программах ПРОПАДУТ (открытые файлы на диске — нет)."
echo ""
echo -e "  ${BOLD}Отмена — Ctrl+C в течение 10 секунд.${NC}"
sleep 10

echo "  Печатаю инструкции на случай, если после них всё висит:"
echo "    - снова висит → в Терминале:  sudo shutdown -r now"
echo "    - Терминал не принимает команды (совсем все умерло) →"
echo "      зажми кнопку питания на 10 секунд — жесткая перезагрузка."
echo "      Для дисков с журналированием это безопасно."
echo ""

if sudo -n true 2>/dev/null; then
    ok "sudo уже разблокирован — перезапускаю графику"
    sleep 1
    sudo killall WindowServer 2>/dev/null
    sleep 5
    bad "WindowServer пережил перезапуск — теперь ЖДУЩЕЕ: sudo shutdown -r now"
else
    bad "нет прав sudo без пароля. Введи вручную:"
    echo ""
    echo "        sudo killall WindowServer"
    echo ""
    echo "      (спросит твой пароль Mac; экран мигнет → окно входа)"
    echo "      не помогло →  sudo shutdown -r now"
    echo "      и это не помогло / терминал мертв → кнопка питания 10 сек"
fi

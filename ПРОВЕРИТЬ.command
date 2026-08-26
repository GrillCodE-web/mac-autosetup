#!/bin/bash

# ============================================================
#  ПРОВЕРКА НАСТРОЙКИ MAC
#  Запускай после перезагрузки. Смотрит все настройки сам
#  и показывает зеленый/красный список. Ничего не меняет.
# ============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GREY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
UNKNOWN=0

good() { echo -e "  ${GREEN}${BOLD}✔${NC}  $1"; PASS=$((PASS+1)); }
bad()  { echo -e "  ${RED}${BOLD}✖${NC}  $1"; FAIL=$((FAIL+1)); }
dunno(){ echo -e "  ${YELLOW}${BOLD}?${NC}  $1"; UNKNOWN=$((UNKNOWN+1)); }
dim()  { echo -e "     ${GREY}$1${NC}"; }

# Папка Telegram: префикс команды (6N38VWS5BX. и др.) у разных сборок отличается
TG_GLOB="*keepcoder.Telegram"
tg_local_dir() {
    local d
    d=$(find "$HOME/Library/Group Containers" -maxdepth 1 -name "$TG_GLOB" 2>/dev/null | head -1)
    [ -z "$d" ] && d="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram"
    echo "$d"
}

sect() {
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}${CYAN}▎${NC}${BOLD} $1${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
}

if [ "$(uname)" != "Darwin" ]; then
    echo "Этот скрипт работает только на macOS."
    exit 1
fi

clear
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "   ${BOLD}ПРОВЕРКА НАСТРОЙКИ MAC  /  MAC SETUP CHECK${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Введи пароль от Mac (нужен только чтобы ПРОЧИТАТЬ настройки, ничего не меняется):"
echo -e "${GREY}Enter your Mac password (read-only check, nothing is changed):${NC}"
read -rs -p "  Пароль / Password: " ADMIN_PASS; echo ""
echo "$ADMIN_PASS" | sudo -S -k true 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}Пароль не подошел. Запусти заново. / Wrong password, run again.${NC}"
    exit 1
fi

sect "ШИФРОВАНИЕ И ДОСТУП / ENCRYPTION & ACCESS"

# --- 1. FileVault ---
if fdesetup status 2>/dev/null | grep -q "On"; then
    good "FileVault (шифрование диска Mac) включен."
else
    bad "FileVault ВЫКЛЮЧЕН! Включи: Настройки -> Конфиденциальность и безопасность -> FileVault."
fi

SIP=$(csrutil status 2>/dev/null)
if echo "$SIP" | grep -qi "enabled"; then
    good "Защита системы SIP включена."
else
    bad "SIP (защита системы) ОТКЛЮЧЕН — так Mac уязвим. Включается только в режиме восстановления."
fi

GK=$(spctl --status 2>/dev/null)
if echo "$GK" | grep -qi "assessments enabled"; then
    good "Gatekeeper включен (не даст запустить левое приложение)."
else
    bad "Gatekeeper выключен — запустится любая программа. Включи: sudo spctl --master-enable."
fi

sect "СЕТЬ И РАДИО / NETWORK & RADIO"

# --- 2. Брандмауэр ---
FW="/usr/libexec/ApplicationFirewall/socketfilterfw"
FWSTATE=$(echo "$ADMIN_PASS" | sudo -S "$FW" --getglobalstate 2>/dev/null)
if echo "$FWSTATE" | grep -qi "enabled"; then
    good "Брандмауэр включен."
else
    bad "Брандмауэр ВЫКЛЮЧЕН! Настройки -> Сеть -> Брандмауэр."
fi
if echo "$ADMIN_PASS" | sudo -S "$FW" --getblockall 2>/dev/null | grep -qi "enabled"; then
    dunno "Блокировка ВСЕХ входящих включена — с ней VeraCrypt/FUSE-T может виснуть на монтировании."
else
    good "Блокировка всех входящих выключена — так и задумано (иначе ломается VeraCrypt/FUSE-T)."
fi
if echo "$ADMIN_PASS" | sudo -S "$FW" --getstealthmode 2>/dev/null | grep -qi "enabled"; then
    good "Режим невидимости (stealth) включен."
else
    bad "Режим невидимости выключен."
fi

# --- 3. Wi-Fi ---
if networksetup -listallnetworkservices 2>/dev/null | grep -qi "wi-fi"; then
    bad "Wi-Fi ЕСТЬ в сетевых службах! Удали: Настройки -> Сеть -> Wi-Fi -> ... -> Удалить службу."
else
    good "Wi-Fi отсутствует в сетевых службах (только кабель)."
fi
WIFI_DEV=$(networksetup -listallhardwareports 2>/dev/null | grep -A1 -i "Wi-Fi" | grep Device | awk '{print $2}' | head -1)
if [ -n "$WIFI_DEV" ]; then
    if networksetup -getairportpower "$WIFI_DEV" 2>/dev/null | grep -qi "off"; then
        good "Радиомодуль Wi-Fi ($WIFI_DEV) выключен."
    else
        dunno "Радиомодуль Wi-Fi ($WIFI_DEV) еще питается, но службы Wi-Fi нет — подключиться нельзя."
    fi
fi

# --- 3b. Удаленный доступ: вход по SSH, удаленное управление, общий доступ ---
if echo "$ADMIN_PASS" | sudo -S systemsetup -getremotelogin 2>/dev/null | grep -qi "off"; then
    good "Удаленный вход (SSH) выключен."
else
    bad "Удаленный вход (SSH) ВКЛЮЧЕН — выключи: Настройки -> Общий доступ -> Удаленный вход."
fi
if launchctl list 2>/dev/null | grep -qi "com.apple.screensharing"; then
    bad "Общий экран / удаленное управление ВКЛЮЧЕНО — выключи в Настройки -> Общий доступ."
else
    good "Общий экран и удаленное управление выключены."
fi
if launchctl list 2>/dev/null | grep -qi "com.apple.smbd\|AppleFileServer"; then
    bad "Общий доступ к файлам ВКЛЮЧЕН — выключи: Настройки -> Общий доступ -> Общие файлы."
else
    good "Общий доступ к файлам выключен."
fi
if defaults read com.apple.NetworkBrowser DisableAirDrop 2>/dev/null | grep -q "1"; then
    good "AirDrop отключен."
else
    dunno "AirDrop не помечен как отключенный — проверь в Finder -> AirDrop (должно быть «Никто»)."
fi

# --- 4. Bluetooth ---
BT=$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null)
BT_LIVE=$(system_profiler SPBluetoothDataType 2>/dev/null | grep -i "State:" | head -1)
if echo "$BT_LIVE" | grep -qi "off"; then
    good "Bluetooth выключен."
elif echo "$BT_LIVE" | grep -qi "on"; then
    bad "Bluetooth ВКЛЮЧЕН! Выключи: Настройки -> Bluetooth."
elif [ "$BT" = "0" ]; then
    good "Bluetooth выключен (по настройке)."
else
    dunno "Bluetooth: не смог определить — проверь глазами: Настройки -> Bluetooth."
fi

sect "СЕКРЕТНЫЙ ДИСК И ДАННЫЕ / SECRET DISK & DATA"

# --- 5. Секретный диск и симлинки ---
# Папка данных у каждого называется по-своему (DataAPP, AppData, своя структура),
# поэтому сначала ищем по имени, потом — по реальным данным приложений.
DATA_DIR=$(find /Volumes -maxdepth 3 -type d \( -iname "DataAPP" -o -iname "AppData" \) \
           -not -path "*/.Trashes/*" 2>/dev/null | head -1)
if [ -z "$DATA_DIR" ]; then
    HIT=$(find /Volumes -maxdepth 6 -type d \
          \( -name "$TG_GLOB" -o -name "app.ls" -o -name "Tox" -o -name "MailMate" -o -iname "*tukan*" \) \
          -not -path "*/.Trashes/*" 2>/dev/null | head -1)
    if [ -n "$HIT" ]; then
        DATA_DIR=$(dirname "$HIT")
        case "$(basename "$DATA_DIR")" in
            Telegram|telegram) DATA_DIR=$(dirname "$DATA_DIR") ;;
        esac
    fi
fi
# Последний вариант: том, на который реально смотрят наши симлинки
if [ -z "$DATA_DIR" ]; then
    for S in "$(tg_local_dir)/stable" \
             "$HOME/Library/Application Support/Sublime Text" \
             "$HOME/Library/Application Support/app.ls"; do
        if [ -L "$S" ]; then
            T=$(readlink "$S")
            case "$T" in /Volumes/*) [ -e "$T" ] && { DATA_DIR=$(dirname "$T"); break; } ;; esac
        fi
    done
fi
if [ -n "$DATA_DIR" ]; then
    DISK_VOL="/Volumes/$(echo "$DATA_DIR" | cut -d/ -f3)"
    good "Секретный диск подключен: $DISK_VOL"
    dim "папка данных: $DATA_DIR"
    FREE=$(df -h "$DISK_VOL" 2>/dev/null | tail -1 | awk '{print $4}')
    [ -n "$FREE" ] && dim "свободно на диске: $FREE"
else
    dunno "Секретный диск НЕ найден — проверки данных будут неполными."
    dim "Подключи его через VeraCrypt и запусти проверку снова."
    OTHER=$(ls /Volumes 2>/dev/null | tr '\n' ' ')
    dim "сейчас подключены тома: ${OTHER:-нет}"
fi

check_link() {
    local src="$1" name="$2"
    if [ -L "$src" ]; then
        local target=$(readlink "$src")
        case "$target" in
            /Volumes/*)
                if [ -e "$src" ]; then
                    local sz cnt
                    cnt=$(ls -A "$src/" 2>/dev/null | wc -l | tr -d ' ')
                    sz=$(du -sh "$src/" 2>/dev/null | awk '{print $1}')
                    if [ "$cnt" = "0" ]; then
                        bad "$name — симлинк рабочий, но папка на диске ПУСТАЯ ($target)."
                    else
                        good "$name — данные на секретном диске (${sz:-?}, файлов: $cnt)."
                        dim "$target"
                    fi
                else
                    dunno "$name — симлинк на диск есть, но диск сейчас не подключен (это норма без диска)."
                fi ;;
            *)
                bad "$name — симлинк ведет НЕ на внешний диск, а в: $target" ;;
        esac
    elif [ -d "$src" ]; then
        bad "$name — данные лежат В СИСТЕМЕ (не на диске)! Запусти ЗАПУСТИТЬ.command еще раз."
    else
        dunno "$name — данных нет ни в системе, ни симлинка (приложение еще не запускалось?)."
    fi
}

check_link "$(tg_local_dir)/stable" "Telegram"
check_link "$HOME/Library/Application Support/Sublime Text" "Sublime Text"
check_link "$HOME/Library/Application Support/app.ls" "Sphere"
[ -d "/Applications/MailMate.app" ] && check_link "$HOME/Library/Application Support/MailMate" "MailMate"
[ -d "/Applications/qTox.app" ] && check_link "$HOME/Library/Application Support/Tox" "qTox"
TUK=$(find "$HOME/Library/Application Support" -maxdepth 1 -iname "*tukan*" 2>/dev/null | head -1)
[ -n "$TUK" ] && check_link "$TUK" "Tukan"

# Данные, которые НЕ должны валяться в системе
for JUNK in "$HOME/Desktop" "$HOME/Documents" "$HOME/Downloads"; do
    N=$(ls -A "$JUNK" 2>/dev/null | grep -v "^autosetup$" | wc -l | tr -d ' ')
    if [ "$N" = "0" ]; then
        good "$(basename "$JUNK"): пусто — правильно, файлы должны быть только на диске."
    else
        dunno "$(basename "$JUNK"): лежит $N объектов — перенеси их на секретный диск."
    fi
done

sect "ПРОГРАММЫ / APPLICATIONS"

# --- 6. Приложения на месте ---
for APP in "VeraCrypt" "Telegram" "Sublime Text"; do
    if [ -d "/Applications/$APP.app" ]; then
        good "Программа $APP установлена."
    else
        bad "Программа $APP НЕ установлена!"
    fi
done
for APP in "MailMate" "qTox"; do
    [ -d "/Applications/$APP.app" ] && good "Программа $APP установлена (ставилась по желанию)."
done
if pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t"; then
    good "FUSE-T установлен (без него VeraCrypt не смонтирует диск)."
else
    bad "FUSE-T НЕ установлен — VeraCrypt не сможет подключить диск."
fi
# Дубли приложений: «MailMate 2.app» и т.п.
DUPS=$(find /Applications -maxdepth 1 -iname "* 2.app" -o -maxdepth 1 -iname "*копия*.app" 2>/dev/null)
if [ -n "$DUPS" ]; then
    bad "В /Applications есть дубли программ — удали лишние:"
    echo "$DUPS" | while IFS= read -r d; do dim "$d"; done
else
    good "Дублей приложений в /Applications нет."
fi

sect "СИСТЕМНЫЕ НАСТРОЙКИ / SYSTEM SETTINGS"

# --- 7. Аналитика ---
AS=$(defaults read "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" AutoSubmit 2>/dev/null)
if [ "$AS" = "0" ]; then
    good "Отправка аналитики Apple выключена."
else
    dunno "Аналитика: не смог подтвердить — проверь: Настройки -> Конфиденциальность -> Аналитика."
fi

# --- 8. Автовыход ---
AL=$(defaults read /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay 2>/dev/null)
if [ -n "$AL" ] && [ "$AL" -gt 0 ] 2>/dev/null; then
    good "Автовыход из системы включен: через $((AL / 60)) мин."
else
    dunno "Автовыход выключен (так и задумано, если выбрал «выключить») — Настройки -> Конфиденциальность -> Дополнительно."
fi

# --- 9. Пароль админа для общесистемных настроек ---
SHARED=$(echo "$ADMIN_PASS" | sudo -S security authorizationdb read system.preferences 2>/dev/null | grep -A1 "<key>shared</key>" | grep -o "false")
if [ "$SHARED" = "false" ]; then
    good "Общесистемные настройки — только с паролем администратора."
else
    bad "Ползунок «пароль админа для общесистемных настроек» выключен (Настройки -> Конфиденциальность -> Дополнительно)."
fi

# --- 10. Автообновления ---
AU=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null)
if [ "$AU" = "1" ]; then
    good "Автопроверка обновлений macOS включена."
else
    bad "Автообновления выключены (Настройки -> Основные -> Обновление ПО)."
fi

# --- 11. Экран блокировки / выключение дисплея ---
DS=$(pmset -g 2>/dev/null | awk '/^ displaysleep/{print $2}')
if [ "$DS" = "0" ]; then
    dunno "Дисплей не гаснет по таймеру (так и задумано, если выбрал «никогда»)."
elif [ -n "$DS" ]; then
    good "Дисплей гаснет через $DS мин (значение, которое ты выбрал при настройке)."
else
    dunno "Выключение дисплея прочитать не смог — проверь: Настройки -> Экран блокировки."
fi
SLK=$(sysadminctl -screenLock status 2>&1)
if echo "$SLK" | grep -qi "immediate"; then
    good "Пароль запрашивается СРАЗУ после заставки/сна экрана."
elif echo "$SLK" | grep -qi "off"; then
    bad "Пароль после заставки НЕ запрашивается! Настройки -> Экран блокировки."
else
    dunno "Пароль после заставки: не смог прочитать ($(echo "$SLK" | tail -1)) — проверь глазами."
fi
SS=$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null)
if [ -n "$SS" ] && [ "$SS" -gt 0 ] 2>/dev/null; then
    good "Заставка включается через $((SS / 60)) мин бездействия."
else
    dunno "Заставка по бездействию выключена — экран все равно гаснет по таймеру дисплея."
fi

# --- 12. Раскладки клавиатуры ---
KBD=$(defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null)
if echo "$KBD" | grep -qi "russian" && echo "$KBD" | grep -q "U.S."; then
    good "Раскладки клавиатуры: английская (U.S.) + русская."
elif echo "$KBD" | grep -qi "russian"; then
    dunno "Русская раскладка есть, а английской (U.S.) в списке не вижу."
else
    bad "Русская раскладка не добавлена (Настройки -> Клавиатура -> Источники ввода -> +)."
fi
HK=$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null | tr -d ' \n')
if echo "$HK" | grep -q "60={enabled=1"; then
    good "Сочетание переключения раскладки включено (проверь в бою: нажми его в любом тексте)."
else
    dunno "Сочетание переключения раскладки: не подтвердилось — Настройки -> Клавиатура -> Сочетания клавиш -> Источники ввода."
fi

# --- 13. Учетные записи и вход ---
if [ "$(defaults read /Library/Preferences/com.apple.loginwindow SHOWFULLNAME 2>/dev/null)" = "1" ]; then
    good "На экране входа список пользователей скрыт (нужно вводить имя)."
else
    dunno "На экране входа показан список пользователей — можно скрыть для приватности."
fi
if [ "$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null)" != "" ]; then
    bad "Включен автоматический вход без пароля! Настройки -> Пользователи -> Параметры входа."
else
    good "Автоматический вход выключен (при старте спрашивают пароль)."
fi
GUEST=$(defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled 2>/dev/null)
if [ "$GUEST" = "0" ] || [ -z "$GUEST" ]; then
    good "Гостевая учетная запись выключена."
else
    bad "Гостевая учетная запись ВКЛЮЧЕНА — выключи в Настройки -> Пользователи."
fi

# --- 14. Следы: логи, корзина, история терминала ---
TRASH=$(ls -A "$HOME/.Trash" 2>/dev/null | wc -l | tr -d ' ')
if [ "$TRASH" = "0" ]; then
    good "Корзина пуста."
else
    dunno "В корзине $TRASH объектов — очисти, из нее данные восстанавливаются."
fi
if [ -s "$HOME/.bash_history" ] || [ -s "$HOME/.zsh_history" ]; then
    dunno "История терминала не пуста — если вводил там что-то лишнее, почисти."
else
    good "История терминала пуста."
fi

# --- ИТОГ ---
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "   ${BOLD}ИТОГ / RESULT:${NC}   ${GREEN}${BOLD}✔ $PASS${NC}    ${RED}${BOLD}✖ $FAIL${NC}    ${YELLOW}${BOLD}? $UNKNOWN${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}✔${NC} в порядке / fine    ${RED}✖${NC} проблема / problem    ${YELLOW}?${NC} проверь глазами / check"
echo ""
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  Красных пунктов нет — Mac настроен правильно.${NC}"
    echo -e "${GREY}  No red items — the Mac is set up correctly.${NC}"
else
    echo -e "${RED}${BOLD}  Есть красные пункты — сделай то, что в них написано, и запусти проверку снова.${NC}"
    echo -e "${GREY}  There are red items — fix them and run this check again.${NC}"
fi
echo ""
echo "Окно можно закрыть. / You can close this window."

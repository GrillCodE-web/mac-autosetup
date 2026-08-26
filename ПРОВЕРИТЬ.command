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
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
UNKNOWN=0

good() { echo -e "${GREEN}[ДА ]${NC} $1"; PASS=$((PASS+1)); }
bad()  { echo -e "${RED}[НЕТ]${NC} $1"; FAIL=$((FAIL+1)); }
dunno(){ echo -e "${YELLOW}[ ? ]${NC} $1"; UNKNOWN=$((UNKNOWN+1)); }

if [ "$(uname)" != "Darwin" ]; then
    echo "Этот скрипт работает только на macOS."
    exit 1
fi

clear
echo -e "${CYAN}============================================================${NC}"
echo -e "${BOLD}  ПРОВЕРКА НАСТРОЙКИ MAC${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo "Введи пароль от Mac (нужен только чтобы ПРОЧИТАТЬ настройки, ничего не меняется):"
read -rs -p "Пароль: " ADMIN_PASS; echo ""
echo "$ADMIN_PASS" | sudo -S -k true 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}Пароль не подошел. Запусти заново.${NC}"
    exit 1
fi
echo ""

# --- 1. FileVault ---
if fdesetup status 2>/dev/null | grep -q "On"; then
    good "FileVault (шифрование диска Mac) включен."
else
    bad "FileVault ВЫКЛЮЧЕН! Включи: Настройки -> Конфиденциальность и безопасность -> FileVault."
fi

# --- 2. Брандмауэр ---
FW="/usr/libexec/ApplicationFirewall/socketfilterfw"
FWSTATE=$(echo "$ADMIN_PASS" | sudo -S "$FW" --getglobalstate 2>/dev/null)
if echo "$FWSTATE" | grep -qi "enabled"; then
    good "Брандмауэр включен."
else
    bad "Брандмауэр ВЫКЛЮЧЕН! Настройки -> Сеть -> Брандмауэр."
fi
if echo "$ADMIN_PASS" | sudo -S "$FW" --getblockall 2>/dev/null | grep -qi "enabled"; then
    good "Блокировка всех входящих соединений включена."
else
    bad "Блокировка входящих соединений выключена."
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

# --- 5. Секретный диск и симлинки ---
DATA_DIR=$(find /Volumes -maxdepth 2 -type d -name "DataAPP" 2>/dev/null | head -1)
if [ -n "$DATA_DIR" ]; then
    good "Секретный диск подключен: $DATA_DIR"
else
    dunno "Секретный диск НЕ подключен — проверки Telegram/симлинков будут неполными. Подключи диск через VeraCrypt и запусти проверку снова."
fi

check_link() {
    local src="$1" name="$2"
    if [ -L "$src" ]; then
        local target=$(readlink "$src")
        case "$target" in
            /Volumes/*)
                if [ -e "$src" ]; then
                    good "$name — данные на секретном диске (симлинк рабочий)."
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

check_link "$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable" "Telegram"
check_link "$HOME/Library/Application Support/Sublime Text" "Sublime Text"
check_link "$HOME/Library/Application Support/app.ls" "Sphere"

# --- 6. Приложения на месте ---
for APP in "VeraCrypt" "Telegram"; do
    if [ -d "/Applications/$APP.app" ]; then
        good "Программа $APP установлена."
    else
        bad "Программа $APP НЕ установлена!"
    fi
done

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
dunno "«Запрашивать пароль после заставки = СРАЗУ» — автоматом не читается, проверь глазами: Настройки -> Экран блокировки."

# --- 12. Раскладки клавиатуры ---
KBD=$(defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null)
if echo "$KBD" | grep -qi "russian" && echo "$KBD" | grep -q "U.S."; then
    good "Раскладки клавиатуры: английская (U.S.) + русская."
else
    bad "Русская раскладка не добавлена (Настройки -> Клавиатура -> Источники ввода -> +)."
fi
HK=$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null | tr -d ' \n')
if echo "$HK" | grep -q "60={enabled=1"; then
    good "Сочетание переключения раскладки включено (проверь в бою: нажми его в любом тексте)."
else
    dunno "Сочетание переключения раскладки: не подтвердилось — Настройки -> Клавиатура -> Сочетания клавиш -> Источники ввода."
fi

# --- ИТОГ ---
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${BOLD}  ИТОГ:${NC} ${GREEN}$PASS в порядке${NC}, ${RED}$FAIL проблем${NC}, ${YELLOW}$UNKNOWN проверь глазами${NC}"
echo -e "${CYAN}============================================================${NC}"
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}${BOLD}Красных пунктов нет — Mac настроен правильно.${NC}"
else
    echo -e "${RED}${BOLD}Есть красные пункты — сделай, что написано в них, или пришли скриншот тому, кто настраивал.${NC}"
fi
echo ""
echo "Окно можно закрыть."

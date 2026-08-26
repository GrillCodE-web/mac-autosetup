#!/bin/bash

# ============================================================
#  АВТОНАСТРОЙКА MAC — ПОЛНЫЙ АВТОМАТ
#  Человеку нужно только: нажимать Enter и один раз ввести пароль
# ============================================================

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

LOG="/tmp/autosetup_log.txt"
DLOG="/tmp/autosetup_commands.txt"
: > "$LOG"
echo "=== ДЕТАЛЬНЫЙ ЛОГ КОМАНД, запуск: $(date) ===" > "$DLOG"
exec > >(tee >(sed -l $'s/\x1b\\[[0-9;]*m//g' >> "$LOG")) 2>&1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[$(L 'ОШИБКА' 'ERROR')]${NC} $1"; }

# Двуязычный вывод: L "русский" "english" -> печатает СРАЗУ оба языка (дублирует)
L() { printf '%s / %s' "$1" "$2"; }
# Нормализация ответа да/нет на обоих языках -> всегда "да" или "нет"
yn() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        yes|y|да|д|ДА|Д|1) echo "да" ;;
        no|n|нет|н|НЕТ|Н|0) echo "нет" ;;
        *) echo "$1" ;;
    esac
}

logcmd() {
    local a line=""
    for a in "$@"; do
        [ -n "$ADMIN_PASS" ] && [ "$a" = "$ADMIN_PASS" ] && a="<пароль>"
        [ -n "$DISK_PASS" ] && [ "$a" = "$DISK_PASS" ] && a="<пароль>"
        [ -n "$USER_PASS" ] && [ "$a" = "$USER_PASS" ] && a="<пароль>"
        line="$line $a"
    done
    echo "[$(date '+%H:%M:%S')] \$$line" >> "$DLOG"
}
run() { logcmd "$@"; "$@"; local rc=$?; [ $rc -ne 0 ] && echo "    ^ код возврата: $rc" >> "$DLOG"; return $rc; }
as_root() { logcmd sudo "$@"; printf '%s\n' "$ADMIN_PASS" | sudo -S "$@"; local rc=$?; [ $rc -ne 0 ] && echo "    ^ код возврата: $rc" >> "$DLOG"; return $rc; }

step() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${CYAN}============================================================${NC}"
    { echo ""; echo "########## $1 ##########"; } >> "$DLOG"
}

pause() {
    echo ""
    echo -e "${YELLOW}>>> $(L 'Когда сделаешь — нажми Enter' 'When done — press Enter') <<<${NC}"
    read -r
}

# Проверка: мы на маке?
if [ "$(uname)" != "Darwin" ]; then
    err "Этот скрипт работает только на macOS."
    exit 1
fi

# Делаем скрипт проверки запускаемым (после копирования с флешки права теряются)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$SCRIPT_DIR/ПРОВЕРИТЬ.command" 2>/dev/null

clear

step "$(L 'НАЧАЛО НАСТРОЙКИ' 'SETUP START')"
echo "$(L 'Сейчас скрипт настроит этот Mac полностью сам.' 'This script will set up this Mac automatically.')"
echo "$(L 'От тебя нужно минимум действий — просто следуй экрану.' 'Minimal input needed — just follow the screen.')"
echo "$(L 'Весь ход записывается в файл:' 'Full log is written to:') $LOG"
echo ""

# ------------------------------------------------------------
# ВОПРОСЫ В НАЧАЛЕ (чтобы потом не отвлекать)
# ------------------------------------------------------------
step "ВОПРОСЫ (один раз, в начале)"

echo "1) Создать ОТДЕЛЬНУЮ рабочую учетную запись (вторая, кроме основной)?"
echo "   НЕТ — проще: одна учетка, один пароль, запутаться невозможно."
echo "   ДА  — чуть безопаснее, но будет две учетки и два пароля."
read -r -p "   (да/нет) [нет]: " CREATE_USER
CREATE_USER=$(yn "${CREATE_USER:-нет}")

if [ "$CREATE_USER" = "да" ]; then
    echo "   Придумай ПАРОЛЬ для новой рабочей учетной записи."
    echo "   (ввод не будет виден на экране — это нормально)"
    while true; do
        read -rs -p "   Пароль: " USER_PASS; echo ""
        read -rs -p "   Еще раз: " USER_PASS2; echo ""
        if [ -z "$USER_PASS" ]; then
            err "Пароль пустой. Попробуй снова."
        elif [ "$USER_PASS" != "$USER_PASS2" ]; then
            err "Пароли не совпадают. Попробуй снова."
        else
            ok "Пароль принят."
            break
        fi
    done
    echo ""
    read -r -p "   Имя учетки (латиницей, без пробелов) [user]: " NEW_USER
    NEW_USER=${NEW_USER:-user}
    ok "Учетная запись будет: $NEW_USER"
fi

echo ""
echo "2) Пароль от этого Mac (тот, что задал при первой настройке):"
read -rs -p "   Пароль администратора: " ADMIN_PASS; echo ""

# Проверяем sudo сразу
as_root -k true 2>/dev/null
if [ $? -ne 0 ]; then
    err "Пароль администратора не подошел. Запусти скрипт заново."
    exit 1
fi
ok "Пароль администратора верный."

echo ""
echo "3) Внешний диск (флешка/SSD) для секретных данных:"
echo "   У большинства он УЖЕ зашифрован и с данными — поэтому по умолчанию стоит «да»."
echo "   «да»  = НИЧЕГО не стирать, просто подключить диск."
echo "   «нет» = диск будет СТЕРТ начисто и зашифрован заново!"
read -r -p "   Он УЖЕ зашифрован VeraCrypt раньше? (да/нет) [да]: " HAVE_DISK
HAVE_DISK=$(yn "${HAVE_DISK:-да}")
if [ "$HAVE_DISK" = "да" ]; then
    echo "   Ок. Пароль и PIM вводить НЕ нужно — когда дойдем до диска,"
    echo "   ты сам смонтируешь его через окно VeraCrypt, а я дальше все найду."
else
    echo "   Придумай ПАРОЛЬ ДЛЯ ДИСКА (запомни — без него данные не вернуть):"
    echo "   ВАЖНО: ТОЛЬКО английские буквы и цифры! Без русских букв и без"
    echo "   необычных символов — на macOS Tahoe VeraCrypt ломается на них."
    while true; do
        read -rs -p "   Пароль диска: " DISK_PASS; echo ""
        read -rs -p "   Еще раз: " DISK_PASS2; echo ""
        if [ -n "$DISK_PASS" ] && [ "$DISK_PASS" = "$DISK_PASS2" ]; then ok "Пароль принят."; break; fi
        err "Пусто или не совпадает. Снова."
    done
    read -r -p "   Как назвать диск? [Data]: " DISK_NAME
    DISK_NAME=${DISK_NAME:-Data}
    echo "   Режим шифрования:"
    echo "     1 — быстрый (несколько минут)"
    echo "     2 — полный (надежнее; большой диск может шифроваться ЧАСАМИ)"
    read -r -p "   Выбор [2]: " ENC_MODE
    ENC_MODE=${ENC_MODE:-2}
    read -r -p "   PIM (Enter = без PIM): " DISK_PIM
fi
DISK_PIM=${DISK_PIM:-0}
if ! [[ "$DISK_PIM" =~ ^[0-9]+$ ]]; then
    warn "PIM должен быть числом — введено «$DISK_PIM», использую «без PIM»."
    DISK_PIM=0
fi

state_tz() {
    case "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')" in
        CT|DE|FL|GA|KY|ME|MD|MA|NH|NJ|NY|NC|OH|PA|RI|SC|VT|VA|WV|DC) echo "America/New_York" ;;
        MI) echo "America/Detroit" ;;
        IN) echo "America/Indiana/Indianapolis" ;;
        AL|AR|IL|IA|KS|LA|MN|MS|MO|NE|ND|OK|SD|TN|TX|WI) echo "America/Chicago" ;;
        CO|MT|NM|UT|WY) echo "America/Denver" ;;
        AZ) echo "America/Phoenix" ;;
        ID) echo "America/Boise" ;;
        CA|NV|OR|WA) echo "America/Los_Angeles" ;;
        AK) echo "America/Anchorage" ;;
        HI) echo "Pacific/Honolulu" ;;
        *) echo "" ;;
    esac
}

echo ""
echo "4) $(L 'Часовой пояс под VPN (чтобы часы не палили реальное место).' 'Time zone matching your VPN (so the clock does not leak your real location).')"
echo "   $(L 'Определяю штат по текущему IP...' 'Detecting US state from current IP...')"
IP_STATE=$(curl -s --max-time 8 "https://ipapi.co/region_code" 2>/dev/null)
[[ "$IP_STATE" =~ ^[A-Z]{2}$ ]] || IP_STATE=$(curl -s --max-time 8 "http://ip-api.com/line/?fields=region" 2>/dev/null)
IP_TZ=""
[[ "$IP_STATE" =~ ^[A-Za-z]{2}$ ]] && IP_TZ=$(state_tz "$IP_STATE")
VPN_TZ=""
if [ -n "$IP_TZ" ]; then
    ok "$(L 'По IP: штат' 'By IP: state') $IP_STATE -> $IP_TZ"
    echo "   $(L 'Использовать этот (по VPN) или выбрать штат самому?' 'Use this (VPN) or pick a state yourself?')"
    read -r -p "   $(L 'Enter = по VPN, или введи код штата (напр. NY, CA, TX)' 'Enter = VPN, or type a state code (e.g. NY, CA, TX)'): " TZ_CH
else
    warn "$(L 'Штат по IP не определился (нет сети/VPN).' 'Could not detect state from IP (no net/VPN).')"
    read -r -p "   $(L 'Введи код штата (напр. NY) или Enter — не менять' 'Type a state code (e.g. NY) or Enter to skip'): " TZ_CH
fi
if [ -z "$TZ_CH" ]; then
    VPN_TZ="$IP_TZ"
else
    VPN_TZ=$(state_tz "$TZ_CH")
    if [ -z "$VPN_TZ" ]; then
        warn "$(L 'Не знаю такой штат — часовой пояс не меняю.' 'Unknown state — time zone not changed.')"
        echo "   $(L 'Коды штатов:' 'State codes:') AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY DC"
    fi
fi

echo ""
echo "5) $(L 'Через сколько ГАСИТЬ ЭКРАН (сон дисплея).' 'Display sleep timeout.')"
echo "   1 — 1 $(L 'мин' 'min')   2 — 2 $(L 'мин' 'min')   3 — 5 $(L 'мин' 'min') ($(L 'по умолчанию' 'default'))"
echo "   4 — 10 $(L 'мин' 'min')  5 — 15 $(L 'мин' 'min')  6 — 30 $(L 'мин' 'min')  7 — $(L 'никогда' 'never')"
read -r -p "   $(L 'Выбор' 'Choice') [3]: " DS_CH
case "${DS_CH:-3}" in
    1) DISPLAY_SLEEP=1 ;; 2) DISPLAY_SLEEP=2 ;; 3) DISPLAY_SLEEP=5 ;;
    4) DISPLAY_SLEEP=10 ;; 5) DISPLAY_SLEEP=15 ;; 6) DISPLAY_SLEEP=30 ;; 7) DISPLAY_SLEEP=0 ;;
    *) warn "$(L 'Непонятный ответ — беру 5 минут.' 'Unknown answer — using 5 minutes.')"; DISPLAY_SLEEP=5 ;;
esac

echo ""
echo "6) $(L 'Через сколько АВТОВЫХОД из системы (бездействие).' 'Auto logout after idle.')"
echo "   1 — 5 $(L 'мин' 'min')   2 — 10 $(L 'мин' 'min')  3 — 15 $(L 'мин' 'min')"
echo "   4 — 30 $(L 'мин' 'min') ($(L 'по умолчанию' 'default'))  5 — 60 $(L 'мин' 'min')  6 — $(L 'выключить' 'off')"
read -r -p "   $(L 'Выбор' 'Choice') [4]: " AL_CH
case "${AL_CH:-4}" in
    1) AUTOLOGOUT_MIN=5 ;; 2) AUTOLOGOUT_MIN=10 ;; 3) AUTOLOGOUT_MIN=15 ;;
    4) AUTOLOGOUT_MIN=30 ;; 5) AUTOLOGOUT_MIN=60 ;; 6) AUTOLOGOUT_MIN=0 ;;
    *) warn "$(L 'Непонятный ответ — беру 30 минут.' 'Unknown answer — using 30 minutes.')"; AUTOLOGOUT_MIN=30 ;;
esac

echo ""
echo "7) $(L 'Раскладки клавиатуры: английская + русская.' 'Keyboard layouts: English + Russian.')"
echo "   $(L 'Сочетание для переключения:' 'Switch shortcut:')"
echo "   1 — Ctrl + Space ($(L 'по умолчанию' 'default'))"
echo "   2 — Option(Alt) + Space"
echo "   3 — Cmd + Space ($(L 'Spotlight переедет на Ctrl+Cmd+Space' 'Spotlight moves to Ctrl+Cmd+Space'))"
echo "   4 — Caps Lock ($(L 'штатное переключение macOS' 'native macOS switching')) "
echo "   5 — $(L 'не трогать сочетание' 'do not change shortcut')"
read -r -p "   $(L 'Выбор' 'Choice') [1]: " KB_CH
KB_CH=${KB_CH:-1}
case "$KB_CH" in
    1|2|3|4|5) ;;
    *) warn "$(L 'Непонятный ответ — беру Ctrl+Space.' 'Unknown answer — using Ctrl+Space.')"; KB_CH=1 ;;
esac

echo ""
ok "$(L 'Все вопросы заданы. Дальше скрипт работает сам (пару раз попросит вставить диск).' 'All questions done. The script runs on its own now (it will ask to insert the disk a couple of times).')"

# ------------------------------------------------------------
# ФАЗА 1: УЧЕТНАЯ ЗАПИСЬ
# ------------------------------------------------------------
step "ФАЗА 1/6 — Учетная запись"

if [ "$CREATE_USER" != "да" ]; then
    ok "Одна учетная запись — ничего создавать не нужно, пропускаю."
elif id "$NEW_USER" &>/dev/null; then
    warn "Учетная запись $NEW_USER уже существует — пропускаю."
else
    LAST_ID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
    NEW_ID=$((LAST_ID + 1))
    as_root dscl . -create /Users/"$NEW_USER"
    as_root dscl . -create /Users/"$NEW_USER" UserShell /bin/bash
    as_root dscl . -create /Users/"$NEW_USER" RealName "$NEW_USER"
    as_root dscl . -create /Users/"$NEW_USER" UniqueID "$NEW_ID"
    as_root dscl . -create /Users/"$NEW_USER" PrimaryGroupID 20
    as_root dscl . -create /Users/"$NEW_USER" NFSHomeDirectory /Users/"$NEW_USER"
    as_root dscl . -passwd /Users/"$NEW_USER" "$USER_PASS"
    as_root createhomedir -c -u "$NEW_USER" &>/dev/null
    ok "Учетная запись $NEW_USER создана (стандартная, без прав админа)."
fi

# ------------------------------------------------------------
# ФАЗА 2: НАСТРОЙКИ БЕЗОПАСНОСТИ (все автоматом)
# ------------------------------------------------------------
step "ФАЗА 2/6 — Настройки безопасности системы"

# Экран блокировки: пароль сразу. Основной способ — sysadminctl (работает на новых macOS),
# defaults — запасной для старых. В конце все равно есть пункт проверить глазами.
if sysadminctl -screenLock immediate -password "$ADMIN_PASS" &>/dev/null; then
    ok "Пароль при блокировке — сразу."
else
    defaults write com.apple.screensaver askForPassword -int 1
    defaults write com.apple.screensaver askForPasswordDelay -int 0
    warn "Пароль при блокировке: задан старым способом — в конце проверь руками (пункт в списке доделок)."
fi

# Выключение дисплея (выбрано в вопросе 5; 0 = никогда)
DISPLAY_SLEEP=${DISPLAY_SLEEP:-5}
as_root pmset -a displaysleep "$DISPLAY_SLEEP" &>/dev/null
if [ "$DISPLAY_SLEEP" = "0" ]; then
    ok "$(L 'Дисплей не гаснет по таймеру (выбрано «никогда»).' 'Display never sleeps (you chose never).')"
else
    ok "$(L 'Дисплей выключается через' 'Display sleeps after') $DISPLAY_SLEEP $(L 'мин.' 'min.')"
fi

# Автовыход из системы (выбрано в вопросе 6; 0 = выключить)
AUTOLOGOUT_MIN=${AUTOLOGOUT_MIN:-30}
if [ "$AUTOLOGOUT_MIN" = "0" ]; then
    as_root defaults delete /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay 2>/dev/null
    ok "$(L 'Автовыход из системы выключен.' 'Auto logout is off.')"
else
    as_root defaults write /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay -int $((AUTOLOGOUT_MIN * 60))
    ok "$(L 'Автовыход из системы через' 'Auto logout after') $AUTOLOGOUT_MIN $(L 'мин.' 'min.')"
fi

# Раскладки клавиатуры: английская (уже есть) + русская, и сочетание переключения
KB_PLIST="$HOME/Library/Preferences/com.apple.HIToolbox.plist"
US_SRC='<dict><key>InputSourceKind</key><string>Keyboard Layout</string><key>KeyboardLayout ID</key><integer>0</integer><key>KeyboardLayout Name</key><string>U.S.</string></dict>'
RU_SRC='<dict><key>InputSourceKind</key><string>Keyboard Layout</string><key>KeyboardLayout ID</key><integer>19456</integer><key>KeyboardLayout Name</key><string>Russian</string></dict>'
defaults write com.apple.HIToolbox AppleEnabledInputSources -array "$US_SRC" "$RU_SRC" 2>/dev/null
defaults write com.apple.HIToolbox AppleInputSourceHistory -array "$US_SRC" "$RU_SRC" 2>/dev/null
defaults write com.apple.HIToolbox AppleSelectedInputSources -array "$US_SRC" "$RU_SRC" 2>/dev/null
if [ -f "$KB_PLIST" ]; then
    ok "$(L 'Раскладки: английская (U.S.) + русская (применятся после перезагрузки).' 'Layouts: English (U.S.) + Russian (applied after reboot).')"
else
    warn "$(L 'Не смог записать раскладки — добавь русскую руками: Настройки -> Клавиатура -> Источники ввода.' 'Could not set layouts — add Russian manually: Settings -> Keyboard -> Input Sources.')"
fi

# Сочетание переключения раскладки (AppleSymbolicHotKeys: 60 — предыдущий источник, 61 — следующий)
set_hotkey() {
    local id="$1" char="$2" code="$3" mod="$4" enabled="$5"
    local PB=/usr/libexec/PlistBuddy f="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
    logcmd PlistBuddy "set hotkey $id enabled=$enabled"
    $PB -c "Add :AppleSymbolicHotKeys dict" "$f" 2>/dev/null
    $PB -c "Delete :AppleSymbolicHotKeys:$id" "$f" 2>/dev/null
    $PB -c "Add :AppleSymbolicHotKeys:$id dict" "$f" 2>/dev/null
    $PB -c "Add :AppleSymbolicHotKeys:$id:enabled bool $enabled" "$f" 2>/dev/null
    $PB -c "Add :AppleSymbolicHotKeys:$id:value dict" "$f" 2>/dev/null
    $PB -c "Add :AppleSymbolicHotKeys:$id:value:type string standard" "$f" 2>/dev/null
    $PB -c "Add :AppleSymbolicHotKeys:$id:value:parameters array" "$f" 2>/dev/null
    $PB -c "Add :AppleSymbolicHotKeys:$id:value:parameters: integer $char" "$f" 2>/dev/null
    $PB -c "Add :AppleSymbolicHotKeys:$id:value:parameters: integer $code" "$f" 2>/dev/null
    $PB -c "Add :AppleSymbolicHotKeys:$id:value:parameters: integer $mod" "$f" 2>/dev/null
}
KB_CH=${KB_CH:-1}
case "$KB_CH" in
    1)  set_hotkey 60 32 49 262144 true
        set_hotkey 61 32 49 786432 true
        ok "$(L 'Переключение раскладки: Ctrl + Space.' 'Layout switch: Ctrl + Space.')" ;;
    2)  set_hotkey 60 32 49 524288 true
        set_hotkey 61 32 49 1572864 true
        ok "$(L 'Переключение раскладки: Option(Alt) + Space.' 'Layout switch: Option(Alt) + Space.')" ;;
    3)  set_hotkey 64 32 49 1048576 false
        set_hotkey 65 32 49 1572864 false
        set_hotkey 60 32 49 1048576 true
        set_hotkey 61 32 49 1310720 true
        ok "$(L 'Переключение раскладки: Cmd + Space (Spotlight по Cmd+Space отключен).' 'Layout switch: Cmd + Space (Spotlight Cmd+Space disabled).')" ;;
    4)  set_hotkey 60 32 49 262144 false
        set_hotkey 61 32 49 786432 false
        warn "$(L 'Caps Lock включается только галочкой: Настройки -> Клавиатура -> Источники ввода -> «Использовать Caps Lock для переключения» (добавлено в список доделок).' 'Caps Lock switching is a checkbox: Settings -> Keyboard -> Input Sources -> Use Caps Lock to switch (added to the manual list).')"
        KB_MANUAL=1 ;;
    5)  ok "$(L 'Сочетание переключения не менял.' 'Switch shortcut left as is.')" ;;
esac
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null

# Второй ползунок «Дополнительно»: пароль администратора для общесистемных настроек
AUTH_TMP="/tmp/sysprefs_auth.plist"
as_root security authorizationdb read system.preferences > "$AUTH_TMP" 2>/dev/null
if [ -s "$AUTH_TMP" ] && plutil -replace shared -bool false "$AUTH_TMP" 2>/dev/null; then
    logcmd sudo security authorizationdb write system.preferences "<$AUTH_TMP"
    echo "$ADMIN_PASS" | sudo -S true 2>/dev/null
    if sudo -n security authorizationdb write system.preferences < "$AUTH_TMP" 2>/dev/null; then
        ok "Общесистемные настройки — только с паролем администратора."
    else
        warn "Не смог включить «пароль админа для общесистемных настроек» — включи руками (Настройки -> Конфиденциальность -> Дополнительно)."
    fi
else
    warn "Не смог включить «пароль админа для общесистемных настроек» — включи руками (Настройки -> Конфиденциальность -> Дополнительно)."
fi
rm -f "$AUTH_TMP"

# Экран входа: без подсказок пароля, без сообщения, без кнопок сна/перезагрузки
as_root defaults write /Library/Preferences/com.apple.loginwindow RetriesUntilHint -int 0 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText -string "" 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.loginwindow PowerOffDisabled -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.loginwindow RestartDisabled -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.loginwindow SleepDisabled -bool true 2>/dev/null
ok "Экран входа: подсказки, сообщение и кнопки питания отключены."

# Брандмауэр: вкл + stealth. БЕЗ --setblockall: режим «блокировать все
# входящие» ломает FUSE-T (он монтирует диски через локальный NFS/SMB на
# 127.0.0.1) — VeraCrypt тогда вечно висит на «пожалуйста подождите».
FW="/usr/libexec/ApplicationFirewall/socketfilterfw"
as_root "$FW" --setglobalstate on &>/dev/null
as_root "$FW" --setblockall off &>/dev/null
as_root "$FW" --setstealthmode on &>/dev/null
ok "Брандмауэр: включен + режим невидимости (блок ВСЕХ входящих выключен — он ломает VeraCrypt/FUSE-T)."

# AirDrop и Handoff выключить
defaults write com.apple.NetworkBrowser DisableAirDrop -bool YES 2>/dev/null
defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool no 2>/dev/null
defaults -currentHost write com.apple.coreservices.useractivityd ActivityReceivingAllowed -bool no 2>/dev/null
ok "AirDrop и Handoff выключены."

# Геолокация выключить
as_root defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool false 2>/dev/null
ok "Службы геолокации выключены."

# Аналитика выключить
defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit -bool false 2>/dev/null
as_root defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit -bool false 2>/dev/null
ok "Аналитика и отправка отчетов выключены."

# Siri выключить
defaults write com.apple.assistant.support "Assistant Enabled" -bool false 2>/dev/null
ok "Siri выключена."

# Gatekeeper: в новых macOS включен всегда и командой не управляется — ничего не делаем
ok "Установка приложений: App Store + известные разработчики (стандарт macOS, менять не нужно)."

# Wi-Fi: выключаем насовсем — работа ТОЛЬКО по кабелю (никаких утечек по воздуху)
WIFI_DEV=$(networksetup -listallhardwareports 2>/dev/null | awk '/Hardware Port: Wi-Fi/{getline; print $2}')
if [ -n "$WIFI_DEV" ]; then
    CUR_IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    if [ "$CUR_IF" = "$WIFI_DEV" ]; then
        warn "Интернет сейчас идет через Wi-Fi! Воткни кабель (Ethernet или Raspberry Pi), иначе скачивание оборвется."
        pause
        CUR_IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    fi
    if [ "$CUR_IF" != "$WIFI_DEV" ]; then
        networksetup -setairportpower "$WIFI_DEV" off &>/dev/null
        WIFI_SVC=$(networksetup -listnetworkserviceorder 2>/dev/null | grep -B1 "Device: $WIFI_DEV)" | head -1 | sed 's/^([^)]*) //')
        [ -z "$WIFI_SVC" ] && WIFI_SVC="Wi-Fi"
        as_root networksetup -removenetworkservice "$WIFI_SVC" &>/dev/null
        if networksetup -listallnetworkservices 2>/dev/null | grep -qx "\*\{0,1\}$WIFI_SVC"; then
            warn "Wi-Fi выключен, но удалить службу «$WIFI_SVC» не вышло — удали руками: Настройки -> Сеть -> Wi-Fi -> ... -> Удалить службу."
        else
            ok "Wi-Fi выключен и удален из сетевых служб — только кабель. Обратно: Настройки -> Сеть -> ... -> Добавить службу."
        fi
    else
        err "Кабель так и не появился — Wi-Fi НЕ трогаю (иначе упадут скачивания). Воткни кабель и перезапусти скрипт."
    fi
fi

# Часовой пояс под страну VPN
if [ -n "$VPN_TZ" ]; then
    # Автоустановку времени по геолокации выключаем, иначе macOS вернет реальный пояс
    as_root defaults write /Library/Preferences/com.apple.timezone.auto Active -bool NO 2>/dev/null
    as_root systemsetup -settimezone "$VPN_TZ" &>/dev/null && ok "$(L 'Часовой пояс:' 'Time zone:') $VPN_TZ ($(L 'автоопределение в macOS отключено' 'macOS auto time zone disabled'))" || warn "$(L 'Не смог поставить часовой пояс' 'Could not set time zone') $VPN_TZ"
fi

# Bluetooth: глушим (второй канал утечки после Wi-Fi)
as_root defaults write /Library/Preferences/com.apple.Bluetooth.plist ControllerPowerState -int 0 2>/dev/null
as_root pkill bluetoothd 2>/dev/null
ok "Bluetooth выключен (окончательно отключится после перезагрузки — в конце проверим вручную)."

echo ""
warn "Дальше скрипт сам: поставит программы, включит FileVault (ты только перепишешь ключ),"
echo "зашифрует диск и подключит данные. Руками в конце останется 2 пункта на 3 минуты."

# ------------------------------------------------------------
# ФАЗА 3: СКАЧИВАНИЕ И УСТАНОВКА ПРИЛОЖЕНИЙ
# ------------------------------------------------------------
step "ФАЗА 3/6 — Установка приложений"

DL="$HOME/Downloads/autosetup"
mkdir -p "$DL"

net_ok() {
    curl -s --max-time 5 -o /dev/null "https://captive.apple.com/hotspot-detect.html" && return 0
    curl -s --max-time 5 -o /dev/null "https://www.google.com" && return 0
    return 1
}

wait_for_internet() {
    if net_ok; then return 0; fi
    warn "Интернета НЕТ. Подключи кабель (Wi-Fi отключен) — жду и проверяю каждые 5 секунд..."
    echo "[$(date '+%H:%M:%S')] нет интернета, жду подключения" >> "$DLOG"
    local n=0
    while ! net_ok; do
        sleep 5
        n=$((n + 1))
        [ $((n % 6)) -eq 0 ] && echo "   ...все еще нет интернета ($((n * 5)) сек), жду."
    done
    ok "Интернет появился — продолжаю."
    echo "[$(date '+%H:%M:%S')] интернет появился" >> "$DLOG"
}

app_installed() {
    case "$1" in
        "FUSE-T")       pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t" ;;
        "VeraCrypt")    [ -d "/Applications/VeraCrypt.app" ] ;;
        "Telegram")     [ -d "/Applications/Telegram.app" ] ;;
        "Sublime Text") [ -d "/Applications/Sublime Text.app" ] ;;
        "Sphere")       [ -n "$(find /Applications -maxdepth 1 -iname '*sphere*' -o -iname 'ls*.app' 2>/dev/null | head -1)" ] ;;
        "Tukan")        [ -n "$(find /Applications -maxdepth 1 -iname '*tukan*' 2>/dev/null | head -1)" ] ;;
        *) return 1 ;;
    esac
}

install_dmg() {
    local url="$1" appname="$2" fname="$3"
    if app_installed "$appname"; then
        ok "$appname уже установлен — пропускаю."
        echo "[$(date '+%H:%M:%S')] $appname уже установлен, пропуск" >> "$DLOG"
        return 0
    fi
    [ -z "$fname" ] && fname=$(basename "$url")
    local dmg="$DL/$fname"
    wait_for_internet
    echo "Скачиваю $appname..."
    run curl -L -s -o "$dmg" "$url"
    if [ ! -f "$dmg" ] || [ ! -s "$dmg" ]; then
        err "$appname не скачался. Поставь вручную позже."
        return 1
    fi
    echo "Устанавливаю $appname..."
    if [[ "$fname" == *.pkg ]]; then
        as_root installer -pkg "$dmg" -target / >/dev/null
        if [ $? -eq 0 ]; then
            ok "$appname установлен (pkg)."
        else
            err "$appname: установка pkg не удалась — поставь вручную."
        fi
        return 0
    fi
    if [[ "$fname" == *.zip ]]; then
        unzip -q -o "$dmg" -d "$DL/unzipped_$appname"
        local zapp
        zapp=$(find "$DL/unzipped_$appname" -maxdepth 2 -name "*.app" | head -1)
        if [ -n "$zapp" ]; then
            as_root cp -R "$zapp" /Applications/ 2>/dev/null
            as_root xattr -dr com.apple.quarantine "/Applications/$(basename "$zapp")" 2>/dev/null
            ok "$appname установлен."
        else
            warn "$appname: в архиве нет .app — поставь вручную."
        fi
        return 0
    fi
    local mnt
    logcmd hdiutil attach "$dmg" -nobrowse
    mnt=$(yes | hdiutil attach "$dmg" -nobrowse 2>/dev/null | grep -o '/Volumes/.*' | tail -1)
    if [ -z "$mnt" ]; then
        mnt=$(as_root hdiutil attach "$dmg" -nobrowse 2>/dev/null | grep -o '/Volumes/.*' | tail -1)
    fi
    if [ -n "$mnt" ]; then
        app=$(find "$mnt" -maxdepth 1 -name "*.app" | head -1)
        if [ -n "$app" ]; then
            as_root cp -R "$app" /Applications/ 2>/dev/null
            as_root xattr -dr com.apple.quarantine "/Applications/$(basename "$app")" 2>/dev/null
            ok "$appname установлен."
        else
            pkg=$(find "$mnt" -maxdepth 1 -name "*.pkg" | head -1)
            if [ -n "$pkg" ]; then
                as_root installer -pkg "$pkg" -target / >/dev/null
                if [ $? -eq 0 ]; then
                    ok "$appname установлен (pkg)."
                else
                    err "$appname: установка pkg не удалась — поставь вручную."
                fi
            else
                warn "$appname: внутри dmg нет .app/.pkg — поставь вручную."
            fi
        fi
        hdiutil detach "$mnt" -quiet 2>/dev/null
    else
        err "$appname: не удалось открыть dmg. Поставь вручную."
    fi
}

# FUSE-T (нужен для VeraCrypt; на Tahoe поддерживает FSKit — без кернел-расширений)
install_dmg "https://github.com/macos-fuse-t/fuse-t/releases/download/1.2.7/fuse-t-macos-installer-1.2.7.pkg" "FUSE-T" "fuse-t-installer.pkg"

# VeraCrypt (сборка под FUSE-T — рекомендована для Apple Silicon)
install_dmg "https://launchpad.net/veracrypt/trunk/1.26.29/+download/VeraCrypt_FUSE-T_1.26.29.dmg" "VeraCrypt"

# Telegram
install_dmg "https://telegram.org/dl/macos/stable" "Telegram"

# Sublime Text
install_dmg "https://download.sublimetext.com/sublime_text_build_4200_mac.zip" "Sublime Text"

# Sublime Text — программа по умолчанию для текстовых файлов
if [ -d "/Applications/Sublime Text.app" ]; then
    SUBL_ID=$(defaults read "/Applications/Sublime Text.app/Contents/Info" CFBundleIdentifier 2>/dev/null)
    SUBL_ID=${SUBL_ID:-com.sublimetext.4}
    logcmd defaults write LSHandlers "расширения -> $SUBL_ID"
    for EXT in txt md markdown csv tsv json xml yaml yml log ini conf cfg env sh py js toml sql; do
        defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add \
            "{LSHandlerContentTag=\"$EXT\"; LSHandlerContentTagClass=\"public.filename-extension\"; LSHandlerRoleAll=\"$SUBL_ID\";}" 2>/dev/null
    done
    for UTI in public.plain-text public.text net.daringfireball.markdown public.comma-separated-values-text; do
        defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add \
            "{LSHandlerContentType=\"$UTI\"; LSHandlerRoleAll=\"$SUBL_ID\";}" 2>/dev/null
    done
    run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user >/dev/null 2>&1
    killall Finder 2>/dev/null
    ok "Sublime Text назначен по умолчанию для txt, md, csv, json, xml, yaml, log, sh и др."
else
    warn "Sublime Text не найден в /Applications — назначить его по умолчанию не вышло."
fi

# Sphere (Linken Sphere) — версия зависит от процессора
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    SPHERE_URL="https://cdn.ls.app/ls2_1.9.9_arm64.dmg"
else
    SPHERE_URL="https://cdn.ls.app/ls2_1.9.9_x86_64.dmg"
fi
install_dmg "$SPHERE_URL" "Sphere"

# Tukan
install_dmg "https://tukan.me/download/mac" "Tukan" "Tukan.dmg"

# ------------------------------------------------------------
# ФАЗА 4: FILEVAULT
# ------------------------------------------------------------
step "ФАЗА 4/6 — FileVault (шифрование диска)"

FV_STATUS=$(fdesetup status 2>/dev/null)
if echo "$FV_STATUS" | grep -q "On"; then
    ok "FileVault уже включен."
else
    echo "Сейчас я включу FileVault."
    echo "ВАЖНО: на экране появится КЛЮЧ ВОССТАНОВЛЕНИЯ."
    echo ""
    echo -e "${RED}${BOLD}>>> ПЕРЕПИШИ ЕГО НА БУМАГУ ИЛИ В ЗАМЕТКИ! БЕЗ НЕГО ДАННЫЕ НЕ ВЕРНУТЬ! <<<${NC}"
    echo ""
    echo "   Если спросит пароль еще раз — введи свой пароль от Mac."
    pause
    FV_OUT=$(as_root fdesetup enable -user "$(stat -f%Su /dev/console)" 2>&1)
    echo "$FV_OUT" > /dev/tty
    unset FV_OUT
    echo ""
    warn "Ключ выше — перепиши его прямо сейчас."
    pause
fi

# ------------------------------------------------------------
# ФАЗА 5: ЗАШИФРОВАННЫЙ ДИСК
# ------------------------------------------------------------
step "ФАЗА 5/6 — Внешний зашифрованный диск (VeraCrypt)"

VC="/Applications/VeraCrypt.app/Contents/MacOS/VeraCrypt"
SKIP_LINKS=0

list_external() {
    diskutil list external physical 2>/dev/null | awk '/^\/dev\//{print $1}'
}

wait_new_disk() {
    local before="$1" tries=0 new
    while [ $tries -lt 30 ]; do
        sleep 2
        new=$(comm -13 <(echo "$before" | sort) <(list_external | sort) | head -1)
        if [ -n "$new" ]; then echo "$new"; return 0; fi
        tries=$((tries + 1))
    done
    return 1
}

vc_mounted_vol() {
    "$VC" --text --list 2>/dev/null | grep -o '/Volumes/.*' | head -1
}

gui_mount_flow() {
    MOUNTED_PATH=$(vc_mounted_vol)
    if [ -n "$MOUNTED_PATH" ]; then
        ok "Диск уже смонтирован через VeraCrypt: $MOUNTED_PATH"
    else
        echo "Диск монтируешь ТЫ САМ через VeraCrypt — я подожду и продолжу автоматически."
        echo ""
        echo "  1) Вставь диск (если окно «диск не читается» — жми ИГНОРИРОВАТЬ, не «Инициализировать»!)."
        echo "  2) В окне VeraCrypt: кнопка «Select Device» -> выбери свой диск."
        echo "  3) Нажми «Mount», введи пароль (и PIM, если был)."
        echo ""
        open -a VeraCrypt 2>/dev/null
        echo "Жду, пока диск появится (до 15 минут)..."
        MOUNTED_PATH=""
        local i
        for i in $(seq 1 180); do
            sleep 5
            MOUNTED_PATH=$(vc_mounted_vol)
            [ -n "$MOUNTED_PATH" ] && break
        done
    fi
    if [ -z "$MOUNTED_PATH" ]; then
        err "За 15 минут диск в VeraCrypt так и не появился. Смонтируй его и запусти скрипт заново."
        SKIP_LINKS=1
    else
        VOL_NAME=$(basename "$MOUNTED_PATH")
        ok "Диск подключен: /Volumes/$VOL_NAME"
        DATA="/Volumes/$VOL_NAME/DataAPP"
        mkdir -p "$DATA"
        if [ ! -d "$DATA" ]; then
            err "Не смог создать папку на диске ($DATA) — диск только для чтения?"
            SKIP_LINKS=1
        fi
    fi
}

if [ "$HAVE_DISK" = "да" ]; then
    gui_mount_flow
else

echo "Сейчас настроим внешний диск (флешку/SSD) для секретных данных."
echo ""
echo "1) Если диск сейчас вставлен в Mac — ВЫТАЩИ его."
pause
BEFORE_DISKS=$(list_external)
echo "2) Теперь ВСТАВЬ диск в Mac. Ничего не жми — я сам его увижу."
echo -e "${RED}${BOLD}   Если выскочит окно «диск не читается» — жми ИГНОРИРОВАТЬ! Ни в коем случае не «Инициализировать»!${NC}"
DISK_DEV=$(wait_new_disk "$BEFORE_DISKS")

if [ -z "$DISK_DEV" ]; then
    err "Не увидел диск за 60 секунд. Вставь диск и запусти скрипт еще раз."
    SKIP_LINKS=1
else
    DINFO=$(diskutil info "$DISK_DEV" 2>/dev/null)
    DNAME=$(echo "$DINFO" | awk -F: '/Device \/ Media Name/{print $2}' | xargs)
    DSIZE=$(echo "$DINFO" | awk -F: '/Disk Size/{print $2}' | xargs | cut -d'(' -f1 | xargs)
    ok "Нашел диск: $DNAME ($DSIZE) на $DISK_DEV"
    read -r -p "Это тот самый диск? (да/нет) [да]: " CONFIRM
    CONFIRM=$(yn "${CONFIRM:-да}")
    if [ "$CONFIRM" != "да" ]; then
        err "Тогда вытащи лишние диски и запусти скрипт заново."
        SKIP_LINKS=1
    elif [ "$HAVE_DISK" != "да" ]; then
        FS_CHECK=$(diskutil list "$DISK_DEV" 2>/dev/null | grep -Ei 'Apple_|Microsoft|Windows_|ExFAT|HFS|APFS|FAT')
        if [ -z "$FS_CHECK" ]; then
            warn "macOS не видит на нем файловую систему — похоже, диск УЖЕ зашифрован VeraCrypt."
            read -r -p "   Это так? Тогда ничего стирать не буду, просто подключу. (да/нет) [да]: " ALREADY
            ALREADY=$(yn "${ALREADY:-да}")
            if [ "$ALREADY" = "да" ]; then
                HAVE_DISK="да"
                gui_mount_flow
            fi
        fi
    fi
fi

if [ "$SKIP_LINKS" = "0" ] && [ "$HAVE_DISK" != "да" ]; then
    QUICK=""
    [ "$ENC_MODE" = "1" ] && QUICK="--quick"
    echo ""
    warn "ВСЁ содержимое диска $DNAME будет УНИЧТОЖЕНО."
    read -r -p "Точно продолжаем? (да/нет) [да]: " WIPE_OK
    WIPE_OK=$(yn "${WIPE_OK:-да}")
    if [ "$WIPE_OK" != "да" ]; then
        SKIP_LINKS=1
    else
        echo "Отключаю диск и запускаю шифрование (прогресс в процентах)..."
        diskutil unmountDisk "$DISK_DEV" &>/dev/null
        # Файловая система HFS+ (Mac OS Extended) — родная для macOS. НЕ exFAT:
        # данные приложений (Telegram, Sphere и т.д.) используют права доступа,
        # расширенные атрибуты и симлинки, которые exFAT НЕ хранит — на exFAT
        # приложения ломаются. HFS+ хранит всё как надо на Apple Silicon (M1).
        as_root "$VC" --text --non-interactive --create "$DISK_DEV" --volume-type normal --encryption AES --hash SHA-512 --filesystem "HFS+" --pim "$DISK_PIM" -k "" --password "$DISK_PASS" --random-source /dev/urandom $QUICK
        if [ $? -ne 0 ]; then
            err "VeraCrypt не смогла зашифровать диск. Запусти скрипт еще раз."
            SKIP_LINKS=1
        else
            ok "Диск зашифрован."
        fi
    fi
fi

if [ "$SKIP_LINKS" = "0" ] && [ "$HAVE_DISK" != "да" ]; then
    echo "Подключаю зашифрованный диск..."
    BEFORE_VOL=$(ls /Volumes/)
    diskutil unmountDisk "$DISK_DEV" &>/dev/null

    try_mount() {
        local dev="$1" out
        out=$(as_root "$VC" --text --non-interactive --pim "$DISK_PIM" -k "" --protect-hidden no --password "$DISK_PASS" "$dev" 2>&1)
        VC_ERR="$out"
        local i
        for i in $(seq 1 10); do
            sleep 2
            MOUNTED=$(comm -13 <(echo "$BEFORE_VOL" | sort) <(ls /Volumes/ | sort) | head -1)
            [ -n "$MOUNTED" ] && return 0
        done
        return 1
    }

    MOUNTED=""
    if ! try_mount "$DISK_DEV"; then
        # Возможно, зашифрован не весь диск, а раздел (так делает GUI VeraCrypt)
        for SLICE in $(diskutil list "$DISK_DEV" 2>/dev/null | awk '/disk[0-9]+s[0-9]+/{print "/dev/"$NF}'); do
            echo "   Пробую раздел $SLICE..."
            try_mount "$SLICE" && break
        done
    fi

    if [ -z "$MOUNTED" ]; then
        err "Диск не подключился. Либо пароль/PIM неверный, либо неверный ответ в начале («уже зашифрован?»)."
        [ -n "$VC_ERR" ] && echo "   Ответ VeraCrypt: $(echo "$VC_ERR" | grep -vi password | tail -3)"
        echo "   Если диск НОВЫЙ (его никогда не шифровали) — запусти скрипт еще раз и ответь «нет»."
        SKIP_LINKS=1
    else
        if [ "$HAVE_DISK" != "да" ] && [ -n "$DISK_NAME" ]; then
            as_root diskutil rename "/Volumes/$MOUNTED" "$DISK_NAME" &>/dev/null
            sleep 2
            [ -d "/Volumes/$DISK_NAME" ] && MOUNTED="$DISK_NAME"
        fi
        VOL_NAME="$MOUNTED"
        ok "Диск подключен: /Volumes/$VOL_NAME"
        DATA="/Volumes/$VOL_NAME/DataAPP"
        mkdir -p "$DATA"
    fi
fi

fi # конец ветки «диск новый, шифруем с нуля»

# ------------------------------------------------------------
# ФАЗА 6: ПЕРЕНОС ДАННЫХ + СИМЛИНКИ
# ------------------------------------------------------------
step "ФАЗА 6/6 — Подключение данных приложений"

if [ "$SKIP_LINKS" = "1" ]; then
    warn "Пропущено (нет диска)."
else
    link_to() {
        local src="$1" dst="$2"
        if [ -L "$src" ]; then
            ok "$(basename "$src") — симлинк уже есть."
            return 0
        fi
        mkdir -p "$(dirname "$src")"
        if [ -e "$src" ]; then
            rm -rf "$src"
            ok "$(basename "$src"): старая папка из системы стерта (данные уже на диске)."
        fi
        ln -s "$dst" "$src"
        if [ -L "$src" ]; then
            ok "$(basename "$src") — подключен с диска."
        else
            err "$(basename "$src") — симлинк НЕ создан!"
        fi
    }

    # --- 0a) ГЛУБОКИЙ ПОИСК: данные могут лежать в ЛЮБОЙ подпапке диска, не только в DataAPP ---
    DISK_ROOT="/Volumes/$VOL_NAME"
    deep_find() {
        logcmd find "$DISK_ROOT" -type d -iname "$1"
        find "$DISK_ROOT" -maxdepth 8 -type d -iname "$1" \
            -not -path "$DATA/*" -not -path "*/.Trashes/*" \
            -not -path "*/.Spotlight-V100/*" -not -path "*/.fseventsd/*" 2>/dev/null | head -1
    }
    # НИЧЕГО НЕ ПЕРЕНОСИМ: папки остаются там, где лежат на диске —
    # к ним просто делается симлинк из системы.
    link_in_place() {
        local found="$1" src="$2"
        [ -d "$found" ] || return 1
        echo ""
        echo "$(L 'Нашел данные на диске:' 'Found data on the disk:') $found"
        read -r -p "   $(L 'Подключить симлинком (ничего не переношу)? (да/нет) [да]' 'Link it with a symlink (nothing is moved)? (yes/no) [yes]'): " LK
        LK=$(yn "${LK:-да}")
        [ "$LK" != "да" ] && return 1
        link_to "$src" "$found"
        LINKED_SRC="$LINKED_SRC|$src"
        return 0
    }
    LINKED_SRC=""

    echo "$(L 'Ищу данные приложений по ВСЕМУ диску (включая подпапки) — переносить никуда не буду.' 'Scanning the whole disk (all subfolders) — nothing will be moved.')"
    TG_SRC="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable"
    if [ ! -d "$DATA/Telegram/stable" ]; then
        TG_FOUND=$(deep_find "6N38VWS5BX.ru.keepcoder.Telegram")
        if [ -n "$TG_FOUND" ] && [ -d "$TG_FOUND/stable" ]; then
            link_in_place "$TG_FOUND/stable" "$TG_SRC"
        else
            TG_FOUND=$(deep_find "stable")
            if [ -n "$TG_FOUND" ] && [ -e "$TG_FOUND/accounts-metadata" ]; then
                link_in_place "$TG_FOUND" "$TG_SRC"
            fi
        fi
    fi
    [ ! -d "$DATA/Sublime Text" ] && { ST_FOUND=$(deep_find "Sublime Text"); [ -n "$ST_FOUND" ] && link_in_place "$ST_FOUND" "$HOME/Library/Application Support/Sublime Text"; }
    [ ! -d "$DATA/app.ls" ] && { LS_FOUND=$(deep_find "app.ls"); [ -n "$LS_FOUND" ] && link_in_place "$LS_FOUND" "$HOME/Library/Application Support/app.ls"; }
    if ! find "$DATA" -maxdepth 1 -iname "*tukan*" 2>/dev/null | grep -q .; then
        TK_FOUND=$(deep_find "*tukan*")
        [ -n "$TK_FOUND" ] && link_in_place "$TK_FOUND" "$HOME/Library/Application Support/$(basename "$TK_FOUND")"
    fi

    # --- 0) TELEGRAM С ФЛЕШКИ: доступа к номеру нет, сессия живет только в этих файлах ---
    TG_ON_DISK="$DATA/Telegram/stable"
    TG_LOCAL="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable"
    if [ ! -d "$TG_ON_DISK" ] && [ ! -d "$TG_LOCAL" ] && [ ! -L "$TG_LOCAL" ]; then
        echo ""
        warn "Данных Telegram нет ни в системе, ни на диске."
        warn "Если доступа к номеру телефона НЕТ — без бэкапа в Telegram ты больше НЕ ВОЙДЕШЬ."
        read -r -p "Есть бэкап папки Telegram на флешке? (да/нет) [да]: " HAVE_BK
        HAVE_BK=$(yn "${HAVE_BK:-да}")
        if [ "$HAVE_BK" = "да" ]; then
            echo "Вставь флешку с бэкапом (секретный диск вытаскивать НЕ нужно)."
            pause
            BK_SRC=$(find /Volumes -maxdepth 8 -type d -name "6N38VWS5BX.ru.keepcoder.Telegram" -not -path "*/.Trashes/*" 2>/dev/null | grep -v "^/Volumes/$VOL_NAME" | head -1)
            if [ -z "$BK_SRC" ]; then
                warn "Сам не нашел бэкап. Перетащи мышкой папку «6N38VWS5BX.ru.keepcoder.Telegram» в это окно и нажми Enter:"
                read -r BK_IN
                BK_SRC="${BK_IN% }"
                BK_SRC="${BK_SRC//\\ / }"
                BK_SRC="${BK_SRC//\'/}"
            fi
            if [ -d "$BK_SRC/stable" ]; then
                mkdir -p "$DATA/Telegram"
                cp -R "$BK_SRC/stable" "$DATA/Telegram/stable"
                if [ -d "$DATA/Telegram/stable" ]; then
                    ok "Telegram восстановлен на секретный диск. После настройки откроется уже вошедшим."
                else
                    err "Копирование не удалось. После настройки скопируй вручную в DataAPP/Telegram на диске."
                fi
            else
                err "В папке $BK_SRC нет «stable» — это не тот бэкап. После настройки скопируй вручную в DataAPP/Telegram."
            fi
        else
            warn "Бэкапа нет — Telegram будет ПУСТЫМ. Войти получится только с доступом к номеру телефона."
        fi
    fi

    # --- 1) ВОССТАНОВЛЕНИЕ: сканируем диск и предлагаем подключить найденное ---
    FOUND=0
    for item in "$DATA"/*; do
        [ -e "$item" ] || continue
        name=$(basename "$item")
        case "$name" in
            Telegram)
                src="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable"
                [ -d "$item/stable" ] || continue
                sub="$item/stable" ;;
            *)
                src="$HOME/Library/Application Support/$name"
                sub="$item" ;;
        esac
        echo "Нашел на диске: «$name»"
        read -r -p "   Подключить к системе? (да/нет) [да]: " L
        L=$(yn "${L:-да}")
        [ "$L" != "да" ] && continue
        FOUND=1
        link_to "$src" "$sub"
    done
    [ $FOUND -eq 0 ] && echo "На диске пока нет данных — настроим с нуля."

    # --- 2) ОБЯЗАТЕЛЬНЫЕ ПРИЛОЖЕНИЯ: если не подключены — переносим с системы или создаем ---
    ensure_app() {
        local src="$1" dstname="$2"
        local dst="$DATA/$dstname"
        [ -L "$src" ] && return 0
        if [ -d "$dst" ]; then
            link_to "$src" "$dst"
        elif [ -d "$src" ]; then
            mkdir -p "$(dirname "$dst")"
            cp -R "$src" "$dst"
            if [ $? -eq 0 ]; then
                rm -rf "$src"
                ok "$dstname — данные перенесены на диск, копия в системе СТЕРТА."
                link_to "$src" "$dst"
            else
                err "$dstname — копирование на диск не удалось, оригинал оставлен в системе!"
            fi
        else
            mkdir -p "$dst"
            link_to "$src" "$dst"
        fi
    }

    ensure_app "$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable" "Telegram/stable"
    ensure_app "$HOME/Library/Application Support/Sublime Text" "Sublime Text"
    ensure_app "$HOME/Library/Application Support/app.ls" "app.ls"

    TUKAN_DIR=$(find "$HOME/Library/Application Support" -maxdepth 1 -iname "*tukan*" 2>/dev/null | head -1)
    if [ -n "$TUKAN_DIR" ]; then
        ensure_app "$TUKAN_DIR" "$(basename "$TUKAN_DIR")"
    else
        warn "Tukan: папка не найдена. Запусти Tukan один раз и перезапусти скрипт."
    fi
fi

# ------------------------------------------------------------
# ОБНОВЛЕНИЯ MACOS (автоматически)
# ------------------------------------------------------------
step "ОБНОВЛЕНИЯ macOS"

as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true 2>/dev/null
ok "Автообновления включены (система и App Store)."

echo "Проверяю и ставлю обновления macOS — может занять ДОЛГО (не закрывай окно, Mac не трогай)..."
if as_root softwareupdate --install --all --agree-to-license 2>&1 | grep -qi "restart"; then
    warn "Обновления скачаны, но требуют перезагрузки — она и так будет в конце проверки."
else
    ok "Обновления macOS установлены (или их не было)."
fi

# ------------------------------------------------------------
# ФИНАЛ
# ------------------------------------------------------------
step "ГОТОВО"

echo "Что осталось сделать РУКАМИ (2 минуты):"
echo "What is left to do MANUALLY (2 minutes):"
echo ""
echo "  1. Если Tukan не подключился — запусти его 1 раз, потом запусти этот скрипт еще раз."
echo "     If Tukan is not linked — launch it once, then run this script again."
echo "  2. Настройки -> Bluetooth -> должен быть ВЫКЛ (если включен — выключи)."
echo "     Settings -> Bluetooth -> must be OFF (turn it off if it is on)."
echo "  3. Настройки -> Экран блокировки -> «Запрашивать пароль после включения заставки» = СРАЗУ."
echo "     Settings -> Lock Screen -> «Require password after screen saver begins» = IMMEDIATELY."
echo "  4. TUKAN: задай ДВА пароля — один для входа, ВТОРОЙ на удаление данных (аварийный)."
echo "     Второй пароль стирает всё при вводе — никому не говори и не проверяй ради интереса."
echo "     TUKAN: set TWO passwords — one to log in, the SECOND one wipes the data (panic password)."
echo "     The second password erases everything — never share it and never test it."
echo "  5. Раскладки: Настройки -> Клавиатура -> Источники ввода — должны быть U.S. и Русская."
echo "     Layouts: Settings -> Keyboard -> Input Sources — must list U.S. and Russian."
if [ "$KB_MANUAL" = "1" ]; then
    echo "  6. Там же поставь галочку «Использовать Caps Lock для переключения раскладки»."
    echo "     There, tick «Use Caps Lock key to switch input source»."
fi
echo ""
echo -e "  ${BOLD}ГЛАВНОЕ ПРАВИЛО:${NC} ничего не храни в системе Mac и на Рабочем столе —"
echo "  все файлы ТОЛЬКО на подключенном секретном диске. Что попало в систему,"
echo "  можно восстановить даже после удаления. Отключил диск -> на Mac ноль твоих файлов."
echo -e "  ${BOLD}MAIN RULE:${NC} keep nothing inside macOS or on the Desktop — all files ONLY on the"
echo "  mounted secret disk. Anything written to the system can be recovered even after deletion."
echo ""
echo "  ВАЖНО: Wi-Fi выключен насовсем (работа только по кабелю)."
echo "  Вернуть, если вдруг надо: Настройки -> Сеть -> кнопка ... -> Добавить службу -> Wi-Fi."
echo "  IMPORTANT: Wi-Fi is disabled for good (cable only). To bring it back:"
echo "  Settings -> Network -> ... button -> Add Service -> Wi-Fi."
if [ "$CREATE_USER" = "да" ]; then
    echo ""
    echo "  УЧЕТКИ: работай под «$NEW_USER» (её пароль). Основная (админ) — только для установки программ."
fi
echo ""
echo "ПРОВЕРКА, ЧТО ВСЁ РАБОТАЕТ (обязательно, 3 минуты):"
echo "FINAL CHECK (mandatory, 3 minutes):"
echo "  0. После перезагрузки запусти ПРОВЕРИТЬ.command (лежит рядом с этим скриптом) —"
echo "     он сам проверит все настройки и покажет зеленый/красный список."
echo "     After the reboot run ПРОВЕРИТЬ.command (next to this script) — it checks everything."
echo "  1. Яблоко -> Перезагрузить.  /  Apple menu -> Restart."
echo "  2. После входа открой VeraCrypt (Программы -> VeraCrypt):"
echo "     After login open VeraCrypt (Applications -> VeraCrypt):"
echo "     - кнопка Select Device -> выбери свою флешку/диск (строка целиком) -> OK"
echo "     - кнопка Mount -> введи пароль диска (и PIM, если задавал)"
echo "     - если спросит пароль от Mac — введи"
echo "     - диск появится в Finder"
echo "  3. Открой Telegram — чаты должны быть на месте.  /  Open Telegram — chats must be there."
echo "  4. В VeraCrypt нажми Dismount, ВЫТАЩИ диск и снова открой Telegram — он должен быть ПУСТОЙ."
echo "     Пустой = данные живут только на диске. Это и была цель."
echo "     In VeraCrypt press Dismount, unplug the disk, open Telegram — it must be EMPTY."
echo "  5. Подключи диск обратно (пункт 2) — чаты вернутся.  /  Mount the disk again — chats return."
echo "  6. Настройки -> Сеть: Wi-Fi в списке быть не должно.  /  Settings -> Network: no Wi-Fi."
echo "  7. Если бэкап Telegram был на обычной флешке — УДАЛИ его с неё (это полный доступ к телеге)."
echo "     If the Telegram backup was on a normal flash drive — DELETE it there (it is full access)."
echo ""
ok "Технический лог (на всякий случай): $LOG"
ok "Детальный лог всех команд (что и когда выполнялось): $DLOG"
echo ""
echo -e "${GREEN}${BOLD}НАСТРОЙКА ЗАВЕРШЕНА. Можно закрыть окно.${NC}"

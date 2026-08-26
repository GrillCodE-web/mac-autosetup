#!/bin/bash

# ============================================================
#  АВТОНАСТРОЙКА MAC — ПОЛНЫЙ АВТОМАТ
#  Человеку нужно только: нажимать Enter и один раз ввести пароль
# ============================================================

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Логи НЕ ведутся принципиально: любой файл с историей настройки — это след,
# который потом восстанавливается с диска. Все видно только на экране.
rm -f /tmp/autosetup_log.txt /tmp/autosetup_commands.txt 2>/dev/null

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GREY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}${BOLD}✔${NC}  $1"; }
warn() { echo -e "  ${YELLOW}${BOLD}▲${NC}  $1"; }
err()  { echo -e "  ${RED}${BOLD}✖${NC}  $1"; }
info() { echo -e "  ${BLUE}${BOLD}•${NC}  $1"; }
dim()  { echo -e "     ${GREY}$1${NC}"; }
hr()   { echo -e "${GREY}   ────────────────────────────────────────────────────────${NC}"; }

# Папка Telegram называется по-разному в разных сборках: префикс команды
# (6N38VWS5BX. и др.) может отличаться. Поэтому везде ищем по хвосту имени.
TG_GLOB="*keepcoder.Telegram"
tg_local_dir() {
    local d
    d=$(find "$HOME/Library/Group Containers" -maxdepth 1 -name "$TG_GLOB" 2>/dev/null | head -1)
    [ -z "$d" ] && d="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram"
    echo "$d"
}

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

# Ничего никуда не пишем — заглушка оставлена, чтобы не менять вызовы по всему скрипту
logcmd() { :; }
run() { "$@"; }
as_root() { printf '%s\n' "$ADMIN_PASS" | sudo -S "$@"; }

step() {
    local t="$1"
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}${CYAN}▎${NC}${BOLD} $t${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
}

ask() {
    echo ""
    echo -e "${BOLD}${YELLOW}?${NC} ${BOLD}$1${NC}"
}

pause() {
    echo ""
    echo -e "${YELLOW}${BOLD}⏎${NC}  $(L 'Когда сделаешь — нажми Enter' 'When done — press Enter')"
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

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "   ${BOLD}АВТОНАСТРОЙКА И ЗАЩИТА MAC  /  MAC SETUP & HARDENING${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo ""
info "$(L 'Скрипт настроит этот Mac сам — просто следуй экрану.' 'The script sets this Mac up on its own — just follow the screen.')"
info "$(L 'Сначала несколько вопросов, потом всё идет без тебя.' 'A few questions first, then it runs unattended.')"
dim "$(L 'Логи не ведутся — никаких следов в системе не остается.' 'No logs are written — no traces left in the system.')"

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
echo "8) $(L 'Дополнительные программы (по желанию).' 'Optional extra apps.')"
echo "   $(L 'Их данные тоже уедут на зашифрованный диск (симлинками).' 'Their data also goes to the encrypted disk (via symlinks).')"
read -r -p "   $(L 'Ставить MailMate (почтовый клиент)? (да/нет) [нет]' 'Install MailMate (email client)? (yes/no) [no]'): " INSTALL_MM
INSTALL_MM=$(yn "${INSTALL_MM:-нет}")
read -r -p "   $(L 'Ставить qTox (мессенджер Tox)? (да/нет) [нет]' 'Install qTox (Tox messenger)? (yes/no) [no]'): " INSTALL_QTOX
INSTALL_QTOX=$(yn "${INSTALL_QTOX:-нет}")

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
# Пишем через defaults export -> PlistBuddy -> defaults import: прямая правка
# файла бесполезна (cfprefsd держит настройки в памяти и перезатрет их).
add_layout() {
    local key="$1" name="$2" id="$3"
    local tmp="/tmp/hitoolbox_$$.plist" n
    defaults export com.apple.HIToolbox "$tmp" 2>/dev/null || return 1
    if /usr/libexec/PlistBuddy -c "Print :$key" "$tmp" 2>/dev/null | grep -q "KeyboardLayout Name = $name$"; then
        rm -f "$tmp"; return 0
    fi
    /usr/libexec/PlistBuddy -c "Add :$key array" "$tmp" 2>/dev/null
    n=$(/usr/libexec/PlistBuddy -c "Print :$key" "$tmp" 2>/dev/null | grep -c "Dict {")
    /usr/libexec/PlistBuddy -c "Add :$key:$n dict" "$tmp" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :$key:$n:InputSourceKind string 'Keyboard Layout'" "$tmp" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :$key:$n:'KeyboardLayout ID' integer $id" "$tmp" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :$key:$n:'KeyboardLayout Name' string '$name'" "$tmp" 2>/dev/null
    logcmd defaults import com.apple.HIToolbox "(+$name)"
    defaults import com.apple.HIToolbox "$tmp" 2>/dev/null
    rm -f "$tmp"
}

add_layout AppleEnabledInputSources "U.S." 0
add_layout AppleEnabledInputSources "Russian" 19456
add_layout AppleInputSourceHistory "Russian" 19456
if defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -q "Russian"; then
    ok "$(L 'Раскладки: английская (U.S.) + русская — обе на месте.' 'Layouts: English (U.S.) + Russian — both present.')"
    KB_ADDED=1
else
    warn "$(L 'macOS не принял раскладку из терминала. Открою настройки — добавь русскую сам, я подожду.' 'macOS refused the layout from the terminal. Opening settings — add Russian yourself, I will wait.')"
    open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" 2>/dev/null
    KB_TRY=0
    while [ $KB_TRY -lt 40 ]; do
        sleep 3
        KB_TRY=$((KB_TRY + 1))
        if defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -q "Russian"; then
            KB_ADDED=1; break
        fi
        [ $((KB_TRY % 10)) -eq 0 ] && dim "$(L 'жду русскую раскладку...' 'waiting for the Russian layout...')"
    done
    if [ "$KB_ADDED" = "1" ]; then
        ok "$(L 'Русская раскладка появилась.' 'Russian layout is now present.')"
    else
        err "$(L 'Русской раскладки так и нет — добавь: Настройки -> Клавиатура -> Источники ввода -> +.' 'Russian layout is still missing — add it: Settings -> Keyboard -> Input Sources -> +.')"
        KB_LAYOUT_MANUAL=1
    fi
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

# Bluetooth: глушим (второй канал утечки после Wi-Fi).
# На свежих macOS одного defaults мало — сервис надо ПЕРЕЗАПУСТИТЬ и проверить реальное состояние.
bt_is_on() {
    local s
    s=$(system_profiler SPBluetoothDataType 2>/dev/null | grep -i -m1 "State:")
    case "$s" in
        *[Oo]ff*) return 1 ;;
        *[Oo]n*)  return 0 ;;
    esac
    s=$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null)
    [ "$s" = "0" ] && return 1
    return 0
}

bt_off() {
    as_root defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 0 2>/dev/null
    as_root defaults write /Library/Preferences/com.apple.Bluetooth.plist ControllerPowerState -int 0 2>/dev/null
    as_root launchctl kickstart -k system/com.apple.bluetoothd 2>/dev/null \
        || as_root killall -9 bluetoothd 2>/dev/null
    sleep 3
}

info "$(L 'Выключаю Bluetooth...' 'Turning Bluetooth off...')"
bt_off
if bt_is_on; then
    bt_off
fi
if bt_is_on; then
    warn "$(L 'macOS не дает выключить Bluetooth из терминала (так на свежих версиях).' 'macOS refuses to turn Bluetooth off from the terminal (common on recent versions).')"
    info "$(L 'Открываю настройки Bluetooth — переключи тумблер в ВЫКЛ, я подожду и проверю сам.' 'Opening Bluetooth settings — flip the switch OFF, I will wait and verify.')"
    open "x-apple.systempreferences:com.apple.BluetoothSettings" 2>/dev/null || open -b com.apple.systempreferences 2>/dev/null
    BT_TRY=0
    while bt_is_on && [ $BT_TRY -lt 60 ]; do
        sleep 3
        BT_TRY=$((BT_TRY + 1))
        [ $((BT_TRY % 10)) -eq 0 ] && dim "$(L 'жду, Bluetooth все еще включен...' 'waiting, Bluetooth is still on...')"
    done
    if bt_is_on; then
        err "$(L 'Bluetooth так и остался ВКЛЮЧЕН — выключи его вручную (добавил в список доделок).' 'Bluetooth is still ON — turn it off manually (added to the manual list).')"
        BT_MANUAL=1
    else
        ok "$(L 'Bluetooth выключен — вижу это в системе.' 'Bluetooth is off — confirmed by the system.')"
    fi
else
    ok "$(L 'Bluetooth выключен — вижу это в системе.' 'Bluetooth is off — confirmed by the system.')"
fi

# Пароль сразу после заставки/сна экрана — раньше это был ручной пункт
logcmd sysadminctl -screenLock immediate -password '<пароль>'
SL_OUT=$(sysadminctl -screenLock immediate -password "$ADMIN_PASS" 2>&1)
SL_NOW=$(sysadminctl -screenLock status 2>&1)
if echo "$SL_NOW" | grep -qi "immediate"; then
    ok "$(L 'Пароль запрашивается СРАЗУ после заставки/сна экрана.' 'Password is required IMMEDIATELY after screen saver / display sleep.')"
elif ! echo "$SL_OUT" | grep -qi "error\|usage"; then
    ok "$(L 'Пароль сразу после заставки — команда принята (проверю в ПРОВЕРИТЬ.command).' 'Immediate password after screen saver — command accepted (verify with ПРОВЕРИТЬ.command).')"
else
    osascript -e 'tell application "System Events" to set require password to wake of security preferences to true' 2>/dev/null \
        && ok "$(L 'Пароль после заставки включен (через System Events).' 'Password after screen saver enabled (via System Events).')" \
        || { warn "$(L 'Не смог включить «пароль сразу после заставки» — добавил в список доделок.' 'Could not enable «require password immediately» — added to the manual list.')"; SL_MANUAL=1; }
fi

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
    local n=0
    while ! net_ok; do
        sleep 5
        n=$((n + 1))
        [ $((n % 6)) -eq 0 ] && echo "   ...все еще нет интернета ($((n * 5)) сек), жду."
    done
    ok "Интернет появился — продолжаю."
}

app_installed() {
    case "$1" in
        "FUSE-T")       pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t" ;;
        "VeraCrypt")    [ -d "/Applications/VeraCrypt.app" ] ;;
        "Telegram")     [ -d "/Applications/Telegram.app" ] ;;
        "Sublime Text") [ -d "/Applications/Sublime Text.app" ] ;;
        "Sphere")       [ -n "$(find /Applications -maxdepth 1 -iname '*sphere*' -o -iname 'ls*.app' 2>/dev/null | head -1)" ] ;;
        "Tukan")        [ -n "$(find /Applications -maxdepth 1 -iname '*tukan*' 2>/dev/null | head -1)" ] ;;
        "MailMate")     [ -d "/Applications/MailMate.app" ] ;;
        "qTox")         [ -d "/Applications/qTox.app" ] ;;
        *) return 1 ;;
    esac
}

install_dmg() {
    local url="$1" appname="$2" fname="$3"
    if app_installed "$appname"; then
        ok "$appname уже установлен — пропускаю."
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
    if [[ "$fname" == *.tbz || "$fname" == *.tar.bz2 || "$fname" == *.tbz2 ]]; then
        rm -rf "$DL/untar_$appname"
        mkdir -p "$DL/untar_$appname"
        run tar -xjf "$dmg" -C "$DL/untar_$appname"
        local tapp
        tapp=$(find "$DL/untar_$appname" -maxdepth 2 -name "*.app" | head -1)
        if [ -n "$tapp" ]; then
            # Старую копию сносим целиком, иначе macOS плодит «MailMate 2.app» и т.п.
            as_root rm -rf "/Applications/$(basename "$tapp")" 2>/dev/null
            as_root cp -R "$tapp" /Applications/ 2>/dev/null
            as_root xattr -dr com.apple.quarantine "/Applications/$(basename "$tapp")" 2>/dev/null
            ok "$appname установлен."
        else
            warn "$appname: в архиве нет .app — поставь вручную."
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

# MailMate (по желанию) — раздается архивом .tbz; берем актуальную сборку 2.0 (её рекомендует разработчик)
if [ "$INSTALL_MM" = "да" ]; then
    install_dmg "https://updates.mailmate-app.com/archives/MailMateBeta.tbz" "MailMate" "MailMate.tbz"
fi

# qTox (по желанию) — актуальный релиз форка TokTok, dmg под свой процессор
if [ "$INSTALL_QTOX" = "да" ]; then
    if ! app_installed "qTox"; then
        wait_for_internet
        [ "$(uname -m)" = "arm64" ] && QT_ARCH="arm64" || QT_ARCH="x86_64"
        QTOX_URL=$(curl -L -s https://api.github.com/repos/TokTok/qTox/releases/latest 2>/dev/null \
            | grep -o "https://[^\"]*qTox-v[0-9.]*\.${QT_ARCH}-12\.0\.dmg" | head -1)
        if [ -z "$QTOX_URL" ]; then
            QTOX_URL=$(curl -L -s https://api.github.com/repos/TokTok/qTox/releases/latest 2>/dev/null \
                | grep -o "https://[^\"]*${QT_ARCH}[^\"]*\.dmg" | head -1)
        fi
    fi
    if app_installed "qTox"; then
        ok "qTox уже установлен — пропускаю."
    elif [ -n "$QTOX_URL" ]; then
        install_dmg "$QTOX_URL" "qTox" "qTox.dmg"
    else
        err "qTox: не смог получить ссылку на релиз (github.com/TokTok/qTox/releases) — поставь вручную."
    fi
fi

# Дубли в /Applications («MailMate 2.app», «Telegram копия.app» и т.п.) — убираем,
# иначе человек открывает не ту копию и не понимает, почему данные пустые.
dedupe_app() {
    local base="$1" keep="/Applications/$1.app" d
    [ -d "$keep" ] || return 0
    while IFS= read -r d; do
        [ "$d" = "$keep" ] && continue
        echo ""
        warn "$(L 'Нашел лишнюю копию программы:' 'Found a duplicate copy of the app:') $d"
        read -r -p "   $(L 'Удалить ее (оставлю' 'Delete it (keeping') $keep)? (да/нет) [да]: " DUPOK < /dev/tty
        [ "$(yn "${DUPOK:-да}")" = "да" ] && { as_root rm -rf "$d" && ok "$(L 'Удалено:' 'Deleted:') $d"; }
    done < <(find /Applications -maxdepth 1 -iname "$base*.app" 2>/dev/null)
}
for A in "MailMate" "Telegram" "VeraCrypt" "qTox" "Sublime Text"; do dedupe_app "$A"; done

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

# Кандидаты на «секретный диск»: все тома, кроме системных.
# Нужно потому, что VeraCrypt --list не всегда отвечает (другая версия, другой ПК,
# диск смонтирован не через CLI) — тогда просто смотрим, что реально есть в /Volumes.
list_candidate_vols() {
    local v boot
    boot=$(basename "$(df / 2>/dev/null | tail -1 | awk '{for(i=9;i<=NF;i++) printf "%s ",$i}' | xargs)" 2>/dev/null)
    for v in /Volumes/*; do
        [ -d "$v" ] || continue
        case "$(basename "$v")" in
            "Macintosh HD"|"Data"|"Preboot"|"Recovery"|"VM"|"Update"|"xarts"|"iSCPreboot"|"Hardware"|"$boot") continue ;;
        esac
        [ -L "$v" ] && continue
        echo "$v"
    done
}

vc_mounted_vol() {
    local v out
    out=$("$VC" --text --list 2>/dev/null | grep -o '/Volumes/.*' | head -1)
    if [ -n "$out" ] && [ -d "$out" ]; then echo "$out"; return 0; fi
    # Запасной путь: том, на котором уже лежат данные приложений.
    # Имя папки данных у каждого свое, поэтому ищем по самим данным.
    for v in $(list_candidate_vols); do
        if find "$v" -maxdepth 5 -type d \
               \( -iname "DataAPP" -o -iname "AppData" -o -name "$TG_GLOB" \
                  -o -name "app.ls" -o -name "Tox" -o -name "MailMate" -o -iname "*tukan*" \) \
               -not -path "*/.Trashes/*" 2>/dev/null | grep -q .; then
            echo "$v"; return 0
        fi
    done
    # Иначе — если внешний том ровно один, это он
    local all cnt
    all=$(list_candidate_vols)
    cnt=$(echo "$all" | grep -c . )
    if [ "$cnt" = "1" ]; then echo "$all"; return 0; fi
    return 1
}

# Папка данных на диске: у каждого называется по-своему (DataAPP, AppData, Данные,
# или вообще никак — данные лежат прямо в корне). Порядок поиска:
#   1) папка с подходящим именем;
#   2) папка, в которой РЕАЛЬНО лежат данные приложений (имя любое);
#   3) если ничего нет — создаем DataAPP (это первая настройка чистого диска).
resolve_data_dir() {
    local vol="$1" found hit
    found=$(find "$vol" -maxdepth 3 -type d \( -iname "DataAPP" -o -iname "AppData" -o -iname "APPDATA" \) \
            -not -path "*/.Trashes/*" 2>/dev/null | head -1)
    if [ -z "$found" ]; then
        hit=$(find "$vol" -maxdepth 6 -type d \
              \( -name "$TG_GLOB" -o -name "app.ls" -o -name "Tox" -o -name "MailMate" -o -iname "*tukan*" \) \
              -not -path "*/.Trashes/*" -not -path "*/.Spotlight-V100/*" 2>/dev/null | head -1)
        # Для Telegram структура «<папка данных>/Telegram/<контейнер>», для
        # остальных — «<папка данных>/<имя>»: поднимаемся на нужный уровень.
        if [ -n "$hit" ]; then
            found=$(dirname "$hit")
            case "$(basename "$found")" in
                Telegram|telegram) found=$(dirname "$found") ;;
            esac
        fi
    fi
    # Если данные лежат прямо в корне диска — папка данных и есть корень.
    if [ -z "$found" ]; then
        found="$vol/DataAPP"
        mkdir -p "$found" 2>/dev/null
    fi
    echo "$found"
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
        ok "$(L 'Диск подключен:' 'Disk mounted:') /Volumes/$VOL_NAME"
        DATA=$(resolve_data_dir "/Volumes/$VOL_NAME")
        info "$(L 'Папка данных на диске:' 'Data folder on the disk:') $DATA"
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
        ok "$(L 'Диск подключен:' 'Disk mounted:') /Volumes/$VOL_NAME"
        DATA=$(resolve_data_dir "/Volumes/$VOL_NAME")
        info "$(L 'Папка данных на диске:' 'Data folder on the disk:') $DATA"
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
    # Без maxdepth: у каждого своя структура папок, данные могут быть закопаны глубоко
    deep_find() {
        logcmd find "$DISK_ROOT" -type d -iname "$1"
        find "$DISK_ROOT" -type d -iname "$1" \
            -not -path "$DATA/*" -not -path "*/.Trashes/*" \
            -not -path "*/.Spotlight-V100/*" -not -path "*/.fseventsd/*" \
            -not -path "*/.DocumentRevisions*" -not -path "*/.TemporaryItems/*" 2>/dev/null | head -1
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
    TG_SRC="$(tg_local_dir)/stable"
    if [ ! -d "$DATA/Telegram/stable" ]; then
        TG_FOUND=$(deep_find "$TG_GLOB")
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
    [ ! -d "$DATA/MailMate" ] && { MM_FOUND=$(deep_find "MailMate"); [ -n "$MM_FOUND" ] && link_in_place "$MM_FOUND" "$HOME/Library/Application Support/MailMate"; }
    [ ! -d "$DATA/Tox" ] && { TOX_FOUND=$(deep_find "Tox"); [ -n "$TOX_FOUND" ] && link_in_place "$TOX_FOUND" "$HOME/Library/Application Support/Tox"; }
    if ! find "$DATA" -maxdepth 1 -iname "*tukan*" 2>/dev/null | grep -q .; then
        TK_FOUND=$(deep_find "*tukan*")
        [ -n "$TK_FOUND" ] && link_in_place "$TK_FOUND" "$HOME/Library/Application Support/$(basename "$TK_FOUND")"
    fi

    # --- 0) TELEGRAM С ФЛЕШКИ: доступа к номеру нет, сессия живет только в этих файлах ---
    TG_ON_DISK="$DATA/Telegram/stable"
    TG_LOCAL="$(tg_local_dir)/stable"
    if [ ! -d "$TG_ON_DISK" ] && [ ! -d "$TG_LOCAL" ] && [ ! -L "$TG_LOCAL" ]; then
        echo ""
        warn "Данных Telegram нет ни в системе, ни на диске."
        warn "Если доступа к номеру телефона НЕТ — без бэкапа в Telegram ты больше НЕ ВОЙДЕШЬ."
        read -r -p "Есть бэкап папки Telegram на флешке? (да/нет) [да]: " HAVE_BK
        HAVE_BK=$(yn "${HAVE_BK:-да}")
        if [ "$HAVE_BK" = "да" ]; then
            echo "Вставь флешку с бэкапом (секретный диск вытаскивать НЕ нужно)."
            pause
            BK_SRC=$(find /Volumes -type d -name "$TG_GLOB" -not -path "*/.Trashes/*" 2>/dev/null | grep -v "^/Volumes/$VOL_NAME" | head -1)
            if [ -z "$BK_SRC" ]; then
                warn "Сам не нашел бэкап. Перетащи мышкой папку Telegram (та, что заканчивается на «keepcoder.Telegram») в это окно и нажми Enter:"
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
                    err "Копирование не удалось. После настройки скопируй вручную в $DATA/Telegram."
                fi
            else
                err "В папке $BK_SRC нет «stable» — это не тот бэкап. После настройки скопируй вручную в $DATA/Telegram."
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
            Telegram|telegram)
                src="$(tg_local_dir)/stable"
                [ -d "$item/stable" ] || continue
                sub="$item/stable" ;;
            *keepcoder.Telegram)
                src="$(tg_local_dir)/stable"
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

    ensure_app "$(tg_local_dir)/stable" "Telegram/stable"
    ensure_app "$HOME/Library/Application Support/Sublime Text" "Sublime Text"
    ensure_app "$HOME/Library/Application Support/app.ls" "app.ls"

    # MailMate: почта (Messages) и настройки аккаунтов — только на диске
    if [ "$INSTALL_MM" = "да" ] || [ -d "/Applications/MailMate.app" ] || [ -e "$HOME/Library/Application Support/MailMate" ]; then
        ensure_app "$HOME/Library/Application Support/MailMate" "MailMate"
    fi

    # qTox: профиль .tox, история переписки и настройки — только на диске
    if [ "$INSTALL_QTOX" = "да" ] || [ -d "/Applications/qTox.app" ] || [ -e "$HOME/Library/Application Support/Tox" ]; then
        ensure_app "$HOME/Library/Application Support/Tox" "Tox"
    fi

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

MN=0
mitem() { MN=$((MN + 1)); echo -e "  ${YELLOW}${BOLD}$MN.${NC} $1"; echo "     $2"; }

echo -e "${BOLD}Что осталось сделать РУКАМИ (автоматом это сделать нельзя):${NC}"
echo -e "${GREY}What is left to do MANUALLY (cannot be automated):${NC}"
echo ""
mitem "TUKAN: задай ДВА пароля — один для входа, ВТОРОЙ на удаление данных (аварийный)." \
      "TUKAN: set TWO passwords — one to log in, the SECOND wipes all data (panic password)."
dim "Второй пароль стирает всё при вводе — никому не говори и не проверяй ради интереса."
[ ! -e "$TUKAN_DIR" ] && mitem "Tukan: запусти его 1 раз, потом запусти этот скрипт еще раз — подключу его данные." \
      "Tukan: launch it once, then run this script again so I can link its data."
[ "$BT_MANUAL" = "1" ] && mitem "Настройки -> Bluetooth -> выключи (я не смог из терминала)." \
      "Settings -> Bluetooth -> turn it off (I could not from the terminal)."
[ "$SL_MANUAL" = "1" ] && mitem "Настройки -> Экран блокировки -> «Запрашивать пароль после заставки» = СРАЗУ." \
      "Settings -> Lock Screen -> «Require password after screen saver begins» = IMMEDIATELY."
[ "$KB_LAYOUT_MANUAL" = "1" ] && mitem "Настройки -> Клавиатура -> Источники ввода -> + -> Русская." \
      "Settings -> Keyboard -> Input Sources -> + -> Russian."
[ "$KB_MANUAL" = "1" ] && mitem "Там же: галочка «Использовать Caps Lock для переключения раскладки»." \
      "Same place: tick «Use Caps Lock key to switch input source»."
if [ "$INSTALL_MM" = "да" ] || [ -d "/Applications/MailMate.app" ]; then
    mitem "MailMate: запусти при ПОДКЛЮЧЕННОМ диске и введи пароли почты один раз, галочка «запомнить»." \
          "MailMate: launch it WITH the disk mounted and enter mail passwords once, tick «remember»."
    dim "Пароли почты хранит Связка ключей macOS, а не папка на диске — поэтому после переезда"
    dim "на другой Mac их спрашивают заново. Это нормально и по-другому не бывает."
fi
[ "$INSTALL_QTOX" = "да" ] && mitem "qTox: запусти при ПОДКЛЮЧЕННОМ диске — профиль Tox создастся сразу на диске." \
      "qTox: launch it WITH the disk mounted — the Tox profile is created straight on the disk."
[ $MN -eq 0 ] && ok "Ручных пунктов нет — все сделано скриптом."
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
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "   ${GREEN}${BOLD}НАСТРОЙКА ЗАВЕРШЕНА. Можно закрыть окно.${NC}"
echo -e "   ${GREY}SETUP COMPLETE. You can close this window.${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"

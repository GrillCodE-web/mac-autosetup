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

# Маркер версии: если при запуске НЕ напечаталась строка «ВЕРСИЯ СКРИПТА» ниже —
# ты запускаешь УСТАРЕВШУЮ копию (в старых та самая гонка, что вешала меню).
# Проверка без запуска: grep -c SCRIPT_VERSION ЗАПУСТИТЬ.command  (0 = старая)
readonly SCRIPT_VERSION="v3-2026.08.26 — исправлены «недавние» (вешали меню) и подмена папок"
echo -e "${BOLD}ВЕРСИЯ СКРИПТА: ${CYAN}${SCRIPT_VERSION}${NC}"

# --- Визуальный каркас -----------------------------------------------------
# Ширина окна Терминала (линии и баннеры подстраиваются под окно, 60..120)
tw() {
    local w
    w=$(tput cols 2>/dev/null) || w=${COLUMNS:-80}
    case "$w" in ''|*[!0-9]*) w=80 ;; esac
    [ "$w" -lt 60 ] && w=60
    [ "$w" -gt 120 ] && w=120
    echo "$w"
}

# Повторить символ N раз: rep "─" 20
rep() { local s="$1" n="$2"; while [ "$n" -gt 0 ]; do printf '%s' "$s"; n=$((n - 1)); done; }

# Секунды -> ММ:СС (больше часа -> Ч:ММ:СС)
t2s() {
    local s="$1"
    if [ "$s" -ge 3600 ]; then
        printf '%d:%02d:%02d' $((s / 3600)) $(( (s % 3600) / 60 )) $((s % 60))
    else
        printf '%02d:%02d' $((s / 60)) $((s % 60))
    fi
}

# Спиннер для ожиданий: вызывай раз в тик с одним текстом, в конце — spin_end.
# Пишет в ту же строку (\r), поэтому во время ожидания НИЧЕГО другое не печатать.
SPIN_N=0
spin() {
    local f='|/-\' c
    c=${f:$SPIN_N:1}
    SPIN_N=$(( (SPIN_N + 1) % 4 ))
    printf '\033[2K  %s  %s ...\r' "$c" "$1"
}
spin_end() { printf '\033[2K'; }

ok()   { echo -e "  ${GREEN}${BOLD}✓${NC}  $1"; }
warn() { echo -e "  ${YELLOW}${BOLD}▲${NC}  $1"; }
err()  { echo -e "  ${RED}${BOLD}✗${NC}  $1"; }
info() { echo -e "  ${BLUE}${BOLD}•${NC}  $1"; }
dim()  { echo -e "  ${GREY}· $1${NC}"; }
sub()  { echo ""; echo -e "  ${BOLD}${CYAN}▸${NC} ${BOLD}$1${NC}"; }

# hr — тонкая серая линия на всю ширину окна
hr()   { echo -e "  ${GREY}$(rep "─" $(($(tw) - 4)))${NC}"; }

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
    local t="$1" w
    w=$(tw)
    echo ""
    echo -e "  ${GREY}─── $(t2s $SECONDS) $(rep "─" $((w - 10)))${NC}"
    echo -e "  ${CYAN}${BOLD}▎${NC} ${BOLD}$t${NC}"
    echo -e "  ${GREY}$(rep "─" $w)${NC}"
}

ask() {
    echo ""
    echo -e "${BOLD}${YELLOW}?${NC} ${BOLD}$1${NC}"
}

# Заголовок вопроса: q 3 "Внешний диск для секретных данных:"
q() {
    echo -e "  ${CYAN}${BOLD}[$1]${NC} ${BOLD}$2${NC}"
}

pause() {
    echo ""
    echo -e "  ${YELLOW}${BOLD}⏎${NC}  ${BOLD}$(L 'Когда сделаешь — нажми Enter' 'When done — press Enter')${NC}"
    read -r
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

# Пока идёт настройка — НЕ давать Mac гасить экран и засыпать. Иначе на долгих
# скачиваниях/обновлениях экран темнеет, человек думает «всё зависло/выключилось»
# и трогает Mac. caffeinate держит экран и систему включёнными до конца скрипта.
caffeinate -dimsu &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null' EXIT

clear

TITLE_W=$(tw)
echo ""
echo -e "  ${CYAN}$(rep "━" "$TITLE_W")${NC}"
echo -e "  ${CYAN}▎${NC}${BOLD}  АВТОНАСТРОЙКА И ЗАЩИТА MAC${NC}"
echo -e "  ${CYAN}▎${NC}  ${GREY}MAC SETUP & HARDENING${NC}"
echo -e "  ${CYAN}$(rep "━" "$TITLE_W")${NC}"
echo -e "  ${GREY}macOS $(sw_vers -productVersion 2>/dev/null) · $(sysctl -n hw.model 2>/dev/null) · $(date '+%d.%m.%Y %H:%M')${NC}"
echo ""
info "$(L 'Скрипт настроит этот Mac сам — просто следуй экрану.' 'The script sets this Mac up on its own — just follow the screen.')"
info "$(L 'Сначала несколько вопросов, потом всё идет без тебя.' 'A few questions first, then it runs unattended.')"
dim "$(L 'Логи не ведутся — никаких следов в системе не остается.' 'No logs are written — no traces left in the system.')"

# ------------------------------------------------------------
# ПРОВЕРКА СНАЧАЛА — ДО ВСЕХ ВОПРОСОВ (ничего не меняем, только смотрим)
# ------------------------------------------------------------
# 1) Какие приложения УЖЕ установлены — про них вопросы не задаются.
# 2) Какие данные УЖЕ подключены симлинками — про них тоже не спрашиваем.
step "ПРОВЕРКА (до вопросов): что уже установлено и подключено"

app_check() { [ -d "/Applications/$1.app" ]; }
MM_INSTALLED=нет;    app_check "MailMate"        && MM_INSTALLED=да
QTOX_INSTALLED=нет;  app_check "qTox"            && QTOX_INSTALLED=да
EXCEL_INSTALLED=нет; app_check "Microsoft Excel" && EXCEL_INSTALLED=да

sub "$(L 'Приложения' 'Apps')"
show_app() {
    if [ "$2" = "да" ]; then ok "$1 — $(L 'уже установлен' 'already installed')"
    else dim "$1 — $(L 'не установлен' 'not installed')"; fi
}
A_VC=нет;  app_check "VeraCrypt"    && A_VC=да
A_TG=нет;  app_check "Telegram"     && A_TG=да
A_ST=нет;  app_check "Sublime Text" && A_ST=да
show_app "VeraCrypt" "$A_VC"; show_app "Telegram" "$A_TG"; show_app "Sublime Text" "$A_ST"
show_app "MailMate" "$MM_INSTALLED"; show_app "qTox" "$QTOX_INSTALLED"; show_app "Microsoft Excel" "$EXCEL_INSTALLED"

sub "$(L 'Данные приложений (симлинки)' 'App data (symlinks)')"
precheck_link() {
    local label="$1" path="$2"
    if [ -L "$path" ]; then
        ok "$label — $(L 'уже симлинк (подключён к диску)' 'already a symlink (linked to disk)')"
    elif [ -e "$path" ]; then
        info "$label — $(L 'обычная папка в системе (перенесу на диск и заменю симлинком)' 'plain folder in system (will move to disk and replace with a symlink)')"
    else
        dim "$label — $(L 'данных пока нет' 'no data yet')"
    fi
}
precheck_link "Telegram"      "$(tg_local_dir)/stable"
precheck_link "Sublime Text"  "$HOME/Library/Application Support/Sublime Text"
precheck_link "Linken Sphere" "$HOME/Library/Application Support/app.ls"
precheck_link "Safari"        "$HOME/Library/Safari"
precheck_link "MailMate"      "$HOME/Library/Application Support/MailMate"
precheck_link "Tox (qTox)"    "$HOME/Library/Application Support/Tox"
TUKAN_PRECHECK=$(find "$HOME/Library/Application Support" -maxdepth 1 -iname "*tukan*" 2>/dev/null | head -1)
precheck_link "Tukan"         "${TUKAN_PRECHECK:-$HOME/Library/Application Support/Tukan}"
sub "$(L 'Пользовательские папки' 'User folders')"
precheck_link "$(L 'Рабочий стол' 'Desktop')"   "$HOME/Desktop"
precheck_link "$(L 'Документы' 'Documents')"    "$HOME/Documents"
precheck_link "$(L 'Загрузки' 'Downloads')"     "$HOME/Downloads"
dim "$(L 'Это только осмотр — данные подключаются на Фазе 6, когда диск смонтирован.' 'This is just a look — data is linked in Phase 6 once the disk is mounted.')"

# ------------------------------------------------------------
# ВОПРОСЫ В НАЧАЛЕ (чтобы потом не отвлекать)
# ------------------------------------------------------------
step "ВОПРОСЫ (один раз, в начале)"

q 1 "Создать ОТДЕЛЬНУЮ рабочую учетную запись (вторая, кроме основной)?"
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
q 2 "Пароль от этого Mac (тот, что задал при первой настройке):"
read -rs -p "   Пароль администратора: " ADMIN_PASS; echo ""

# Проверяем sudo сразу
as_root -k true 2>/dev/null
if [ $? -ne 0 ]; then
    err "Пароль администратора не подошел. Запусти скрипт заново."
    exit 1
fi
ok "Пароль администратора верный."

# --- ПОЛНЫЙ ДОСТУП К ДИСКУ (FDA) -------------------------------------------
# В macOS НЕТ способа запросить его автоматически: ни промпта, ни API — только
# руками в Настройках). Без него Терминалу запрещено трогать ~/Library/Safari и
# другие TCC-защищённые папки: rm/ln/cp там падают с «Operation not permitted».
# Поэтому скрипт проверяет доступ САМ, и если его нет — открывает нужную секцию
# Настроек и ждёт, пока включишь тумблер. Больше скрипт ничего сделать не может.
fda_granted() {
    head -c 1 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" >/dev/null 2>&1 && return 0
    [ -e "$HOME/Library/Safari/Bookmarks.plist" ] \
        && head -c 1 "$HOME/Library/Safari/Bookmarks.plist" >/dev/null 2>&1 && return 0
    [ -e "$HOME/Library/Application Support/Knowledge/knowledgeC.db" ] \
        && head -c 1 "$HOME/Library/Application Support/Knowledge/knowledgeC.db" >/dev/null 2>&1 && return 0
    return 1
}
if fda_granted; then
    ok "$(L 'Полный доступ к диску у Терминала уже есть — защищённые папки (Safari и др.) доступны.' 'Terminal already has Full Disk Access — protected folders (Safari etc.) are reachable.')"
else
    warn "$(L 'У Терминала НЕТ «Полного доступа к диску» — без него macOS не даст перенести Safari и часть данных на диск.' 'Terminal lacks Full Disk Access — without it macOS will not let me move Safari and some data to the disk.')"
    echo "   $(L 'Открываю Настройки — включи Терминалу тумблер и возвращайся сюда:' 'Opening Settings — enable the switch for Terminal and come back here:')"
    echo "   Настройки -> Конфиденциальность и безопасность -> Полный доступ к диску -> Терминал -> ВКЛ"
    echo "   Settings -> Privacy & Security -> Full Disk Access -> Terminal -> ON"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null
    echo "   $(L 'Жду, пока включишь (до 3 минут; я сам замечу и поеду дальше)...' 'Waiting for you to enable it (up to 3 minutes; I will notice and continue)...')"
    FDA_WAIT=0
    SPIN_N=0
    while ! fda_granted && [ $FDA_WAIT -lt 90 ]; do
        sleep 2
        FDA_WAIT=$((FDA_WAIT + 1))
        spin "$(L 'жду Полный доступ к диску' 'waiting for Full Disk Access') — $((FDA_WAIT * 2)) $(L 'сек' 'sec')"
    done
    spin_end
    if fda_granted; then
        ok "$(L 'Полный доступ к диску включен — продолжаю.' 'Full Disk Access is on — continuing.')"
    else
        warn "$(L 'Не дождался. Safari перенести НЕ СМОГУ, остальное продолжаю (в конце будет ручной пункт).' 'Did not get it. Safari CANNOT be moved; continuing with the rest (a manual item will be at the end).')"
        FDA_MISSING=1
    fi
fi
echo ""

# ВОТ ЧТО ГАСИЛО ЭКРАН И «ПЕРЕЗАГРУЖАЛО» ПОСРЕДИ РАБОТЫ (пока ждёшь Enter
# или идёт скачивание, а ты Mac не трогаешь):
# 1) АВТОВЫХОД (AutoLogOutDelay) — раньше включался в Фазе 2, и через 30 мин
#    бездействия macOS РАЗЛОГИНИВАЛА: экран гас, скрипт убивался, выкидывало на
#    экран входа — выглядит как перезагрузка. caffeinate от этого НЕ спасает.
# 2) ЗАСТАВКА + «пароль сразу» — заставка стартует по своему таймеру бездействия
#    (caffeinate её тоже не держит), экран гаснет и требует пароль.
# Поэтому НА ВРЕМЯ РАБОТЫ скрипта убираем оба, а твои выборы применим В КОНЦЕ.
as_root defaults delete /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay 2>/dev/null
SAVED_SS_IDLE=$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null)
defaults -currentHost write com.apple.screensaver idleTime -int 0 2>/dev/null
ok "На время настройки: автовыход и заставка ВЫКЛЮЧЕНЫ — экран не погаснет и из системы не выкинет."

# АвтоУСТАНОВКУ обновлений macOS гасим СРАЗУ и держим выключенной до конца: с
# включенным ключом macOS сама ставит скачанное обновление и САМА перезагружается,
# когда ей вздумается — в том числе посреди настройки, до/во время скачиваний.
# Автопроверку и автоскачивание не трогаем (перезагрузок они не вызывают).
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false 2>/dev/null

echo ""
q 3 "Внешний диск (флешка/SSD) для секретных данных:"
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
q 4 "$(L 'Часовой пояс под VPN (чтобы часы не палили реальное место).' 'Time zone matching your VPN (so the clock does not leak your real location).')"
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
q 5 "$(L 'Через сколько ГАСИТЬ ЭКРАН (сон дисплея).' 'Display sleep timeout.')"
echo "   1 — 1 $(L 'мин' 'min')   2 — 2 $(L 'мин' 'min')   3 — 5 $(L 'мин' 'min') ($(L 'по умолчанию' 'default'))"
echo "   4 — 10 $(L 'мин' 'min')  5 — 15 $(L 'мин' 'min')  6 — 30 $(L 'мин' 'min')  7 — $(L 'никогда' 'never')"
read -r -p "   $(L 'Выбор' 'Choice') [3]: " DS_CH
case "${DS_CH:-3}" in
    1) DISPLAY_SLEEP=1 ;; 2) DISPLAY_SLEEP=2 ;; 3) DISPLAY_SLEEP=5 ;;
    4) DISPLAY_SLEEP=10 ;; 5) DISPLAY_SLEEP=15 ;; 6) DISPLAY_SLEEP=30 ;; 7) DISPLAY_SLEEP=0 ;;
    *) warn "$(L 'Непонятный ответ — беру 5 минут.' 'Unknown answer — using 5 minutes.')"; DISPLAY_SLEEP=5 ;;
esac

echo ""
q 6 "$(L 'Через сколько АВТОВЫХОД из системы (бездействие).' 'Auto logout after idle.')"
echo "   1 — 5 $(L 'мин' 'min')   2 — 10 $(L 'мин' 'min')  3 — 15 $(L 'мин' 'min')"
echo "   4 — 30 $(L 'мин' 'min') ($(L 'по умолчанию' 'default'))  5 — 60 $(L 'мин' 'min')  6 — $(L 'выключить' 'off')"
read -r -p "   $(L 'Выбор' 'Choice') [4]: " AL_CH
case "${AL_CH:-4}" in
    1) AUTOLOGOUT_MIN=5 ;; 2) AUTOLOGOUT_MIN=10 ;; 3) AUTOLOGOUT_MIN=15 ;;
    4) AUTOLOGOUT_MIN=30 ;; 5) AUTOLOGOUT_MIN=60 ;; 6) AUTOLOGOUT_MIN=0 ;;
    *) warn "$(L 'Непонятный ответ — беру 30 минут.' 'Unknown answer — using 30 minutes.')"; AUTOLOGOUT_MIN=30 ;;
esac

echo ""
q 7 "$(L 'Раскладки клавиатуры: английская + русская.' 'Keyboard layouts: English + Russian.')"
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
q 8 "$(L 'Дополнительные программы (по желанию).' 'Optional extra apps.')"
echo "   $(L 'Их данные тоже уедут на зашифрованный диск (симлинками).' 'Their data also goes to the encrypted disk (via symlinks).')"
# Про то, что уже установлено (проверено выше, до вопросов) — не спрашиваем.
if [ "$MM_INSTALLED" = "да" ]; then
    INSTALL_MM=да
    ok "MailMate $(L 'уже установлен — не спрашиваю.' 'already installed — not asking.')"
else
    read -r -p "   $(L 'Ставить MailMate (почтовый клиент)? (да/нет) [нет]' 'Install MailMate (email client)? (yes/no) [no]'): " INSTALL_MM
    INSTALL_MM=$(yn "${INSTALL_MM:-нет}")
fi
if [ "$QTOX_INSTALLED" = "да" ]; then
    INSTALL_QTOX=да
    ok "qTox $(L 'уже установлен — не спрашиваю.' 'already installed — not asking.')"
else
    read -r -p "   $(L 'Ставить qTox (мессенджер Tox)? (да/нет) [нет]' 'Install qTox (Tox messenger)? (yes/no) [no]'): " INSTALL_QTOX
    INSTALL_QTOX=$(yn "${INSTALL_QTOX:-нет}")
fi
if [ "$EXCEL_INSTALLED" = "да" ]; then
    INSTALL_EXCEL=да
    ok "Microsoft Excel $(L 'уже установлен — не спрашиваю.' 'already installed — not asking.')"
else
    read -r -p "   $(L 'Ставить Microsoft Excel? (да/нет) [да]' 'Install Microsoft Excel? (yes/no) [yes]'): " INSTALL_EXCEL
    INSTALL_EXCEL=$(yn "${INSTALL_EXCEL:-да}")
fi

echo ""
q 9 "$(L 'Что делать с Wi-Fi (второй канал утечки после Bluetooth).' 'What to do with Wi-Fi (a leak channel like Bluetooth).')"
echo "   1) $(L 'удалить службу Wi-Fi НАВСЕГДА — только кабель (рекомендуется)' 'remove the Wi-Fi service FOREVER — cable only (recommended)')"
echo "   2) $(L 'только выключить радиомодуль (службу оставить, легко вернуть)' 'just power the radio off (keep the service, easy to bring back)')"
echo "   3) $(L 'не трогать Wi-Fi' 'leave Wi-Fi as is')"
read -r -p "   $(L 'Выбор' 'Choice') [1]: " WIFI_MODE
WIFI_MODE=${WIFI_MODE:-1}

echo ""
q 10 "$(L 'Данные приложений (Telegram, Sphere, Safari и т.д.) на зашифрованный диск.' 'App data (Telegram, Sphere, Safari, etc.) onto the encrypted disk.')"
echo "    $(L 'ДА  — подключать всё найденное симлинками САМ, не спрашивая по каждому (рекомендуется).' 'YES — link everything found automatically, without asking about each one (recommended).')"
echo "    $(L 'НЕТ — спрашивать по каждому приложению отдельно.' 'NO  — ask about each app separately.')"
read -r -p "   $(L '(да/нет) [да]' '(yes/no) [yes]'): " AUTO_LINK
AUTO_LINK=$(yn "${AUTO_LINK:-да}")

echo ""
ok "$(L 'Все вопросы заданы. Дальше скрипт работает сам (пару раз попросит вставить диск).' 'All questions done. The script runs on its own now (it will ask to insert the disk a couple of times).')"
hr

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

# Выключение дисплея (выбрано в вопросе 5; 0 = никогда).
# ВАЖНО: сам таймер гашения экрана применяем В КОНЦЕ скрипта. Если поставить его
# сейчас, то на долгих скачиваниях/обновлениях экран погаснет прямо во время
# настройки и будет казаться, что Mac выключился. Пока идёт работа — экран держит
# включённым caffeinate (запущен в начале), а твой выбор применится в самом финале.
DISPLAY_SLEEP=${DISPLAY_SLEEP:-5}
if [ "$DISPLAY_SLEEP" = "0" ]; then
    ok "$(L 'Дисплей не будет гаснуть по таймеру (применю в конце).' 'Display will never sleep (applied at the end).')"
else
    ok "$(L 'Таймер гашения экрана' 'Display sleep timer') $DISPLAY_SLEEP $(L 'мин — применю в конце (сейчас экран держу включённым).' 'min — applied at the end (screen kept awake for now).')"
fi

# Автовыход из системы (выбрано в вопросе 6; 0 = выключить).
# ВАЖНО: применяем В КОНЦЕ скрипта, а не сейчас. Если включить сейчас, то через
# 30 минут бездействия (пока качается/шифруется или ты отошёл от «нажми Enter»)
# macOS РАЗЛОГИНИТ прямо посреди настройки — экран гаснет, скрипт умирает,
# и это выглядит как перезагрузка.
AUTOLOGOUT_MIN=${AUTOLOGOUT_MIN:-30}
if [ "$AUTOLOGOUT_MIN" = "0" ]; then
    ok "$(L 'Автовыход из системы будет выключен.' 'Auto logout will be off.')"
else
    ok "$(L 'Автовыход через' 'Auto logout after') $AUTOLOGOUT_MIN $(L 'мин — применю в самом конце (сейчас он бы выкинул из системы посреди настройки).' 'min — applied at the very end (right now it would log you out mid-setup).')"
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
# Запись в plist сама по себе не «оживает»: cfprefsd держит домен HIToolbox в
# памяти, поэтому в файле раскладка есть, а в меню строки меню — нет. Сбрасываем
# кэш и просим систему перечитать источники ввода, иначе проверка врет «зеленым».
killall cfprefsd 2>/dev/null
sleep 1
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null
if defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -q "Russian"; then
    ok "$(L 'Русская раскладка записана. ПРОВЕРЬ флажок раскладки в строке меню — если её там нет, добавь через + (открою настройки).' 'Russian layout written. CHECK the layout flag in the menu bar — if it is missing, add it via + (I will open settings).')"
    KB_ADDED=1
else
    warn "$(L 'macOS не принял раскладку из терминала. Открою настройки — добавь русскую сам, я подожду.' 'macOS refused the layout from the terminal. Opening settings — add Russian yourself, I will wait.')"
    open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" 2>/dev/null
    KB_TRY=0
    SPIN_N=0
    while [ $KB_TRY -lt 40 ]; do
        sleep 3
        KB_TRY=$((KB_TRY + 1))
        if defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -q "Russian"; then
            KB_ADDED=1; break
        fi
        spin "$(L 'жду русскую раскладку' 'waiting for the Russian layout') — $((KB_TRY * 3)) сек"
    done
    spin_end
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
# На macOS 15 (Sequoia) socketfilterfw умеет ответить «managed only by MDM»
# и НЕ включить ничего, а старый скрипт все равно печатал ✓. Поэтому состояние
# ПЕРЕЧИТЫВАЕТСЯ после установки; если macOS не дала — пробую запасной ключ,
# потом открываю Настройки и жду тумблер руками (как с Bluetooth).
FW="/usr/libexec/ApplicationFirewall/socketfilterfw"
# состояния: on / off / unknown. Sequoia/Tahoe может ответить «managed only by
# MDM» или пустотой вместо «enabled/disabled» — это НЕ «выключен», это «не смог
# прочитать». Раньше такой ответ считался «выключен», и скрипт зря ждал тумблер
# по 3 минуты, хотя в Настройках всё уже было включено.
fw_sig() {
    local out
    out=$("$FW" "$1" 2>/dev/null)
    case "$out" in *"enabled"*|*"State = 1"*) echo "on" ;;
                   *"disabled"*|*"State = 0"*) echo "off" ;;
                   *) echo "unknown" ;; esac
}
# по чтению sudo не нужен; но если без него пусто — пробую с ним
fw_probe() { local s; s=$(fw_sig "$1"); [ "$s" = "unknown" ] && s=$(as_root "$FW" "$1" 2>/dev/null | awk 'tolower($0) ~ /enabled/ {print "on"; exit} tolower($0) ~ /disabled/ {print "off"; exit}'); echo "${s:-unknown}"; }
fw_global()  { fw_probe --getglobalstate; }
fw_stealth() { fw_probe --getstealthmode; }
if [ "$(fw_global)" = "on" ] && [ "$(fw_stealth)" = "on" ]; then
    # уже включено и до этого ничего не трогаем
    ok "$(L 'Брандмауэр: уже включен + режим невидимости (проверил ДО любых изменений).' 'Firewall: already on + stealth mode (checked BEFORE changing anything).')"
    dim "$(L 'Блок ВСЕХ входящих выключен — он ломает VeraCrypt/FUSE-T.' 'Block-all incoming is off — it breaks VeraCrypt/FUSE-T.')"
else
as_root "$FW" --setglobalstate on >/dev/null 2>&1
as_root "$FW" --setblockall off >/dev/null 2>&1
as_root "$FW" --setstealthmode on >/dev/null 2>&1
if [ "$(fw_global)" != "on" ]; then
    # запасной способ: старый ключ, который Sequoia иногда всё же уважает
    as_root defaults write /Library/Preferences/com.apple.alf globalstate -int 1 2>/dev/null
    sleep 2
fi
if [ "$(fw_global)" = "on" ] && [ "$(fw_stealth)" != "on" ]; then
    as_root "$FW" --setstealthmode on >/dev/null 2>&1
    sleep 1
fi
FW_G=$(fw_global); FW_S=$(fw_stealth)
if [ "$FW_G" = "on" ] && [ "$FW_S" = "on" ]; then
    ok "$(L 'Брандмауэр: включен + режим невидимости (проверил, перечитав состояние).' 'Firewall: on + stealth mode (verified by re-reading the state).')"
    dim "$(L 'Блок ВСЕХ входящих выключен — он ломает VeraCrypt/FUSE-T.' 'Block-all incoming is off — it breaks VeraCrypt/FUSE-T.')"
elif [ "$FW_G" = "unknown" ] || [ "$FW_S" = "unknown" ]; then
    # терминал НЕ МОЖЕТ прочитать состояние (MDM-ответ/пусто): ждать тумблер
    # бессмысленно — проверка никогда не сработает. Спрашиваю у человека.
    warn "$(L 'macOS не дает прочитать состояние брандмауэра из терминала.' 'macOS will not let the terminal read the firewall state.')"
    echo ""
    read -r -p "   $(L 'Открой Настройки -> Сеть -> Брандмауэр: тумблер включен И в «Параметры» стоит «Включить режим невидимости»? (да/нет)' 'Open Settings -> Network -> Firewall: is the toggle ON and «Enable stealth mode» ON in Options? (yes/no)'): " FW_EYES
    if [ "$(yn "${FW_EYES:-да}")" = "да" ]; then
        ok "$(L 'Брандмауэр + режим невидимости: подтверждаешь глазами в Настройках — принято.' 'Firewall + stealth: confirmed by your eyes in Settings — accepted.')"
    else
        info "$(L 'Открываю Настройки -> Сеть -> Брандмауэр — включи тумблер, затем Параметры -> «Включить режим невидимости».' 'Opening Settings -> Network -> Firewall — flip it on, then Options -> «Enable stealth mode».')"
        open "x-apple.systempreferences:com.apple.Network-Settings" 2>/dev/null \
            || open "x-apple.systempreferences:com.apple.preference.network" 2>/dev/null \
            || open -b com.apple.systempreferences 2>/dev/null
        err "$(L 'Брандмауэр/невидимость выключены — добавил в список доделок.' 'Firewall/stealth are off — added to the manual list.')"
        FW_MANUAL=1
    fi
else
    info "$(L 'Открываю Настройки -> Сеть -> Брандмауэр — включи тумблер, затем Параметры -> «Включить режим невидимости». Я подожду и проверю сам.' 'Opening Settings -> Network -> Firewall — flip it on, then Options -> «Enable stealth mode». I will wait and verify.')"
    open "x-apple.systempreferences:com.apple.Network-Settings" 2>/dev/null \
        || open "x-apple.systempreferences:com.apple.preference.network" 2>/dev/null \
        || open -b com.apple.systempreferences 2>/dev/null
    FW_WAIT=0
    SPIN_N=0
    while { [ "$(fw_global)" != "on" ] || [ "$(fw_stealth)" != "on" ]; } && [ $FW_WAIT -lt 60 ]; do
        sleep 3
        FW_WAIT=$((FW_WAIT + 1))
        spin "$(L 'жду брандмауэр и режим невидимости' 'waiting for the firewall and stealth mode') — $((FW_WAIT * 3)) $(L 'сек' 'sec')"
    done
    spin_end
    if [ "$(fw_global)" = "on" ] && [ "$(fw_stealth)" = "on" ]; then
        ok "$(L 'Брандмауэр + режим невидимости включены — подтверждаю перечитыванием.' 'Firewall + stealth mode enabled — confirmed by re-reading.')"
    else
        err "$(L 'Брандмауэр/невидимость так и не включились — добавил в список доделок.' 'Firewall/stealth still not enabled — added to the manual list.')"
        FW_MANUAL=1
    fi
fi
fi

# Общий экран / Удалённое управление (ARD) / Удалённый вход (SSH) — глушим.
# Это прямые каналы удалённого доступа к Mac.
# ПОЧЕМУ ЗДЕСЬ Mac «тупо уходил в перезагрузку» ещё ДО скачиваний: прежний
# вариант выгружал демоны через launchctl bootout, а на свежих macOS bootout
# демона Общего экрана валит GUI-сессию (WindowServer): экран гаснет, всё
# закрывается и перезапускается — выглядит ровно как перезагрузка. Плюс, если
# этот Mac сейчас смотрят ЧЕРЕЗ Общий экран/ARD, kill/bootout демона обрывает
# то самое соединение посреди настройки. Поэтому:
#   - launchctl disable (выключает службу насовсем) — безопасно, делаем всегда;
#   - демоны глушим мягко (pkill/kickstart) и ТОЛЬКО когда нет активного сеанса;
#   - launchctl bootout для экрана/ARD — ЗАПРЕЩЁН, он и «перезагружал» Mac.
SS_SESSION=0
pgrep -x ScreensharingAgent >/dev/null 2>&1 && SS_SESSION=1
as_root launchctl disable "system/com.apple.screensharing" 2>/dev/null
as_root launchctl disable "system/com.apple.RemoteDesktop.agent" 2>/dev/null
# SSH: сначала смотрим состояние. На чистой macOS он УЖЕ выключен из коробки —
# тогда systemsetup не дёргаем вовсе (его вызов дважды переспрашивает
# по-английски «точно выключить?» и сыплет служебный текст прямо в вывод).
# Если включен — гасим молча («yes» уходит в stdin) и проверяем результат.
if as_root systemsetup -getremotelogin 2>/dev/null | grep -qi "off"; then
    ok "$(L 'Удалённый вход (SSH): уже был выключен.' 'Remote Login (SSH): already off.')"
else
    printf '%s\nyes\n' "$ADMIN_PASS" | sudo -S systemsetup -setremotelogin off >/dev/null 2>&1
    if as_root systemsetup -getremotelogin 2>/dev/null | grep -qi "off"; then
        ok "$(L 'Удалённый вход (SSH) выключен.' 'Remote Login (SSH) turned off.')"
    else
        warn "$(L 'Удалённый вход (SSH) не выключился из терминала — открою Общий доступ, выключи сам.' 'Remote Login (SSH) did not go off — opening Sharing, turn it off yourself.')"
        open "x-apple.systempreferences:com.apple.Sharing-Settings.extension" 2>/dev/null
        SS_MANUAL=1
    fi
fi
if [ "$SS_SESSION" = "1" ]; then
    warn "$(L 'Сейчас идёт АКТИВНЫЙ сеанс Общего экрана/удалённого управления (ты, возможно, смотришь через него). Соединение НЕ рву: службы уже выключены насовсем и полностью отключатся при перезагрузке в конце.' 'A Screen Sharing / remote control session is ACTIVE (you may be watching through it). NOT dropping it: the services are disabled for good and fully turn off at the final reboot.')"
else
    # kickstart печатает «Starting... / Removed preference... / Done.» — глушим,
    # своё сообщение об успехе печатаем сами.
    as_root /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop >/dev/null 2>&1
    as_root pkill -x screensharingd 2>/dev/null
    sleep 1
    if pgrep -x screensharingd >/dev/null 2>&1; then
        warn "$(L 'Общий экран не выключился из терминала — открою Общий доступ, сними галки сам.' 'Screen Sharing did not go off from the terminal — opening Sharing, uncheck it yourself.')"
        open "x-apple.systempreferences:com.apple.Sharing-Settings.extension" 2>/dev/null
        SS_MANUAL=1
    else
        ok "$(L 'Общий экран и удалённое управление (ARD) выключены (насовсем).' 'Screen Sharing and Remote Management (ARD) are off (for good).')"
    fi
fi

# AirDrop и Handoff выключить
defaults write com.apple.NetworkBrowser DisableAirDrop -bool YES 2>/dev/null
defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool no 2>/dev/null
defaults -currentHost write com.apple.coreservices.useractivityd ActivityReceivingAllowed -bool no 2>/dev/null
ok "AirDrop и Handoff выключены."

# Recents («Недавние») — глушим ВЕЗДЕ. Речь о секции недавних программ в Dock,
# о меню « > Недавние объекты» и об истории недавно открытых файлов: всё это
# показывает, с чем ты недавно работал, даже когда секретный диск отключен.
# ВАЖНО (из-за этого раньше «недавние» ОСТАВАЛИСЬ в меню): сами списки лежат
# НЕ в настройках, а в .sfl2-файлах sharedfilelist — пока их не стереть, меню
# так и остаётся заполненным, сколько ни выключай лимиты.
defaults write com.apple.dock show-recents -bool false 2>/dev/null
defaults write NSGlobalDomain NSRecentDocumentsLimit -int 0 2>/dev/null
defaults write NSGlobalDomain NSRecentApplicationsLimit -int 0 2>/dev/null
defaults write NSGlobalDomain NSRecentServerAddressesLimit -int 0 2>/dev/null
defaults delete com.apple.recentitems 2>/dev/null
# лимит «Недавние объекты: Нет» — пишем и plist-ключами, как это делает сама macOS
defaults write com.apple.recentitems RecentApplications -dict MaxAmount 0 2>/dev/null
defaults write com.apple.recentitems RecentDocuments -dict MaxAmount 0 2>/dev/null
defaults write com.apple.recentitems RecentServers -dict MaxAmount 0 2>/dev/null
# сами списки: атомарно уводим ВСЮ папку в сторону и гасим демона ПОСЛЕ переименования.
# ВАЖНО: раньше здесь был killall + rm отдельных .sfl2 — launchd поднимал демона
# посреди удаления, файл оставался обрезанным, демон уходил в цикл крашей и
# вешал меню системы (SystemUIServer). Полное переименование папки гонки не дает:
# демон при следующем старте создает папку пустой.
SFL_DIR="$HOME/Library/Application Support/com.apple.sharedfilelist"
if [ -d "$SFL_DIR" ]; then
    rm -rf "$SFL_DIR.old" 2>/dev/null
    mv "$SFL_DIR" "$SFL_DIR.old" 2>/dev/null
fi
killall sharedfilelistd 2>/dev/null
sleep 1
killall Dock 2>/dev/null
killall Finder 2>/dev/null
killall SystemUIServer 2>/dev/null
# честная проверка: папки нет / пустая — списков не осталось
if [ ! -d "$SFL_DIR" ] || [ -z "$(ls -A "$SFL_DIR" 2>/dev/null)" ]; then
    ok "$(L 'Recents выключен ВЕЗДЕ: секция в Dock скрыта, списки «Недавние объекты» стерты (папка уведена целиком), новые записи не собираются (лимиты = 0).' 'Recents is off everywhere: Dock section hidden, Recent Items wiped (folder moved aside whole), no new entries collected (limits = 0).')"
else
    warn "$(L 'Списки «Недавние объекты» стерты не до конца — перезагрузи Mac (перезагрузка есть в конце скрипта), меню очистится полностью.' 'Recent Items lists were not fully wiped — reboot the Mac (the script reboots at the end) to fully clear the menu.')"
    REC_MANUAL=1
fi

# Геолокация выключить
as_root defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool false 2>/dev/null
ok "Службы геолокации выключены."

# Аналитика («Поделиться аналитикой с Apple») выключить. На свежих macOS
# настройку читают из домена com.apple.SubmitDiagInfo (ключ AutoSubmit), а не из
# старого DiagnosticMessagesHistory.plist — пишем оба, плюс запрет через
# applicationaccess, чтобы галка была снята и не вернулась.
as_root defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit -bool false 2>/dev/null
as_root defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmitVersion -int 4 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SubmitDiagInfo AutoSubmit -bool false 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SubmitDiagInfo AutoSubmitVersion -int 4 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.applicationaccess allowDiagnosticSubmission -bool false 2>/dev/null
ok "Аналитика Apple и отправка отчетов выключены (com.apple.SubmitDiagInfo)."

# Siri выключить
defaults write com.apple.assistant.support "Assistant Enabled" -bool false 2>/dev/null
ok "Siri выключена."

# Gatekeeper: в новых macOS включен всегда и командой не управляется — ничего не делаем
ok "Установка приложений: App Store + известные разработчики (стандарт macOS, менять не нужно)."

# Wi-Fi: что делать — выбрал человек в вопросе 9 (WIFI_MODE: 1 удалить службу,
# 2 только выключить радио, 3 не трогать).
WIFI_DEV=$(networksetup -listallhardwareports 2>/dev/null | awk '/Hardware Port: Wi-Fi/{getline; print $2}')
if [ "$WIFI_MODE" = "3" ]; then
    ok "Wi-Fi оставлен как есть (по твоему выбору)."
elif [ -n "$WIFI_DEV" ]; then
    CUR_IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    if [ "$CUR_IF" = "$WIFI_DEV" ]; then
        warn "Интернет сейчас идет через Wi-Fi! Воткни кабель (Ethernet или Raspberry Pi), иначе скачивание оборвется."
        pause
        CUR_IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    fi
    if [ "$CUR_IF" != "$WIFI_DEV" ]; then
        networksetup -setairportpower "$WIFI_DEV" off &>/dev/null
        if [ "$WIFI_MODE" = "2" ]; then
            ok "Wi-Fi: радиомодуль выключен, служба оставлена. Вернуть: Настройки -> Сеть -> Wi-Fi -> Включить."
        else
            WIFI_SVC=$(networksetup -listnetworkserviceorder 2>/dev/null | grep -B1 "Device: $WIFI_DEV)" | head -1 | sed 's/^([^)]*) //')
            [ -z "$WIFI_SVC" ] && WIFI_SVC="Wi-Fi"
            as_root networksetup -removenetworkservice "$WIFI_SVC" &>/dev/null
            if networksetup -listallnetworkservices 2>/dev/null | grep -qx "\*\{0,1\}$WIFI_SVC"; then
                warn "Wi-Fi выключен, но удалить службу «$WIFI_SVC» не вышло — удали руками: Настройки -> Сеть -> Wi-Fi -> ... -> Удалить службу."
            else
                ok "Wi-Fi выключен и удален из сетевых служб НАВСЕГДА — только кабель. Обратно: Настройки -> Сеть -> ... -> Добавить службу."
            fi
        fi
    else
        err "Кабель так и не появился — Wi-Fi НЕ трогаю (иначе упадут скачивания). Воткни кабель и перезапусти скрипт."
    fi
fi

# Часовой пояс под страну VPN. Раньше ✓ печатался по коду возврата
# systemsetup, а в системе пояс мог остаться прежним — теперь ПРОВЕРЯЮ факт:
# читаю /etc/localtime и systemsetup, при промахе ставлю прямым симлинком.
if [ -n "$VPN_TZ" ]; then
    # Автоустановку времени по геолокации выключаем, иначе macOS вернет реальный пояс
    as_root defaults write /Library/Preferences/com.apple.timezone.auto Active -bool false 2>/dev/null
    as_root defaults write /Library/Preferences/com.apple.timezone.auto Active -int 0 2>/dev/null
    as_root systemsetup -settimezone "$VPN_TZ" &>/dev/null
    sleep 1
    tz_now() { readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||'; }
    if [ "$(tz_now)" != "$VPN_TZ" ]; then
        # запасной способ: прямой симлинк /etc/localtime (работает, даже когда
        # systemsetup «отрабатывает», но пояс в системе не меняется)
        as_root ln -sf "/usr/share/zoneinfo/$VPN_TZ" /etc/localtime 2>/dev/null
        sleep 1
    fi
    if [ "$(tz_now)" = "$VPN_TZ" ] || [ "$(as_root systemsetup -gettimezone 2>/dev/null | awk -F': ' '{print $2}')" = "$VPN_TZ" ]; then
        ok "$(L 'Часовой пояс' 'Time zone') $VPN_TZ — $(L 'проверил в системе по /etc/localtime: применился. Автоопределение по геолокации отключено (часы не паливают место).' 'verified via /etc/localtime: applied. Auto (location-based) time zone is off.')"
    else
        warn "$(L 'Часовой пояс НЕ применился:' 'Time zone did NOT apply:') $(tz_now) $(L 'вместо' 'instead of') $VPN_TZ. $(L 'Поставь руками: Настройки -> Основные -> Дата и время, зона' 'Set it manually: Settings -> General -> Date & Time, zone') $VPN_TZ."
        TZ_MANUAL=1
    fi
fi

# Bluetooth: глушим (второй канал утечки после Wi-Fi).
# ПРАВДА (проверено на свежих macOS): «defaults + перезапуск bluetoothd» радио
# НЕ выключает, а старая проверка через system_profiler в этот момент показывала
# «выключено» — отсюда ✓ при реально включенном Bluetooth. Единственный
# рабочий способ — утилита blueutil: она выключает BT-чип напрямую. Homebrew в
# скрипте нет, поэтому готовый бинарник качается с GitHub во временную папку
# /tmp и после перезагрузки исчезает сам.
BT_BIN=""
bt_get_util() {
    [ -n "$BT_BIN" ] && return 0
    command -v blueutil >/dev/null 2>&1 && { BT_BIN="$(command -v blueutil)"; return 0; }
    local url z d
    url=$(curl -sL --max-time 15 "https://api.github.com/repos/toy/blueutil/releases/latest" 2>/dev/null \
        | tr ',' '\n' | grep -o 'https://[^"]*\.zip' | head -1)
    [ -z "$url" ] && return 1
    z="/tmp/blueutil_$$.zip"; d="/tmp/blueutil_$$"
    info "$(L 'Скачиваю утилиту выключения Bluetooth (blueutil)...' 'Downloading the Bluetooth-off utility (blueutil)...')"
    curl -sL --fail --max-time 90 -o "$z" "$url" 2>/dev/null || return 1
    mkdir -p "$d" && ditto -x -k "$z" "$d" 2>/dev/null
    BT_BIN=$(find "$d" -type f -name blueutil 2>/dev/null | head -1)
    [ -z "$BT_BIN" ] && return 1
    chmod +x "$BT_BIN" 2>/dev/null
    "$BT_BIN" --version >/dev/null 2>&1 || { BT_BIN=""; return 1; }
    return 0
}

# Истинное состояние радио: сначала blueutil (читает сам чип), иначе system_profiler.
bt_is_on() {
    if [ -n "$BT_BIN" ]; then
        [ "$("$BT_BIN" --power 2>/dev/null)" = "1" ] && return 0
        return 1
    fi
    local s
    s=$(system_profiler SPBluetoothDataType 2>/dev/null | grep -i -m1 "State:")
    case "$s" in
        *[Oo]ff*) return 1 ;;
        *[Oo]n*)  return 0 ;;
    esac
    # состояния не поняли — считаем ВКЛЮЧЕННЫМ (худший случай)
    return 0
}

# ПОЧЕМУ Bluetooth «сам включился», хотя мы его выключали:
# если к Mac подключены беспроводные устройства (Magic Keyboard/Mouse/Trackpad),
# macOS НЕ даёт держать Bluetooth выключенным — иначе ты останешься без клавиатуры
# и мыши — и включает его обратно при перезагрузке. Плюс есть автопоиск клавы/мыши
# (BluetoothAutoSeek*), который тоже поднимает радио. Поэтому глушим автопоиск и,
# если это только Bluetooth-устройства ввода, предупреждаем — их надо заменить на
# проводные, иначе выключить BT насовсем нельзя.
bt_off() {
    if [ -n "$BT_BIN" ]; then
        # blueutil под sudo запускать НЕЛЬЗЯ (сам запрещает) — только от пользователя
        "$BT_BIN" --power 0 >/dev/null 2>&1
        sleep 2
        return 0
    fi
    as_root defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 0 2>/dev/null
    as_root defaults write /Library/Preferences/com.apple.Bluetooth.plist ControllerPowerState -int 0 2>/dev/null
    # Автопоиск беспроводных клавы/мыши — из-за него радио включается само
    as_root defaults write /Library/Preferences/com.apple.Bluetooth BluetoothAutoSeekKeyboard -int 0 2>/dev/null
    as_root defaults write /Library/Preferences/com.apple.Bluetooth BluetoothAutoSeekPointingDevice -int 0 2>/dev/null
    as_root launchctl kickstart -k system/com.apple.bluetoothd 2>/dev/null \
        || as_root killall -9 bluetoothd 2>/dev/null
    sleep 3
    return 0
}

# Есть ли подключённые Bluetooth-устройства (из-за них система не отпускает радио)
BT_CONNECTED=$(system_profiler SPBluetoothDataType 2>/dev/null | grep -c -i "Connected: Yes")
if [ "${BT_CONNECTED:-0}" -gt 0 ] 2>/dev/null; then
    warn "$(L 'К Mac подключены Bluetooth-устройства (клавиатура/мышь/наушники). Пока они подключены, macOS будет сам включать Bluetooth обратно. Для полной изоляции используй ПРОВОДНЫЕ клавиатуру и мышь.' 'Bluetooth devices are connected (keyboard/mouse/headphones). While they are connected macOS will keep turning Bluetooth back on. For full isolation use a WIRED keyboard and mouse.')"
fi

info "$(L 'Выключаю Bluetooth...' 'Turning Bluetooth off...')"
bt_get_util || dim "$(L 'blueutil скачать не удалось — пробую штатный способ.' 'Could not fetch blueutil — trying the built-in way.')"
bt_off
if bt_is_on; then
    bt_off
fi
if bt_is_on; then
    bt_off
fi
sleep 2
if bt_is_on; then
    warn "$(L 'Выключить из терминала не вышло (macOS так умеет).' 'Could not turn it off from the terminal (macOS does this).')"
    info "$(L 'Открываю настройки Bluetooth — переключи тумблер в ВЫКЛ, я подожду и проверю сам.' 'Opening Bluetooth settings — flip the switch OFF, I will wait and verify.')"
    open "x-apple.systempreferences:com.apple.BluetoothSettings" 2>/dev/null || open -b com.apple.systempreferences 2>/dev/null
    BT_TRY=0
    SPIN_N=0
    while bt_is_on && [ $BT_TRY -lt 60 ]; do
        sleep 3
        BT_TRY=$((BT_TRY + 1))
        spin "$(L 'жду, Bluetooth все еще включен' 'waiting, Bluetooth is still on') — $((BT_TRY * 3)) $(L 'сек' 'sec')"
    done
    spin_end
    if bt_is_on; then
        err "$(L 'Bluetooth так и остался ВКЛЮЧЕН — выключи его вручную (добавил в список доделок).' 'Bluetooth is still ON — turn it off manually (added to the manual list).')"
        BT_MANUAL=1
    else
        ok "$(L 'Bluetooth выключен — подтверждаю по состоянию самого чипа.' 'Bluetooth is off — confirmed from the chip state itself.')"
    fi
else
    # Перепроверка через 5 сек: macOS умеет тут же включить радио обратно
    # (беспроводная клавиатура/мышь/наушники рядом) — не даю напечатать ложное ✓
    sleep 5
    if bt_is_on; then
        warn "$(L 'Bluetooth выключился, но macOS включила его ОБРАТНО в течение 5 секунд — рядом беспроводная клавиатура/мышь (или AirPods в ушах). macOS делает так всегда, пока устройство ввода беспроводное: используй ПРОВОДНЫЕ клавиатуру и мышь.' 'Bluetooth went off but macOS turned it right back ON within 5 seconds — a wireless keyboard/mouse (or AirPods) is nearby. macOS always does this while the input device is wireless: use a WIRED keyboard and mouse.')"
        BT_MANUAL=1
    else
        ok "$(L 'Bluetooth выключен — подтверждаю по состоянию самого чипа.' 'Bluetooth is off — confirmed from the chip state itself.')"
    fi
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
    warn "$(L 'Интернета НЕТ. Подключи кабель (Wi-Fi отключен) — жду...' 'No internet. Plug in the cable (Wi-Fi is off) — waiting...')"
    local n=0
    SPIN_N=0
    while ! net_ok; do
        sleep 1
        n=$((n + 1))
        spin "$(L 'жду интернет' 'waiting for internet') — ${n} сек"
    done
    spin_end
    ok "$(L 'Интернет появился — продолжаю.' 'Internet is up — continuing.')"
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
        "Excel")        [ -d "/Applications/Microsoft Excel.app" ] ;;
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
    info "$(L 'Скачиваю' 'Downloading') $appname..."
    curl -L --fail --progress-bar --retry 2 --retry-delay 2 -o "$dmg" "$url"
    if [ ! -f "$dmg" ] || [ ! -s "$dmg" ]; then
        err "$appname $(L 'не скачался. Поставь вручную позже.' 'did not download. Install manually later.')"
        return 1
    fi
    info "$(L 'Устанавливаю' 'Installing') $appname..."
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

# Microsoft Excel (по желанию). Официальный прямой .pkg с CDN Microsoft
# (go.microsoft.com/fwlink/?linkid=525135) — подписан и нотаризован, Gatekeeper
# его пускает. Ставится «пробным»: активируется при входе в аккаунт Microsoft 365.
if [ "$INSTALL_EXCEL" = "да" ]; then
    install_dmg "https://go.microsoft.com/fwlink/?linkid=525135" "Excel" "MicrosoftExcel.pkg"
fi

# Дубли в /Applications («MailMate 2.app», «Telegram копия.app» и т.п.) — удаляем САМИ.
# ОТКУДА они берутся: когда в /Applications уже лежит копия программы (её кто-то
# перетащил вручную или прошлый запуск скрипта её поставил) и она в этот момент
# ЗАПУЩЕНА/занята, Finder и cp не могут перезаписать существующий .app и создают
# рядом «Имя 2.app». Поэтому: сначала гасим запущенную копию, потом сносим лишние,
# оставляя ровно один «Имя.app».
dedupe_app() {
    local base="$1" keep="/Applications/$1.app" d
    while IFS= read -r d; do
        [ "$d" = "$keep" ] && continue
        # Если «чистого» keep нет, а есть дубль — первый дубль делаем основным.
        if [ ! -d "$keep" ]; then
            as_root mv "$d" "$keep" 2>/dev/null && { ok "$(L 'Переименовал дубль в основной:' 'Renamed duplicate to primary:') $keep"; continue; }
        fi
        pkill -f "$d" 2>/dev/null
        as_root rm -rf "$d" 2>/dev/null && ok "$(L 'Удалён дубль:' 'Removed duplicate:') $d"
    done < <(find /Applications -maxdepth 1 \( -iname "$base*.app" \) 2>/dev/null | sort)
}
for A in "MailMate" "Telegram" "VeraCrypt" "qTox" "Sublime Text" "Microsoft Excel"; do dedupe_app "$A"; done
# Общий добор: «* 2.app / *копия*.app» — но ТОЛЬКО если рядом есть базовая копия без
# номера. Иначе снесём легальные приложения, которые сами так называются (например
# «Linken Sphere 2.app» — это НЕ дубль, а название версии 2).
while IFS= read -r d; do
    [ -z "$d" ] && continue
    base=$(echo "$d" | sed -E 's/ [0-9]+\.app$/.app/; s/ ?(копия|copy)[^/]*\.app$/.app/I')
    [ "$base" = "$d" ] && continue
    [ -d "$base" ] || continue   # базовой копии нет — значит это не дубль, не трогаем
    pkill -f "$d" 2>/dev/null
    as_root rm -rf "$d" 2>/dev/null && ok "$(L 'Удалён дубль:' 'Removed duplicate:') $d"
done < <(find /Applications -maxdepth 1 \( -iname "* [0-9].app" -o -iname "*копия*.app" -o -iname "*copy*.app" \) 2>/dev/null)

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
            # TCC-защищённые папки (~/Library/Safari) rm не трогает без Полного
            # доступа к диску — раньше «моё» сообщение о стирании печаталось
            # ВСЕГДА, а ln потом делал вложенный симлинк «Safari/Safari».
            if rm -rf "$src" 2>/dev/null && [ ! -e "$src" ]; then
                ok "$(basename "$src"): старая папка из системы стерта (данные уже на диске)."
            else
                err "$(basename "$src") — macOS не дала стереть папку в системе («Operation not permitted»)."
                dim "$(L 'Симлинк НЕ создаю (иначе он «провалится» внутрь старой папки). Причина: у Терминала нет Полного доступа к диску.' 'NOT creating the symlink (it would nest INSIDE the old folder). Cause: Terminal lacks Full Disk Access.')"
                TCC_BLOCK=1
                return 1
            fi
        fi
        ln -s "$dst" "$src"
        if [ -L "$src" ]; then
            ok "$(basename "$src") — подключен с диска."
        else
            err "$(basename "$src") — симлинк НЕ создан!"
            return 1
        fi
        return 0
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
        if [ "$AUTO_LINK" = "да" ]; then
            dim "$(L 'Подключаю симлинком автоматически (выбрано в начале).' 'Linking automatically (chosen at the start).')"
        else
            read -r -p "   $(L 'Подключить символьной ссылкой (ничего не переношу)? (да/нет) [да]' 'Link it with a symlink (nothing is moved)? (yes/no) [yes]'): " LK
            LK=$(yn "${LK:-да}")
            [ "$LK" != "да" ] && return 1
        fi
        link_to "$src" "$found"
        LINKED_SRC="$LINKED_SRC|$src"
        return 0
    }
    LINKED_SRC=""

    # СНАЧАЛА проверяем симлинки: то, что уже подключено, НЕ ищем по диску заново
    # и НЕ спрашиваем про него — сразу отчитываемся и пропускаем.
    already_linked() {
        [ -L "$1" ] || return 1
        ok "$2 — $(L 'уже подключен симлинком, пропускаю.' 'already linked with a symlink, skipping.')"
        return 0
    }
    echo "$(L 'Ищу данные приложений по ВСЕМУ диску (включая подпапки) — переносить никуда не буду.' 'Scanning the whole disk (all subfolders) — nothing will be moved.')"
    # Чистка после старой версии скрипта: Safari по ошибке линковался в
    # Application Support/Safari (лишний симлинк не туда) — убираю, если есть.
    if [ -L "$HOME/Library/Application Support/Safari" ]; then
        rm -f "$HOME/Library/Application Support/Safari" 2>/dev/null
        dim "$(L 'Убрал лишний симлинк Safari из Application Support (баг старой версии).' 'Removed a stray Safari symlink from Application Support (old-version bug).')"
    fi
    TG_SRC="$(tg_local_dir)/stable"
    if already_linked "$TG_SRC" "Telegram"; then
        :
    elif [ ! -d "$DATA/Telegram/stable" ]; then
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
    already_linked "$HOME/Library/Application Support/Sublime Text" "Sublime Text" || { [ ! -d "$DATA/Sublime Text" ] && { ST_FOUND=$(deep_find "Sublime Text"); [ -n "$ST_FOUND" ] && link_in_place "$ST_FOUND" "$HOME/Library/Application Support/Sublime Text"; }; }
    already_linked "$HOME/Library/Safari" "Safari" || { [ ! -d "$DATA/Safari" ] && { SF_FOUND=$(deep_find "Safari"); [ -n "$SF_FOUND" ] && { osascript -e 'quit app "Safari"' 2>/dev/null; sleep 1; link_in_place "$SF_FOUND" "$HOME/Library/Safari"; }; }; }
    already_linked "$HOME/Library/Application Support/app.ls" "Linken Sphere" || { [ ! -d "$DATA/app.ls" ] && { LS_FOUND=$(deep_find "app.ls"); [ -n "$LS_FOUND" ] && link_in_place "$LS_FOUND" "$HOME/Library/Application Support/app.ls"; }; }
    already_linked "$HOME/Library/Application Support/MailMate" "MailMate" || { [ ! -d "$DATA/MailMate" ] && { MM_FOUND=$(deep_find "MailMate"); [ -n "$MM_FOUND" ] && link_in_place "$MM_FOUND" "$HOME/Library/Application Support/MailMate"; }; }
    already_linked "$HOME/Library/Application Support/Tox" "Tox (qTox)" || { [ ! -d "$DATA/Tox" ] && { TOX_FOUND=$(deep_find "Tox"); [ -n "$TOX_FOUND" ] && link_in_place "$TOX_FOUND" "$HOME/Library/Application Support/Tox"; }; }
    TK_LINKED=$(find "$HOME/Library/Application Support" -maxdepth 1 -type l -iname "*tukan*" 2>/dev/null | head -1)
    if [ -n "$TK_LINKED" ]; then
        ok "Tukan — $(L 'уже подключен симлинком, пропускаю.' 'already linked with a symlink, skipping.')"
    elif ! find "$DATA" -maxdepth 1 -iname "*tukan*" 2>/dev/null | grep -q .; then
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
            Safari)
                # Данные Safari лежат в ~/Library/Safari, а НЕ в Application
                # Support — раньше линковались не туда.
                src="$HOME/Library/Safari"
                sub="$item" ;;
            *)
                src="$HOME/Library/Application Support/$name"
                sub="$item" ;;
        esac
        if [ -L "$src" ]; then
            ok "«$name» — уже подключен симлинком, пропускаю."
            FOUND=1
            continue
        fi
        echo "Нашел на диске: «$name»"
        if [ "$AUTO_LINK" = "да" ]; then
            dim "$(L 'Подключаю автоматически (выбрано в начале).' 'Linking automatically (chosen at the start).')"
        else
            read -r -p "   Подключить к системе? (да/нет) [да]: " L
            L=$(yn "${L:-да}")
            [ "$L" != "да" ] && continue
        fi
        FOUND=1
        link_to "$src" "$sub"
    done
    [ $FOUND -eq 0 ] && echo "На диске пока нет данных — настроим с нуля."

    # Если данных нет НИГДЕ (ни в системе, ни на диске) — предлагаем запустить
    # приложение один раз, чтобы оно само создало папку с реальными данными,
    # а не подключать пустую (иначе проверка справедливо ругается «папка пустая»).
    offer_launch() {
        local launchname="$1" src="$2" appmatch
        [ -z "$launchname" ] && return 1
        appmatch=$(find /Applications -maxdepth 1 -iname "$launchname*.app" 2>/dev/null | head -1)
        [ -z "$appmatch" ] && return 1
        echo ""
        warn "$(L "Данных «$launchname» нет ни в системе, ни на диске — папку создавать нечем." "No data for \"$launchname\" anywhere — nothing to create the folder from.")"
        read -r -p "   $(L 'Запустить приложение сейчас, чтобы оно создало папку? (да/нет) [да]' 'Launch the app now so it creates its folder? (yes/no) [yes]'): " OL
        OL=$(yn "${OL:-да}")
        [ "$OL" != "да" ] && return 1
        # Intel-приложения (tukan среди них) на Apple Silicon не открываются без
        # Rosetta — ставлю заранее, иначе выскакивает «To open ... you need to
        # install Rosetta» и запуск тихо проваливается.
        local base mb
        base=$(basename "$appmatch" .app)
        mb=$(find "$appmatch/Contents/MacOS" -maxdepth 1 -type f 2>/dev/null | head -1)
        if [ -n "$mb" ] && [ "$(uname -m)" = "arm64" ] && [ ! -e /usr/libexec/rosetta/oahd ] \
           && ! lipo -archs "$mb" 2>/dev/null | grep -q arm64; then
            info "$(L 'Приложению нужна Rosetta — ставлю (до минуты)...' 'The app needs Rosetta — installing (up to a minute)...')"
            as_root softwareupdate --install-rosetta --agree-to-license >/dev/null 2>&1
            [ -e /usr/libexec/rosetta/oahd ] && ok "$(L 'Rosetta установлена.' 'Rosetta installed.')"
        fi
        # Снимаю карантин Gatekeeper, иначе первый запуск упирается в
        # «Apple could not verify ... is free of malware» и приложение не стартует.
        as_root xattr -dr com.apple.quarantine "$appmatch" 2>/dev/null
        # Первый запуск бывает капризным: перезапускаю приложение, пока оно не
        # поднимется (то самое «надо несколько раз перезапустить») или пока не
        # появится его папка с данными.
        local n
        open "$appmatch" 2>/dev/null
        n=0
        while [ ! -d "$src" ] && [ $n -lt 6 ]; do
            pgrep -if "$base" >/dev/null 2>&1 && break
            open "$appmatch" 2>/dev/null
            sleep 5
            n=$((n + 1))
        done
        echo "$(L 'Войди/настрой, потом ЗАКРОЙ приложение и нажми Enter.' 'Sign in / set up, then QUIT the app and press Enter.')"
        pause
        osascript -e "quit app \"$base\"" 2>/dev/null
        sleep 2
        [ -d "$src" ]
    }

    # --- 2) ОБЯЗАТЕЛЬНЫЕ ПРИЛОЖЕНИЯ: если не подключены — переносим с системы или создаем ---
    # 3-й аргумент (необязательный) — имя приложения в /Applications для offer_launch.
    ensure_app() {
        local src="$1" dstname="$2" launchname="$3"
        local dst="$DATA/$dstname"
        [ -L "$src" ] && return 0
        if [ -d "$dst" ]; then
            link_to "$src" "$dst"
        elif [ -d "$src" ]; then
            mkdir -p "$(dirname "$dst")"
            cp -R "$src" "$dst" 2>/dev/null
            if [ $? -eq 0 ]; then
                rm -rf "$src" 2>/dev/null
                if [ ! -e "$src" ]; then
                    ok "$dstname — данные перенесены на диск, копия в системе СТЕРТА."
                    link_to "$src" "$dst"
                else
                    err "$dstname — скопировано на диск, но стереть копию в системе macOS не дала («Operation not permitted»)."
                    dim "$(L 'Данные теперь И на диске, И в системе. Дай Терминалу «Полный доступ к диску» (Настройки -> Конфиденциальность и безопасность -> Полный доступ к диску), перезапусти Терминал и запусти скрипт — он дотрёт и подключит симлинк.' 'Data is now BOTH on the disk and in the system. Grant Terminal Full Disk Access (Settings -> Privacy & Security -> Full Disk Access), restart Terminal and re-run the script — it will finish wiping and link it.')"
                    TCC_BLOCK=1
                fi
            else
                rm -rf "$dst"
                err "$dstname — копирование на диск не удалось (macOS не дала), оригинал остался в системе."
                dim "$(L 'Причина почти всегда одна: дай Терминалу «Полный доступ к диску» (Настройки -> Конфиденциальность и безопасность -> Полный доступ к диску), перезапусти Терминал и запусти скрипт еще раз.' 'Almost always the same cause: grant Terminal Full Disk Access (Settings -> Privacy & Security -> Full Disk Access), restart Terminal and run the script again.')"
                TCC_BLOCK=1
            fi
        elif offer_launch "$launchname" "$src"; then
            # Приложение создало папку в системе — переносим её на диск
            mkdir -p "$(dirname "$dst")"
            cp -R "$src" "$dst" 2>/dev/null && rm -rf "$src" 2>/dev/null
            if [ ! -e "$src" ]; then
                ok "$dstname — папка создана приложением и перенесена на диск."
                link_to "$src" "$dst"
            else
                err "$dstname — папка создана приложением, но перенести на диск не вышло; папка осталась в системе."
                dim "$(L 'Проверь Полный доступ к диску у Терминала (см. выше) и запусти скрипт еще раз.' 'Check Terminal Full Disk Access (see above) and re-run the script.')"
                TCC_BLOCK=1
            fi
        else
            mkdir -p "$dst"
            link_to "$src" "$dst"
        fi
    }

    ensure_app "$(tg_local_dir)/stable" "Telegram/stable" "Telegram"
    ensure_app "$HOME/Library/Application Support/Sublime Text" "Sublime Text" "Sublime Text"
    ensure_app "$HOME/Library/Application Support/app.ls" "app.ls" "Linken Sphere"
    # Linken Sphere 2 капризнее остальных: приложение бывает не обновляется и
    # ругается, пока его не удалить и не поставить заново. Помечаю проблему
    # (симлинка нет ИЛИ папка на диске пустая), в конце напомню что делать.
    LS_SRC="$HOME/Library/Application Support/app.ls"
    LS_TGT=$(readlink "$LS_SRC" 2>/dev/null)
    if [ ! -L "$LS_SRC" ] || [ -z "$LS_TGT" ] || [ -z "$(ls -A "$LS_TGT" 2>/dev/null)" ]; then
        LS_FAIL=1
    fi

    # Safari: закладки, история, настройки — тоже на секретный диск. Safari надо
    # ЗАКРЫТЬ, иначе он держит файлы. Папка ~/Library/Safari защищена системой (TCC):
    # если копирование не пройдёт — Терминалу нужен «Полный доступ к диску».
    osascript -e 'quit app "Safari"' 2>/dev/null; sleep 2
    ensure_app "$HOME/Library/Safari" "Safari" "Safari"

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
        ensure_app "$TUKAN_DIR" "$(basename "$TUKAN_DIR")" "Tukan"
    elif find /Applications -maxdepth 1 -iname "*tukan*" 2>/dev/null | grep -q .; then
        # Tukan установлен, но данных нет — предложим запустить, чтобы создалась папка
        ensure_app "$HOME/Library/Application Support/Tukan" "Tukan" "Tukan"
    else
        warn "Tukan: папка не найдена. Запусти Tukan один раз и перезапусти скрипт."
    fi

    # --- 3) ПОЛЬЗОВАТЕЛЬСКИЕ ПАПКИ: Рабочий стол, Документы, Загрузки ---
    # Главное правило схемы: в системе не остается НИ ОДНОГО файла, включая
    # «просто скриншот на столе». Содержимое этих трёх папок переезжает на
    # секретный диск, а сами папки становятся симлинками на диск: Finder и
    # диалоги сохранения работают как обычно, но файлы физически пишутся
    # сразу на диск. Без диска папки «пустые» — так и задумано.
    # Ненулевой код выхода не роняет скрипт: файлы остаются в системе, об
    # этом честно скажет ПРОВЕРИТЬ.command.
    ensure_user_dir() {
        local src="$1" dstname="$2" label="$3"
        local dst="$DATA/$dstname"
        if [ -L "$src" ]; then
            ok "$label — $(L 'уже симлинк на диск, пропускаю.' 'already a symlink to the disk, skipping.')"
            return 0
        fi
        mkdir -p "$(dirname "$dst")"
        # Пустоту папки определяем ТОЛЬКО если её удалось прочитать: без
        # «Полного доступа к диску» чтение Desktop/Documents/Downloads молча
        # проваливается, и папку нельзя считать пустой — иначе удалили бы
        # непрочитанные файлы.
        local src_cnt=0 unreadable=0
        if [ -d "$src" ]; then
            if ls -A "$src" >/dev/null 2>&1; then
                src_cnt=$(find "$src" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
            else
                unreadable=1
            fi
        fi
        if [ "$unreadable" = "1" ]; then
            err "$label — $(L 'не смог прочитать папку (macOS не дала), ничего не трогаю.' 'could not read the folder (macOS refused), leaving it untouched.')"
            dim "$(L 'Дай Терминалу «Полный доступ к диску» (Настройки -> Конфиденциальность и безопасность -> Полный доступ к диску), перезапусти Терминал и запусти скрипт еще раз.' 'Grant Terminal Full Disk Access (Settings -> Privacy & Security -> Full Disk Access), restart Terminal and run the script again.')"
            return 1
        fi
        if [ "$src_cnt" -gt 0 ]; then
            local dst_cnt=0
            [ -d "$dst" ] && dst_cnt=$(find "$dst" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
            if [ "$dst_cnt" -lt "$src_cnt" ]; then
                mkdir -p "$dst"
                cp -Rp "$src/." "$dst/" 2>/dev/null
                local rc=$?
                dst_cnt=$(find "$dst" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
                if [ $rc -ne 0 ] || [ -z "$dst_cnt" ] || [ "$dst_cnt" -lt "$src_cnt" ]; then
                    err "$label — $(L 'перенос не удался, оригиналы ОСТАЛИСЬ в системе.' 'move failed, originals are KEPT in the system.')"
                    dim "$(L 'Либо дай Терминалу «Полный доступ к диску» (Настройки -> Конфиденциальность и безопасность -> Полный доступ к диску), либо на диске кончилось место. Перезапусти Терминал и запусти скрипт еще раз.' 'Either grant Terminal Full Disk Access (Settings -> Privacy & Security -> Full Disk Access), or the disk is out of space. Restart Terminal and run the script again.')"
                    return 1
                fi
            fi
        fi
        mkdir -p "$dst" 2>/dev/null
        # ЗАМЕНА ПАПКИ СИМЛИНКОМ. Раньше было rm -rf + ln -s, и между rm и ln
        # Finder/iCloud успевали пересоздать папку: ln падал («File exists»),
        # и скрипт после УДАЧНОГО переноса писал «симлинк НЕ создан», а папка
        # оставалась в системе. Теперь: гасим Finder, ПЕРЕИМЕНОВЫВАЕМ папку в
        # сторону, ставим симлинк, запускаем Finder. Оригинал стираю только
        # ПОСЛЕ удачного симлинка; если не стерся — скажу имя оставшейся папки.
        osascript -e 'quit app "Finder"' 2>/dev/null
        sleep 1
        local old="$src.autosetup-old" swapped=0
        rm -rf "$old" 2>/dev/null
        if mv "$src" "$old" 2>/dev/null; then
            if ln -s "$dst" "$src" 2>/dev/null; then
                swapped=1
            else
                # папку кто-то успел пересоздать — убираю пустышку и возвращаю оригинал
                rm -rf "$src" 2>/dev/null
                mv "$old" "$src" 2>/dev/null
            fi
        fi
        open -a Finder 2>/dev/null
        if [ "$swapped" = "1" ]; then
            if [ "$src_cnt" -gt 0 ]; then
                ok "$label — $(L 'перенесено объектов:' 'items moved:') $src_cnt → $(L 'на секретный диск, в системе остался симлинк.' 'to the secret disk, a symlink left in the system.')"
            else
                ok "$label — $(L 'папка была пуста, подключена с диска симлинком.' 'folder was empty, linked from the disk with a symlink.')"
            fi
            rm -rf "$old" 2>/dev/null
            [ -e "$old" ] && warn "$label — $(L 'оригинал не стерся: в ~ осталась папка' 'original did not wipe: the folder left in ~') «$(basename "$old")» — $(L 'удали её руками (данные уже на диске).' 'delete it by hand (data is already on the disk).')"
            return 0
        else
            err "$label — $(L 'симлинк НЕ создан (папка осталась в системе).' 'symlink NOT created (folder left in the system).')"
            return 1
        fi
    }

    echo ""
    info "$(L 'Пользовательские папки: Рабочий стол, Документы, Загрузки — тоже на секретный диск.' 'User folders: Desktop, Documents, Downloads — onto the secret disk too.')"
    DO_UF="да"
    if [ "$AUTO_LINK" != "да" ]; then
        read -r -p "   $(L 'Перенести их содержимое на диск и заменить папки симлинками? (да/нет) [да]' 'Move their contents to the disk and replace the folders with symlinks? (yes/no) [yes]'): " UF
        DO_UF=$(yn "${UF:-да}")
    fi
    if [ "$DO_UF" = "да" ]; then
        # iCloud-синхронизация «Рабочий стол и папки Документов» (FileProvider)
        # сама пересоздает эти папки и тянет их содержимое в облако — симлинки
        # будут срываться, а Finder после подмены папок может упасть. Отключена?
        if [ "$(defaults read com.apple.finder FXICloudDriveDesktop 2>/dev/null)" = "1" ] \
            || [ "$(defaults read com.apple.finder FXICloudDriveDocuments 2>/dev/null)" = "1" ]; then
            err "$(L 'iCloud синхронизирует Рабочий стол/Документы — папки на диск НЕ подключаю.' 'iCloud syncs Desktop/Documents — NOT linking these folders to the disk.')"
            dim "$(L 'Сначала выключи: Настройки -> [твоё имя] -> iCloud -> Диск iCloud -> синхронизацию «Рабочий стол и папки Документов». Потом запусти скрипт еще раз.' 'First turn it off: Settings -> [your name] -> iCloud -> iCloud Drive -> «Desktop & Documents Folders» sync. Then re-run the script.')"
            UF_ICLOUD=1
        else
            dim "$(L 'macOS может спросить «Терминалу нужен доступ к папке...» — нажми «Разрешить».' 'macOS may ask "Terminal would like to access files in..." — click "Allow".')"
            ensure_user_dir "$HOME/Desktop"   "Desktop"   "$(L 'Рабочий стол' 'Desktop')"
            ensure_user_dir "$HOME/Documents" "Documents" "$(L 'Документы' 'Documents')"
            # Установщики из ~/Downloads/autosetup уже отработали — их сотни мегабайт
            # незачем катать на шифрованный диск (в конце они все равно стираются).
            [ -d "$DL" ] && rm -rf "$DL" 2>/dev/null
            ensure_user_dir "$HOME/Downloads" "Downloads" "$(L 'Загрузки' 'Downloads')"
            dim "$(L 'Всё, что теперь сохраняешь в эти папки, сразу попадает на диск. Без диска они пустые — так и задумано.' 'Everything saved into these folders now goes straight to the disk. Without the disk they are empty — by design.')"
        fi
    else
        warn "$(L 'Пользовательские папки остались в системе — файлы в них видны и без диска, ПРОВЕРИТЬ будет ругаться.' 'User folders stayed in the system — files in them are visible without the disk, ПРОВЕРИТЬ will complain.')"
    fi
fi

# ------------------------------------------------------------
# ОБНОВЛЕНИЯ MACOS (автоматически)
# ------------------------------------------------------------
step "ОБНОВЛЕНИЯ macOS"

# ПОЧЕМУ Mac УХОДИЛ В ПЕРЕЗАГРУЗКУ ПОСРЕДИ НАСТРОЙКИ:
# ключ AutomaticallyInstallMacOSUpdates=true разрешает macOS САМОЙ поставить
# скачанное обновление системы и САМОЙ перезагрузиться — она это делала прямо
# во время работы скрипта. Поэтому:
#   - автоПРОВЕРКУ и автоСКАЧИВАНИЕ включаем (перезагрузок не вызывают);
#   - автоУСТАНОВКУ обновлений macOS ВЫКЛЮЧАЕМ — ставить будешь сам из
#     Настройки -> Основные -> Обновление ПО, когда удобно;
#   - команду softwareupdate вообще не запускаем — даже скачивание при включенной
#     автоустановке провоцировало установку с перезагрузкой.
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true 2>/dev/null
# Перечитываю ключи и проверяю, что реально записалось: раньше «ок» печаталось
# всегда, а проверка потом честно говорила «выключено». Теперь вранья нет.
AU_ON=$(as_root defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null)
AU_DL=$(as_root defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload 2>/dev/null)
if [ "$AU_ON" = "1" ] && [ "$AU_DL" = "1" ]; then
    ok "$(L 'Обновления: автопроверка и автоскачивание ВКЛ — Mac сам узнает о новых.' 'Updates: auto-check and auto-download ON — the Mac learns about new ones itself.')"
else
    warn "$(L 'Автопроверка/автоскачивание записались не до конца — включи руками: Настройки -> Основные -> Обновление ПО.' 'Auto-check/auto-download did not stick — enable by hand: Settings -> General -> Software Update.')"
fi
ok "$(L 'АвтоУСТАНОВКА системы ВЫКЛ — Mac не будет сам перезагружаться из-за обновлений, ставишь их сам, когда удобно.' 'Auto-INSTALL is OFF — the Mac will not reboot itself for updates; you install them yourself when convenient.')"

# ------------------------------------------------------------
# ЧИСТКА ИСТОРИИ ТЕРМИНАЛА
# ------------------------------------------------------------
step "Чистка истории терминала"
# Сначала — Downloads: скачанные установщики (Telegram, VeraCrypt, Excel, ...)
# лежали в ~/Downloads/autosetup. Они больше не нужны, а Downloads должен
# остаться пустым — ноль следов настройки в системе.
if [ -d "$DL" ]; then
    rm -rf "$DL" 2>/dev/null
    [ -d "$DL" ] && warn "$(L 'Downloads не отчистился до конца — загляни в ~/Downloads/autosetup и удали руками.' 'Downloads did not clean fully — check ~/Downloads/autosetup and delete it by hand.')" \
                  || ok "$(L 'Downloads почищен: скачанные установщики удалены.' 'Downloads cleaned: downloaded installers removed.')"
fi
# Терминал сохраняет ВСЁ, что ты набирал (пути к секретному диску, имена, пароли,
# если вводил их в командах), в файлы истории. Стираем их и историю текущей сессии.
for HF in "$HOME/.zsh_history" "$HOME/.bash_history" "$HOME/.sh_history" \
          "$HOME/.python_history" "$HOME/.lesshst" "$HOME/.local/share/fish/fish_history"; do
    [ -e "$HF" ] && rm -f "$HF" 2>/dev/null
done
# Штатный выключатель zsh-сессий от Apple (/etc/zshrc_Apple_Terminal проверяет
# этот файл). Без него уже открытое окно Терминала при закрытии сыплет ошибками
# «locking failed ... .historynew» (то, что ты видел) — с ним новые окна вообще
# не записывают сессии.
touch "$HOME/.zsh_sessions_disable"
rm -rf "$HOME/.zsh_sessions" 2>/dev/null
# пустая папка взамен — уже открытое окно Терминала при закрытии не ругается
mkdir -p "$HOME/.zsh_sessions"
history -c 2>/dev/null
ok "История терминала очищена."
echo ""
echo "$(L 'Если позже снова наберёшь что-то в Терминале — почисти этими командами:' 'If you type anything in Terminal again — clean it with these commands:')"
echo '   history -c'
echo '   rm -f ~/.zsh_history ~/.bash_history ~/.python_history'
echo '   touch ~/.zsh_sessions_disable'
echo '   rm -rf ~/.zsh_sessions && mkdir -p ~/.zsh_sessions'
echo "$(L '   про файл .zsh_sessions_disable: это ШТАТНЫЙ выключатель сессий zsh от Apple — с ним Терминал вообще перестаёт записывать историю сессий (ошибок «locking failed» после ручного удаления папки тоже не будет). Скрипт создал его тебе заранее.' '   about .zsh_sessions_disable: it is Apple OFFICIAL opt-out for zsh sessions — Terminal stops persisting session history at all (and the «locking failed» errors after manual folder removal disappear too). The script has already created it for you.')"

# ------------------------------------------------------------
# ТАЙМЕРЫ ЭКРАНА, ЗАСТАВКИ И АВТОВЫХОДА (применяем в самом конце)
# ------------------------------------------------------------
# Всё долгое (скачивания, обновления, шифрование) уже позади — теперь можно
# отпустить экран и применить твои выборы. На время работы они были отключены,
# иначе гасили экран и разлогинивали посреди настройки.
kill "$CAFFEINATE_PID" 2>/dev/null
trap - EXIT
DISPLAY_SLEEP=${DISPLAY_SLEEP:-5}
as_root pmset -a displaysleep "$DISPLAY_SLEEP" &>/dev/null
if [ "$DISPLAY_SLEEP" = "0" ]; then
    ok "$(L 'Дисплей не гаснет по таймеру (выбрано «никогда»).' 'Display never sleeps (you chose never).')"
else
    ok "$(L 'Дисплей выключается через' 'Display sleeps after') $DISPLAY_SLEEP $(L 'мин.' 'min.')"
fi

# Заставка: возвращаем таймер, который был до скрипта (или стандартные 20 мин)
if [[ "$SAVED_SS_IDLE" =~ ^[0-9]+$ ]] && [ "$SAVED_SS_IDLE" != "0" ]; then
    defaults -currentHost write com.apple.screensaver idleTime -int "$SAVED_SS_IDLE" 2>/dev/null
else
    defaults -currentHost write com.apple.screensaver idleTime -int 1200 2>/dev/null
fi
ok "$(L 'Заставка снова включена (на время настройки была отключена).' 'Screen saver re-enabled (it was off during setup).')"

# Автовыход: применяем выбор из вопроса 6 только теперь
AUTOLOGOUT_MIN=${AUTOLOGOUT_MIN:-30}
if [ "$AUTOLOGOUT_MIN" = "0" ]; then
    as_root defaults delete /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay 2>/dev/null
    ok "$(L 'Автовыход из системы выключен.' 'Auto logout is off.')"
else
    as_root defaults write /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay -int $((AUTOLOGOUT_MIN * 60))
    ok "$(L 'Автовыход из системы через' 'Auto logout after') $AUTOLOGOUT_MIN $(L 'мин.' 'min.')"
fi

# ------------------------------------------------------------
# ФИНАЛ
# ------------------------------------------------------------
step "ГОТОВО"

MN=0
mitem() { MN=$((MN + 1)); echo -e "  ${YELLOW}${BOLD}[$MN]${NC} ${BOLD}$1${NC}"; echo -e "       ${GREY}$2${NC}"; }

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
[ "$FW_MANUAL" = "1" ] && mitem "Настройки -> Сеть -> Брандмауэр: тумблер ВКЛ, затем Параметры -> «Включить режим невидимости»." \
      "Settings -> Network -> Firewall: toggle ON, then Options -> «Enable stealth mode»."
[ "$UF_ICLOUD" = "1" ] && mitem "Выключи iCloud-синхронизацию «Рабочий стол и папки Документов» (Настройки -> [твоё имя] -> iCloud -> Диск iCloud), затем запусти скрипт еще раз — он подключит эти папки к диску." \
      "Turn off iCloud «Desktop & Documents Folders» sync (Settings -> [your name] -> iCloud -> iCloud Drive), then re-run the script — it will link those folders to the disk."
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
[ "$SS_MANUAL" = "1" ] && mitem "Настройки -> Общий доступ -> выключи «Общий экран», «Удалённое управление» и «Удалённый вход» (SSH)." \
      "Settings -> Sharing -> turn off «Screen Sharing» and «Remote Management»."
if [ "$LS_FAIL" = "1" ]; then
    mitem "Linken Sphere 2: была проблема с подключением его данных — удали приложение и установи заново," \
          "Linken Sphere 2: its data linking had a problem — uninstall the app and install it again,"
    dim "$(L 'тогда апдейт приложения сработает. После переустановки запусти ПРОВЕРИТЬ.command — он покажет, что симлинк в порядке.' 'then the app update works. After reinstalling, run ПРОВЕРИТЬ.command — it will confirm the symlink is fine.')"
fi
if [ "$INSTALL_EXCEL" = "да" ] || [ -d "/Applications/Microsoft Excel.app" ]; then
    mitem "Excel: открой один раз и войди в аккаунт Microsoft 365 — иначе работает как пробный." \
          "Excel: open once and sign in to a Microsoft 365 account — otherwise it stays a trial."
fi
if [ "$TCC_BLOCK" = "1" ] || [ "$FDA_MISSING" = "1" ]; then
    mitem "Safari/данные: перенос уперся в «Полный доступ к диску» Терминала — дай его:" \
          "Safari/data: the move hit Terminal Full Disk Access — grant it:"
    dim "Настройки -> Конфиденциальность и безопасность -> Полный доступ к диску -> Терминал -> ВКЛ, перезапусти Терминал и запусти скрипт снова — он всё дотащит."
    dim "Settings -> Privacy & Security -> Full Disk Access -> Terminal -> ON, restart Terminal and re-run the script — it will finish the job."
fi
[ "$TZ_MANUAL" = "1" ] && mitem "Часовой пояс не применился: Настройки -> Основные -> Дата и время -> часовой пояс $VPN_TZ (автоопределение — выкл)." \
      "Time zone did not apply: Settings -> General -> Date & Time -> zone $VPN_TZ (auto — off)."
[ "$REC_MANUAL" = "1" ] && mitem "«Недавние объекты»: после перезагрузки открой меню  -> «Недавние объекты» и убедись, что оно пустое." \
      "Recent Items: after the reboot open  -> «Recent Items» and make sure it is empty."
[ $MN -eq 0 ] && ok "Ручных пунктов нет — все сделано скриптом."
echo ""
echo -e "  ${BOLD}ГЛАВНОЕ ПРАВИЛО:${NC} ничего не храни в системе Mac и на Рабочем столе —"
echo "  все файлы ТОЛЬКО на подключенном секретном диске. Что попало в систему,"
echo "  можно восстановить даже после удаления. Отключил диск -> на Mac ноль твоих файлов."
echo -e "  ${BOLD}MAIN RULE:${NC} keep nothing inside macOS or on the Desktop — all files ONLY on the"
echo "  mounted secret disk. Anything written to the system can be recovered even after deletion."
echo ""
case "$WIFI_MODE" in
    1) echo "  ВАЖНО: служба Wi-Fi удалена насовсем (работа только по кабелю)."
       echo "  Вернуть, если вдруг надо: Настройки -> Сеть -> кнопка ... -> Добавить службу -> Wi-Fi."
       echo "  IMPORTANT: the Wi-Fi service was removed for good (cable only). To bring it back:"
       echo "  Settings -> Network -> ... button -> Add Service -> Wi-Fi." ;;
    2) echo "  ВАЖНО: радиомодуль Wi-Fi выключен, служба оставлена. Включить: Настройки -> Сеть -> Wi-Fi."
       echo "  IMPORTANT: Wi-Fi radio is off, the service kept. Turn on: Settings -> Network -> Wi-Fi." ;;
    *) echo "  ВАЖНО: Wi-Fi оставлен как есть (по твоему выбору)."
       echo "  IMPORTANT: Wi-Fi left as is (your choice)." ;;
esac
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
echo -e "  ${GREEN}$(rep "━" "$(tw)")${NC}"
echo -e "  ${GREEN}▎${NC}${BOLD}  НАСТРОЙКА ЗАВЕРШЕНА${NC}   ${GREY}— $(L 'общее время' 'total time') $(t2s $SECONDS)${NC}"
echo -e "  ${GREEN}▎${NC}  ${GREY}$(L 'Можно закрыть окно.' 'You can close this window.')${NC}"
echo -e "  ${GREEN}$(rep "━" "$(tw)")${NC}"

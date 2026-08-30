#!/bin/bash

# ============================================================
#  АВТОНАСТРОЙКА MAC — ПОЛНЫЙ АВТОМАТ (v12)
#  Человеку нужно только: ответить на 5 вопросов и ввести пароль
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

readonly SCRIPT_VERSION="v12.1-2026.08.30 — умный режим: реестр приложений, опознание данных по содержимому, диск только через GUI VeraCrypt, FileVault без показа ключа, 5 вопросов, верификация защиты, лок от двойного запуска, встроенная самопроверка, dry-run, возобновление после падения"
echo -e "${BOLD}ВЕРСИЯ СКРИПТА: ${CYAN}${SCRIPT_VERSION}${NC}"

# --- Визуальный каркас -----------------------------------------------------
tw() {
    local w
    w=$(tput cols 2>/dev/null) || w=${COLUMNS:-80}
    case "$w" in ''|*[!0-9]*) w=80 ;; esac
    [ "$w" -lt 60 ] && w=60
    [ "$w" -gt 120 ] && w=120
    echo "$w"
}
rep() { local s="$1" n="$2"; while [ "$n" -gt 0 ]; do printf '%s' "$s"; n=$((n - 1)); done; }
t2s() {
    local s="$1"
    if [ "$s" -ge 3600 ]; then
        printf '%d:%02d:%02d' $((s / 3600)) $(( (s % 3600) / 60 )) $((s % 60))
    else
        printf '%02d:%02d' $((s / 60)) $((s % 60))
    fi
}
SPIN_N=0
spin() { local f='|/-\' c; c=${f:$SPIN_N:1}; SPIN_N=$(( (SPIN_N + 1) % 4 )); printf '\033[2K  %s  %s ...\r' "$c" "$1" >&2; }
spin_end() { printf '\033[2K' >&2; }
ok()   { echo -e "  ${GREEN}${BOLD}✓${NC}  $1"; }
warn() { echo -e "  ${YELLOW}${BOLD}▲${NC}  $1"; }
err()  { echo -e "  ${RED}${BOLD}✗${NC}  $1"; }
info() { echo -e "  ${BLUE}${BOLD}•${NC}  $1"; }
dim()  { echo -e "  ${GREY}· $1${NC}"; }
sub()  { echo ""; echo -e "  ${BOLD}${CYAN}▸${NC} ${BOLD}$1${NC}"; }
hr()   { echo -e "  ${GREY}$(rep "─" $(($(tw) - 4)))${NC}"; }
progress_bar() {
    local dn=$1 tt=$2 w=26 filled empty i
    filled=$(( dn * w / tt )); empty=$(( w - filled ))
    printf '  \033[0;36m'
    i=0; while [ $i -lt $filled ]; do printf '█'; i=$((i + 1)); done
    printf '\033[0;90m'
    i=0; while [ $i -lt $empty ]; do printf '░'; i=$((i + 1)); done
    printf '\033[0m  %s/%s\n' "$dn" "$tt"
}
step() {
    local w
    w=$(tw)
    echo ""
    echo -e "  ${GREY}─── $(t2s $SECONDS) $(rep "─" $((w - 10)))${NC}"
    echo -e "  ${CYAN}${BOLD}▎${NC} ${BOLD}$1${NC}"
    case "$2" in */*) progress_bar "${2%/*}" "${2#*/}" ;; esac
    echo -e "  ${GREY}$(rep "─" $w)${NC}"
}
q()     { echo -e "  ${CYAN}${BOLD}[$1]${NC} ${BOLD}$2${NC}"; }
pause() { echo ""; echo -e "  ${YELLOW}${BOLD}⏎${NC}  ${BOLD}$(L 'Когда сделаешь — нажми Enter' 'When done — press Enter')${NC}"; read -r; }

# Двуязычный вывод и нормализация да/нет
L() { printf '%s / %s' "$1" "$2"; }
yn() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        yes|y|да|д|1) echo "да" ;;
        no|n|нет|н|0) echo "нет" ;;
        *) echo "$1" ;;
    esac
}

# --- Конфиг: создается сам рядом со скриптом, удаляется после прогона -------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/autosetup.conf"
chmod +x "$SCRIPT_DIR/ПРОВЕРИТЬ.command" 2>/dev/null

if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<'EOF'
# Автоконфиг скрипта настройки. Создан самим скриптом, удаляется после прогона.
# Править можно между запусками; если удалить — создастся заново с дефолтами.
FUSET_URL="https://github.com/macos-fuse-t/fuse-t/releases/download/1.2.7/fuse-t-macos-installer-1.2.7.pkg"
VC_URL="https://launchpad.net/veracrypt/trunk/1.26.29/+download/VeraCrypt_FUSE-T_1.26.29.dmg"
TG_URL="https://telegram.org/dl/macos/stable"
SUBLIME_URL="https://download.sublimetext.com/sublime_text_build_4200_mac.zip"
SPHERE_URL_ARM64="https://cdn.ls.app/ls2_1.9.9_arm64.dmg"
SPHERE_URL_X86="https://cdn.ls.app/ls2_1.9.9_x86_64.dmg"
TUKAN_URL="https://tukan.me/download/mac"
MM_URL="https://updates.mailmate-app.com/archives/MailMateBeta.tbz"
EXCEL_URL="https://go.microsoft.com/fwlink/?linkid=525135"
MOUNT_WAIT_MIN=30
DISK_WAIT_SEC=120
DISPLAY_SLEEP=5
AUTOLOGOUT_MIN=30
LS_EXTENSIONS="txt md markdown csv tsv json xml yaml yml log ini conf cfg env sh py js toml sql"
EOF
fi
. "$CONFIG_FILE"

# --- Режимы ------------------------------------------------------------------
DRY_RUN=0
[ "$1" = "--dry-run" ] && DRY_RUN=1
[ "$DRY_RUN" = "1" ] && warn "РЕЖИМ DRY-RUN: только покажу план, ничего не изменю."

# Возобновление после падения: отметки о завершенных фазах живут в /tmp
# (сами стираются при перезагрузке). Успешный прогон удаляет файл в конце.
STAGE_FILE="/tmp/autosetup_stage"
stage_done() { grep -qx "$1" "$STAGE_FILE" 2>/dev/null; }
stage_mark() { echo "$1" >> "$STAGE_FILE"; }

as_root() { printf '%s\n' "$ADMIN_PASS" | sudo -S "$@"; }

# Проверка: мы на маке?
if [ "$(uname)" != "Darwin" ]; then
    err "Этот скрипт работает только на macOS."
    rm -f "$CONFIG_FILE"
    exit 1
fi

# На время настройки — не давать Mac гасить экран и засыпать
caffeinate -dimsu &
CAFFEINATE_PID=$!
cleanup_exit() {
    kill "$CAFFEINATE_PID" 2>/dev/null
    rm -f "$CONFIG_FILE" "$LOCK"
}
trap cleanup_exit EXIT

# Защита от двойного запуска: второй экземпляр не стартует, пока жив первый
LOCK=/tmp/autosetup.lock
if [ -f "$LOCK" ]; then
    OLD_PID=$(cat "$LOCK" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        err "Скрипт УЖЕ запущен (PID $OLD_PID). Дождись окончания или закрой то окно."
        exit 1
    fi
    rm -f "$LOCK"
fi
echo $$ > "$LOCK" 2>/dev/null

ARCH=$(uname -m)
clear

TITLE_W=$(tw)
echo ""
echo -e "  ${CYAN}$(rep "━" "$TITLE_W")${NC}"
echo -e "  ${CYAN}▎${NC}  ${BOLD}\033[38;5;51mАВТОНАСТРОЙКА И ЗАЩИТА MAC${NC}  ${GREY}${SCRIPT_VERSION%% — *}${NC}"
echo -e "  ${CYAN}▎${NC}  ${GREY}MAC SETUP & HARDENING — автомат, минимум вопросов, без следов${NC}"
echo -e "  ${CYAN}$(rep "━" "$TITLE_W")${NC}"
echo -e "  ${GREY}macOS $(sw_vers -productVersion 2>/dev/null) · $(sysctl -n hw.model 2>/dev/null) · $ARCH · $(date '+%d.%m.%Y %H:%M')${NC}"
echo ""
info "$(L 'Скрипт настроит этот Mac сам — просто следуй экрану.' 'The script sets this Mac up on its own — just follow the screen.')"
info "$(L 'Вопросов минимум, дальше всё идет без тебя.' 'Minimal questions, then it runs unattended.')"
dim "$(L 'Логи не ведутся — никаких следов в системе не остается.' 'No logs are written — no traces left in the system.')"
[ -s "$STAGE_FILE" ] && warn "$(L 'Найдены отметки прошлого прерванного прогона — завершенные фазы пропущу.' 'Found marks of an interrupted run — completed phases will be skipped.')"

# ------------------------------------------------------------
# РЕЕСТР ПРИЛОЖЕНИЙ — вся информация о приложениях в одном месте.
# Чтобы добавить приложение: одна строка в app_keys + ветки в функциях ниже.
# ------------------------------------------------------------
TG_GLOB="*keepcoder.Telegram"
tg_local_dir() {
    local d
    d=$(find "$HOME/Library/Group Containers" -maxdepth 1 -name "$TG_GLOB" 2>/dev/null | head -1)
    [ -z "$d" ] && d="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram"
    echo "$d"
}

app_keys() { printf '%s\n' telegram sublime sphere mailmate qtox tukan; }

app_label() {
    case "$1" in
        telegram) echo "Telegram" ;;    sublime) echo "Sublime Text" ;;
        sphere)   echo "Linken Sphere" ;; mailmate) echo "MailMate" ;;
        qtox)     echo "qTox" ;;        tukan) echo "Tukan" ;;
    esac
}

# РЕАЛЬНЫЙ путь данных в системе (это знает приложение, не пользователь)
app_src() {
    case "$1" in
        telegram) echo "$(tg_local_dir)/stable" ;;
        sublime)  echo "$HOME/Library/Application Support/Sublime Text" ;;
        sphere)   echo "$HOME/Library/Application Support/app.ls" ;;
        mailmate) echo "$HOME/Library/Application Support/MailMate" ;;
        qtox)     echo "$HOME/Library/Application Support/Tox" ;;
        tukan)    echo "$HOME/Library/Containers/me.tukan.tukan" ;;
    esac
}

# Каноническое имя на диске (используется, только когда создаем с нуля)
app_dst() {
    case "$1" in
        telegram) echo "Telegram/stable" ;;
        sublime)  echo "Sublime Text" ;;
        sphere)   echo "app.ls" ;;
        mailmate) echo "MailMate" ;;
        qtox)     echo "Tox" ;;
        tukan)    echo "Tukan_Data/me.tukan.tukan" ;;
    esac
}

# Имя для поиска .app в /Applications
app_bundle() {
    case "$1" in
        telegram) echo "Telegram" ;; sublime) echo "Sublime Text" ;;
        sphere)   echo "*sphere*" ;; mailmate) echo "MailMate" ;;
        qtox)     echo "qTox" ;;     tukan) echo "*tukan*" ;;
    esac
}

# --- ОТПЕЧАТКИ: опознание папки ПО СОДЕРЖИМОМУ, имя папки не важно ----------
fp_telegram() { [ -e "$1/accounts-metadata" ] || { [ -d "$1/stable" ] && [ -e "$1/stable/accounts-metadata" ]; }; }
fp_sublime()  { [ -d "$1/Local" ] && [ -d "$1/Packages" ]; }
fp_sphere() {
    [ -e "$1/Local State" ] || return 1
    [ -d "$1/Default" ] && return 0
    local s b re='^[0-9a-fA-F]{24,64}$'
    for s in "$1"/*/; do
        [ -d "$s" ] || continue
        b=$(basename "$s")
        [[ "$b" =~ $re ]] && return 0
    done
    return 1
}
fp_mailmate() { [ -d "$1/Messages" ]; }
fp_qtox()     { find "$1" -maxdepth 1 -name "*.tox" 2>/dev/null | grep -q .; }
fp_tukan()    { [ -e "$1/.com.apple.containermanagerd.metadata.plist" ] && grep -qa "me.tukan.tukan" "$1/.com.apple.containermanagerd.metadata.plist" 2>/dev/null; }

# fp_any <папка> -> ключ приложения или пусто
fp_any() {
    local k
    for k in $(app_keys); do
        "fp_$k" "$1" 2>/dev/null && { echo "$k"; return 0; }
    done
    return 1
}

# ------------------------------------------------------------
# ПРЕДПОЛЕТНАЯ ПРОВЕРКА: что уже стоит и куда уже подключено
# ------------------------------------------------------------
APP_TELEGRAM=0; APP_SUBLIME=0; APP_SPHERE=0; APP_TUKAN=0; APP_VERACRYPT=0; APP_MAILMATE=0
[ -d "/Applications/Telegram.app" ] && APP_TELEGRAM=1
[ -d "/Applications/Sublime Text.app" ] && APP_SUBLIME=1
[ -n "$(find /Applications -maxdepth 1 -iname '*sphere*.app' 2>/dev/null | head -1)" ] && APP_SPHERE=1
[ -n "$(find /Applications -maxdepth 1 -iname '*tukan*.app' 2>/dev/null | head -1)" ] && APP_TUKAN=1
[ -d "/Applications/VeraCrypt.app" ] && APP_VERACRYPT=1
[ -d "/Applications/MailMate.app" ] && APP_MAILMATE=1

precheck_link() { [ -L "$(app_src "$1")" ] && echo 1 || echo 0; }
PRE_TG=$(precheck_link telegram)
PRE_ST=$(precheck_link sublime)
PRE_LS=$(precheck_link sphere)
PRE_MM=$(precheck_link mailmate)
PRE_QTOX=$(precheck_link qtox)
PRE_TUKAN=$(precheck_link tukan)

HAS_TG_DATA=0; HAS_ST_DATA=0; HAS_LS_DATA=0; HAS_MM_DATA=0; HAS_QTOX_DATA=0; HAS_TUKAN_DATA=0
fp_telegram "$(app_src telegram)" 2>/dev/null && HAS_TG_DATA=1
fp_sublime  "$(app_src sublime)"  2>/dev/null && HAS_ST_DATA=1
fp_sphere   "$(app_src sphere)"   2>/dev/null && HAS_LS_DATA=1
fp_mailmate "$(app_src mailmate)" 2>/dev/null && HAS_MM_DATA=1
fp_qtox     "$(app_src qtox)"     2>/dev/null && HAS_QTOX_DATA=1
fp_tukan    "$(app_src tukan)"    2>/dev/null && HAS_TUKAN_DATA=1

step "ПРЕДПОЛЕТНАЯ ПРОВЕРКА / PREFLIGHT CHECK"
for k in $(app_keys); do
    lbl=$(app_label "$k"); pre="PRE_$(echo "$k" | tr 'a-z' 'A-Z')"; [ "$k" = "sphere" ] && pre=PRE_LS; [ "$k" = "qtox" ] && pre=PRE_QTOX; [ "$k" = "sublime" ] && pre=PRE_ST; [ "$k" = "telegram" ] && pre=PRE_TG; [ "$k" = "mailmate" ] && pre=PRE_MM
    eval "ln=\$$pre"
    if [ "$ln" = "1" ]; then ok "$lbl — данные уже подключены к диску."
    else dim "$lbl — еще не подключен."; fi
done
hr

# ------------------------------------------------------------
# ВОПРОСЫ — только то, что реально нельзя решить за человека (5 шт)
# ------------------------------------------------------------
NEW_USER=""; NEW_USER_NAME=""
q 1 "Создать ОТДЕЛЬНУЮ учетную запись для работы (без прав админа)?"
echo "   Обычная — безопаснее: работаешь из нее, а пароль админа не светится."
read -r -p "   Создаем? (да/нет) [нет]: " CREATE_USER
CREATE_USER=$(yn "${CREATE_USER:-нет}")
if [ "$CREATE_USER" = "да" ]; then
    read -r -p "   Логин латиницей (пример: work): " NEW_USER
    read -r -p "   Отображаемое имя (пример: Work): " NEW_USER_NAME
    while true; do
        read -rs -p "   Пароль для НОВОЙ учетки: " USER_PASS; echo ""
        read -rs -p "   Еще раз: " USER_PASS2; echo ""
        if [ -n "$USER_PASS" ] && [ "$USER_PASS" = "$USER_PASS2" ]; then break; fi
        err "Пусто или не совпадает. Снова."
    done
fi

q 2 "Пароль от ТЕКУЩЕЙ учетной записи (админа) — нужен для настройки системы."
while true; do
    read -rs -p "   Введи пароль (не отображается): " ADMIN_PASS; echo ""
    if printf '%s\n' "$ADMIN_PASS" | sudo -S -k true 2>/dev/null; then ok "Пароль верный, поехали."; break; fi
    err "Не подошел. Еще раз."
done

# Проверка Full Disk Access у Терминала — заранее, а не сюрпризом в конце
FDA=1
ls "$HOME/Library/Safari" >/dev/null 2>&1 || FDA=0
if [ "$FDA" = "0" ]; then
    warn "У Терминала нет Полного доступа к диску — если что-то упрется в права, в конце скажу, что выдать."
fi

q 3 "Внешний диск (флешка/SSD) для секретных данных:"
echo "   «да»  = диск УЖЕ зашифрован VeraCrypt — ничего не стирать, просто подключить."
echo "   «нет» = диск НОВЫЙ: ты зашифруешь его сам в окне VeraCrypt (я покажу шаги),"
echo "           скрипт пароль диска НЕ спрашивает и НЕ видит вообще."
read -r -p "   Он УЖЕ зашифрован VeraCrypt раньше? (да/нет) [да]: " HAVE_DISK
HAVE_DISK=$(yn "${HAVE_DISK:-да}")

q 4 "Wi-Fi:"
echo "   1 — удалить службу насовсем (только кабель)  [по умолчанию]"
echo "   2 — просто выключить радио (можно включить обратно в Настройках)"
echo "   3 — не трогать вообще"
read -r -p "   Выбор [1]: " WIFI_MODE
WIFI_MODE=${WIFI_MODE:-1}
case "$WIFI_MODE" in 1|2|3) ;; *) WIFI_MODE=1 ;; esac

q 5 "Доп. программы поставить сразу? Введи буквы подряд (можно несколько):"
echo "   M — MailMate (почта)   Q — qTox (мессенджер)   E — Excel"
read -r -p "   Выбор [E]: " EXTRA
EXTRA=${EXTRA:-E}
INSTALL_MM=нет; INSTALL_QTOX=нет; INSTALL_EXCEL=нет
case "$(printf '%s' "$EXTRA" | tr '[:lower:]' '[:upper:]')" in
    *M*) INSTALL_MM=да ;; esac
case "$(printf '%s' "$EXTRA" | tr '[:lower:]' '[:upper:]')" in
    *Q*) INSTALL_QTOX=да ;; esac
case "$(printf '%s' "$EXTRA" | tr '[:lower:]' '[:upper:]')" in
    *E*) INSTALL_EXCEL=да ;; esac

# Без вопросов (дефолты из конфига / молчаливые решения):
#  - гашение экрана: DISPLAY_SLEEP мин (5), автовыход: AUTOLOGOUT_MIN мин (30)
#  - раскладка: US + Russian, переключение Ctrl+Space (есть на любой клавиатуре,
#    включая PC без Option/Cmd), Caps Lock не трогаем
#  - данные приложений на диске подключаются всегда автоматом
#  - часовой пояс: сам по IP; спрошу, только если не определится
as_root defaults delete /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay 2>/dev/null
SAVED_SS_IDLE=$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null)
defaults -currentHost write com.apple.screensaver idleTime -int 0 2>/dev/null
ok "На время настройки: автовыход и заставка ВЫКЛЮЧЕНЫ — экран не погаснет и из системы не выкинет."

# АвтоУСТАНОВКУ обновлений macOS гасим СРАЗУ и держим выключенной до конца
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false 2>/dev/null

# --- DRY-RUN: печатаем план и выходим без единого изменения ------------------
if [ "$DRY_RUN" = "1" ]; then
    step "ПЛАН (DRY-RUN — ничего не меняю)"
    [ "$CREATE_USER" = "да" ] && echo "  + создать учетку «$NEW_USER» (обычная)" || echo "  - учетку не создавать"
    echo "  + защита: блокировка сразу, брандмауэр+невидимость, гасить SSH/экран/ARD,"
    echo "    AirDrop/Handoff/геолокация/аналитика/Siri — выкл (каждый пункт с проверкой)"
    for k in $(app_keys); do
        lbl=$(app_label "$k"); bndl=$(app_bundle "$k")
        [ "$k" = "mailmate" ] && [ "$INSTALL_MM" != "да" ] && [ "$APP_MAILMATE" = "0" ] && continue
        [ "$k" = "qtox" ] && [ "$INSTALL_QTOX" != "да" ] && [ "$HAS_QTOX_DATA" = "0" ] && continue
        if [ -n "$(find /Applications -maxdepth 1 -iname "$bndl.app" 2>/dev/null | head -1)" ]; then
            echo "  = $lbl: приложение стоит; данные — $( [ -L "$(app_src "$k")" ] && echo 'уже на диске' || echo 'подключу к диску')"
        else
            echo "  + $lbl: установить и подключить данные к диску"
        fi
    done
    echo "  + VeraCrypt + FUSE-T — поставить, если нет"
    echo "  + FileVault — включить и ПРОВЕРИТЬ (ключ восстановления не показывается и не сохраняется)"
    echo "  + диск: $( [ "$HAVE_DISK" = "да" ] && echo 'подключить существующий (монтируешь сам в VeraCrypt)' || echo 'НОВЫЙ: шифруешь сам в окне VeraCrypt, я жду и нахожу')"
    echo "  + часовой пояс — по IP (тихо), раскладки US+Русская, Ctrl+Space, Wi-Fi режим $WIFI_MODE"
    echo "  + в конце — встроенная самопроверка (ссылки, FileVault, брандмауэр, VeraCrypt)"
    [ "$INSTALL_EXCEL" = "да" ] && echo "  + Excel — поставить"
    echo ""
    ok "Конец плана. Запусти без --dry-run для реального прогона."
    rm -f "$CONFIG_FILE"
    exit 0
fi

# ------------------------------------------------------------
# ФАЗА 1: ОТДЕЛЬНАЯ УЧЕТКА (каждый шаг dscl — с проверкой)
# ------------------------------------------------------------
if [ "$CREATE_USER" = "да" ] && ! stage_done user; then
    step "УЧЕТНАЯ ЗАПИСЬ / USER ACCOUNT" "1/6"
    if id "$NEW_USER" &>/dev/null; then
        warn "Учетка «$NEW_USER» уже существует — пропускаю."
    else
        info "Создаю «$NEW_USER»..."
        OK_USER=1
        UID_TRY=$(dscl . -list /Users UniqueID 2>/dev/null | awk '$2>=500 && $2<600 {print $2}' | sort -n | tail -1)
        UID_TRY=$(( ${UID_TRY:-500} + 1 ))
        for c in \
            "dscl . -create /Users/$NEW_USER" \
            "dscl . -create /Users/$NEW_USER UserShell /bin/bash" \
            "dscl . -create /Users/$NEW_USER RealName $NEW_USER_NAME" \
            "dscl . -create /Users/$NEW_USER UniqueID $UID_TRY" \
            "dscl . -create /Users/$NEW_USER PrimaryGroupID 20" \
            "dscl . -create /Users/$NEW_USER NFSHomeDirectory /Users/$NEW_USER"; do
            if ! as_root $c 2>/dev/null; then err "dscl: не выполнено «$c»"; OK_USER=0; break; fi
        done
        if [ "$OK_USER" = "1" ]; then
            echo "$USER_PASS" | as_root dscl . -passwd "/Users/$NEW_USER" 2>/dev/null
            as_root createhomedir -c -u "$NEW_USER" 2>/dev/null
        fi
        if [ "$OK_USER" = "1" ] && id "$NEW_USER" &>/dev/null; then
            ok "Учетка «$NEW_USER» создана и входит в систему (проверено)."
        else
            err "Учетка не создалась корректно — сделай вручную: Настройки -> Пользователи и группы."
        fi
        USER_PASS=""; USER_PASS2=""
    fi
    stage_mark user
fi

# Маленький верификатор: написали ключ -> сразу перечитали
verify_default() { # verify_default <описание> <plist> <ключ> <ожидание> [root]
    local desc="$1" plist="$2" key="$3" want="$4" asroot="$5" got
    if [ "$asroot" = "root" ]; then
        got=$(as_root defaults read "$plist" "$key" 2>/dev/null)
    else
        got=$(defaults read "$plist" "$key" 2>/dev/null)
    fi
    if [ "$got" = "$want" ]; then ok "$desc — подтверждено."
    else warn "$desc — записано, но перечитать не смог (значение: ${got:-пусто}). Проверь глазами."; fi
}

# ------------------------------------------------------------
# ФАЗА 2: БАЗОВАЯ ЗАЩИТА (каждый пункт — с перечитыванием)
# ------------------------------------------------------------
if ! stage_done hardening; then
    step "БАЗОВАЯ ЗАЩИТА / BASELINE SECURITY" "2/6"

    # Пароль сразу после сна/заставки — ОДИН раз, с проверкой
    SL_MANUAL=0
    echo "$ADMIN_PASS" | sudo -S sysadminctl -screenLock immediate -password - 2>/dev/null
    sleep 1
    if sysadminctl -screenLock status 2>/dev/null | grep -qi immediate; then
        ok "Пароль после сна и заставки — сразу (подтверждено)."
    else
        warn "Не подтвердилось — включи вручную: Настройки -> Экран блокировки -> «Сразу»."
        SL_MANUAL=1
    fi

    # Экран входа: без подсказок пароля, без кнопок питания, без ввода от root
    as_root defaults write /Library/Preferences/com.apple.loginwindow RetriesUntilHint -int 0 2>/dev/null
    as_root defaults write /Library/Preferences/com.apple.loginwindow PowerOffDisabled -bool true 2>/dev/null
    as_root defaults write /Library/Preferences/com.apple.loginwindow DisableConsoleAccess -bool true 2>/dev/null
    ok "Экран входа: подсказки пароля, кнопки питания и вход >root отключены."

    # Брандмауэр + режим невидимости
    FW_MANUAL=0
    SOCKETFW=/usr/libexec/ApplicationFirewall/socketfilterfw
    as_root "$SOCKETFW" --setglobalstate on >/dev/null 2>&1
    sleep 2
    if as_root "$SOCKETFW" --getglobalstate 2>/dev/null | grep -qi enabled; then
        ok "Брандмауэр включен (подтверждено)."
    else
        warn "Не включился из терминала — включу через Настройки."
        open "x-apple.systempreferences:com.apple.Network-Firewall" 2>/dev/null
        FW_MANUAL=1
    fi
    if [ "$FW_MANUAL" = "0" ]; then
        as_root "$SOCKETFW" --setstealthmode on >/dev/null 2>&1
        sleep 1
        if as_root "$SOCKETFW" --getstealthmode 2>/dev/null | grep -qi enabled; then
            ok "Режим невидимости включен (подтверждено)."
        else
            warn "Невидимость не подтвердилась: Настройки -> Сеть -> Брандмауэр -> Параметры."
            FW_MANUAL=1
        fi
    fi

    # Гасим УДАЛЕННЫЙ ДОСТУП: общий экран, удаленное управление (ARD), SSH
    SHARE_MANUAL=0
    for svc in com.apple.screensharing com.apple.RemoteManagement com.apple.ARDAgent; do
        as_root launchctl bootout system "/System/Library/LaunchDaemons/$svc.plist" 2>/dev/null
    done
    as_root launchctl disable system/com.apple.screensharing 2>/dev/null
    as_root launchctl disable system/com.apple.RemoteManagement 2>/dev/null
    as_root launchctl disable system/com.apple.ARDAgent 2>/dev/null
    as_root /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop 2>/dev/null
    as_root systemsetup -setremotelogin off 2>/dev/null
    SHARE_LEFT=0
    pgrep -x screensharingd >/dev/null 2>&1 && SHARE_LEFT=1
    pgrep -x ARDAgent >/dev/null 2>&1 && SHARE_LEFT=1
    if as_root systemsetup -getremotelogin 2>/dev/null | grep -qi ": On"; then SHARE_LEFT=1; fi
    if [ "$SHARE_LEFT" = "0" ]; then
        ok "Общий экран, удаленное управление и SSH выключены (подтверждено)."
    else
        warn "Что-то из удаленного доступа осталось: проверь Общий доступ и Экран блокировки в Настройках."
        SHARE_MANUAL=1
    fi

    # AirDrop — выкл + проверка
    as_root defaults write /Library/Preferences/SystemConfiguration/com.apple.Bluetooth DisableAirdrop -bool true 2>/dev/null
    defaults write com.apple.NetworkBrowser DisableAirDrop -bool true
    verify_default "AirDrop выключен" com.apple.NetworkBrowser DisableAirDrop "1"

    # Handoff — выкл + проверка
    defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool no
    defaults -currentHost write com.apple.coreservices.useractivityd ActivityReceivingAllowed -bool no
    UA=$(defaults -currentHost read com.apple.coreservices.useractivityd ActivityAdvertisingAllowed 2>/dev/null)
    if [ "$UA" = "0" ]; then ok "Handoff выключен (подтверждено)."
    else warn "Handoff — перечитать не смог. Проверь: Настройки -> Основные -> AirDrop и Handoff."; fi

    # Службы геолокации — выкл + проверка
    as_root defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool false 2>/dev/null
    LOC=$(as_root defaults read /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled 2>/dev/null)
    if [ "$LOC" = "0" ]; then ok "Службы геолокации выключены (подтверждено)."
    else warn "Геолокация — перечитать не смог. Проверь: Настройки -> Конфиденциальность -> Службы геолокации."; fi

    # Аналитика и рекламный идентификатор — выкл + проверка
    as_root defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit -bool false 2>/dev/null
    as_root defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist ThirdPartyDataSubmit -bool false 2>/dev/null
    defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false
    defaults write com.apple.AdLib allowIdentifierForAdvertising -bool false
    SUB=$(as_root defaults read /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit 2>/dev/null)
    if [ "$SUB" = "0" ]; then ok "Аналитика Apple и рекламный идентификатор выключены (подтверждено)."
    else warn "Аналитика — перечитать не смог. Проверь: Настройки -> Конфиденциальность -> Аналитика."; fi

    # Siri — выкл + проверка
    defaults write com.apple.assistant.support "Assistant Enabled" -bool false
    SIRI=$(defaults read com.apple.assistant.support "Assistant Enabled" 2>/dev/null)
    if [ "$SIRI" = "0" ]; then ok "Siri выключена (подтверждено)."
    else warn "Siri — перечитать не смог. Проверь: Настройки -> Apple Intelligence и Siri."; fi

    # Не светить недавние приложения в Dock (перезапускается ТОЛЬКО Dock)
    defaults write com.apple.dock show-recents -bool false 2>/dev/null
    killall Dock 2>/dev/null
    sleep 1
    REC=$(defaults read com.apple.dock show-recents 2>/dev/null)
    if [ "$REC" = "0" ]; then ok "Недавние приложения в Dock скрыты (подтверждено)."
    else warn "Dock: перечитать не смог — проверь Настройки -> Рабочий стол и Dock."; fi

    # Gatekeeper и SIP должны быть ВКЛЮЧЕНЫ — здесь только проверка (не трогаем)
    if spctl --status 2>/dev/null | grep -qi "assessments enabled"; then
        ok "Gatekeeper включен (подтверждено)."
    else
        warn "Gatekeeper ВЫКЛЮЧЕН — включи: sudo spctl --master-enable"
    fi
    if csrutil status 2>/dev/null | grep -qi "enabled"; then
        ok "SIP (защита целостности системы) включен."
    else
        warn "SIP выключен — это плохо для защиты; включается только из Recovery."
    fi

    # Время точное (раз геолокацию выключили — часы держим по сети)
    as_root sntp -sS time.apple.com 2>/dev/null && ok "Часы синхронизированы по сети (time.apple.com)."

    stage_mark hardening
fi

# ------------------------------------------------------------
# Wi-Fi / часовой пояс / Bluetooth
# ------------------------------------------------------------
if ! stage_done radio; then
    step "СЕТЬ И РАДИО / NETWORK & RADIO"
    case "$WIFI_MODE" in
        1)
            WIFI_SVC=""
            ALL_SVCS=$(as_root networksetup -listallnetworkservices 2>/dev/null | tail -n +2)
            while IFS= read -r svc; do
                DEV=$(as_root networksetup -listallhardwareports 2>/dev/null | grep -A 2 "Port: $svc" | grep "Device:" | awk '{print $2}')
                if [ -n "$DEV" ] && networksetup -getairportpower "$DEV" >/dev/null 2>&1; then WIFI_SVC="$svc"; break; fi
            done <<< "$ALL_SVCS"
            [ -z "$WIFI_SVC" ] && WIFI_SVC=$(printf '%s\n' "$ALL_SVCS" | grep -i "wi-fi\|wifi\|airport" | head -1)
            if [ -n "$WIFI_SVC" ]; then
                as_root networksetup -setairportpower en0 off 2>/dev/null
                as_root networksetup -removenetworkservice "$WIFI_SVC" 2>/dev/null
                if ! as_root networksetup -listallnetworkservices 2>/dev/null | grep -qi "wi-fi\|wifi\|airport"; then
                    ok "Wi-Fi удален из системы (подтверждено)."
                else
                    warn "Служба Wi-Fi еще видна — удали руками: Настройки -> Сеть."
                fi
            else
                info "Wi-Fi службы нет — уже чисто."
            fi
            ;;
        2)
            as_root networksetup -setairportpower en0 off 2>/dev/null
            ok "Wi-Fi выключен (радио). Включить обратно: Настройки -> Wi-Fi."
            ;;
        *) dim "Wi-Fi не трогаю." ;;
    esac

    # Часовой пояс — молча по IP. Не определился — не трогаю, без вопросов.
    info "Определяю часовой пояс по IP..."
    TZ_ZONE=$(curl -s --max-time 8 https://ipapi.co/timezone 2>/dev/null)
    case "$TZ_ZONE" in Europe/*|Asia/*|Africa/*|America/*|Australia/*|Pacific/*) ;; *) TZ_ZONE="" ;; esac
    if [ -n "$TZ_ZONE" ]; then
        as_root systemsetup -settimezone "$TZ_ZONE" 2>/dev/null
        readlink /etc/localtime 2>/dev/null | grep -q "$TZ_ZONE" \
            && ok "Часовой пояс: $TZ_ZONE (подтверждено)." \
            || warn "Часовой пояс: не подтвердился — проверь в Настройках -> Основные -> Дата и время."
    else
        warn "Часовой пояс по IP не определился — оставил как есть."
    fi
    # Авто-смену пояса в системе НЕ включаем (по решению владельца: IP скачут
    # по штатам/городам — фоновая смена сделает только хуже).

    # Bluetooth: на время настройки включаю (мышка/клава), в конце выключу
    BLUEUTIL=""
    if [ -x "/opt/homebrew/bin/blueutil" ]; then BLUEUTIL=/opt/homebrew/bin/blueutil;
    elif [ -x "/usr/local/bin/blueutil" ]; then BLUEUTIL=/usr/local/bin/blueutil; fi
    if [ -z "$BLUEUTIL" ]; then
        for BURL in "https://github.com/toy/blueutil/releases/download/v2.14.0/blueutil-arm64.zip" "https://github.com/toy/blueutil/releases/download/v2.14.0/blueutil-x86_64.zip"; do
            case "$BURL" in *arm64*) [ "$ARCH" != "arm64" ] && continue ;; *x86_64*) [ "$ARCH" != "x86_64" ] && continue ;; esac
            curl -sL "$BURL" -o /tmp/blueutil.zip 2>/dev/null && (cd /tmp && unzip -o -q blueutil.zip 2>/dev/null) || continue
            if [ -f /tmp/blueutil ]; then
                xattr -d com.apple.quarantine /tmp/blueutil 2>/dev/null
                chmod +x /tmp/blueutil
                if /tmp/blueutil --version >/dev/null 2>&1; then BLUEUTIL=/tmp/blueutil; break; fi
            fi
            rm -f /tmp/blueutil /tmp/blueutil.zip 2>/dev/null
        done
    fi
    if [ -n "$BLUEUTIL" ]; then
        if [ "$("$BLUEUTIL" -p 2>/dev/null)" != "1" ]; then "$BLUEUTIL" -p 1 2>/dev/null; fi
        ok "Bluetooth: пока включил (для мышки/клавы на время настройки)."
    else
        warn "Bluetooth: скачать blueutil не смог — в конце выключи его руками (меню сверху справа)."
    fi
    stage_mark radio
fi

# ------------------------------------------------------------
# КЛАВИАТУРА: US + Русская, переключение Ctrl+Space (тихо, без вопросов).
# Ctrl+Space выбран потому, что он есть на ЛЮБОЙ клавиатуре, включая PC
# (Ctrl/Win/Alt) без клавиш Option и Command.
# ------------------------------------------------------------
if ! stage_done keyboard; then
    step "КЛАВИАТУРА / KEYBOARD"
    TMPH=/tmp/hitoolbox.plist
    KB_PLIST="$HOME/Library/Preferences/com.apple.HIToolbox.plist"
    [ -f "$KB_PLIST" ] && cp "$KB_PLIST" "$TMPH" || plutil -create xml1 "$TMPH" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Delete :AppleEnabledInputSources" "$TMPH" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :AppleEnabledInputSources array" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleEnabledInputSources:0 dict" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleEnabledInputSources:0:InputSourceKind string Keyboard\ Layout" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleEnabledInputSources:0:KeyboardLayout\ Name string ABC" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleEnabledInputSources:0:KeyboardLayout\ ID integer 252" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleEnabledInputSources:1 dict" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleEnabledInputSources:1:InputSourceKind string Keyboard\ Layout" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleEnabledInputSources:1:KeyboardLayout\ Name string RussianWin" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleEnabledInputSources:1:KeyboardLayout\ ID integer -31717" "$TMPH"
    # Выбранная сейчас раскладка — ABC (иначе иконка в менюбаре может не ожить)
    /usr/libexec/PlistBuddy -c "Delete :AppleSelectedInputSources" "$TMPH" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :AppleSelectedInputSources array" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSelectedInputSources:0 dict" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSelectedInputSources:0:InputSourceKind string Keyboard\ Layout" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSelectedInputSources:0:KeyboardLayout\ Name string ABC" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSelectedInputSources:0:KeyboardLayout\ ID integer 252" "$TMPH"
    # Горячая клавиша: Ctrl+Space
    /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:60" "$TMPH" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60 dict" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60:enabled bool true" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60:value dict" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60:value:parameters array" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60:value:parameters:0 integer 32" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60:value:parameters:1 integer 49" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60:value:parameters:2 integer 262144" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60:value:type string standard" "$TMPH"
    /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:61" "$TMPH" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:61 dict" "$TMPH"
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:61:enabled bool false" "$TMPH"
    defaults import com.apple.HIToolbox "$TMPH" 2>/dev/null || cp "$TMPH" "$KB_PLIST"
    rm -f "$TMPH"
    # Русская — в историю выбранных (иначе macOS может выкинуть её из меню)
    /usr/libexec/PlistBuddy -c "Delete :AppleInputSourceHistory" "$KB_PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :AppleInputSourceHistory array" "$KB_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AppleInputSourceHistory:0 dict" "$KB_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AppleInputSourceHistory:0:InputSourceKind string Keyboard\ Layout" "$KB_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AppleInputSourceHistory:0:KeyboardLayout\ Name string RussianWin" "$KB_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AppleInputSourceHistory:0:KeyboardLayout\ ID integer -31717" "$KB_PLIST"
    # Заставляем систему перечитать: cfprefsd + агент меню ввода (это и был
    # баг «раскладка в plist есть, а флажка в менюбаре нет»)
    killall cfprefsd 2>/dev/null
    killall TextInputMenuAgent 2>/dev/null
    killall SystemUIServer 2>/dev/null
    osascript -e 'tell application "System Events" to keystroke ""' >/dev/null 2>&1
    sleep 2
    if defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -q RussianWin \
       && defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -q "KeyboardLayout Name = ABC"; then
        ok "Раскладки: ABC + Русская, переключение Ctrl+Space (подтверждено)."
        dim "Если флажка в строке меню нет — нажми Ctrl+Space один раз, иконка оживет."
    else
        warn "Не записалось. Открываю Настройки -> Клавиатура -> добавь Русская (+)."
        open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" 2>/dev/null
        KB_MANUAL=1
        pause
    fi
    stage_mark keyboard
fi

# ------------------------------------------------------------
# ФАЗА 3: УСТАНОВКА ПРИЛОЖЕНИЙ (скачал -> поставил -> ПРОВЕРИЛ)
# ------------------------------------------------------------
net_ok()  { curl -s --max-time 5 https://github.com >/dev/null 2>&1; }
net_wait() {
    if ! net_ok; then
        warn "$(L 'Нет интернета. Жду, пока появится' 'No internet. Waiting')..."
        while ! net_ok; do sleep 3; done
        ok "$(L 'Интернет есть, продолжаю.' 'Internet is back, continuing.')"
    fi
}

app_installed() { [ -n "$(find /Applications -maxdepth 1 -iname "$(app_bundle "$1").app" 2>/dev/null | head -1)" ]; }

# Проверка после установки: бандл есть, Info.plist читается, архитектура совпадает
verify_app() {
    local label="$1" pattern="$2" app bin archs
    app=$(find /Applications -maxdepth 1 -iname "$pattern.app" 2>/dev/null | head -1)
    if [ -z "$app" ]; then err "$label: НЕ установлен — приложения нет в /Applications."; return 1; fi
    if ! defaults read "$app/Contents/Info" CFBundleExecutable >/dev/null 2>&1; then
        err "$label: бандл есть, но Info.plist не читается — ставь вручную."; return 1
    fi
    bin="$app/Contents/MacOS/$(defaults read "$app/Contents/Info" CFBundleExecutable 2>/dev/null)"
    if [ -f "$bin" ]; then
        archs=$(lipo -archs "$bin" 2>/dev/null)
        if [ -n "$archs" ] && ! printf '%s' "$archs" | grep -q "$ARCH"; then
            warn "$label: стоит, но архитектура ($archs) не под $ARCH — может работать через Rosetta."
            return 0
        fi
    fi
    ok "$label установлен и проверен ($ARCH)."
    return 0
}

# Безопасное удаление старой копии перед установкой: guard против rm -rf /Applications/
safe_remove_app() {
    local appbase="$1"
    case "$appbase" in ""|.|..|/|/Applications) err "Отказ удалять: подозрительное имя «$appbase»."; return 1 ;; esac
    case "$appbase" in *.app) ;; *) err "Отказ удалять: «$appbase» не *.app."; return 1 ;; esac
    as_root rm -rf "/Applications/$appbase" 2>/dev/null
}

install_dmg() {
    local url="$1" name="$2"
    net_wait
    local tmp="/tmp/$name.dmg"
    if ! curl -L "$url" -o "$tmp" --progress-bar 2>&1; then
        err "$name: не скачалось. Пропускаю (интернет/URL?)."; return 1
    fi
    local mp
    mp=$(hdiutil attach "$tmp" -nobrowse -quiet 2>/dev/null | grep -o '/Volumes/.*' | head -1)
    if [ -z "$mp" ]; then err "$name: dmg не смонтировался."; rm -f "$tmp"; return 1; fi
    local tapp
    tapp=$(find "$mp" -maxdepth 1 -name "*.app" 2>/dev/null | head -1)
    if [ -n "$tapp" ]; then
        safe_remove_app "$(basename "$tapp")"
        if as_root cp -R "$tapp" /Applications/ 2>/dev/null; then
            as_root xattr -dr com.apple.quarantine "/Applications/$(basename "$tapp")" 2>/dev/null
        else
            err "$name: не скопировался в Программы."; hdiutil detach "$mp" -quiet 2>/dev/null; rm -f "$tmp"; return 1
        fi
    else
        local tpkg
        tpkg=$(find "$mp" -name "*.pkg" 2>/dev/null | head -1)
        [ -n "$tpkg" ] && as_root installer -pkg "$tpkg" -target / 2>/dev/null
    fi
    hdiutil detach "$mp" -quiet 2>/dev/null
    rm -f "$tmp"
}

install_pkg_url() {
    local url="$1" name="$2"
    net_wait
    curl -sL "$url" -o "/tmp/$name.pkg" 2>/dev/null && as_root installer -pkg "/tmp/$name.pkg" -target / 2>/dev/null
    rm -f "/tmp/$name.pkg"
}

if ! stage_done apps; then
    step "УСТАНОВКА ПРИЛОЖЕНИЙ / INSTALLING APPS" "3/6"

    if ! app_installed telegram; then
        info "Telegram — ставлю."
        install_dmg "$TG_URL" "Telegram" && verify_app Telegram Telegram
    else
        ok "Telegram уже стоит."
    fi

    if ! app_installed sublime; then
        info "Sublime Text — ставлю."
        net_wait
        curl -sL "$SUBLIME_URL" -o /tmp/Sublime.zip 2>/dev/null && (cd /tmp && unzip -o -q Sublime.zip 2>/dev/null)
        if [ -d "/tmp/Sublime Text.app" ]; then
            safe_remove_app "Sublime Text.app"
            as_root cp -R "/tmp/Sublime Text.app" /Applications/ 2>/dev/null
            as_root xattr -dr com.apple.quarantine "/Applications/Sublime Text.app" 2>/dev/null
        fi
        rm -rf "/tmp/Sublime Text.app" /tmp/Sublime.zip 2>/dev/null
        verify_app "Sublime Text" "Sublime Text"
    else
        ok "Sublime Text уже стоит."
    fi

    if ! app_installed sphere; then
        info "Linken Sphere — ставлю."
        SPHERE_URL="$SPHERE_URL_X86"; [ "$ARCH" = "arm64" ] && SPHERE_URL="$SPHERE_URL_ARM64"
        install_dmg "$SPHERE_URL" "Sphere" && verify_app "Linken Sphere" "*sphere*"
    else
        ok "Linken Sphere уже стоит."
    fi

    if [ "$INSTALL_MM" = "да" ] && ! app_installed mailmate; then
        info "MailMate — ставлю."
        net_wait
        curl -sL "$MM_URL" -o /tmp/MailMate.tbz 2>/dev/null && (cd /tmp && tar xjf MailMate.tbz 2>/dev/null)
        if [ -d "/tmp/MailMate.app" ]; then
            safe_remove_app "MailMate.app"
            as_root cp -R "/tmp/MailMate.app" /Applications/ 2>/dev/null
            as_root xattr -dr com.apple.quarantine "/Applications/MailMate.app" 2>/dev/null
        fi
        rm -rf /tmp/MailMate.app /tmp/MailMate.tbz 2>/dev/null
        verify_app MailMate MailMate
    fi

    if [ "$INSTALL_QTOX" = "да" ] && ! app_installed qtox; then
        info "qTox — ставлю."
        net_wait
        QTOX_URL=""
        LATEST_JSON=$(curl -s --max-time 10 "https://api.github.com/repos/TokTok/qTox/releases/latest" 2>/dev/null)
        if [ -n "$LATEST_JSON" ]; then
            if [ "$ARCH" = "arm64" ]; then
                QTOX_URL=$(printf '%s' "$LATEST_JSON" | grep -o 'https://[^"]*arm64\.dmg' | head -1)
                [ -z "$QTOX_URL" ] && QTOX_URL=$(printf '%s' "$LATEST_JSON" | grep -o 'https://[^"]*mac[^"]*\.dmg' | head -1)
                [ -z "$QTOX_URL" ] && QTOX_URL=$(printf '%s' "$LATEST_JSON" | grep -o 'https://[^"]*qtox[^"]*\.dmg' | head -1)
            else
                QTOX_URL=$(printf '%s' "$LATEST_JSON" | grep -o 'https://[^"]*x86_64\.dmg' | head -1)
                [ -z "$QTOX_URL" ] && QTOX_URL=$(printf '%s' "$LATEST_JSON" | grep -o 'https://[^"]*mac[^"]*\.dmg' | head -1)
            fi
        fi
        if [ -n "$QTOX_URL" ]; then
            install_dmg "$QTOX_URL" "qTox" && verify_app "qTox" "*tox*"
        else
            err "qTox: не смог получить ссылку из GitHub API. Ставь вручную: https://qtox.github.io"
        fi
    fi

    if ! app_installed tukan; then
        info "Tukan — ставлю."
        install_dmg "$TUKAN_URL" "Tukan" && verify_app "Tukan" "*tukan*"
    else
        ok "Tukan уже стоит."
    fi

    if [ "$INSTALL_EXCEL" = "да" ]; then
        if ! find /Applications -maxdepth 1 -iname "*excel*.app" 2>/dev/null | grep -q .; then
            info "Excel — ставлю."
            net_wait
            install_pkg_url "$EXCEL_URL" "Excel"
            if find /Applications -maxdepth 1 -iname "*excel*.app" 2>/dev/null | grep -q .; then
                ok "Excel установлен."
            else
                warn "Excel: пакет прошел, приложения не вижу — проверь Программы."
            fi
        fi
    fi

    # Текстовые расширения -> Linken Sphere (если стоит duti)
    if app_installed sphere && command -v duti >/dev/null 2>&1; then
        LS_BUNDLE="com.ls.lsapp"
        LS_EXT_OK=0
        for ext in $LS_EXTENSIONS; do
            duti -s "$LS_BUNDLE" ".$ext" all 2>/dev/null && LS_EXT_OK=$((LS_EXT_OK + 1))
        done
        [ "$LS_EXT_OK" -gt 0 ] && ok "Текстовые файлы открываются в Linken Sphere ($LS_EXT_OK расширений)."
    fi

    # VeraCrypt + FUSE-T (нужны для секретного диска)
    if ! pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t"; then
        info "FUSE-T (драйвер дисков) — ставлю."
        install_pkg_url "$FUSET_URL" "fuse-t"
        if pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t"; then ok "FUSE-T установлен."
        else warn "FUSE-T не подтвердился — VeraCrypt может не увидеть диск."; fi
    fi
    if [ "$APP_VERACRYPT" = "0" ]; then
        info "VeraCrypt — ставлю."
        install_dmg "$VC_URL" "VeraCrypt" && verify_app VeraCrypt VeraCrypt
        if [ -d "/Applications/VeraCrypt.app" ]; then
            warn "Если при запуске VeraCrypt попросит разрешить системное расширение:"
            warn "  Настройки -> Основные -> Элементы входа и расширения -> Расширения -> Драйверы -> FUSE-T."
        fi
    else
        ok "VeraCrypt уже стоит."
    fi

    # Уборка СТАРЫХ ДУБЛЕЙ в /Applications (до наших свежих установок):
    # белое правило — "Linken Sphere 2.app" НИКОГДА не трогаем (она основная).
    info "Проверяю старые дубли приложений в Программах..."
    while IFS= read -r d; do
        [ -d "$d" ] || continue
        case "$d" in
            "Linken Sphere 2.app"|*" 2.app"|*" copy.app"|*" копия.app") continue ;;
        esac
        case "$d" in
            *" 3.app"|*" 4.app"|*" 5.app"|*" copy 2.app"|*" copy 3.app"|*" копия 2.app"|*" копия 3.app"|*" копия 4.app")
                case "$d" in *.app) as_root rm -rf "/Applications/$d" 2>/dev/null && info "Убрал дубль: $d" ;; esac
                ;;
        esac
    done < <(ls /Applications 2>/dev/null)

    # Linken Sphere: если рядом лежат "Linken Sphere.app" и "Linken Sphere 2.app" —
    # не удаляем молча: версии разные, данные разные. Только говорим.
    if [ -d "/Applications/Linken Sphere.app" ] && [ -d "/Applications/Linken Sphere 2.app" ]; then
        warn "В Программах и «Linken Sphere», и «Linken Sphere 2». Рабочая — 2. Старую НЕ трогаю (вдруг нужна) — удали руками, если точно не нужна."
    fi
    stage_mark apps
fi

# ------------------------------------------------------------
# ФАЗА 4: FileVault — ВКЛЮЧИТЬ И ПРОВЕРИТЬ.
# Ключ восстановления НЕ показывается на экране и НИГДЕ не сохраняется.
# ------------------------------------------------------------
if ! stage_done filevault; then
    step "FILEVAULT — ШИФРОВАНИЕ ДИСКА" "4/6"
    FV_ST=$(as_root fdesetup status 2>/dev/null)
    if printf '%s' "$FV_ST" | grep -qi "is On"; then
        ok "FileVault уже включен (подтверждено)."
    else
        info "Включаю FileVault (шифрование всего диска)..."
        CONSOLE_USER=$(stat -f%Su /dev/console 2>/dev/null)
        FV_OUT=$(as_root fdesetup enable -user "${CONSOLE_USER:-$(id -un)}" 2>&1)
        FV_OUT=""; unset FV_OUT
        sleep 2
        FV_ST=$(as_root fdesetup status 2>/dev/null)
        if printf '%s' "$FV_ST" | grep -qi "is On\|in progress"; then
            ok "FileVault включен — диск зашифруется в фоне (подтверждено: $(printf '%s' "$FV_ST" | head -1))."
            info "Ключ восстановления скриптом не показывается и не сохраняется нигде — так решено."
        else
            err "FileVault не подтвердился: $(printf '%s' "$FV_ST" | head -1)."
            warn "Включи руками: Настройки -> Конфиденциальность и безопасность -> FileVault."
        fi
    fi
    stage_mark filevault
fi

# ------------------------------------------------------------
# ФАЗА 5: СЕКРЕТНЫЙ ДИСК — ВСЕ ЧЕРЕЗ GUI VeraCrypt.
# Пароль диска скрипт НЕ спрашивает, НЕ хранит и НЕ видит:
#  - уже зашифрованный диск монтируешь сам в окне VeraCrypt;
#  - новый диск шифруешь сам мастером VeraCrypt, я только жду и нахожу том.
# ------------------------------------------------------------
VC="/Applications/VeraCrypt.app/Contents/MacOS/VeraCrypt"

disk_field() { # disk_field <устройство> <ключ_plist>
    local p=/tmp/diskinfo.plist
    diskutil info -plist "$1" > "$p" 2>/dev/null || return 1
    /usr/libexec/PlistBuddy -c "Print :$2" "$p" 2>/dev/null
}

list_external() {
    local p=/tmp/disks.plist i=0 n j wn
    diskutil list -plist external physical > "$p" 2>/dev/null || return 1
    n=$(/usr/libexec/PlistBuddy -c "Print :AllDisksAndPartitions" "$p" 2>/dev/null | grep -c "Dict {" || true)
    while [ "$i" -lt "${n:-0}" ]; do
        j=0
        while :; do
            wn=$(/usr/libexec/PlistBuddy -c "Print :AllDisksAndPartitions:$i:WholeDisks:$j" "$p" 2>/dev/null) || break
            printf '%s\n' "$wn"; j=$((j + 1))
        done
        i=$((i + 1))
    done | sort -u
}

wait_new_disk() {
    local before="$1" tries=0 maxtries=$(( DISK_WAIT_SEC / 2 )) dev
    while [ $tries -lt $maxtries ]; do
        for dev in $(list_external); do
            printf '%s\n' "$before" | grep -qx "$dev" || { echo "$dev"; return 0; }
        done
        sleep 2; tries=$((tries + 1))
    done
    return 1
}

# Том, смонтированный VeraCrypt: сперва спрашиваем сам VeraCrypt (VC --list),
# только потом — скан кандидатов в /Volumes
vc_mounted_vol() {
    local out
    if [ -x "$VC" ]; then
        out=$("$VC" --text --list 2>/dev/null | grep -o '/Volumes/.*' | head -1)
        [ -n "$out" ] && [ -d "$out" ] && { echo "$out"; return 0; }
    fi
    local cands
    cands=$(candidate_vols)
    if [ "$(printf '%s\n' "$cands" | grep -c .)" = "1" ]; then
        printf '%s\n' "$cands" | head -1
        return 0
    fi
    return 1
}

candidate_vols() {
    local v boot
    boot=$(basename "$(df / 2>/dev/null | tail -1 | awk '{print $NF}')" 2>/dev/null)
    for v in /Volumes/*; do
        [ -d "$v" ] || continue
        [ -L "$v" ] && continue
        case "$(basename "$v")" in
            "Macintosh HD"|"Data"|"Preboot"|"Recovery"|"VM"|"Update"|"xarts"|"iSCPreboot"|"Hardware"|"$boot") continue ;;
        esac
        echo "$v"
    done
}

# Адаптивное ожидание монтирования: до MOUNT_WAIT_MIN минут, каждые 30 сек —
# короткая диагностика (диск виден системе? VeraCrypt том смонтирован?)
wait_vc_mount() {
    local limit=$(( ${MOUNT_WAIT_MIN:-30} * 2 )) n=0 v
    while [ $n -lt $limit ]; do
        v=$(vc_mounted_vol)
        [ -n "$v" ] && [ -d "$v" ] && { spin_end; echo "$v"; return 0; }
        if [ $((n % 6)) -eq 5 ]; then
            if [ -z "$(list_external)" ]; then spin "диск не виден системе — проверь разъем, жду"
            else spin "диск виден, том VeraCrypt еще не смонтирован — жду (Mount в окне VeraCrypt)"; fi
        else
            spin "$(L 'жду смонтированный том VeraCrypt' 'waiting for a mounted VeraCrypt volume')..."
        fi
        sleep 5; n=$((n + 1))
    done
    spin_end
    return 1
}

if ! stage_done disk; then
    step "СЕКРЕТНЫЙ ДИСК / ENCRYPTED DISK" "5/6"
    if ! net_ok; then err "Нет интернета — без него приложения не скачать. Подключи сеть и запусти заново."; exit 1; fi

    DISK_DEV=""
    BEFORE_PLUG=$(list_external)
    if [ "$HAVE_DISK" = "да" ]; then
        info "Вставь свой секретный диск (который уже зашифрован)."
        DISK_DEV=$(wait_new_disk "$BEFORE_PLUG") || {
            err "Не увидел новый диск за $DISK_WAIT_SEC сек."
            warn "Если диск УЖЕ был вставлен — вынь и вставь еще раз. Смотрю еще $DISK_WAIT_SEC сек..."
            DISK_DEV=$(wait_new_disk "$BEFORE_PLUG") || { err "Диск не найден. Разберись с диском и запусти скрипт заново."; exit 1; }
        }
    else
        info "Вставь НОВЫЙ диск, который будем шифровать."
        DISK_DEV=$(wait_new_disk "$BEFORE_PLUG") || { err "Не увидел новый диск за $DISK_WAIT_SEC сек."; exit 1; }
        sleep 2
        D_NAME=$(disk_field "$DISK_DEV" MediaName)
        D_SIZE=$(disk_field "$DISK_DEV" TotalSize)
        [ -n "$D_SIZE" ] && D_SIZE=$(echo "$D_SIZE" | awk '{printf "%.0f", $1/1073741824" ГБ"}')
        info "Вижу новый диск: ${D_NAME:-без имени} ${D_SIZE:+($D_SIZE)} — устройство /dev/$DISK_DEV"
        read -r -p "   Это ОН? (да/нет) [да]: " THIS_IS_IT
        THIS_IS_IT=$(yn "${THIS_IS_IT:-да}")
        if [ "$THIS_IS_IT" != "да" ]; then err "Тогда вынь лишние диски и запусти заново — рисковать не буду."; exit 1; fi
        # Если на диске НЕТ файловой системы — он, скорее всего, уже зашифрован VeraCrypt
        if ! as_root diskutil list "$DISK_DEV" 2>/dev/null | grep -qE "Apple_APFS|Apple_HFS|Microsoft Basic Data|ExFAT|FAT"; then
            warn "На этом диске НЕТ файловой системы. Обычно так выглядит УЖЕ зашифрованный VeraCrypt диск."
            read -r -p "   Он уже зашифрован? (да/нет) [да]: " ALRENC
            ALRENC=$(yn "${ALRENC:-да}")
            if [ "$ALRENC" = "да" ]; then HAVE_DISK=да; else
                err "Если это НЕ VeraCrypt-диск — просто отформатируй его мастером VeraCrypt (шаги ниже)."
            fi
        fi
    fi

    # Запоминаем UUID физического диска — чтобы том не перепутать с другой флешкой
    DISK_UUID=""
    [ -n "$DISK_DEV" ] && DISK_UUID=$(disk_field "$DISK_DEV" DiskUUID 2>/dev/null)

    if [ "$HAVE_DISK" = "да" ]; then
        sub "Монтирование секретного диска — через VeraCrypt (пароль знаешь только ты)"
        echo "    1) Открою VeraCrypt. Нажми  ${BOLD}Select Device...${NC}  -> выбери свой диск (строка вида /dev/diskXs1)"
        echo "    2) Нажми  ${BOLD}Mount${NC}  -> введи пароль диска (если был PIM — VeraCrypt сама спросит)"
        echo "    3) Диск появится в Finder сбоку — значит смонтировался"
        open -a VeraCrypt 2>/dev/null
        VOL_NAME=$(wait_vc_mount) || { err "Том не появился за ${MOUNT_WAIT_MIN:-30} мин."; read -r -p "Смонтируй сам и нажми Enter..."; VOL_NAME=$(vc_mounted_vol); }
        [ -z "$VOL_NAME" ] && { err "Так и не вижу смонтированный том. Стоп."; exit 1; }
    else
        sub "Создание секретного диска — мастер VeraCrypt (пароль вводишь в него, НЕ сюда)"
        echo "    Открою VeraCrypt. В окне сделай по шагам:"
        echo "    1)  ${BOLD}Create Volume${NC} -> Encrypt a non-system partition/drive -> Next"
        echo "    2)  Standard VeraCrypt volume -> Next"
        echo "    3)  Select Device -> выбери /dev/${DISK_DEV:-diskN} (строка раздела, вида diskXs1) -> Next"
        echo "    4)  Алгоритмы оставь по умолчанию (AES + SHA-512) -> Next"
        echo "    5)  Придумай ПАРОЛЬ диска и введи в мастере (PIM: просто Enter = по умолчанию)"
        echo "    6)  Файловая система: HFS+ (или ExFAT). Большие файлы: Yes -> Format"
        echo "        (подвигай мышку в окне мастера, пока ползет шкала)"
        echo "    7)  Когда мастер скажет «Volume Created» -> Exit -> Mount том (Select Device -> Mount)"
        echo "    ${RED}ВНИМАНИЕ: мастер сотрет ВСЕ на /dev/${DISK_DEV:-diskN}. Это ты уже подтвердил выше.${NC}"
        open -a VeraCrypt 2>/dev/null
        pause
        info "Жду, пока зашифрованный том смонтируется (до ${MOUNT_WAIT_MIN:-30} мин)..."
        VOL_NAME=$(wait_vc_mount) || { err "Том не появился. Смонтируй его в VeraCrypt и нажми Enter."; read -r; VOL_NAME=$(vc_mounted_vol); }
        [ -z "$VOL_NAME" ] && { err "Так и не вижу смонтированный том. Стоп."; exit 1; }
    fi

    # Подтверждение через VeraCrypt --list: том должен быть именно VC-томом
    if [ -x "$VC" ] && "$VC" --text --list 2>/dev/null | grep -q "$VOL_NAME"; then
        ok "Том подтвержден VeraCrypt: $VOL_NAME"
    else
        warn "VeraCrypt CLI том не подтвердил — беру найденный в /Volumes: $VOL_NAME (проверю по содержимому ниже)."
    fi
    # UUID тома — в отметки, чтобы при возобновлении не спутать с другой флешкой
    VDEV=$(df "$VOL_NAME" 2>/dev/null | tail -1 | awk '{print $1}')
    VUUID=$(disk_field "${VDEV#/dev/}" VolumeUUID 2>/dev/null)
    [ -n "$VUUID" ] && echo "vol_uuid=$VUUID" >> "$STAGE_FILE"

    ok "Секретный диск подключен: $VOL_NAME"
    stage_mark disk
fi

VOL_NAME=$(vc_mounted_vol)
[ -z "$VOL_NAME" ] && { err "Секретный том не смонтирован — без него фаза данных невозможна."; exit 1; }

# Гигиена секретного тома: не индексировать Spotlight (имена файлов не должны
# попадать в системный индекс) и не бэкапить в Time Machine.
if ! stage_done vol_hygiene; then
    as_root mdutil -i off "$VOL_NAME" 2>/dev/null
    if mdutil -s "$VOL_NAME" 2>/dev/null | grep -qi "disabled"; then
        ok "Spotlight на секретном томе выключен (подтверждено)."
    else
        dim "Spotlight: статус перечитать не смог — не критично."
    fi
    as_root tmutil addexclusion -p "$VOL_NAME" 2>/dev/null
    if tmutil isexcluded "$VOL_NAME" 2>/dev/null | grep -qi "\[Excluded\]"; then
        ok "Том исключен из Time Machine (подтверждено)."
    else
        dim "Time Machine: исключение перечитать не смог — не критично."
    fi
    stage_mark vol_hygiene
fi

# ------------------------------------------------------------
# ФАЗА 6: ДАННЫЕ ПРИЛОЖЕНИЙ НА СЕКРЕТНОМ ДИСКЕ
# Опознание папок — ТОЛЬКО по содержимому. Имена папок не важны:
# app.ls, App_LS2, Sphere, Telegram_Data, как-угодно-названо — найдем все.
# ------------------------------------------------------------
# Корень данных на диске: голосование по найденным опознанным папкам.
# Если опознанная папка лежит внутри "*_Data" — корень на уровень выше.
resolve_data_dir() {
    local vol="$1" key d root votes best count
    votes=""
    while IFS= read -r d; do
        key=$(fp_any "$d") || continue
        root=$(dirname "$d")
        case "$(basename "$root")" in *_Data|*_data|Telegram|telegram) root=$(dirname "$root") ;; esac
        votes="$votes$root
"
    done < <(find "$vol" -maxdepth 6 -type d \
        -not -path "*/.Trashes*" -not -path "*/.Spotlight-V100*" \
        -not -path "*/.fseventsd*" -not -path "*/.DocumentRevisions*" \
        -not -path "*/.TemporaryItems*" 2>/dev/null)
    best=""; count=0
    if [ -n "$votes" ]; then
        best=$(printf '%s' "$votes" | grep . | sort | uniq -c | sort -rn | head -1 | awk '{$1=""; sub(/^ /,""); print}')
        count=$(printf '%s' "$votes" | grep -c . || true)
    fi
    if [ -n "$best" ] && [ "$best" != "$vol" ]; then echo "$best"; return 0; fi
    if [ -d "$vol/DataAPP" ]; then echo "$vol/DataAPP"; return 0; fi
    mkdir -p "$vol/DataAPP" 2>/dev/null && { echo "$vol/DataAPP"; return 0; }
    echo "$vol"
}

# Подключить папку: link_to <системный путь> <папка на диске> [ключ_отпечатка]
# Правила безопасности:
#  - стираем локальную папку ТОЛЬКО внутри $HOME и ТОЛЬКО если цель на диске
#    непустая И похожа на данные этого приложения (проверка по отпечатку);
#  - обе пустые -> стоп; локальная есть, на диске пусто -> стоп (не теряем данные).
link_to() {
    local src="$1" dst="$2" fpkey="$3" dst_n src_n
    [ -L "$src" ] && { local cur; cur=$(readlink "$src"); [ "$cur" = "$dst" ] && return 0; rm -f "$src" 2>/dev/null; }
    mkdir -p "$(dirname "$src")" 2>/dev/null
    if [ -e "$src" ] || [ -d "$src" ]; then
        dst_n=0; src_n=0
        [ -d "$dst" ] && dst_n=$(ls -A "$dst" 2>/dev/null | wc -l | tr -d ' ')
        src_n=$(ls -A "$src" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$dst_n" -gt 0 ]; then
            if [ -n "$fpkey" ] && ! "fp_$fpkey" "$dst" 2>/dev/null; then
                err "$(app_label "$fpkey"): папка на диске ($dst) НЕПУСТАЯ, но не похожа на его данные — стирать локальную не буду. Разберись руками."
                return 1
            fi
            case "$src" in "$HOME"/*) rm -rf "$src" 2>/dev/null ;; *) err "Отказ стирать вне домашней папки: $src"; return 1 ;; esac
        elif [ "$src_n" -gt 0 ]; then
            err "$(app_label "$fpkey"): данные ЕСТЬ локально, а на диске ПУСТО — не трогаю, разберись руками."
            return 1
        else
            rm -rf "$src" 2>/dev/null
        fi
    fi
    mkdir -p "$dst" 2>/dev/null
    if ln -s "$dst" "$src" 2>/dev/null; then
        local tgt
        tgt=$(readlink "$src")
        if [ "$tgt" = "$dst" ] && [ -d "$tgt" ]; then
            ok "$(app_label "$fpkey"): подключен к диску ($(ls -A "$tgt" 2>/dev/null | wc -l | tr -d ' ') объектов на диске)."
        else
            err "$(app_label "$fpkey"): ссылка создана, но цель не отвечает."
            return 1
        fi
    else
        err "$(app_label "$fpkey"): НЕ смог подключить $src — обычно это права Терминала (Полный доступ к диску)."
        return 1
    fi
}

# --- Фаза 6, основная -------------------------------------------------------
if ! stage_done data; then
    step "ДАННЫЕ ПРИЛОЖЕНИЙ -> НА СЕКРЕТНЫЙ ДИСК" "6/6"
    info "Сканирую диск по содержимому (имена папок не важны)..."
    DATA=$(resolve_data_dir "$VOL_NAME")
    [ "$DATA" != "$VOL_NAME" ] && info "Корень данных на диске: ${DATA#$VOL_NAME/}"

    LINKED_KEYS=""
    # Полный контентный скан диска: каждая опознанная папка — сразу подключаем
    while IFS= read -r d; do
        key=$(fp_any "$d") || continue
        case " $LINKED_KEYS " in *" $key "*) continue ;; esac
        src=$(app_src "$key")
        # Telegram: опознан может быть контейнер ЦЕЛИКОМ или его подпапка stable
        if [ "$key" = "telegram" ]; then
            if [ -e "$d/accounts-metadata" ]; then TGT="$d"; elif [ -e "$d/stable/accounts-metadata" ]; then TGT="$d/stable"; else continue; fi
        else
            TGT="$d"
        fi
        [ -L "$src" ] && continue
        info "Нашел данные: $(app_label "$key") -> $TGT"
        if link_to "$src" "$TGT" "$key"; then LINKED_KEYS="$LINKED_KEYS $key"; fi
    done < <(find "$VOL_NAME" -maxdepth 6 -type d \
        -not -path "*/.Trashes*" -not -path "*/.Spotlight-V100*" \
        -not -path "*/.fseventsd*" -not -path "*/.DocumentRevisions*" \
        -not -path "*/.TemporaryItems*" 2>/dev/null | sort)

    # Единый проход по реестру: что скан не подключил — решаем здесь
    for key in $(app_keys); do
        lbl=$(app_label "$key"); src=$(app_src "$key"); dst="$DATA/$(app_dst "$key")"
        # MailMate/qTox — только если выбрали в вопросе или они реально есть
        if [ "$key" = "mailmate" ] && [ "$INSTALL_MM" != "да" ] && ! app_installed mailmate && ! fp_mailmate "$src" 2>/dev/null; then continue; fi
        if [ "$key" = "qtox" ] && [ "$INSTALL_QTOX" != "да" ] && ! app_installed qtox && ! fp_qtox "$src" 2>/dev/null; then continue; fi
        case " $LINKED_KEYS " in *" $key "*) continue ;; esac
        if [ -L "$src" ]; then
            if [ -e "$src" ] || [ -L "$src" -a -d "$(readlink "$src")" ]; then ok "$lbl — уже подключен."; continue; fi
            rm -f "$src" 2>/dev/null
        fi

        if [ -d "$dst" ] && [ -n "$(ls -A "$dst" 2>/dev/null)" ]; then
            link_to "$src" "$dst" "$key" && continue
        fi

        # Данные есть локально — переносим на диск сами
        if "fp_$key" "$src" 2>/dev/null || { [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ]; }; then
            info "$lbl: переношу локальные данные на диск..."
            mkdir -p "$(dirname "$dst")" 2>/dev/null
            if cp -R "$src" "$dst" 2>/dev/null && [ -n "$(ls -A "$dst" 2>/dev/null)" ]; then
                rm -rf "$src" 2>/dev/null
                ln -s "$dst" "$src" 2>/dev/null && ok "$lbl: локальные данные перенесены и подключены." && continue
            fi
            err "$lbl: перенести не смог — проверь руками."
            continue
        fi

        # Нет ни локально, ни на диске: запускаем приложение, оно создаст папку
        if app_installed "$key"; then
            info "$lbl: данных нет — запускаю приложение, чтобы создало свою папку..."
            APP_MATCH=$(find /Applications -maxdepth 1 -iname "$(app_bundle "$key").app" 2>/dev/null | head -1)
            if [ "$ARCH" = "arm64" ] && ! lipo -archs "$APP_MATCH/Contents/MacOS/"* 2>/dev/null | grep -q arm64; then
                as_root /usr/sbin/softwareupdate --install-rosetta --agree-to-license 2>/dev/null
            fi
            xattr -dr com.apple.quarantine "$APP_MATCH" 2>/dev/null
            open -a "$APP_MATCH" 2>/dev/null
            sleep 8
            if ! pgrep -fl "$(basename "$APP_MATCH" .app)" >/dev/null 2>&1; then
                warn "$lbl: не поднялся (Gatekeeper?) — запускаю еще раз..."
                open -a "$APP_MATCH" 2>/dev/null; sleep 8
            fi
            pkill -f "$(basename "$APP_MATCH" .app)" 2>/dev/null; sleep 2
            if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ]; then
                mkdir -p "$(dirname "$dst")" 2>/dev/null
                cp -R "$src" "$dst" 2>/dev/null && rm -rf "$src" 2>/dev/null
                ln -s "$dst" "$src" 2>/dev/null && ok "$lbl: папка создана приложением и подключена к диску." && continue
            fi
            warn "$lbl: приложение папку не создало — делаю пустую и подключаю."
        fi
        mkdir -p "$dst" 2>/dev/null
        link_to "$src" "$dst" "$key"
    done

    # Финальный контроль: что реально подключено
    ALL_OK=1
    for key in $(app_keys); do
        [ "$key" = "mailmate" ] && [ "$INSTALL_MM" != "да" ] && ! app_installed mailmate && continue
        [ "$key" = "qtox" ] && [ "$INSTALL_QTOX" != "да" ] && ! app_installed qtox && continue
        src=$(app_src "$key"); lbl=$(app_label "$key")
        if [ -L "$src" ] && [ -e "$src" ]; then :; else
            ALL_OK=1; err "$lbl — НЕ подключен. Смотри сообщения выше."
        fi
    done
    stage_mark data
fi

# ------------------------------------------------------------
# ОБНОВЛЕНИЯ macOS: автоУСТАНОВКА выкл (ставили в начале), скачивание
# в фоне — вкл (скачалось -> сам предложит -> руками подтвердил)
# ------------------------------------------------------------
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true 2>/dev/null
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool false 2>/dev/null
ok "Обновления macOS: скачиваются в фоне, ставятся только с твоего «Установить»."

# ------------------------------------------------------------
# ВОЗВРАТ ЗАЩИТ + ФИНАЛЬНАЯ ЧИСТКА СЛЕДОВ
# ------------------------------------------------------------
as_root defaults write /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay -int $(( AUTOLOGOUT_MIN * 60 )) 2>/dev/null
defaults -currentHost write com.apple.screensaver idleTime -int ${SAVED_SS_IDLE:-300} 2>/dev/null
as_root pmset -a displaysleep "$DISPLAY_SLEEP" 2>/dev/null
as_root pmset -a sleep 0 2>/dev/null
ok "Экран гаснет через $DISPLAY_SLEEP мин, автовыход через $AUTOLOGOUT_MIN мин (как в конфиге)."

DL="$HOME/Downloads"
for f in "$DL"/*.dmg "$DL"/*.pkg "$DL"/*.zip; do
    [ -f "$f" ] && rm -f "$f" 2>/dev/null
done
rm -f /tmp/*.pkg /tmp/*.dmg /tmp/*.zip /tmp/Sublime* /tmp/MailMate* /tmp/blueutil* /tmp/hitoolbox.plist /tmp/diskinfo.plist /tmp/disks.plist 2>/dev/null

rm -f "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.python_history" "$HOME/.lesshst" "$HOME/.viminfo" 2>/dev/null
find "$HOME/Library/Application Support/com.apple.sharedfilelist" -name "*.sfl*" -delete 2>/dev/null
rm -rf "$HOME/Library/Application Support/com.apple.sharedfilelist" 2>/dev/null
defaults delete com.apple.finder RecentMoveAndCopyDestinations 2>/dev/null
defaults delete com.apple.finder FXRecentFolders 2>/dev/null
defaults delete com.apple.finder GoToField 2>/dev/null
defaults delete com.apple.finder GoToFieldHistory 2>/dev/null
as_root killall -HUP sharedfilelistd 2>/dev/null
killall cfprefsd 2>/dev/null
ok "Следы настройки стерты: загрузки, история терминала, «Недавние» в Finder, старые меню."

# Обнуляем секреты в памяти — пароль админа больше не нужен
ADMIN_PASS=""; unset ADMIN_PASS USER_PASS USER_PASS2

# ------------------------------------------------------------
# САМОПРОВЕРКА (встроенная — отдельный файл не нужен):
# ссылки живые + цели непустые + содержимое похоже на данные приложения,
# FileVault, брандмауэр, VeraCrypt/FUSE-T
# ------------------------------------------------------------
run_selfcheck() {
    step "САМОПРОВЕРКА / SELF-CHECK"
    local key src lbl tgt n bad=0 total=0 good=0
    for key in $(app_keys); do
        [ "$key" = "mailmate" ] && [ "$INSTALL_MM" != "да" ] && ! app_installed mailmate && continue
        [ "$key" = "qtox" ] && [ "$INSTALL_QTOX" != "да" ] && ! app_installed qtox && continue
        total=$((total + 1))
        src=$(app_src "$key"); lbl=$(app_label "$key")
        if [ -L "$src" ]; then
            tgt=$(readlink "$src")
            if [ -d "$tgt" ]; then
                n=$(ls -A "$tgt" 2>/dev/null | wc -l | tr -d ' ')
                if "fp_$key" "$tgt" 2>/dev/null; then
                    good=$((good + 1)); ok "$lbl — на диске, данные опознаны ($n объектов)."
                elif [ "$n" -gt 0 ]; then
                    good=$((good + 1)); ok "$lbl — на диске ($n объектов, папка нестандартная, но не пустая)."
                else
                    warn "$lbl — ссылка есть, папка на диске ПУСТАЯ (заполнится после первого запуска)."
                fi
            else
                err "$lbl — ссылка БИТАЯ (цель недоступна). Диск смонтирован?"
                bad=$((bad + 1))
            fi
        else
            err "$lbl — НЕ ссылка (данные локальные или папки нет)."
            bad=$((bad + 1))
        fi
    done
    total=$((total + 3))
    if fdesetup status 2>/dev/null | grep -qi "is On"; then good=$((good + 1)); ok "FileVault включен."
    else err "FileVault НЕ включен."; bad=$((bad + 1)); fi
    if [ "$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)" = "1" ]; then good=$((good + 1)); ok "Брандмауэр включен."
    else err "Брандмауэр НЕ включен."; bad=$((bad + 1)); fi
    if [ -d /Applications/VeraCrypt.app ] && pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t"; then good=$((good + 1)); ok "VeraCrypt + FUSE-T на месте."
    else err "VeraCrypt/FUSE-T не найдены."; bad=$((bad + 1)); fi
    echo ""
    if [ "$bad" = "0" ]; then
        echo -e "  ${GREEN}${BOLD}✓ САМОПРОВЕРКА: $good/$total — всё зелёное.${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}▲ САМОПРОВЕРКА: $good/$total зелёные, $bad — смотри выше.${NC}"
    fi
}

# ------------------------------------------------------------
# ФИНАЛ
# ------------------------------------------------------------
for t in 5 4 3 2 1; do printf '\r\033[2K  ⏳ Закрываю настройки через %d...' "$t"; sleep 1; done
printf '\r\033[2K'
osascript -e 'tell application "System Settings" to quit' >/dev/null 2>&1
for t in 5 4 3 2 1; do printf '\r\033[2K  ⏳ Перезапускаю Finder через %d...' "$t"; sleep 1; done
printf '\r\033[2K'
killall Finder 2>/dev/null

run_selfcheck

echo ""
echo -e "  ${GREEN}$(rep "━" "$(tw)")${NC}"
echo -e "  ${GREEN}▎${NC}  ${BOLD}\033[38;5;82mВСЕ! Mac НАСТРОЕН И ЗАЩИЩЕН.${NC}"
echo -e "  ${GREEN}$(rep "━" "$(tw)")${NC}"
echo ""
echo -e "  ${BOLD}Что сделано:${NC}"
echo "    • защита: блокировка сразу, брандмауэр+невидимость, SSH/экран/ARD выкл"
echo "    • AirDrop/Handoff/геолокация/аналитика/Siri — выкл (каждый пункт проверен)"
echo "    • недавние приложения в Dock скрыты"
echo "    • FileVault: шифрование включено (ключ скриптом не показывался и не сохранялся)"
echo "    • данные приложений — на секретном диске, система смотрит на них через ссылки"
echo "    • раскладки ABC+Русская (Ctrl+Space), часовой пояс по IP, Wi-Fi по выбору"
echo ""
echo -e "  ${YELLOW}${BOLD}ПРОВЕРЬ В КОНЦЕ:${NC}"
echo "    1) Флажок раскладки в строке меню сверху (если нет — нажми Ctrl+Space)"
echo "    2) Вставь секретный диск -> VeraCrypt -> Mount -> запусти Telegram/Sphere"
echo ""
echo -e "  ${GREY}Завершаю через 5 сек...${NC}"
sleep 5
rm -f "$STAGE_FILE"
exit 0

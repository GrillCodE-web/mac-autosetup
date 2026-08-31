#!/bin/bash

# ============================================================
#  АВТОНАСТРОЙКА MAC — ПОЛНЫЙ АВТОМАТ (v13)
#  Репозиторий: https://github.com/GrillCodE-web/mac-autosetup
#  Человеку нужно только: ответить на 5 вопросов и ввести пароль
# ============================================================

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Режим определяем ПЕРВЫМ делом: dry-run обещает «без единой мутации», поэтому
# он не должен успеть ничего удалить/создать до вывода плана.
DRY_RUN=0
[ "$1" = "--dry-run" ] && DRY_RUN=1

# Логи НЕ ведутся принципиально: любой файл с историей настройки — это след,
# который потом восстанавливается с диска. Все видно только на экране.
[ "$DRY_RUN" = "0" ] && rm -f /tmp/autosetup_log.txt /tmp/autosetup_commands.txt 2>/dev/null

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GREY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

readonly SCRIPT_VERSION="v13.1-2026.08.31 — геолокация по STIG (kill locationd + верификация демоном), Wi-Fi радио с фолбэком ifconfig для Tahoe, adprivacyd перезапуск после AdLib, живой URL панели Сети вместо мёртвого Network-Firewall, только Apple Silicon (Intel выпилен), поддержка macOS 14-15/26/27 (Ventura выпилена: EOL), умный режим: реестр приложений, опознание данных по содержимому, диск только через GUI VeraCrypt, FileVault через -inputplist без показа ключа, 5 вопросов, верификация защиты, лок от двойного запуска, встроенная самопроверка, расширения в Sublime через LaunchServices, Bluetooth без сторонних утилит, все расширения видны в Finder, честный dry-run (без единой мутации), возобновление после падения со сверкой тома по UUID, тайминг фаз, автообновление с GitHub, проверка версии macOS, проверка места на диске, Wi-Fi без хардкода en0, честные единицы скорости сети"
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
# Живой прогресс внутри фазы: перерисовывает одну строку
STEP_DONE=0; STEP_TOTAL=0
step_prog_init() { STEP_TOTAL=$1; STEP_DONE=0; }
step_prog() {
    [ "$STEP_TOTAL" -gt 0 ] || return 0
    STEP_DONE=$((STEP_DONE + 1))
    [ $STEP_DONE -gt $STEP_TOTAL ] && STEP_DONE=$STEP_TOTAL
    local w=22 filled i
    filled=$(( STEP_DONE * w / STEP_TOTAL ))
    printf '\r\033[2K    \033[0;36m' >&2
    i=0; while [ $i -lt $filled ]; do printf '█' >&2; i=$((i + 1)); done
    printf '\033[0;90m' >&2
    i=0; while [ $i -lt $((w - filled)) ]; do printf '░' >&2; i=$((i + 1)); done
    printf '\033[0m %s/%s %s' "$STEP_DONE" "$STEP_TOTAL" "${1:-}" >&2
    [ $STEP_DONE -eq $STEP_TOTAL ] && printf '\n' >&2
}
q()     { echo -e "  ${CYAN}${BOLD}[$1]${NC} ${BOLD}$2${NC}"; }
# Короткий звук без блокировки (не мешает прогону)
ding() { afplay /System/Library/Sounds/Glass.aiff >/dev/null 2>&1 & }
ding_subtle() { afplay /System/Library/Sounds/Pop.aiff >/dev/null 2>&1 & }
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

# --- Параметры и источники загрузок: живут ТОЛЬКО здесь ---------------------
# Внешнего конфига больше нет: autosetup.conf замораживал старые значения и
# молча перекрывал свежие дефолты после самообновления скрипта (так старый
# launchpad-URL качал VeraCrypt в мертвый хост вопреки новому коду).
# Поменять что-то — правится прямо тут. autosetup.conf игнорируется.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FUSET_URL="https://github.com/macos-fuse-t/fuse-t/releases/download/1.2.7/fuse-t-macos-installer-1.2.7.pkg"
# Основной источник — GitHub-релизы VeraCrypt: launchpadlibrarian.net (CDN
# launchpad.net) из части сетей просто недоступен (curl 28, таймаут 15 сек x3).
VC_URL="https://github.com/veracrypt/VeraCrypt/releases/download/VeraCrypt_1.26.29/VeraCrypt_FUSE-T_1.26.29.dmg"
VC_URL_ALT="https://launchpad.net/veracrypt/trunk/1.26.29/+download/VeraCrypt_FUSE-T_1.26.29.dmg"
TG_URL="https://telegram.org/dl/macos/stable"
SUBLIME_URL="https://download.sublimetext.com/sublime_text_build_4200_mac.zip"
SPHERE_URL_ARM64="https://cdn.ls.app/ls2_1.9.9_arm64.dmg"
TUKAN_URL="https://tukan.me/download/mac"
MM_URL="https://updates.mailmate-app.com/archives/MailMateBeta.tbz"
EXCEL_URL="https://go.microsoft.com/fwlink/?linkid=525135"
MOUNT_WAIT_MIN=30
DISK_WAIT_SEC=120
DISPLAY_SLEEP=5
AUTOLOGOUT_MIN=30
LS_EXTENSIONS="txt md markdown csv tsv json xml yaml yml log ini conf cfg env sh py js toml sql"
# Подчистка хвоста от старых версий скрипта: рядом мог остаться autosetup.conf
[ "$DRY_RUN" = "0" ] && rm -f "$SCRIPT_DIR/autosetup.conf" 2>/dev/null

[ "$DRY_RUN" = "1" ] && warn "РЕЖИМ DRY-RUN: только покажу план, ничего не изменю."

# Возобновление после падения: отметки о завершенных фазах живут в /tmp
# (сами стираются при перезагрузке). Успешный прогон удаляет файл в конце.
STAGE_FILE="/tmp/autosetup_stage"
stage_done() { grep -qx "$1" "$STAGE_FILE" 2>/dev/null; }
stage_mark() { echo "$1" >> "$STAGE_FILE"; }

# Тайминг фаз: phase_begin в начале, phase_end после stage_mark — сводка в финале
# Копим строки вида "<секунды>|<имя фазы>" с НАСТОЯЩИМИ переводами строк:
# два параллельных списка с литеральным "\n" раньше не разбирались и ломали t2s.
PHASE_LOG=""; _PHASE_T0=0
phase_begin() { _PHASE_T0=$SECONDS; }
phase_end() { # phase_end <имя фазы>
    [ -z "$1" ] && return 0
    local d=$(( SECONDS - _PHASE_T0 ))
    PHASE_LOG="${PHASE_LOG}${d}|${1}
"
}
phase_summary() {
    local line t name
    [ -z "$PHASE_LOG" ] && return 0
    sub "ВРЕМЯ ПО ФАЗАМ"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        t=${line%%|*}; name=${line#*|}
        case "$t" in ''|*[!0-9]*) t=0 ;; esac
        printf '    %s  %s\n' "$(t2s "$t")" "$name"
    done <<EOF
$PHASE_LOG
EOF
    ok "Весь прогон: $(t2s $SECONDS)"
}

as_root() { printf '%s\n' "$ADMIN_PASS" | sudo -S "$@"; }

# Проверка: мы на маке?
if [ "$(uname)" != "Darwin" ]; then
    err "Этот скрипт работает только на macOS."
    exit 1
fi

LOCK=/tmp/autosetup.lock
if [ "$DRY_RUN" = "0" ]; then
# Защита от двойного запуска: второй экземпляр не стартует, пока жив первый.
# Лок захватываем ДО установки trap: иначе выход второго экземпляра снес бы
# лок (и конфиг) живого первого.
if [ -f "$LOCK" ]; then
    OLD_PID=$(cat "$LOCK" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        err "Скрипт УЖЕ запущен (PID $OLD_PID). Дождись окончания или закрой то окно."
        exit 1
    fi
    rm -f "$LOCK"
fi
echo $$ > "$LOCK" 2>/dev/null

# На время настройки — не давать Mac гасить экран и засыпать
caffeinate -dimsu &
CAFFEINATE_PID=$!
cleanup_exit() {
    kill "$CAFFEINATE_PID" 2>/dev/null
    # wait съедает job-уведомление «Terminated: 15 caffeinate» — без него shell
    # печатал эту строку в терминал при каждом выходе из скрипта.
    wait "$CAFFEINATE_PID" 2>/dev/null
    # Снимаем ТОЛЬКО свой лок: чужой (живого экземпляра) не трогаем
    [ "$(cat "$LOCK" 2>/dev/null)" = "$$" ] && rm -f "$LOCK"
}
trap cleanup_exit EXIT
fi  # конец блока «только реальный прогон»: в dry-run ни лока, ни caffeinate

ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    err "Только Apple Silicon (arm64). Intel-маки больше не поддерживаются."
    exit 1
fi
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

# Проверка версии macOS: тестирован на 14-15 (Sonoma/Sequoia), 26 (Tahoe) и 27
# (Golden Gate). Ventura (13) выпилена: с выхода Tahoe патчей безопасности нет.
# На других — предупреждаю, но продолжаю (вдруг повезло).
MACOS_VER=$(sw_vers -productVersion 2>/dev/null)
MACOS_MAJOR=${MACOS_VER%%.*}
case "$MACOS_MAJOR" in
    14|15|26|27) : ;;
    13) warn "macOS 13 Ventura больше не получает обновления безопасности — обновись хотя бы до Sonoma." ;;
    *) warn "macOS $MACOS_VER не входит в тестированные (14-15, 26, 27). Продолжаю, но смотри глазами." ;;
esac

# Автопроверка обновления скрипта на GitHub (не навязчиво: только если есть сеть)
SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
REPO_RAW="https://raw.githubusercontent.com/GrillCodE-web/mac-autosetup/main"
SELF_VER_SHORT="${SCRIPT_VERSION%%-*}"          # например v12.5
REMOTE_VER=$(curl -s --max-time 5 "$REPO_RAW/MacForge.command" 2>/dev/null \
    | grep -m1 'readonly SCRIPT_VERSION=' | sed 's/.*readonly SCRIPT_VERSION="\(v[0-9.]*\).*/\1/')
if [ -n "$REMOTE_VER" ] && [ "$REMOTE_VER" != "$SELF_VER_SHORT" ]; then
    warn "На GitHub есть новая версия скрипта: $REMOTE_VER (у тебя $SELF_VER_SHORT)."
    # В dry-run только сообщаем: перезапись файла скрипта — это тоже мутация
    if [ "$DRY_RUN" = "1" ]; then
        dim "dry-run: обновляться не предлагаю."
        DO_UPD=нет
    else
        read -r -p "   Скачать и перезапуститься на новой? (да/нет) [нет]: " DO_UPD
    fi
    if [ "$(yn "${DO_UPD:-нет}")" = "да" ]; then
        if curl -fsL --max-time 30 "$REPO_RAW/MacForge.command" -o "$SELF_PATH.new" 2>/dev/null \
            && grep -q 'readonly SCRIPT_VERSION=' "$SELF_PATH.new"; then
            chmod +x "$SELF_PATH.new"; mv "$SELF_PATH.new" "$SELF_PATH"
            ok "Обновился до $REMOTE_VER. Перезапускаю..."
            rm -f "$LOCK"   # exec сохраняет PID — иначе новый процесс упрется в свой же лок
            exec "$SELF_PATH" "$@"
        else
            err "Не скачалось — остаюсь на $SELF_VER_SHORT."; rm -f "$SELF_PATH.new"
        fi
    fi
fi

# ------------------------------------------------------------
# РЕЕСТР ПРИЛОЖЕНИЙ — вся информация о приложениях в одном месте.
# Чтобы добавить приложение: одна строка в app_keys + ветки в функциях ниже.
# ------------------------------------------------------------
# >>> TESTABLE registry — область между маркерами вырезает tests/run_tests.sh
# и проверяет НАСТОЯЩИЙ код этих функций. Не добавлять сюда top-level команды.
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
        excel)    echo "Microsoft Excel" ;;
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
# <<< TESTABLE registry

# ------------------------------------------------------------
# ПРЕДПОЛЕТНАЯ ПРОВЕРКА: что уже стоит и куда уже подключено
# ------------------------------------------------------------
APP_TELEGRAM=0; APP_SUBLIME=0; APP_SPHERE=0; APP_TUKAN=0; APP_VERACRYPT=0; APP_MAILMATE=0; APP_QTOX=0
[ -d "/Applications/Telegram.app" ] && APP_TELEGRAM=1
[ -d "/Applications/Sublime Text.app" ] && APP_SUBLIME=1
[ -n "$(find /Applications -maxdepth 1 -iname '*sphere*.app' 2>/dev/null | head -1)" ] && APP_SPHERE=1
[ -n "$(find /Applications -maxdepth 1 -iname '*tukan*.app' 2>/dev/null | head -1)" ] && APP_TUKAN=1
[ -d "/Applications/VeraCrypt.app" ] && APP_VERACRYPT=1
[ -d "/Applications/MailMate.app" ] && APP_MAILMATE=1
[ -n "$(find /Applications -maxdepth 1 -iname 'qTox.app' 2>/dev/null | head -1)" ] && APP_QTOX=1

# Единый источник правды — реестр app_keys. Раньше рядом жили PRE_TG/PRE_ST/...
# с ручным маппингом ключей на имена переменных и eval; добавление приложения
# требовало правок в трех местах и легко рассинхронивалось.
precheck_link() { [ -L "$(app_src "$1")" ]; }
precheck_data() { "fp_$1" "$(app_src "$1")" 2>/dev/null; }

step "ПРЕДПОЛЕТНАЯ ПРОВЕРКА / PREFLIGHT CHECK"
for k in $(app_keys); do
    lbl=$(app_label "$k")
    if precheck_link "$k"; then ok "$lbl — данные уже подключены к диску."
    elif precheck_data "$k"; then dim "$lbl — еще не подключен (локальные данные есть)."
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
    # Логин валидируем: пустой или с пробелами/кириллицей создал бы битую запись
    while true; do
        read -r -p "   Логин латиницей, без пробелов (пример: work): " NEW_USER
        # Явный список символов, а не [a-z]: в UTF-8-локали диапазон захватил бы
        # и заглавные, и часть не-латиницы.
        case "$NEW_USER" in
            ""|*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*)
                err "Только строчные латинские буквы, цифры, _ и -." ;;
            -*|[0-9]*) err "Логин должен начинаться с буквы." ;;
            *) break ;;
        esac
    done
    read -r -p "   Отображаемое имя (пример: Work): " NEW_USER_NAME
    NEW_USER_NAME=${NEW_USER_NAME:-$NEW_USER}
    while true; do
        read -rs -p "   Пароль для НОВОЙ учетки: " USER_PASS; echo ""
        read -rs -p "   Еще раз: " USER_PASS2; echo ""
        if [ -n "$USER_PASS" ] && [ "$USER_PASS" = "$USER_PASS2" ]; then break; fi
        err "Пусто или не совпадает. Снова."
    done
fi

q 2 "Пароль от ТЕКУЩЕЙ учетной записи (админа) — нужен для настройки системы."
if [ "$DRY_RUN" = "1" ]; then
    # В dry-run пароль не нужен: sudo не вызывается, а лишний запрос пугает
    dim "dry-run: пароль не спрашиваю."
else
    while true; do
        read -rs -p "   Введи пароль (не отображается): " ADMIN_PASS; echo ""
        if printf '%s\n' "$ADMIN_PASS" | sudo -S -k true 2>/dev/null; then ok "Пароль верный, поехали."; break; fi
        err "Не подошел. Еще раз."
    done
fi

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
echo "   2 — просто выключить радио, можно вернуть в Настройках (на Tahoe при ошибке скрипт сам погасит через ifconfig)"
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

# --- DRY-RUN: печатаем план и выходим ДО любых изменений ---------------------
if [ "$DRY_RUN" = "1" ]; then
    step "ПЛАН (DRY-RUN — ничего не меняю)"
    [ "$CREATE_USER" = "да" ] && echo "  + создать учетку «$NEW_USER» (обычная)" || echo "  - учетку не создавать"
    echo "  + защита: блокировка сразу, брандмауэр+невидимость, гасить SSH/экран/ARD,"
    echo "    AirDrop/Handoff/геолокация/аналитика/Siri — выкл (каждый пункт с проверкой)"
    for k in $(app_keys); do
        lbl=$(app_label "$k"); bndl=$(app_bundle "$k")
        [ "$k" = "mailmate" ] && [ "$INSTALL_MM" != "да" ] && [ "$APP_MAILMATE" = "0" ] && continue
        [ "$k" = "qtox" ] && [ "$INSTALL_QTOX" != "да" ] && ! precheck_data qtox && continue
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
    exit 0
fi

# Ниже — ТОЛЬКО реальный прогон: гасим автовыход/заставку на время настройки
as_root defaults delete /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay 2>/dev/null
SAVED_SS_IDLE=$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null)
defaults -currentHost write com.apple.screensaver idleTime -int 0 2>/dev/null
ok "На время настройки: автовыход и заставка ВЫКЛЮЧЕНЫ — экран не погаснет и из системы не выкинет."

# АвтоУСТАНОВКУ обновлений macOS гасим СРАЗУ и держим выключенной до конца
as_root defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false 2>/dev/null

# ------------------------------------------------------------
# ФАЗА 1: ОТДЕЛЬНАЯ УЧЕТКА (каждый шаг dscl — с проверкой)
# ------------------------------------------------------------
if [ "$CREATE_USER" = "да" ] && ! stage_done user; then
    step "УЧЕТНАЯ ЗАПИСЬ / USER ACCOUNT" "1/6"
    phase_begin
    USER_STAGE_OK=0
    if id "$NEW_USER" &>/dev/null; then
        warn "Учетка «$NEW_USER» уже существует — пропускаю."
        USER_STAGE_OK=1
    else
        info "Создаю «$NEW_USER»..."
        OK_USER=1
        UID_TRY=$(dscl . -list /Users UniqueID 2>/dev/null | awk '$2>=500 && $2<600 {print $2}' | sort -n | tail -1)
        UID_TRY=$(( ${UID_TRY:-500} + 1 ))
        # Каждый вызов — отдельной командой с кавычками: имя из двух слов
        # («Work Mac») в общей строке разъезжалось на лишние аргументы dscl.
        dscl_step() { # dscl_step <описание> <аргументы dscl...>
            local d="$1"; shift
            as_root dscl . "$@" 2>/dev/null && return 0
            err "dscl: не выполнено — $d"; OK_USER=0; return 1
        }
        dscl_step "создание записи"   -create "/Users/$NEW_USER" \
            && dscl_step "оболочка"   -create "/Users/$NEW_USER" UserShell /bin/bash \
            && dscl_step "имя"        -create "/Users/$NEW_USER" RealName "$NEW_USER_NAME" \
            && dscl_step "UID"        -create "/Users/$NEW_USER" UniqueID "$UID_TRY" \
            && dscl_step "группа"     -create "/Users/$NEW_USER" PrimaryGroupID 20 \
            && dscl_step "домашняя"   -create "/Users/$NEW_USER" NFSHomeDirectory "/Users/$NEW_USER"
        if [ "$OK_USER" = "1" ]; then
            # Пароль — аргументом: пайп сломался бы (его съел бы sudo -S), а dscl
            # мог повиснуть на интерактивном запросе. В ps на миг виден — приемлемо.
            as_root dscl . -passwd "/Users/$NEW_USER" "$USER_PASS" 2>/dev/null
            as_root createhomedir -c -u "$NEW_USER" 2>/dev/null
        fi
        if [ "$OK_USER" = "1" ] && id "$NEW_USER" &>/dev/null; then
            ok "Учетка «$NEW_USER» создана и входит в систему (проверено)."
            USER_STAGE_OK=1
        else
            err "Учетка не создалась корректно — сделай вручную: Настройки -> Пользователи и группы."
        fi
        USER_PASS=""; USER_PASS2=""
    fi
    # Фазу отмечаем выполненной ТОЛЬКО при успехе: иначе следующий запуск
    # молча пропустит создание учетки, которой нет.
    [ "${USER_STAGE_OK:-0}" = "1" ] && stage_mark user
    phase_end "Учетная запись"
fi

# Маленький верификатор: записали ключ -> сразу перечитали
verify_default() { # verify_default <описание> <plist> <ключ> <ожидание> [root]
    local desc="$1" plist="$2" key="$3" want="$4" asroot="$5" got
    if [ "$asroot" = "root" ]; then
        got=$(as_root defaults read "$plist" "$key" 2>/dev/null)
    else
        got=$(defaults read "$plist" "$key" 2>/dev/null)
    fi
    if [ "$got" = "$want" ]; then ok "$desc (подтверждено)."
    else warn "$desc — записано, но перечитать не смог (значение: ${got:-пусто}). Проверь глазами."; fi
}

# ------------------------------------------------------------
# ФАЗА 2: БАЗОВАЯ ЗАЩИТА (каждый пункт — с перечитыванием)
# ------------------------------------------------------------
if ! stage_done hardening; then
    step "БАЗОВАЯ ЗАЩИТА / BASELINE SECURITY" "2/6"
    phase_begin

    # Пароль сразу после сна/заставки — ОДИН раз, с проверкой.
    # ДВЕ строки в пайпе: первую съедает sudo -S, вторую читает sysadminctl -password -.
    SL_MANUAL=0
    # sysadminctl дергаем от САМОГО пользователя, без sudo: настройка живет в его
    # связке ключей, под root она либо отклоняется, либо пишется не туда.
    printf '%s\n' "$ADMIN_PASS" | sysadminctl -screenLock immediate -password - 2>/dev/null
    sleep 1
    # status печатает ответ в STDERR (NSLog-формат «sysadminctl[pid] ...»), поэтому
    # 2>&1 обязателен — с 2>/dev/null проверка всегда видела пустоту и ложно ругалась.
    # Для «сразу» система пишет либо "immediate", либо "delay is 0" — принимаем оба.
    if sysadminctl -screenLock status 2>&1 | grep -qiE "immediate|delay is 0"; then
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
        warn "Не включился из терминала — открыл Сеть, включи Брандмауэр тумблером."
        # com.apple.Network-Firewall мёртв с Ventura; живой путь — Network-Settings
        open "x-apple.systempreferences:com.apple.Network-Settings.extension" 2>/dev/null
        FW_MANUAL=1
    fi
    if [ "$FW_MANUAL" = "0" ]; then
        # Ставим и проверяем в цикле: ALF-демон применяет настройку асинхронно,
        # а формат --getstealthmode гуляет между версиями macOS (в Tahoe это
        # "Stealth Mode = On" — слова enabled там нет, старый grep его не видел).
        # Источник истины — com.apple.alf.plist, читаем его двумя путями.
        STEALTH_OK=0
        STEALTH_RAW=""
        for _i in 1 2 3 4; do
            as_root "$SOCKETFW" --setstealthmode on >/dev/null 2>&1
            sleep 2
            STEALTH_RAW=$(as_root "$SOCKETFW" --getstealthmode 2>/dev/null)
            printf '%s' "$STEALTH_RAW" | grep -qiE "enabled|mode.*on" && { STEALTH_OK=1; break; }
            if [ "$(as_root /usr/libexec/PlistBuddy -c "Print :stealthenabled" /Library/Preferences/com.apple.alf.plist 2>/dev/null)" = "1" ] \
            || [ "$(as_root defaults read /Library/Preferences/com.apple.alf stealthenabled 2>/dev/null)" = "1" ]; then
                STEALTH_OK=1; break
            fi
        done
        if [ "$STEALTH_OK" = "1" ]; then
            ok "Режим невидимости включен (подтверждено)."
        else
            warn "Невидимость не подтвердилась: Настройки -> Сеть -> Брандмауэр -> Параметры."
            [ -n "$STEALTH_RAW" ] && dim "socketfilterfw ответил: $STEALTH_RAW"
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
    # Флаг -f глушит интерактивный вопрос «Do you really want to turn remote login
    # off?» — без него systemsetup читает stdin, получает EOF и спамит вопрос по кругу.
    as_root systemsetup -f -setremotelogin off 2>/dev/null
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

    # Службы геолокации — выкл + проверка.
    # На Sequoia/Tahoe locationd держит конфиг в памяти: простая запись в plist
    # системой игнорируется (и чтение того же файла — ложное «подтверждено»).
    # STIG-подход для macOS 26: пишем ключ, убиваем демона (он перечитает
    # конфиг), верифицируем глазами самого демона (от пользователя _locationd).
    as_root defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool false 2>/dev/null
    LOC_PID=$(as_root launchctl print system 2>/dev/null | awk '/\tcom\.apple\.locationd/ {print $1; exit}')
    [ -n "$LOC_PID" ] && as_root kill -9 "$LOC_PID" 2>/dev/null
    sleep 1
    LOC=$(as_root -u _locationd defaults -currentHost read /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled 2>/dev/null)
    if [ "$LOC" = "0" ]; then ok "Службы геолокации выключены (подтверждено демоном)."
    else warn "Геолокация — не подтвердилось. Выключи: Настройки -> Конфиденциальность и безопасность -> Службы геолокации."; fi

    # Аналитика и рекламный идентификатор — выкл + проверка
    as_root defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit -bool false 2>/dev/null
    as_root defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist ThirdPartyDataSubmit -bool false 2>/dev/null
    defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false
    defaults write com.apple.AdLib allowIdentifierForAdvertising -bool false
    # adprivacyd держит значения в памяти и может откатить их обратно на диск —
    # перезапускаем, чтобы перечитал
    killall adprivacyd 2>/dev/null
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

    # Показывать ВСЕ расширения файлов в Finder (против подлова photo.jpg.app)
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true 2>/dev/null
    if [ "$(defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null)" = "1" ]; then
        ok "В Finder показываются все расширения файлов (подтверждено)."
    else
        warn "Расширения файлов: перечитать не смог."
    fi

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

    # Удаленные Apple Events — выкл + проверка
    as_root systemsetup -setremoteappleevents off 2>/dev/null
    if as_root systemsetup -getremoteappleevents 2>/dev/null | grep -qi "Off"; then
        ok "Удаленные Apple Events выключены (подтверждено)."
    else
        warn "Remote Apple Events — перечитать не смог. Проверь: Настройки -> Общие -> Общий доступ."
    fi

    # Общий доступ к принтерам — выкл + проверка
    as_root cupsctl --no-share-printers 2>/dev/null
    if cupsctl 2>/dev/null | grep -q "_share_printers=0"; then
        ok "Общий доступ к принтерам выключен (подтверждено)."
    else
        warn "Принтеры: перечитать не смог — проверь Настройки -> Принтеры и сканеры."
    fi

    # Быстрое переключение пользователей — убрать из меню и запретить
    as_root defaults write /Library/Preferences/.GlobalPreferences MultipleSessionEnabled -bool false 2>/dev/null
    defaults -currentHost write com.apple.controlcenter FastUserSwitching -int 0 2>/dev/null
    FUS=$(as_root defaults read /Library/Preferences/.GlobalPreferences MultipleSessionEnabled 2>/dev/null)
    if [ "$FUS" = "0" ]; then ok "Быстрое переключение пользователей выключено (подтверждено)."
    else warn "Переключение пользователей — перечитать не смог. Проверь Control Center в Настройках."; fi

    # Подсказки Spotlight/Siri в поиске — выкл + проверка
    defaults write com.apple.lookup.shared LookupSuggestionsDisabled -bool true 2>/dev/null
    LSUG=$(defaults read com.apple.lookup.shared LookupSuggestionsDisabled 2>/dev/null)
    if [ "$LSUG" = "1" ]; then ok "Подсказки Spotlight/Siri в поиске выключены (подтверждено)."
    else warn "Подсказки поиска — перечитать не смог."; fi

    # Внешние диски не светятся на Рабочем столе (и секретный том в том числе).
    # Применится при перезапуске Finder в конце — отдельно Finder не дергаю.
    defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false 2>/dev/null
    HDD=$(defaults read com.apple.finder ShowExternalHardDrivesOnDesktop 2>/dev/null)
    if [ "$HDD" = "0" ]; then ok "Иконки внешних дисков на Рабочем столе скрыты (применится после рестарта Finder)."
    else warn "Рабочий стол: перечитать не смог."; fi

    ding_subtle
    stage_mark hardening
    phase_end "Базовая защита"
fi

# ------------------------------------------------------------
# Wi-Fi / часовой пояс / Bluetooth
# ------------------------------------------------------------
if ! stage_done radio; then
    step "СЕТЬ И РАДИО / NETWORK & RADIO"
    phase_begin
    # Реальное устройство Wi-Fi (не хардкод en0: на части маков это en1/en2)
    WIFI_DEV=$(as_root networksetup -listallhardwareports 2>/dev/null \
        | awk '/Hardware Port: (Wi-Fi|AirPort)/{getline; print $2; exit}')
    case "$WIFI_MODE" in
        1)
            WIFI_SVC=""
            ALL_SVCS=$(as_root networksetup -listallnetworkservices 2>/dev/null | tail -n +2)
            while IFS= read -r svc; do
                DEV=$(as_root networksetup -listallhardwareports 2>/dev/null | grep -A 2 "Port: $svc" | grep "Device:" | awk '{print $2}')
                if [ -n "$DEV" ] && networksetup -getairportpower "$DEV" >/dev/null 2>&1; then WIFI_SVC="$svc"; WIFI_DEV="$DEV"; break; fi
            done <<< "$ALL_SVCS"
            [ -z "$WIFI_SVC" ] && WIFI_SVC=$(printf '%s\n' "$ALL_SVCS" | grep -i "wi-fi\|wifi\|airport" | head -1)
            if [ -n "$WIFI_SVC" ]; then
                [ -n "$WIFI_DEV" ] && as_root networksetup -setairportpower "$WIFI_DEV" off 2>/dev/null
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
            if [ -n "$WIFI_DEV" ]; then
                as_root networksetup -setairportpower "$WIFI_DEV" off 2>/dev/null
                sleep 1
                if networksetup -getairportpower "$WIFI_DEV" 2>/dev/null | grep -qi ": Off"; then
                    ok "Wi-Fi выключен (радио, $WIFI_DEV). Включить обратно: Настройки -> Wi-Fi."
                else
                    # На Tahoe setairportpower иногда падает с «all AirPort network
                    # services are disabled» — гасим интерфейс на уровне ядра.
                    # Оговорка: configd может поднять его обратно позже — это
                    # разовое гашение, а не постоянная настройка.
                    as_root ifconfig "$WIFI_DEV" down 2>/dev/null
                    sleep 1
                    if ! ifconfig "$WIFI_DEV" 2>/dev/null | grep -q "<UP[,>]"; then
                        ok "Wi-Fi погашен через ifconfig ($WIFI_DEV, интерфейс down). Включить: sudo ifconfig $WIFI_DEV up."
                    else
                        warn "Wi-Fi не погас ни так, ни так — выключи радио руками: Настройки -> Wi-Fi."
                    fi
                fi
            else
                warn "Wi-Fi устройство не нашел — выключи радио руками: Настройки -> Wi-Fi."
            fi
            ;;
        *) dim "Wi-Fi не трогаю." ;;
    esac

    # Часовой пояс — молча по IP. Не определился — не трогаю, без вопросов.
    info "Определяю часовой пояс по IP..."
    # ipapi.co на бесплатном тарифе часто отвечает 429 RateLimited (подтверждено
    # прогоном), а worldtimeapi.org просто лежал. Идем по двум независимым
    # источникам — оба отдают зону IANA чистым текстом.
    TZ_ZONE=""
    for TZ_URL in https://ipapi.co/timezone https://ipinfo.io/timezone; do
        TZ_ZONE=$(curl -s --max-time 8 "$TZ_URL" 2>/dev/null | tr -d '[:space:]')
        case "$TZ_ZONE" in Europe/*|Asia/*|Africa/*|America/*|Australia/*|Pacific/*) break ;; *) TZ_ZONE="" ;; esac
    done
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

    # Bluetooth: никаких сторонних утилит не качаю. Просто открываю панель
    # Настроек с Bluetooth и честно пишу, что выключить — если не подключены
    # беспроводные клава/мышка. (blueutil выпилен по решению владельца.)
    open "x-apple.systempreferences:com.apple.Bluetooth" 2>/dev/null
    info "Bluetooth: открыл панель. Если НЕ подключены беспроводные клава/мышка — выключи тумблер."
    stage_mark radio
    phase_end "Сеть и радио"
fi

# ------------------------------------------------------------
# КЛАВИАТУРА: US + Русская, переключение Ctrl+Space (тихо, без вопросов).
# Ctrl+Space выбран потому, что он есть на ЛЮБОЙ клавиатуре, включая PC
# (Ctrl/Win/Alt) без клавиш Option и Command.
# ------------------------------------------------------------
if ! stage_done keyboard; then
    step "КЛАВИАТУРА / KEYBOARD"
    phase_begin
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
    # defaults read печатает ключи с пробелами В КАВЫЧКАХ: "KeyboardLayout Name" = ABC;
    # поэтому паттерн «KeyboardLayout Name = ABC» не матчился НИКОГДА — раскладка
    # записывалась, а проверка ложно падала. Матчим ключ и значение через .*
    KB_SRCS=$(defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null)
    if printf '%s' "$KB_SRCS" | grep -q RussianWin \
       && printf '%s' "$KB_SRCS" | grep -q "KeyboardLayout Name.*ABC"; then
        ok "Раскладки: ABC + Русская, переключение Ctrl+Space (подтверждено)."
        dim "Если флажка в строке меню нет — нажми Ctrl+Space один раз, иконка оживет."
    else
        warn "Не записалось. Открываю Настройки -> Клавиатура -> добавь Русская (+)."
        open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" 2>/dev/null
        KB_MANUAL=1
        pause
    fi
    stage_mark keyboard
    phase_end "Клавиатура"
fi

# ------------------------------------------------------------
# ФАЗА 3: УСТАНОВКА ПРИЛОЖЕНИЙ (скачал -> поставил -> ПРОВЕРИЛ)
# ------------------------------------------------------------
# Одиночный curl на github.com давал ложный «нет интернета» при мигании сети —
# прогон падал в фазе диска. Пробуем несколько независимых хостов, по 2 попытки.
net_ok() {
    local u i
    for u in https://github.com https://www.apple.com https://cloudflare.com; do
        for i in 1 2; do
            curl -s --max-time 5 "$u" >/dev/null 2>&1 && return 0
        done
    done
    return 1
}
net_speed() { # скорость в БАЙТАХ/с (так отдает curl speed_download)
    local bps
    # LC_ALL=C: в локали с десятичной запятой curl отдает "1234,5", и отсечение
    # по точке возвращало нечисловое значение -> скорость всегда 0.
    bps=$(LC_ALL=C curl -s --max-time 10 -o /dev/null -w '%{speed_download}' https://github.com 2>/dev/null | cut -d'.' -f1 | cut -d',' -f1)
    case "$bps" in ''|*[!0-9]*) bps=0 ;; esac
    echo "$bps"
}
net_wait() {
    if ! net_ok; then
        warn "$(L 'Нет интернета. Жду, пока появится' 'No internet. Waiting')..."
        while ! net_ok; do sleep 3; done
        ok "$(L 'Интернет есть, продолжаю.' 'Internet is back, continuing.')"
    fi
    local sp
    sp=$(net_speed)
    if [ "$sp" -gt 0 ] && [ "$sp" -lt 102400 ]; then
        warn "Канал медленный (~$((sp / 1024)) КБ/с) — загрузки будут долгими."
    elif [ "$sp" -lt 1048576 ]; then
        # 100 КБ/с..1 МБ/с целочисленно давали «~0 МБ/с» — показываем в КБ/с
        dim "Канал: ~$((sp / 1024)) КБ/с."
    else
        dim "Канал: ~$((sp / 1048576)) МБ/с."
    fi
}

app_installed() { [ -n "$(find /Applications -maxdepth 1 -iname "$(app_bundle "$1").app" 2>/dev/null | head -1)" ]; }

# lipo — инструмент Xcode CLT: на чистой системе его вызов выносит диалог
# «The "lipo" command requires the command line developer tools» и качалку на
# несколько ГБ. /usr/bin/file есть в базовой macOS и архитектуры показывает так же.
bin_archs() { /usr/bin/file "$1" 2>/dev/null | grep -oE 'arm64|x86_64|i386' | sort -u | tr '\n' ' ' | sed 's/ $//'; }

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
        archs=$(bin_archs "$bin")
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

# --- Единая политика загрузки ------------------------------------------------
# Раньше curl вызывался с разными наборами флагов (где-то -fsSL, где-то -L без
# -f, таймауты 5/10/без), из-за чего 404 однажды сохранялся как «пакет».
# Здесь одно место: -f (HTTP-ошибка = ненулевой код), таймаут соединения,
# защита от зависшей загрузки, 3 попытки, проверка минимального размера.
FETCH_RETRIES=3
FETCH_MIN_SIZE=1048576
fetch() { # fetch <url> <файл> [имя] [мин_размер] [запасной_url_со_2й_попытки]
    local url="$1" out="$2" name="${3:-файл}" min="${4:-$FETCH_MIN_SIZE}" alt="${5:-}"
    local try=1 sz cur
    net_wait
    while [ "$try" -le "$FETCH_RETRIES" ]; do
        cur="$url"
        [ "$try" -ge 2 ] && [ -n "$alt" ] && cur="$alt"
        rm -f "$out" 2>/dev/null
        if curl -fL "$cur" -o "$out" --progress-bar \
                --connect-timeout 15 --speed-limit 1024 --speed-time 60 2>&1; then
            sz=$(stat -f%z "$out" 2>/dev/null)
            case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
            if [ "$sz" -ge "$min" ]; then return 0; fi
            warn "$name: попытка $try — скачалось что-то кривое ($((sz / 1024)) КБ)."
        else
            warn "$name: попытка $try не скачалась."
        fi
        try=$((try + 1))
        [ "$try" -le "$FETCH_RETRIES" ] && sleep 3
    done
    err "$name: не скачалось после $FETCH_RETRIES попыток. Пропускаю."
    rm -f "$out" 2>/dev/null
    return 1
}

install_dmg() { # install_dmg <url> <имя> [запасной_url]
    local url="$1" name="$2" alt="${3:-}" tmp mp dmg_try cur
    tmp="/tmp/$name.dmg"
    mp=""
    # На медленном канале обрыв ответа без Content-Length проходит мимо curl и
    # проверки размера: файл есть, а dmg битый. Валидируем образ ДО монтирования
    # (imageinfo читает только заголовок — быстро). Второй проход (если задан)
    # идет по ЗАПАСНОМУ источнику — другой хост может быть доступен, когда
    # основной лежит/заблокирован (так было с launchpadlibrarian.net).
    for dmg_try in 1 2; do
        cur="$url"
        [ "$dmg_try" = "2" ] && [ -n "$alt" ] && { cur="$alt"; info "$name: пробую запасной источник."; }
        fetch "$cur" "$tmp" "$name" "$FETCH_MIN_SIZE" || { [ "$dmg_try" = "1" ] && [ -n "$alt" ] && continue; return 1; }
        if ! hdiutil imageinfo "$tmp" >/dev/null 2>&1; then
            err "$name: скачался битый dmg (обрыв на медленном канале?)."
            rm -f "$tmp"; sleep 3; continue
        fi
        # yes| — отвечаем «y» на лицензионное соглашение (SLA), вшитое в dmg:
        # без ответа hdiutil на неинтерактивном вводе молча отваливается.
        # Ошибку hdiutil печатаем — иначе следующий «не смонтировался» слепой.
        mp=$(yes | hdiutil attach "$tmp" -nobrowse 2>/tmp/.hdi_err.$$ | grep -o '/Volumes/.*' | head -1)
        if [ -n "$mp" ]; then rm -f /tmp/.hdi_err.$$; break; fi
        err "$name: dmg не смонтировался."
        [ -s /tmp/.hdi_err.$$ ] && dim "hdiutil: $(tail -1 /tmp/.hdi_err.$$)"
        rm -f "$tmp" /tmp/.hdi_err.$$; sleep 3
    done
    [ -z "$mp" ] && { rm -f "$tmp"; return 1; }
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
        local tpkg rc=1
        tpkg=$(find "$mp" -name "*.pkg" 2>/dev/null | head -1)
        if [ -n "$tpkg" ]; then
            as_root installer -pkg "$tpkg" -target / >/dev/null 2>&1; rc=$?
            [ "$rc" != "0" ] && err "$name: installer вернул ошибку ($rc)."
        else
            err "$name: в образе нет ни .app, ни .pkg."
        fi
        if [ "$rc" != "0" ]; then
            hdiutil detach "$mp" -quiet 2>/dev/null; rm -f "$tmp"; return 1
        fi
    fi
    hdiutil detach "$mp" -quiet 2>/dev/null
    rm -f "$tmp"
    # Явный return: иначе статусом функции был бы результат rm
    return 0
}

install_pkg_url() {
    local url="$1" name="$2" rc
    fetch "$url" "/tmp/$name.pkg" "$name" || return 1
    as_root installer -pkg "/tmp/$name.pkg" -target / >/dev/null 2>&1; rc=$?
    rm -f "/tmp/$name.pkg"
    # Без этого статусом функции был бы rm, и провал установки выглядел успехом
    [ "$rc" = "0" ] || { err "$name: installer вернул ошибку ($rc)."; return 1; }
    return 0
}

if ! stage_done apps; then
    step "УСТАНОВКА ПРИЛОЖЕНИЙ / INSTALLING APPS" "3/6"
    phase_begin
    step_prog_init 8

    if ! app_installed telegram; then
        info "Telegram — ставлю."
        install_dmg "$TG_URL" "Telegram" && verify_app Telegram Telegram
    else
        ok "Telegram уже стоит."
    fi
    step_prog "Telegram"

    if ! app_installed sublime; then
        info "Sublime Text — ставлю."
        fetch "$SUBLIME_URL" /tmp/Sublime.zip "Sublime Text" \
            && (cd /tmp && unzip -o -q Sublime.zip 2>/dev/null)
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
    step_prog "Sublime Text"

    if ! app_installed sphere; then
        info "Linken Sphere — ставлю."
        install_dmg "$SPHERE_URL_ARM64" "Sphere" && verify_app "Linken Sphere" "*sphere*"
    else
        ok "Linken Sphere уже стоит."
    fi
    step_prog "Linken Sphere"

    # Как и qTox: данные на диске = намерение пользователя, даже если M не выбран.
    if ! app_installed mailmate && { [ "$INSTALL_MM" = "да" ] || precheck_data mailmate; }; then
        info "MailMate — ставлю."
        MM_OK=0
        if fetch "$MM_URL" /tmp/MailMate.tbz "MailMate" && (cd /tmp && tar xjf MailMate.tbz 2>/dev/null); then
            MM_OK=1
        else
            warn "MailMate: не скачался/не распаковался — пропускаю (поставишь вручную)."
        fi
        if [ "$MM_OK" = "1" ] && [ -d "/tmp/MailMate.app" ]; then
            safe_remove_app "MailMate.app"
            as_root cp -R "/tmp/MailMate.app" /Applications/ 2>/dev/null
            as_root xattr -dr com.apple.quarantine "/Applications/MailMate.app" 2>/dev/null
        fi
        rm -rf /tmp/MailMate.app /tmp/MailMate.tbz 2>/dev/null
        [ "$MM_OK" = "1" ] && verify_app MailMate MailMate
    fi
    step_prog "MailMate"

    # Ставим, если выбран буквой Q ИЛИ данные qTox уже живут на диске (прошлая
    # попытка установки упала, а в новом прогоне Q не выбрали — приложение без
    # своих данных бессмысленно, доустанавливаем молча).
    if ! app_installed qtox && { [ "$INSTALL_QTOX" = "да" ] || precheck_data qtox; }; then
        info "qTox — ставлю."
        net_wait
        QTOX_URL=""
        LATEST_JSON=$(curl -s --max-time 10 "https://api.github.com/repos/TokTok/qTox/releases/latest" 2>/dev/null)
        if [ -n "$LATEST_JSON" ]; then
            QTOX_URL=$(printf '%s' "$LATEST_JSON" | grep -o 'https://[^"]*arm64\.dmg' | head -1)
            [ -z "$QTOX_URL" ] && QTOX_URL=$(printf '%s' "$LATEST_JSON" | grep -o 'https://[^"]*mac[^"]*\.dmg' | head -1)
            [ -z "$QTOX_URL" ] && QTOX_URL=$(printf '%s' "$LATEST_JSON" | grep -o 'https://[^"]*qtox[^"]*\.dmg' | head -1)
        fi
        if [ -z "$QTOX_URL" ]; then
            # API анонимно дает 60 запросов/час на IP — при лимите (или недоступности
            # API) уходим на прямой редирект latest/download, он API не требует.
            QTOX_URL="https://github.com/TokTok/qTox/releases/latest/download/qTox-arm64.dmg"
            dim "GitHub API не ответил — беру прямую ссылку на последний релиз."
        fi
        install_dmg "$QTOX_URL" "qTox" && verify_app "qTox" "*tox*" \
            || err "qTox: не поставился. Ставь вручную: https://qtox.github.io"
    fi
    step_prog "qTox"

    if ! app_installed tukan; then
        info "Tukan — ставлю."
        install_dmg "$TUKAN_URL" "Tukan" && verify_app "Tukan" "*tukan*"
    else
        ok "Tukan уже стоит."
    fi
    step_prog "Tukan"

    if [ "$INSTALL_EXCEL" = "да" ]; then
        if ! app_installed excel; then
            info "Excel — ставлю (большой, минуту терпения)."
            install_pkg_url "$EXCEL_URL" Excel && verify_app "Microsoft Excel" "Microsoft Excel"
        else
            ok "Excel уже стоит."
        fi
    fi
    step_prog "Excel"

    # Текстовые расширения -> Sublime Text через LaunchServices (secure plist).
    # Раньше был duti: он на свежих macOS ставил часть расширений и молча падал
    # на остальных — потому .txt открывался, а .md и др. нет. Идём напрямую
    # в plist upsert'ом и ПЕРЕЧИТЫВАЕМ результат на каждом расширении.
    if app_installed sublime; then
        SUB_BUNDLE=$(defaults read "/Applications/Sublime Text.app/Contents/Info" CFBundleIdentifier 2>/dev/null)
        if [ -n "$SUB_BUNDLE" ]; then
            LSDOMAIN="com.apple.LaunchServices/com.apple.launchservices.secure"
            ls_upsert() { # ls_upsert <uti> <bundle>
                local uti="$1" bundle="$2" n i cur
                n=$(/usr/libexec/PlistBuddy -c "Print :LSHandlers" "$HOME/Library/Preferences/$LSDOMAIN.plist" 2>/dev/null | grep -c "Dict {" || true)
                i=0
                while [ "$i" -lt "${n:-0}" ]; do
                    cur=$(/usr/libexec/PlistBuddy -c "Print :LSHandlers:$i:LSItemContentTypes" "$HOME/Library/Preferences/$LSDOMAIN.plist" 2>/dev/null)
                    if [ "$cur" = "$uti" ]; then
                        /usr/libexec/PlistBuddy -c "Set :LSHandlers:$i:LSHandlerRoleAll $bundle" "$HOME/Library/Preferences/$LSDOMAIN.plist" 2>/dev/null && return 0
                        /usr/libexec/PlistBuddy -c "Add :LSHandlers:$i:LSHandlerRoleAll string $bundle" "$HOME/Library/Preferences/$LSDOMAIN.plist" 2>/dev/null && return 0
                        return 1
                    fi
                    i=$((i + 1))
                done
                /usr/libexec/PlistBuddy -c "Add :LSHandlers:$i dict" "$HOME/Library/Preferences/$LSDOMAIN.plist" 2>/dev/null || return 1
                /usr/libexec/PlistBuddy -c "Add :LSHandlers:$i:LSItemContentTypes string $uti" "$HOME/Library/Preferences/$LSDOMAIN.plist" 2>/dev/null
                /usr/libexec/PlistBuddy -c "Add :LSHandlers:$i:LSHandlerRoleAll string $bundle" "$HOME/Library/Preferences/$LSDOMAIN.plist" 2>/dev/null
            }
            ls_verify() { # ls_verify <uti> <bundle>
                local uti="$1" bundle="$2" n i cur h
                n=$(/usr/libexec/PlistBuddy -c "Print :LSHandlers" "$HOME/Library/Preferences/$LSDOMAIN.plist" 2>/dev/null | grep -c "Dict {" || true)
                i=0
                while [ "$i" -lt "${n:-0}" ]; do
                    cur=$(/usr/libexec/PlistBuddy -c "Print :LSHandlers:$i:LSItemContentTypes" "$HOME/Library/Preferences/$LSDOMAIN.plist" 2>/dev/null)
                    if [ "$cur" = "$uti" ]; then
                        h=$(/usr/libexec/PlistBuddy -c "Print :LSHandlers:$i:LSHandlerRoleAll" "$HOME/Library/Preferences/$LSDOMAIN.plist" 2>/dev/null)
                        [ "$h" = "$bundle" ] && return 0
                        return 1
                    fi
                    i=$((i + 1))
                done
                return 1
            }
            # Регистрируем Sublime в LaunchServices, чтобы bundle id был известен
            /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Sublime Text.app" 2>/dev/null
            EXT_OK=0; EXT_FAIL=""
            for ext in $LS_EXTENSIONS; do
                ls_upsert "$ext" "$SUB_BUNDLE" 2>/dev/null
                if ls_verify "$ext" "$SUB_BUNDLE"; then EXT_OK=$((EXT_OK + 1)); else EXT_FAIL="$EXT_FAIL .$ext"; fi
            done
            killall cfprefsd 2>/dev/null
            TOT=$(echo $LS_EXTENSIONS | wc -w | tr -d ' ')
            if [ "$EXT_OK" = "$TOT" ]; then
                ok "Текстовые расширения -> Sublime Text: все $EXT_OK подтверждены."
            else
                warn "Расширения: подтверждено $EXT_OK из $TOT. Не встали:$EXT_FAIL — в Finder: правой кнопкой -> Открыть в программе -> Sublime Text -> «Всегда»."
                dim "На Tahoe launchservicesd кэширует ассоциации: записанные могут подхватиться только после перезагрузки."
            fi
        fi
    fi
    step_prog "Расширения"

    # VeraCrypt + FUSE-T (нужны для секретного диска)
    if ! pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t"; then
        info "FUSE-T (драйвер дисков) — ставлю."
        install_pkg_url "$FUSET_URL" "fuse-t" || true
        if pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t"; then ok "FUSE-T установлен."
        else warn "FUSE-T не подтвердился — VeraCrypt может не увидеть диск."; fi
    fi
    if [ "$APP_VERACRYPT" = "0" ]; then
        info "VeraCrypt — ставлю."
        install_dmg "$VC_URL" "VeraCrypt" "$VC_URL_ALT"
        verify_app VeraCrypt VeraCrypt || true
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
    ding_subtle
    # Фазу помечаем завершенной, только если VeraCrypt и FUSE-T на месте: они
    # обязательны для фазы диска. Не встали — отметку не ставим, и следующий
    # запуск вернется в эту фазу и доустановит (все остальное быстро
    # пропустится по «уже стоит»).
    if [ -d "/Applications/VeraCrypt.app" ] && pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t"; then
        stage_mark apps
    else
        warn "VeraCrypt/FUSE-T не подтвердились — фазу приложений НЕ помечаю завершенной: следующий запуск доустановит."
    fi
    phase_end "Установка приложений"
fi

# ------------------------------------------------------------
# ФАЗА 4: FileVault — ВКЛЮЧИТЬ И ПРОВЕРИТЬ.
# Ключ восстановления показывается ОДИН РАЗ прямо в терминал (/dev/tty) —
# в переменных скрипта не задерживается, ни в какие файлы не пишется.
# ------------------------------------------------------------
if ! stage_done filevault; then
    step "FILEVAULT — ШИФРОВАНИЕ ДИСКА" "4/6"
    phase_begin
    FV_STAGE_OK=0
    FV_ST=$(fdesetup status 2>/dev/null)
    if echo "$FV_ST" | grep -qi "FileVault is On"; then
        ok "FileVault включен (подтверждено)."
        FV_STAGE_OK=1
    elif echo "$FV_ST" | grep -qi "Encryption in progress"; then
        ok "FileVault включен — идет шифрование в фоне (подтверждено)."
        FV_STAGE_OK=1
    else
        info "Включаю FileVault (шифрование всего диска)..."
        CONSOLE_USER=$(stat -f%Su /dev/console 2>/dev/null)
        # -inputplist: пароль уходит через stdin вместе с plist — НЕ на экран,
        # НЕ в файл, НЕ в список процессов. as_root тут НЕ подходит: внутри него
        # свой пайп в sudo -S, и внешний stdin до команды не доедет.
        # Одна строка в потоке — пароль sudo, остальное читает fdesetup.
        FV_USER="${CONSOLE_USER:-$(id -un)}"
        FV_PASS_ESC=$(printf '%s' "$ADMIN_PASS" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        FV_OUT=$( { printf '%s\n' "$ADMIN_PASS"; printf '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Username</key><string>%s</string>
<key>Password</key><string>%s</string>
</dict></plist>' "$FV_USER" "$FV_PASS_ESC"; } | sudo -S -k fdesetup enable -user "$FV_USER" -inputplist 2>&1)
        # Ключ восстановления (6 групп по 4 символа) вытаскиваем и показываем
        # ОДИН РАЗ прямо в терминал. Печать идет в /dev/tty, а не в stdout:
        # при перенаправлении вывода ключ не попадет ни в какой файл/лог.
        # В переменной он живет пару строк и сразу затирается.
        FV_KEY=$(printf '%s' "$FV_OUT" | grep -oE '([A-Z0-9]{4}-){5}[A-Z0-9]{4}' | head -1)
        # Пароль из памяти убираем сразу, но причину отказа сохраняем: раньше
        # FV_OUT затирался целиком и диагностировать неудачу было нечем.
        # Строки с ключом отбрасываем, как и все, что похоже на пароль пользователя.
        FV_ERR=$(printf '%s' "$FV_OUT" \
            | grep -vi "recovery key\|[A-Z0-9]\{4\}-[A-Z0-9]\{4\}-[A-Z0-9]\{4\}" \
            | grep -v "^Password:" | grep . | head -2)
        FV_OUT=""; FV_PASS_ESC=""; unset FV_OUT FV_PASS_ESC
        sleep 2
        FV_ST=$(fdesetup status 2>/dev/null)
        if printf '%s' "$FV_ST" | grep -qi "is On\|in progress"; then
            ok "FileVault включен — диск зашифруется в фоне (подтверждено: $(printf '%s' "$FV_ST" | head -1))."
            if [ -n "$FV_KEY" ]; then
                printf '\n  %s%s>>> КЛЮЧ ВОССТАНОВЛЕНИЯ FILEVAULT <<<%s\n' "$YELLOW" "$BOLD" "$NC" > /dev/tty
                printf '  %s%s%s%s\n' "$BOLD" "$YELLOW" "$FV_KEY" "$NC" > /dev/tty
                printf '  %sЗапиши его на бумагу СЕЙЧАС — скрипт его НИГДЕ не сохранил и больше не покажет.%s\n\n' "$YELLOW" "$NC" > /dev/tty
            else
                warn "Ключ восстановления из вывода fdesetup не достался — посмотри его: sudo fdesetup changerecovery -personal"
            fi
            FV_STAGE_OK=1
        else
            err "FileVault не подтвердился: $(printf '%s' "$FV_ST" | head -1)."
            [ -n "$FV_ERR" ] && err "Причина: $FV_ERR"
            warn "Включи руками: Настройки -> Конфиденциальность и безопасность -> FileVault."
        fi
        FV_ERR=""; FV_KEY=""; unset FV_ERR FV_KEY
    fi
    # Отмечаем фазу только при подтвержденном FileVault: иначе следующий
    # запуск пропустил бы незашифрованный диск.
    [ "$FV_STAGE_OK" = "1" ] && stage_mark filevault
    phase_end "FileVault"
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

# UUID тома по пути монтирования. Для тома под FUSE-T (VeraCrypt) diskutil
# часто ничего не отдает — тогда возвращаем пусто, и проверки ниже становятся
# необязательными: лучше без сверки, чем ложный стоп на живом диске.
vol_uuid_of() { # vol_uuid_of <путь тома>
    local vdev
    vdev=$(df "$1" 2>/dev/null | tail -1 | awk '{print $1}')
    case "$vdev" in /dev/*) ;; *) return 1 ;; esac
    disk_field "${vdev#/dev/}" VolumeUUID 2>/dev/null
}
# Значения, запомненные прошлым прогоном (строки вида ключ=значение в STAGE_FILE)
stage_val() { # stage_val <ключ>
    grep "^$1=" "$STAGE_FILE" 2>/dev/null | tail -1 | cut -d= -f2-
}

list_external() {
    # Внешние физические диски в ЛЮБОМ состоянии: вставлен без монтирования
    # (у VeraCrypt-диска macOS том не монтирует вовсе), смонтирован, за хабом.
    {
        # 1) Штатный путь: честный флаг external от diskutil.
        local p=/tmp/disks.plist i=0 n j wn
        diskutil list -plist external physical > "$p" 2>/dev/null
        n=$(/usr/libexec/PlistBuddy -c "Print :AllDisksAndPartitions" "$p" 2>/dev/null | grep -c "Dict {" || true)
        while [ "$i" -lt "${n:-0}" ]; do
            j=0
            while :; do
                wn=$(/usr/libexec/PlistBuddy -c "Print :AllDisksAndPartitions:$i:WholeDisks:$j" "$p" 2>/dev/null) || break
                printf '%s\n' "$wn"; j=$((j + 1))
            done
            i=$((i + 1))
        done
        # 2) Путь без доверия к флагу external (хабы/переходники его врут):
        # ЛЮБОЙ диск, который не Internal и не Virtual (синтезированные APFS-
        # контейнеры), — внешний. Монтирование и файловая система не важны.
        local d intern virt
        diskutil list -plist > /tmp/disks_all.plist 2>/dev/null
        for d in $(/usr/libexec/PlistBuddy -c "Print :AllDisks" /tmp/disks_all.plist 2>/dev/null | grep -oE 'disk[0-9]+'); do
            diskutil info -plist "$d" > /tmp/disk_info.plist 2>/dev/null || continue
            intern=$(/usr/libexec/PlistBuddy -c "Print :Internal" /tmp/disk_info.plist 2>/dev/null)
            [ "$intern" = "true" ] && continue
            virt=$(/usr/libexec/PlistBuddy -c "Print :Virtual" /tmp/disk_info.plist 2>/dev/null)
            [ "$virt" = "true" ] && continue
            printf '%s\n' "$d"
        done
        rm -f /tmp/disks_all.plist /tmp/disk_info.plist
    } | sort -u
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

# Все тома в /Volumes, у которых хост-устройство — ВНЕШНИЙ физический диск.
# Это покрывает случай, когда диск вставлен, том смонтирован, а
# diskutil list external physical его не видит (USB-хабы/переходники —
# чип моста не всегда отдает корректный флаг external). Имена томов
# не сравниваем нигде — только физика.
external_mounted_vols() {
    local v hd
    for v in /Volumes/*; do
        [ -d "$v" ] || continue
        [ -L "$v" ] && continue
        hd=$(diskutil info "$v" 2>/dev/null | awk -F': *' '/Part of Whole/ {print $2; exit}')
        [ -n "$hd" ] || continue
        diskutil info "$hd" 2>/dev/null | grep -qi "Protocol:.*USB" \
            && diskutil info "$hd" 2>/dev/null | grep -qi "Device Location:.*External" \
            && echo "$hd"
    done | sort -u
}

# Том, смонтированный VeraCrypt: сперва спрашиваем сам VeraCrypt (VC --list),
# только потом — скан кандидатов в /Volumes
vc_mounted_vol() {
    local out v
    if [ -x "$VC" ]; then
        # Берем ВСЕ смонтированные тома VC, а не только первый —
        # с двумя вставленными дисками head -1 мог взять не тот.
        out=$("$VC" --text --list 2>/dev/null | grep -o '/Volumes/.*')
        while IFS= read -r v; do
            [ -n "$v" ] && [ -d "$v" ] && { echo "$v"; return 0; }
        done <<EOF
$out
EOF
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
    # df -P: одна строка на том — длинное имя устройства не ломает парсинг колонок
    boot=$(basename "$(df -P / 2>/dev/null | tail -1 | awk '{print $NF}')" 2>/dev/null)
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
    phase_begin
    # Раньше тут был жесткий exit 1 при единичном флаке сети — теперь терпеливо
    # ждем возвращения интернета, как это делает фаза 3 (net_wait).
    net_wait

    DISK_DEV=""
    BEFORE_PLUG=$(list_external)
    # Если том VeraCrypt УЖЕ смонтирован (диск вставили до этой фазы) — не просим
    # перетывать: wait_new_disk ждет только НОВЫЙ диск и вечно молчал бы.
    PRE_MOUNTED=""
    [ "$HAVE_DISK" = "да" ] && PRE_MOUNTED=$(vc_mounted_vol 2>/dev/null || true)
    # VeraCrypt обязателен для обеих веток (подключить готовый диск или
    # зашифровать новый). Фаза приложений могла быть помечена завершенной, не
    # дойдя до него (не встал FUSE-T на медленном канале и т.п.) — тогда
    # доставляем прямо здесь сами, а не отправляем пользователя ставить руками.
    # Исключение: том уже смонтирован — тогда VC не нужен вовсе.
    if [ -z "$PRE_MOUNTED" ] && [ ! -d "/Applications/VeraCrypt.app" ]; then
        warn "VeraCrypt не установлен (фаза приложений до него не дошла) — доставляю сейчас."
        if ! pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t"; then
            install_pkg_url "$FUSET_URL" "fuse-t" || true
            pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t" && ok "FUSE-T установлен." \
                || warn "FUSE-T не подтвердился — VeraCrypt может не увидеть диск."
        fi
        install_dmg "$VC_URL" "VeraCrypt" "$VC_URL_ALT"
        verify_app VeraCrypt VeraCrypt || true
        if [ ! -d "/Applications/VeraCrypt.app" ]; then
            err "VeraCrypt так и не встал — без него секретный диск не подключить."
            exit 1
        fi
    fi
    if [ "$HAVE_DISK" = "да" ] && [ -n "$PRE_MOUNTED" ]; then
        ok "Секретный том уже смонтирован: $PRE_MOUNTED — вставлять ничего не нужно."
        # Физический диск для UUID-сверки: берем, только если внешний ровно один.
        [ "$(printf '%s\n' "$BEFORE_PLUG" | grep -c .)" = "1" ] && DISK_DEV=$BEFORE_PLUG
    elif [ "$HAVE_DISK" = "да" ]; then
        # Диск мог быть вставлен ДО этой фазы: для wait_new_disk он не «новый»,
        # и скрипт молча ждал бы до таймаута. Если внешний ровно один — это он.
        N_EXT=$(printf '%s\n' "$BEFORE_PLUG" | grep -c . || true)
        if [ "$N_EXT" = "1" ]; then
            DISK_DEV=$BEFORE_PLUG
            info "Секретный диск уже вставлен: /dev/$DISK_DEV — перетыкать не нужно."
        elif [ "${N_EXT:-0}" -gt 1 ]; then
            # Несколько внешних (часто — пустые картридеры в хабе): угадать
            # физический диск нельзя, но это и НЕ НУЖНО. Как в исходной
            # версии: просто открываем VeraCrypt, устройство выбирает человек,
            # а скрипт ждет появления смонтированного тома.
            warn "Вижу несколько внешних дисков ($N_EXT) — не угадываю. Ничего страшного: дальше сам выберешь устройство в окне VeraCrypt."
            DISK_DEV=""
        else
            info "Вставь свой секретный диск (который уже зашифрован)."
            # Зашифрованный диск macOS не читает: вылезет окно «не читается» —
            # это НОРМАЛЬНО. Кнопка «Инициализировать» там уничтожит данные.
            warn "Если macOS покажет окно «диск не читается» — жми ТОЛЬКО «Игнорировать». «Инициализировать» — НИКОГДА."
            DISK_DEV=$(wait_new_disk "$BEFORE_PLUG") || {
                err "Не увидел новый диск за $DISK_WAIT_SEC сек."
                warn "Если диск УЖЕ был вставлен — вынь и вставь еще раз. Смотрю еще $DISK_WAIT_SEC сек..."
                DISK_DEV=$(wait_new_disk "$BEFORE_PLUG") || {
                    # Последний шанс: USB-хабы/переходники не всегда отдают
                    # корректный флаг external — ищем по смонтированным томам
                    # на USB-дисках. Диагностику печатаем, чтобы не гадать.
                    err "diskutil диск не видит. Диагностика:"
                    dim "$(diskutil list external 2>/dev/null | head -8)"
                    DISK_DEV=$(external_mounted_vols)
                    N_EMV=$(printf '%s\n' "$DISK_DEV" | grep -c . || true)
                    if [ "$N_EMV" = "1" ]; then
                        info "Нашел по смонтированному тому на USB-диске: /dev/$DISK_DEV"
                    elif [ "${N_EMV:-0}" -gt 1 ]; then
                        # Не угадываем — и не надо: дальше откроем VeraCrypt,
                        # устройство выберет человек (исходное поведение).
                        warn "Вижу несколько USB-дисков ($N_EMV) — не угадываю. Выберешь свое устройство в окне VeraCrypt."
                        DISK_DEV=""
                    else
                        err "Диск не найден никаким способом. Проверь: виден ли он в Дисковой утилите (diskutil list), попробуй другой порт/кабель напрямую без хаба."
                        exit 1
                    fi
                }
            }
        fi
    else
        info "Вставь НОВЫЙ диск, который будем шифровать."
        DISK_DEV=$(wait_new_disk "$BEFORE_PLUG") || { err "Не увидел новый диск за $DISK_WAIT_SEC сек."; exit 1; }
        sleep 2
        D_NAME=$(disk_field "$DISK_DEV" MediaName)
        D_SIZE=$(disk_field "$DISK_DEV" TotalSize)
        # Единицы — в строке формата: конкатенация внутри %.0f их съедала
        [ -n "$D_SIZE" ] && D_SIZE=$(echo "$D_SIZE" | awk '{printf "%.0f ГБ", $1/1073741824}')
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

    if [ "$HAVE_DISK" = "да" ] && [ -n "$PRE_MOUNTED" ]; then
        # Уже смонтирован до фазы — VeraCrypt не открываем, ждать нечего.
        VOL_NAME=$PRE_MOUNTED
    elif [ "$HAVE_DISK" = "да" ]; then
        sub "Монтирование секретного диска — через VeraCrypt (пароль знаешь только ты)"
        if [ -n "$DISK_DEV" ]; then
            echo "    1) Открою VeraCrypt. Нажми  ${BOLD}Select Device...${NC}  -> выбери раздел своего диска (/dev/${DISK_DEV}s1)"
        else
            echo "    1) Открою VeraCrypt. Нажми  ${BOLD}Select Device...${NC}  -> выбери раздел своего диска (ориентируйся по размеру, строка вида /dev/diskXs1)"
        fi
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
    # UUID тома и физического диска — в отметки, чтобы при возобновлении
    # не спутать секретный диск с другой флешкой (см. сверку ниже).
    VUUID=$(vol_uuid_of "$VOL_NAME")
    [ -n "$VUUID" ] && echo "vol_uuid=$VUUID" >> "$STAGE_FILE"
    [ -n "$DISK_UUID" ] && echo "disk_uuid=$DISK_UUID" >> "$STAGE_FILE"
    [ -z "$VUUID" ] && [ -z "$DISK_UUID" ] && \
        dim "UUID тома система не отдала — при перезапуске сверить диск не смогу."

    ok "Секретный диск подключен: $VOL_NAME"
    ding
    stage_mark disk
    phase_end "Секретный диск"
fi

VOL_NAME=$(vc_mounted_vol)
[ -z "$VOL_NAME" ] && { err "Секретный том не смонтирован — без него фаза данных невозможна."; exit 1; }

# Сверка тома с прошлым прогоном: ниже данные приложений уезжают на этот том и
# заменяются симлинками, поэтому чужая флешка вместо секретного диска — это
# потеря данных. Сверяем, только если UUID реально известны с обеих сторон.
SAVED_VOL_UUID=$(stage_val vol_uuid)
if [ -n "$SAVED_VOL_UUID" ]; then
    NOW_VOL_UUID=$(vol_uuid_of "$VOL_NAME")
    if [ -z "$NOW_VOL_UUID" ]; then
        dim "UUID текущего тома система не отдала — сверку с прошлым прогоном пропускаю."
    elif [ "$NOW_VOL_UUID" != "$SAVED_VOL_UUID" ]; then
        err "Смонтирован ДРУГОЙ том, не тот, с которым начинался прогон."
        err "Это не твой секретный диск — переносить на него данные не буду."
        info "Отмонтируй лишние тома, смонтируй нужный в VeraCrypt и запусти скрипт заново."
        info "Если диск правда сменился намеренно — удали $STAGE_FILE и начни с нуля."
        exit 1
    else
        ok "Том тот же, что и в начале прогона (сверено по UUID)."
    fi
fi
# Физический диск: если запомненный UUID есть, а диска среди внешних нет —
# том смонтирован с чего-то другого. Предупреждаем, но не останавливаем:
# у части USB-контейнеров diskutil не отдает DiskUUID вовсе.
SAVED_DISK_UUID=$(stage_val disk_uuid)
if [ -n "$SAVED_DISK_UUID" ]; then
    DISK_SEEN=0
    for dev in $(list_external); do
        [ "$(disk_field "$dev" DiskUUID 2>/dev/null)" = "$SAVED_DISK_UUID" ] && { DISK_SEEN=1; break; }
    done
    [ "$DISK_SEEN" = "0" ] && warn "Физический диск из начала прогона среди подключенных не вижу — проверь, что том с него."
fi

# Гигиена секретного тома: не индексировать Spotlight (имена файлов не должны
# попадать в системный индекс) и не бэкапить в Time Machine.
if ! stage_done vol_hygiene; then
    phase_begin
    as_root mdutil -i off "$VOL_NAME" 2>/dev/null
    if mdutil -s "$VOL_NAME" 2>/dev/null | grep -qi "disabled"; then
        ok "Spotlight на секретном томе выключен (подтверждено)."
    else
        dim "Spotlight: статус перечитать не смог — не критично."
    fi
    # addexclusion на Swift: повторный запуск для уже исключенного тома падает
    # с POSIXError Code=22 ПРЯМО В STDOUT (stderr тут не при делах). Глушим оба
    # потока — решает все равно isexcluded ниже.
    as_root tmutil addexclusion -p "$VOL_NAME" >/dev/null 2>&1
    if tmutil isexcluded "$VOL_NAME" 2>/dev/null | grep -qi "\[Excluded\]"; then
        ok "Том исключен из Time Machine (подтверждено)."
    else
        dim "Time Machine: исключение перечитать не смог — не критично."
    fi
    stage_mark vol_hygiene
    phase_end "Гигиена тома"
fi

# ------------------------------------------------------------
# ФАЗА 6: ДАННЫЕ ПРИЛОЖЕНИЙ НА СЕКРЕТНОМ ДИСКЕ
# Опознание папок — ТОЛЬКО по содержимому. Имена папок не важны:
# app.ls, App_LS2, Sphere, Telegram_Data, как-угодно-названо — найдем все.
# ------------------------------------------------------------
# >>> TESTABLE migrate — см. комментарий у первого маркера
# Корень данных на диске: голосование по найденным опознанным папкам.
# Если опознанная папка лежит внутри "*_Data" — корень на уровень выше.
resolve_data_dir() {
    local vol="$1" key d root votes best
    votes=""
    while IFS= read -r d; do
        key=$(fp_any "$d") || continue
        root=$(dirname "$d")
        case "$(basename "$root")" in *_Data|*_data|Telegram|telegram) root=$(dirname "$root") ;; esac
        # Пишем КАЖДЫЙ голос: прежний «дедуп» по "\n$root\n" не срабатывал
        # никогда (в переменной реальные переводы строк), а сам по себе он
        # обнулял бы смысл голосования ниже.
        votes="$votes$root
"
    done < <(find "$vol" -maxdepth 4 -type d \
        -not -path "*/.Trashes*" -not -path "*/.Spotlight-V100*" \
        -not -path "*/.fseventsd*" -not -path "*/.DocumentRevisions*" \
        -not -path "*/.TemporaryItems*" 2>/dev/null)
    best=""
    if [ -n "$votes" ]; then
        best=$(printf '%s' "$votes" | grep . | sort | uniq -c | sort -rn | head -1 | awk '{$1=""; sub(/^ /,""); print}')
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
    if [ -e "$src" ]; then
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
# Хватит ли места на секретном томе для копии: сравниваю du источника с df тома.
# Не хватит — пропускаем перенос (данные остаются локально, симлинки не создаем).
space_ok() { # space_ok <источник> <том>
    local need_kb free_kb
    need_kb=$(du -sk "$1" 2>/dev/null | awk '{print $1}')
    # -P: POSIX-вывод, одна строка на том (иначе длинное имя устройства ломает колонки)
    free_kb=$(df -kP "$2" 2>/dev/null | awk 'NR==2 {print $4}')
    [ -n "$need_kb" ] && [ -n "$free_kb" ] || return 0
    [ "$free_kb" -gt "$need_kb" ]
}

# Сверка копии с оригиналом: число объектов И суммарный размер.
# "ls -A непустой" пропускал оборванную копию (диск отключили на середине),
# после чего оригинал удалялся — терялась часть профиля.
copy_matches() { # copy_matches <источник> <копия>
    local n1 n2 k1 k2
    n1=$(find "$1" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
    n2=$(find "$2" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
    [ "$n1" = "$n2" ] || { warn "Копия неполная: объектов $n2 из $n1."; return 1; }
    k1=$(du -sk "$1" 2>/dev/null | awk '{print $1}')
    k2=$(du -sk "$2" 2>/dev/null | awk '{print $1}')
    case "$k1$k2" in ''|*[!0-9]*) return 0 ;; esac
    # Допуск 5%: размер каталога на другой ФС отличается из-за размера блока
    [ "$k2" -ge $(( k1 - k1 / 20 )) ] || { warn "Копия меньше оригинала: ${k2} КБ против ${k1} КБ."; return 1; }
    return 0
}

# Перенос данных на диск БЕЗ окна, в котором данных нет нигде.
# Было: cp -> rm -rf оригинала -> ln -s. Если между вторым и третьим шагом
# процесс убить, пользователь остается без данных и без ссылки.
# Стало: копия во временное имя -> проверка -> mv на место (атомарный в
# пределах тома) -> оригинал переименовываем в .bak -> симлинк -> и только
# после успешной проверки ссылки удаляем .bak.
migrate_to_disk() { # migrate_to_disk <источник> <цель на диске> <подпись>
    local src="$1" dst="$2" lbl="$3" stage bak
    stage="$dst.partial.$$"
    bak="$src.bak.$$"
    rm -rf "$stage" 2>/dev/null
    mkdir -p "$(dirname "$dst")" 2>/dev/null
    if ! mkdir -p "$stage" 2>/dev/null || ! cp -R "$src/." "$stage/" 2>/dev/null; then
        err "$lbl: копирование не удалось — данные оставил на месте."
        rm -rf "$stage" 2>/dev/null; return 1
    fi
    if ! copy_matches "$src" "$stage"; then
        err "$lbl: копия не совпала с оригиналом — данные оставил на месте."
        rm -rf "$stage" 2>/dev/null; return 1
    fi
    # Цель могла остаться пустой от прошлого прогона — она не нужна
    [ -d "$dst" ] && [ -z "$(ls -A "$dst" 2>/dev/null)" ] && rmdir "$dst" 2>/dev/null
    if [ -e "$dst" ]; then
        err "$lbl: на диске уже есть $dst — не перезаписываю, разберись руками."
        rm -rf "$stage" 2>/dev/null; return 1
    fi
    if ! mv "$stage" "$dst" 2>/dev/null; then
        err "$lbl: не смог переместить копию в $dst."
        rm -rf "$stage" 2>/dev/null; return 1
    fi
    # Оригинал не удаляем, а отодвигаем: если ссылка не создастся — вернем
    if ! mv "$src" "$bak" 2>/dev/null; then
        err "$lbl: не смог отодвинуть локальную папку — данные на диске ($dst), ссылку сделай руками."
        return 1
    fi
    if ln -s "$dst" "$src" 2>/dev/null && [ -d "$src" ]; then
        rm -rf "$bak" 2>/dev/null
        return 0
    fi
    # Откат: ссылки нет — возвращаем локальные данные, чтобы не остаться ни с чем.
    # Копию на диске тоже убираем: иначе следующий прогон упрется в непустую
    # цель и откажется переносить.
    rm -f "$src" 2>/dev/null
    mv "$bak" "$src" 2>/dev/null
    rm -rf "$dst" 2>/dev/null
    err "$lbl: ссылку создать не смог (права Терминала?) — вернул данные на место."
    return 1
}
# <<< TESTABLE migrate

if ! stage_done data; then
    step "ДАННЫЕ ПРИЛОЖЕНИЙ -> НА СЕКРЕТНЫЙ ДИСК" "6/6"
    phase_begin
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
            if [ -e "$src" ] || { [ -L "$src" ] && [ -d "$(readlink "$src")" ]; }; then ok "$lbl — уже подключен."; continue; fi
            rm -f "$src" 2>/dev/null
        fi

        if [ -d "$dst" ] && [ -n "$(ls -A "$dst" 2>/dev/null)" ]; then
            link_to "$src" "$dst" "$key" && continue
        fi

        # Данные есть локально — переносим на диск сами
        if "fp_$key" "$src" 2>/dev/null || { [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ]; }; then
            if ! space_ok "$src" "$VOL_NAME"; then
                err "$lbl: на диске НЕ ХВАТИТ места (нужно $(du -sh "$src" 2>/dev/null | awk '{print $1}')) — данные оставил локально, освободи диск и запусти снова."
                continue
            fi
            info "$lbl: переношу локальные данные на диск..."
            if migrate_to_disk "$src" "$dst" "$lbl"; then
                ok "$lbl: локальные данные перенесены и подключены."
            fi
            continue
        fi

        # Нет ни локально, ни на диске: запускаем приложение, оно создаст папку
        if app_installed "$key"; then
            info "$lbl: данных нет — запускаю приложение, чтобы создало свою папку..."
            APP_MATCH=$(find /Applications -maxdepth 1 -iname "$(app_bundle "$key").app" 2>/dev/null | head -1)
            # На Apple Silicon приложению без arm64-среза нужна Rosetta — ставим.
            # lipo тут нельзя: это CLT-стаб (см. bin_archs). Rosetta ставим только
            # если её реально нет — проверка arch -x86_64, а не слепой softwareupdate.
            APP_BIN=$(find "$APP_MATCH/Contents/MacOS" -type f 2>/dev/null | head -1)
            if [ -n "$APP_BIN" ] && ! bin_archs "$APP_BIN" | grep -q arm64; then
                /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null \
                    || as_root /usr/sbin/softwareupdate --install-rosetta --agree-to-license 2>/dev/null
            fi
            xattr -dr com.apple.quarantine "$APP_MATCH" 2>/dev/null
            # Bundle ID вместо имени: pkill -f "Sublime Text" — подстрочный матч
            # по всей командной строке, мог поймать чужой процесс (в т.ч. этот
            # скрипт, открытый в редакторе с таким же именем в пути).
            APP_BID=$(defaults read "$APP_MATCH/Contents/Info" CFBundleIdentifier 2>/dev/null)
            open -a "$APP_MATCH" 2>/dev/null
            # Ждем появления папки, а не фиксированные 8 секунд: на быстрой
            # машине уходим раньше, на медленной — дожидаемся.
            waited=0
            while [ "$waited" -lt 20 ]; do
                [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ] && break
                sleep 1; waited=$((waited + 1))
            done
            if [ ! -d "$src" ] || [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
                warn "$lbl: папку пока не создал — пробую еще раз..."
                open -a "$APP_MATCH" 2>/dev/null
                waited=0
                while [ "$waited" -lt 20 ]; do
                    [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ] && break
                    sleep 1; waited=$((waited + 1))
                done
            fi
            if [ -n "$APP_BID" ]; then
                osascript -e "tell application id \"$APP_BID\" to quit" 2>/dev/null
                sleep 2
                pkill -f "$APP_MATCH/Contents/MacOS/" 2>/dev/null
            else
                pkill -f "$APP_MATCH/Contents/MacOS/" 2>/dev/null
            fi
            sleep 2
            if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ]; then
                if ! space_ok "$src" "$VOL_NAME"; then
                    err "$lbl: на диске НЕ ХВАТИТ места — папку оставил локально, освободи диск и запусти снова."
                    continue
                fi
                if migrate_to_disk "$src" "$dst" "$lbl"; then
                    ok "$lbl: папка создана приложением и подключена к диску."
                fi
                continue
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
            ALL_OK=0; err "$lbl — НЕ подключен. Смотри сообщения выше."
        fi
    done
    if [ "$ALL_OK" = "1" ]; then
        ok "Итог фазы: все приложения подключены к диску."
        stage_mark data
    else
        # Фазу НЕ отмечаем завершенной: при повторном запуске она пройдет еще раз
        # (операции идемпотентны) и до линкует, что сегодня не получилось.
        warn "Итог фазы: есть НЕподключенные приложения. Разберись (права Терминала / место на диске) и запусти скрипт еще раз — эта фаза повторится."
    fi
    ding_subtle
    phase_end "Данные приложений"
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
ok "Экран гаснет через $DISPLAY_SLEEP мин, автовыход через $AUTOLOGOUT_MIN мин."

# В Загрузках чистим ТОЛЬКО то, что могли скачать сами: раньше сносились
# все *.dmg/*.pkg/*.zip, включая личные файлы пользователя.
DL="$HOME/Downloads"
for n in Telegram Sublime Sphere MailMate qTox Tukan VeraCrypt Excel fuse-t; do
    for f in "$DL/$n".dmg "$DL/$n".pkg "$DL/$n".zip; do
        [ -f "$f" ] && rm -f "$f" 2>/dev/null
    done
done
rm -f /tmp/*.pkg /tmp/*.dmg /tmp/*.zip /tmp/Sublime* /tmp/MailMate* /tmp/hitoolbox.plist /tmp/diskinfo.plist /tmp/disks.plist 2>/dev/null

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
    local key src lbl tgt n bad=0 total=0 good=0 warnc=0
    local ROWS=""
    row() { # row <статус-символ> <цвет> <имя> <деталь>
        # Паддинг по СИМВОЛАМ (${#} знает UTF-8), а не по байтам, как printf %-14s —
        # иначе рамка «плывет» на кириллице («Брандмауэр», «Секретный том»).
        local pad=$(( 14 - ${#3} )); [ $pad -lt 1 ] && pad=1
        ROWS="$ROWS$2  $1 $3$(printf '%*s' $pad '')${NC} ${GREY}$4${NC}\n"
    }
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
                    good=$((good + 1)); row "✓" "$GREEN" "$lbl" "на диске, данные опознаны ($n объектов)"
                elif [ "$n" -gt 0 ]; then
                    good=$((good + 1)); row "✓" "$GREEN" "$lbl" "на диске ($n объектов, нестандартная папка)"
                else
                    warnc=$((warnc + 1))
                    row "▲" "$YELLOW" "$lbl" "папка на диске пустая (заполнится при запуске)"
                fi
            else
                row "✗" "$RED" "$lbl" "ссылка БИТАЯ — диск смонтирован?"
                bad=$((bad + 1))
            fi
        else
            row "✗" "$RED" "$lbl" "НЕ ссылка — данные локальные или папки нет"
            bad=$((bad + 1))
        fi
    done
    total=$((total + 3))
    if fdesetup status 2>/dev/null | grep -qi "is On"; then good=$((good + 1)); row "✓" "$GREEN" "FileVault" "диск зашифрован"
    else row "✗" "$RED" "FileVault" "НЕ включен"; bad=$((bad + 1)); fi
    # Без sudo: /Library/Preferences/com.apple.alf.plist обычному юзеру недоступен,
    # defaults read молча возвращал пустоту — ложный ✗. Пароль к этому моменту уже
    # стерт выше, поэтому root только через живой таймстамп sudo (-n); на ряде
    # версий macOS --getglobalstate читается и вовсе без root — пробуем оба пути.
    # Если прочитать не удалось — честный ▲, а не выдуманный ✗.
    FW_ST=""
    if sudo -n true 2>/dev/null; then
        FW_ST=$(sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)
    fi
    [ -z "$FW_ST" ] && FW_ST=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)
    if printf '%s' "$FW_ST" | grep -qi enabled; then
        good=$((good + 1)); row "✓" "$GREEN" "Брандмауэр" "включен"
    elif [ -n "$FW_ST" ]; then
        row "✗" "$RED" "Брандмауэр" "НЕ включен"; bad=$((bad + 1))
    else
        warnc=$((warnc + 1)); row "▲" "$YELLOW" "Брандмауэр" "статус не прочитался — глянь в Настройки -> Сеть"
    fi
    if [ -d /Applications/VeraCrypt.app ] && pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t"; then good=$((good + 1)); row "✓" "$GREEN" "VeraCrypt" "установлен + FUSE-T"
    else row "✗" "$RED" "VeraCrypt" "не найден / нет FUSE-T"; bad=$((bad + 1)); fi
    # Инфо-строка (не в счет): сколько свободно на секретном томе
    if [ -n "$VOL_NAME" ] && [ -d "$VOL_NAME" ]; then
        local vfree vtotal
        vfree=$(df -kP "$VOL_NAME" 2>/dev/null | awk 'NR==2 {printf "%.1f", $4/1048576}')
        vtotal=$(df -kP "$VOL_NAME" 2>/dev/null | awk 'NR==2 {printf "%.0f", $2/1048576}')
        row "•" "$CYAN" "Секретный том" "свободно ${vfree:-?} из ${vtotal:-?} ГБ"
    fi

    local W=58
    echo ""
    echo -e "  ${CYAN}┌$(rep "─" $W)┐${NC}"
    echo -e "  ${CYAN}│${NC}${BOLD}  ИТОГ САМОПРОВЕРКИ$(rep " " $((W - 20)))${NC}${CYAN}│${NC}"
    echo -e "  ${CYAN}├$(rep "─" $W)┤${NC}"
    printf '%b' "$ROWS" | while IFS= read -r rline; do
        local vis
        vis=$(printf '%s' "$rline" | sed $'s/\033\[[0-9;]*m//g')
        printf '  \033[0;36m│\033[0m%s%*s\033[0;36m│\033[0m\n' "$rline" $((W - ${#vis})) ""
    done
    echo -e "  ${CYAN}└$(rep "─" $W)┘${NC}"
    echo ""
    # Желтые пункты считаем отдельно: раньше они не попадали ни в good, ни в
    # bad — итог не сходился, а вывод все равно говорил «всё зелёное».
    if [ "$bad" = "0" ] && [ "$warnc" = "0" ]; then
        echo -e "  ${GREEN}${BOLD}✓ САМОПРОВЕРКА: $good/$total — всё зелёное.${NC}"
    elif [ "$bad" = "0" ]; then
        echo -e "  ${YELLOW}${BOLD}▲ САМОПРОВЕРКА: $good/$total зелёные, $warnc с замечанием (▲), ошибок нет.${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}▲ САМОПРОВЕРКА: $good/$total зелёные, $bad с ошибкой (✗), $warnc с замечанием (▲) — смотри выше.${NC}"
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
phase_summary
ding

echo ""
echo -e "  ${GREEN}$(rep "━" "$(tw)")${NC}"
echo -e "  ${GREEN}▎${NC}  ${BOLD}\033[38;5;82mВСЕ! Mac НАСТРОЕН И ЗАЩИЩЕН.${NC}"
echo -e "  ${GREEN}$(rep "━" "$(tw)")${NC}"
echo ""
echo -e "  ${BOLD}Что сделано:${NC}"
echo "    • защита: блокировка сразу, брандмауэр+невидимость, SSH/экран/ARD выкл"
echo "    • AirDrop/Handoff/геолокация/аналитика/Siri — выкл (каждый пункт проверен)"
echo "    • недавние приложения в Dock скрыты"
echo "    • FileVault: шифрование включено (ключ восстановления был показан один раз в терминале, нигде не сохранен)"
echo "    • данные приложений — на секретном диске, система смотрит на них через ссылки"
echo "    • раскладки ABC+Русская (Ctrl+Space), часовой пояс по IP, Wi-Fi по выбору"
echo ""
# Обещание из вопроса про Полный доступ к диску: собираем всё, что не встало
# автоматически. Раньше флаги *_MANUAL выставлялись, но нигде не читались.
MANUAL_LIST=""
[ "${SL_MANUAL:-0}" = "1" ]    && MANUAL_LIST="$MANUAL_LIST    • Блокировка «сразу»: Настройки -> Экран блокировки\n"
[ "${FW_MANUAL:-0}" = "1" ]    && MANUAL_LIST="$MANUAL_LIST    • Брандмауэр и невидимость: Настройки -> Сеть -> Брандмауэр\n"
[ "${SHARE_MANUAL:-0}" = "1" ] && MANUAL_LIST="$MANUAL_LIST    • Общий доступ (экран/ARD/SSH): Настройки -> Общий доступ\n"
[ "${KB_MANUAL:-0}" = "1" ]    && MANUAL_LIST="$MANUAL_LIST    • Русская раскладка: Настройки -> Клавиатура -> Источники ввода\n"
[ "${FDA:-1}" = "0" ]          && MANUAL_LIST="$MANUAL_LIST    • Полный доступ к диску Терминалу: Настройки -> Конфиденциальность и безопасность\n"
if [ -n "$MANUAL_LIST" ]; then
    echo -e "  ${YELLOW}${BOLD}НУЖНО ДОДЕЛАТЬ РУКАМИ:${NC}"
    printf '%b' "$MANUAL_LIST"
    echo ""
fi

echo -e "  ${YELLOW}${BOLD}ПРОВЕРЬ В КОНЦЕ:${NC}"
echo "    1) Флажок раскладки в строке меню сверху (если нет — нажми Ctrl+Space)"
echo "    2) Вставь секретный диск -> VeraCrypt -> Mount -> запусти Telegram/Sphere"
echo ""
echo -e "  ${GREY}Завершаю через 5 сек...${NC}"
sleep 5
# Отметки фаз стираю, только если все фазы отметились; иначе следующий запуск
# продолжит с недоделанного места.
if stage_done data; then rm -f "$STAGE_FILE"
else warn "Есть недоделанные фазы — отметки прогресса оставил: следующий запуск продолжит с них."; fi
exit 0

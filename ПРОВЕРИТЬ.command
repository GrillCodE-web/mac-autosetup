#!/bin/bash

# ============================================================
#  ПРОВЕРКА НАСТРОЙКИ MAC
#  Запускай после перезагрузки. Смотрит все настройки сам
#  и показывает зеленый/красный список. Ничего не меняет.
# ============================================================

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

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

# --- Визуальный каркас (как в ЗАПУСТИТЬ.command) ---------------------------
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
spin() {
    local f='|/-\' c
    c=${f:$SPIN_N:1}
    SPIN_N=$(( (SPIN_N + 1) % 4 ))
    printf '\033[2K  %s  %s ...\r' "$c" "$1"
}
spin_end() { printf '\033[2K'; }

good() { echo -e "  ${GREEN}${BOLD}✓${NC}  $1"; PASS=$((PASS+1)); }
bad()  { echo -e "  ${RED}${BOLD}✗${NC}  $1"; FAIL=$((FAIL+1)); }
dunno(){ echo -e "  ${YELLOW}${BOLD}?${NC}  $1"; UNKNOWN=$((UNKNOWN+1)); }
dim()  { echo -e "  ${GREY}· $1${NC}"; }

# Папка Telegram: префикс команды (6N38VWS5BX. и др.) у разных сборок отличается
TG_GLOB="*keepcoder.Telegram"
tg_local_dir() {
    local d
    d=$(find "$HOME/Library/Group Containers" -maxdepth 1 -name "$TG_GLOB" 2>/dev/null | head -1)
    [ -z "$d" ] && d="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram"
    echo "$d"
}

sect() {
    local t="$1" w
    w=$(tw)
    echo ""
    echo -e "  ${GREY}─── $(t2s $SECONDS) $(rep "─" $((w - 10)))${NC}"
    echo -e "  ${CYAN}${BOLD}▎${NC} ${BOLD}$t${NC}"
    echo -e "  ${GREY}$(rep "─" $w)${NC}"
}

if [ "$(uname)" != "Darwin" ]; then
    echo "Этот скрипт работает только на macOS."
    exit 1
fi

clear
TITLE_W=$(tw)
echo ""
echo -e "  ${CYAN}$(rep "━" "$TITLE_W")${NC}"
echo -e "  ${CYAN}▎${NC}${BOLD}  ПРОВЕРКА НАСТРОЙКИ MAC${NC}"
echo -e "  ${CYAN}▎${NC}  ${GREY}MAC SETUP CHECK${NC}"
echo -e "  ${CYAN}$(rep "━" "$TITLE_W")${NC}"
echo -e "  ${GREY}macOS $(sw_vers -productVersion 2>/dev/null) · $(sysctl -n hw.model 2>/dev/null) · $(date '+%d.%m.%Y %H:%M')${NC}"
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
# socketfilterfw на Sequoia/Tahoe может ответить «managed only by MDM» или
# пустотой. Пустой/странный ответ — это «не смог прочитать» (жёлтый ?), а НЕ
# «выключен»: в Настройках при этом всё может быть включено.
FW="/usr/libexec/ApplicationFirewall/socketfilterfw"
fw_sig() {
    local out
    out=$(printf '%s\n' "$ADMIN_PASS" | sudo -S "$FW" "$1" 2>/dev/null)
    [ -z "$out" ] && out=$("$FW" "$1" 2>/dev/null)
    case "$out" in *"enabled"*|*"State = 1"*) echo "on" ;;
                   *"disabled"*|*"State = 0"*) echo "off" ;;
                   *) echo "unknown" ;; esac
}
case "$(fw_sig --getglobalstate)" in
    on)  good "Брандмауэр включен." ;;
    off) bad "Брандмауэр ВЫКЛЮЧЕН! Настройки -> Сеть -> Брандмауэр." ;;
    *)   dunno "Состояние брандмауэра из терминала не читается — проверь глазами: Настройки -> Сеть -> Брандмауэр." ;;
esac
case "$(fw_sig --getblockall)" in
    on)  dunno "Блокировка ВСЕХ входящих включена — с ней VeraCrypt/FUSE-T может виснуть на монтировании." ;;
    off) good "Блокировка всех входящих выключена — так и задумано (иначе ломается VeraCrypt/FUSE-T)." ;;
    *)   dunno "Состояние блокировки всех входящих не читается из терминала." ;;
esac
case "$(fw_sig --getstealthmode)" in
    on)  good "Режим невидимости (stealth) включен." ;;
    off) bad "Режим невидимости ВЫКЛЮЧЕН! Настройки -> Сеть -> Брандмауэр -> Параметры -> «Включить режим невидимости»." ;;
    *)   dunno "Состояние режима невидимости не читается — проверь: Настройки -> Сеть -> Брандмауэр -> Параметры." ;;
esac

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
# Проверяем по процессу демона и по флагу launchctl (обе проверки через sudo —
# system-домен из user-сессии не виден, прежний «launchctl list» врал «хорошо»).
if pgrep -x screensharingd >/dev/null 2>&1; then
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
    if system_profiler SPBluetoothDataType 2>/dev/null | grep -qi "Connected: Yes"; then
        dim "Причина авто-включения: к Mac подключены Bluetooth-устройства (клавиатура/мышь/наушники)."
        dim "Пока они подключены, macOS сам включает Bluetooth. Замени клаву/мышь на ПРОВОДНЫЕ."
    fi
elif [ "$BT" = "0" ]; then
    dunno "Настройка говорит «выключен», но живое состояние радио не прочитал — проверь глазами: Настройки -> Bluetooth."
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
    # Том может подняться только на чтение или с чужими правами — тогда все
    # приложения «работают», но МОЛЧА не могут сохранять данные. Проверяю
    # записью и тут же стираю тестовый файл (следов не остаётся).
    if ! { touch "$DATA_DIR/.rw-check" 2>/dev/null && rm -f "$DATA_DIR/.rw-check" 2>/dev/null; }; then
        bad "Папка данных на диске НЕДОСТУПНА НА ЗАПИСЬ — Safari и остальные приложения не смогут сохранять данные!"
        dim "Переподключи том VeraCrypt (проверь пароль/права) и запусти проверку снова."
    fi
else
    dunno "Секретный диск НЕ найден — проверки данных будут неполными."
    dim "Подключи его через VeraCrypt и запусти проверку снова."
    OTHER=$(ls /Volumes 2>/dev/null | tr '\n' ' ')
    dim "сейчас подключены тома: ${OTHER:-нет}"
fi

check_link() {
    local src="$1" name="$2" absent_hint="$3"
    if [ -L "$src" ]; then
        local target=$(readlink "$src")
        case "$target" in
            /Volumes/*)
                local vol="/Volumes/$(echo "$target" | cut -d/ -f3)"
                if [ ! -d "$vol" ]; then
                    dunno "$name — том $vol сейчас не подключен: симлинк не проверить (это норма без диска)."
                    [ -n "$absent_hint" ] && dim "$absent_hint"
                elif [ ! -d "$target" ]; then
                    bad "$name — симлинк ВИСИТ В НИКУДА: $target не существует, а диск подключен. Запусти ЗАПУСТИТЬ.command."
                else
                    # Смотрим ПРЯМО на цель на диске: путь ~/Library/Safari закрыт
                    # системой (TCC), и без «Полного доступа к диску» сквозь
                    # симлинк не видно НИЧЕГО — раньше это печаталось как
                    # «диск не подключен», хотя диск подключен. Читаем цель
                    # напрямую — она вне защищенных папок и всегда читается.
                    local sz cnt
                    cnt=$(ls -A "$target/" 2>/dev/null | wc -l | tr -d ' ')
                    sz=$(du -sh "$target/" 2>/dev/null | awk '{print $1}')
                    if [ "$cnt" = "0" ]; then
                        bad "$name — симлинк рабочий, но папка на диске ПУСТАЯ ($target)."
                    else
                        good "$name — данные на секретном диске (${sz:-?}, файлов: $cnt)."
                        dim "$target"
                        if ! [ -e "$src" ]; then
                            dim "внимание: через сам симлинк папка не читается — дай Терминалу «Полный доступ к диску» (Настройки -> Конфиденциальность и безопасность -> Полный доступ к диску), иначе Safari может не увидеть свои данные."
                        fi
                    fi
                fi ;;
            *)
                bad "$name — симлинк ведет НЕ на внешний диск, а в: $target" ;;
        esac
    elif [ -d "$src" ]; then
        bad "$name — данные лежат В СИСТЕМЕ (не на диске)! Запусти ЗАПУСТИТЬ.command еще раз."
    else
        case "$src" in
            */Safari) dunno "$name — папка не видна: либо её нет, либо Терминалу не хватает «Полного доступа к диску» (система закрывает ~/Library/Safari). Дай доступ, перезапусти Терминал и проверь снова." ;;
            *)        dunno "$name — данных нет ни в системе, ни симлинка (приложение еще не запускалось?)." ;;
        esac
    fi
}

check_link "$(tg_local_dir)/stable" "Telegram"
check_link "$HOME/Library/Application Support/Sublime Text" "Sublime Text"
check_link "$HOME/Library/Application Support/app.ls" "Sphere"
# Safari при отключенном диске видит «пустые» данные. Если включена
# синхронизация iCloud — он может решить, что закладки УДАЛЕНЫ, и затереть
# ими облако (классическая потеря закладок после подмены папки). Поэтому
# без диска Safari лучше вообще не открывать.
SF_NO_DISK="Safari без диска лучше не открывать: он увидит «пустые» закладки, и iCloud-синхронизация может затереть закладки в облаке."
check_link "$HOME/Library/Safari" "Safari" "$SF_NO_DISK"
# Safari хранит данные в ДВУХ местах: профиль (~/Library/Safari — выше) и
# контейнер ~/Library/Containers/com.apple.Safari (cookies, настройки, кэш,
# история профилей). Проверяем ОБА — половинчатый перенос оставляет в
# системе cookies и логины.
if [ -L "$HOME/Library/Containers/com.apple.Safari" ] || [ -e "$HOME/Library/Containers/com.apple.Safari" ]; then
    check_link "$HOME/Library/Containers/com.apple.Safari" "Safari — контейнер (cookies)" "$SF_NO_DISK"
fi
[ -d "/Applications/MailMate.app" ] && check_link "$HOME/Library/Application Support/MailMate" "MailMate"
[ -d "/Applications/qTox.app" ] && check_link "$HOME/Library/Application Support/Tox" "qTox"
# Joplin (если стоит/были данные): проверяем как остальные
[ -e "$HOME/Library/Application Support/joplin-desktop" ] && check_link "$HOME/Library/Application Support/joplin-desktop" "Joplin"
# Tukan — sandbox: его данные в контейнере (Application Support он не пишет;
# старые проверки смотрели не туда и видели пустышку)
[ -e "$HOME/Library/Containers/me.tukan.tukan" ] && check_link "$HOME/Library/Containers/me.tukan.tukan" "Tukan"
TUK_STRAY=$(find "$HOME/Library/Application Support" -maxdepth 1 -iname "*tukan*" 2>/dev/null | head -1)
[ -n "$TUK_STRAY" ] && bad "Tukan: лишняя папка в Application Support ($TUK_STRAY) — Tukan туда не пишет; запусти ЗАПУСТИТЬ.command, он уберёт."

# Пользовательские папки (Рабочий стол/Документы/Загрузки) НЕ проверяем:
# фича их переноса на диск снята — папки остаются в системе как есть.

sect "ПРОГРАММЫ / APPLICATIONS"

# --- 6. Приложения на месте ---
for APP in "VeraCrypt" "Telegram" "Sublime Text"; do
    if [ -d "/Applications/$APP.app" ]; then
        good "Программа $APP установлена."
    else
        bad "Программа $APP НЕ установлена!"
    fi
done
for APP in "MailMate" "qTox" "Microsoft Excel"; do
    [ -d "/Applications/$APP.app" ] && good "Программа $APP установлена (ставилась по желанию)."
done
if pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t"; then
    good "FUSE-T установлен (без него VeraCrypt не смонтирует диск)."
else
    bad "FUSE-T НЕ установлен — VeraCrypt не сможет подключить диск."
fi
# Дубли приложений: «MailMate 2.app», «... 3.app», «... копия.app» и т.п.
# Считаем дублем ТОЛЬКО если рядом есть базовая копия без номера (иначе «Linken
# Sphere 2.app» — это название версии, а не дубль).
DUPS=""
while IFS= read -r d; do
    [ -z "$d" ] && continue
    base=$(echo "$d" | sed -E 's/ [0-9]+\.app$/.app/; s/ ?(копия|copy)[^/]*\.app$/.app/I')
    [ "$base" != "$d" ] && [ -d "$base" ] && DUPS="$DUPS$d"$'\n'
done < <(find /Applications -maxdepth 1 \( -iname "* [0-9].app" -o -iname "*копия*.app" -o -iname "*copy*.app" \) 2>/dev/null)
DUPS=$(echo "$DUPS" | grep -v '^$')
if [ -n "$DUPS" ]; then
    bad "В /Applications есть дубли программ — запусти ЗАПУСТИТЬ.command, он их удалит. Лишние:"
    echo "$DUPS" | while IFS= read -r d; do dim "$d"; done
else
    good "Дублей приложений в /Applications нет."
fi

sect "СИСТЕМНЫЕ НАСТРОЙКИ / SYSTEM SETTINGS"

# --- 7. Аналитика («Поделиться аналитикой с Apple») ---
# Читаем оба домена: свежие macOS хранят в com.apple.SubmitDiagInfo, старые — в
# DiagnosticMessagesHistory.plist. Достаточно, чтобы хоть один был выключен (=0).
AS=$(defaults read "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" AutoSubmit 2>/dev/null)
AS2=$(defaults read /Library/Preferences/com.apple.SubmitDiagInfo AutoSubmit 2>/dev/null)
if [ "$AS" = "0" ] || [ "$AS2" = "0" ]; then
    good "Отправка аналитики Apple выключена."
elif [ -z "$AS" ] && [ -z "$AS2" ]; then
    dunno "Аналитика: ключ ещё не записан — проверь глазами: Настройки -> Конфиденциальность -> Аналитика (галки сняты)."
else
    bad "Отправка аналитики Apple ВКЛЮЧЕНА — сними: Настройки -> Конфиденциальность -> Аналитика."
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

# --- 10. Автообновления: включены? и есть ли обновления прямо сейчас ---
# Ключ читаем через sudo: обычный defaults берет кэш cfprefsd и может соврать
# «выключено», хотя всё включено (так и вышло на первом реальном прогоне).
AU=$(echo "$ADMIN_PASS" | sudo -S defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null)
if [ "$AU" = "1" ]; then
    good "Автообновления включены: Mac сам проверяет и скачивает обновления."
else
    bad "Автопроверка обновлений выключена (Настройки -> Основные -> Обновление ПО)."
fi

# Есть ли обновления, которые пора поставить. СТАВИТЬ их за тебя скрипт НЕ будет
# (автоустановка выключена нарочно — без внезапных перезагрузок), просто скажу.
# СНАЧАЛА честно проверяем доступ до серверов Apple: раньше после 36 секунд
# ожидания softwareupdate убивался и печаталось «нет сети», хотя сеть работала —
# Apple просто медленно отвечает после переустановки. Теперь сеть проверяется
# отдельно (до трёх серверов Apple), softwareupdate ждём до 3 минут, а при
# неудаче показываем его собственную ошибку вместо выдумки про «нет сети».
NET_OK=0
for NETURL in "https://swscan.apple.com" "https://swcdn.apple.com" "https://support.apple.com"; do
    if curl -s -m 8 -o /dev/null "$NETURL"; then NET_OK=1; break; fi
done
if [ $NET_OK -eq 0 ]; then
    dunno "Сети до серверов Apple сейчас нет — проверь потом сам: Настройки -> Основные -> Обновление ПО."
else
    UPDF="/tmp/.maccheck_upd_$$"
    UPDE="$UPDF.err"
    ( softwareupdate --list >"$UPDF" 2>"$UPDE" ) &
    UPD_PID=$!
    UPD_TRY=0
    # 600 * 0.3 сек = до 3 минут: после чистой установки каталог тянется долго
    while kill -0 $UPD_PID 2>/dev/null && [ $UPD_TRY -lt 600 ]; do
        spin "проверяю обновления macOS — $((UPD_TRY / 10 * 3 + 3)) сек"
        sleep 0.3
        UPD_TRY=$((UPD_TRY + 1))
    done
    kill $UPD_PID 2>/dev/null; wait $UPD_PID 2>/dev/null
    spin_end
    UPD=$(cat "$UPDF" 2>/dev/null)
    UPDERR=$(grep -m3 -vi "password" "$UPDE" 2>/dev/null | grep -vi '^[[:space:]]*$')
    rm -f "$UPDF" "$UPDE"
    UPDSEC=$((UPD_TRY / 10 * 3))
    if printf '%s\n' "$UPD" | grep -qiE "No new software available|No updates available"; then
        good "Обновлений macOS сейчас нет — всё свежее (сеть работает)."
    elif printf '%s\n' "$UPD" | grep -q '^[[:space:]]*\*'; then
        dunno "Есть обновления macOS — поставь их сам, когда удобно (Настройки -> Основные -> Обновление ПО)."
        printf '%s\n' "$UPD" | grep '^[[:space:]]*\*' | sed 's/^[*[:space:]]*//' | head -5 | while IFS= read -r u; do
            dim "обновление: $u"
        done
    elif [ -n "$UPDERR" ]; then
        dunno "Сеть есть, но проверка обновлений упала с ошибкой (отвечает сам Apple):"
        printf '%s\n' "$UPDERR" | while IFS= read -r u; do dim "$u"; done
        dim "Проверь потом сам: Настройки -> Основные -> Обновление ПО."
    else
        dunno "Сеть работает, но серверы Apple не ответили за $UPDSEC сек (бывает после переустановки). Проверь потом сам: Настройки -> Основные -> Обновление ПО."
    fi
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
    good "Раскладки записаны в настройках: английская (U.S.) + русская. ПРОВЕРЬ флажок в строке меню — если русской нет, добавь через Настройки -> Клавиатура -> Источники ввода -> +."
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
# «Недавние объекты» (Dock-секция, меню яблока, .sfl2) НЕ проверяем и НЕ трогаем:
# вмешательство в списки недавних вешало меню системы — фича снята решением владельца.
TRASH=$(ls -A "$HOME/.Trash" 2>/dev/null | wc -l | tr -d ' ')
if [ "$TRASH" = "0" ]; then
    good "Корзина пуста."
else
    dunno "В корзине $TRASH объектов — очисти, из нее данные восстанавливаются."
fi
if [ -s "$HOME/.bash_history" ] || [ -s "$HOME/.zsh_history" ] || [ -s "$HOME/.python_history" ]; then
    dunno "История терминала не пуста — почисти. Введи в Терминале ЭТИ команды:"
    dim "history -c"
    dim "rm -f ~/.zsh_history ~/.bash_history ~/.python_history"
    dim "touch ~/.zsh_sessions_disable && rm -rf ~/.zsh_sessions && mkdir -p ~/.zsh_sessions"
    dim "потом ЗАКРОЙ окно Терминала (иначе история запишется обратно при выходе)."
else
    good "История терминала пуста."
fi
if [ -e "$HOME/.zsh_sessions_disable" ]; then
    good "Сессионная история zsh отключена насовсем (~/.zsh_sessions_disable)."
else
    dunno "zsh все еще пишет сессионные файлы — создай ~/.zsh_sessions_disable (ЗАПУСТИТЬ.command делает это сам)."
fi

# --- 15. Часовой пояс (не палит реальное место) ---
TZ_LINK=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
TZAUTO=$(defaults read /Library/Preferences/com.apple.timezone.auto Active 2>/dev/null)
if [ -n "$TZ_LINK" ] && [ "$TZAUTO" != "1" ]; then
    good "Часовой пояс зафиксирован: $TZ_LINK (автоопределение по геолокации выключено — часы не выдают реальное место)."
elif [ "$TZAUTO" = "1" ]; then
    bad "Автоопределение часового пояса ВКЛЮЧЕНО — macOS может вернуть реальный пояс (Настройки -> Основные -> Дата и время)."
else
    dunno "Часовой пояс не прочитал — проверь: Настройки -> Основные -> Дата и время."
fi

# --- ИТОГ ---
TOTAL=$((PASS + FAIL + UNKNOWN))
PCT=100
[ "$TOTAL" -gt 0 ] && PCT=$((PASS * 100 / TOTAL))
BAR_W=24
FILLED=$((PCT * BAR_W / 100))
[ "$FILLED" -gt "$BAR_W" ] && FILLED=$BAR_W
EMPTY=$((BAR_W - FILLED))
W=$(tw)
echo ""
echo -e "  ${CYAN}$(rep "━" "$W")${NC}"
echo -e "  ${CYAN}▎${NC}${BOLD}  ИТОГ / RESULT${NC}"
echo -e "  ${CYAN}$(rep "━" "$W")${NC}"
echo ""
echo -e "  ${GREEN}$(rep "▓" "$FILLED")${NC}${GREY}$(rep "░" "$EMPTY")${NC}  ${BOLD}${PCT}%${NC}"
echo -e "   ${GREEN}${BOLD}✓ ${PASS}${NC}     ${RED}${BOLD}✗ ${FAIL}${NC}     ${YELLOW}${BOLD}? ${UNKNOWN}${NC}"
echo -e "   ${GREY}в порядке      проблема      проверь глазами${NC}"
echo ""
if [ "$FAIL" -eq 0 ] && [ "$UNKNOWN" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}ИДЕАЛЬНО — все пункты зеленые, Mac настроен правильно.${NC}"
    echo -e "  ${GREY}PERFECT — every item is green, the Mac is set up correctly.${NC}"
elif [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}Красных пунктов нет — Mac настроен правильно. Желтые проверь глазами.${NC}"
    echo -e "  ${GREY}No red items — the Mac is set up correctly. Check the yellow ones by eye.${NC}"
else
    echo -e "  ${RED}${BOLD}Красных пунктов — ${FAIL}. Сделай, что в них написано, и запусти проверку снова.${NC}"
    echo -e "  ${GREY}There are ${FAIL} red items — fix them and run this check again.${NC}"
fi
echo ""
echo -e "  ${GREY}Окно можно закрыть. / You can close this window. · $(t2s $SECONDS)${NC}"

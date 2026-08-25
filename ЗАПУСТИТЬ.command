#!/bin/bash

# ============================================================
#  АВТОНАСТРОЙКА MAC — ПОЛНЫЙ АВТОМАТ
#  Человеку нужно только: нажимать Enter и один раз ввести пароль
# ============================================================

LOG="/tmp/autosetup_log.txt"
exec > >(tee -a "$LOG") 2>&1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[ОШИБКА]${NC} $1"; }

step() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

pause() {
    echo ""
    echo -e "${YELLOW}>>> Когда сделаешь — нажми Enter <<<${NC}"
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
step "НАЧАЛО НАСТРОЙКИ"
echo "Сейчас скрипт настроит этот Mac полностью сам."
echo "От тебя нужно минимум действий — просто следуй экрану."
echo "Весь ход записывается в файл: $LOG"
echo ""

# ------------------------------------------------------------
# ВОПРОСЫ В НАЧАЛЕ (чтобы потом не отвлекать)
# ------------------------------------------------------------
step "ВОПРОСЫ (один раз, в начале)"

echo "1) Создать ОТДЕЛЬНУЮ рабочую учетную запись (вторая, кроме основной)?"
echo "   НЕТ — проще: одна учетка, один пароль, запутаться невозможно."
echo "   ДА  — чуть безопаснее, но будет две учетки и два пароля."
read -r -p "   (да/нет) [нет]: " CREATE_USER
CREATE_USER=${CREATE_USER:-нет}

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
echo "$ADMIN_PASS" | sudo -S -k true 2>/dev/null
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
HAVE_DISK=${HAVE_DISK:-да}
if [ "$HAVE_DISK" = "да" ]; then
    echo "   Введи пароль от диска:"
    read -rs -p "   Пароль диска: " DISK_PASS; echo ""
    read -r -p "   PIM (если не знаешь, что это — просто Enter): " DISK_PIM
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

echo ""
echo "4) Часовой пояс под страну VPN (чтобы часы не палели реальное место)."
echo "   Примеры: America/New_York, Europe/Berlin, Europe/London"
read -r -p "   Часовой пояс (Enter = не менять): " VPN_TZ

echo ""
ok "Все вопросы заданы. Дальше скрипт работает сам (пару раз попросит вставить диск)."

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
    echo "$ADMIN_PASS" | sudo -S dscl . -create /Users/"$NEW_USER"
    echo "$ADMIN_PASS" | sudo -S dscl . -create /Users/"$NEW_USER" UserShell /bin/bash
    echo "$ADMIN_PASS" | sudo -S dscl . -create /Users/"$NEW_USER" RealName "$NEW_USER"
    echo "$ADMIN_PASS" | sudo -S dscl . -create /Users/"$NEW_USER" UniqueID "$NEW_ID"
    echo "$ADMIN_PASS" | sudo -S dscl . -create /Users/"$NEW_USER" PrimaryGroupID 20
    echo "$ADMIN_PASS" | sudo -S dscl . -create /Users/"$NEW_USER" NFSHomeDirectory /Users/"$NEW_USER"
    echo "$ADMIN_PASS" | sudo -S dscl . -passwd /Users/"$NEW_USER" "$USER_PASS"
    echo "$ADMIN_PASS" | sudo -S createhomedir -c -u "$NEW_USER" &>/dev/null
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

# Выключение дисплея через 5 минут
echo "$ADMIN_PASS" | sudo -S pmset -a displaysleep 5 &>/dev/null
ok "Дисплей выключается через 5 минут."

# Автовыход из системы через 30 минут
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay -int 1800
ok "Автовыход из системы через 30 минут."

# Второй ползунок «Дополнительно»: пароль администратора для общесистемных настроек
AUTH_TMP="/tmp/sysprefs_auth.plist"
echo "$ADMIN_PASS" | sudo -S security authorizationdb read system.preferences > "$AUTH_TMP" 2>/dev/null
if [ -s "$AUTH_TMP" ] && plutil -replace shared -bool false "$AUTH_TMP" 2>/dev/null; then
    if echo "$ADMIN_PASS" | sudo -S security authorizationdb write system.preferences < "$AUTH_TMP" 2>/dev/null; then
        ok "Общесистемные настройки — только с паролем администратора."
    else
        warn "Не смог включить «пароль админа для общесистемных настроек» — включи руками (Настройки -> Конфиденциальность -> Дополнительно)."
    fi
else
    warn "Не смог включить «пароль админа для общесистемных настроек» — включи руками (Настройки -> Конфиденциальность -> Дополнительно)."
fi
rm -f "$AUTH_TMP"

# Экран входа: без подсказок пароля, без сообщения, без кнопок сна/перезагрузки
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.loginwindow RetriesUntilHint -int 0 2>/dev/null
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText -string "" 2>/dev/null
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.loginwindow PowerOffDisabled -bool true 2>/dev/null
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.loginwindow RestartDisabled -bool true 2>/dev/null
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.loginwindow SleepDisabled -bool true 2>/dev/null
ok "Экран входа: подсказки, сообщение и кнопки питания отключены."

# Брандмауэр: вкл + блок входящих + stealth
FW="/usr/libexec/ApplicationFirewall/socketfilterfw"
echo "$ADMIN_PASS" | sudo -S "$FW" --setglobalstate on &>/dev/null
echo "$ADMIN_PASS" | sudo -S "$FW" --setblockall on &>/dev/null
echo "$ADMIN_PASS" | sudo -S "$FW" --setstealthmode on &>/dev/null
ok "Брандмауэр: включен, блок входящих, режим невидимости."

# AirDrop и Handoff выключить
defaults write com.apple.NetworkBrowser DisableAirDrop -bool YES 2>/dev/null
defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool no 2>/dev/null
defaults -currentHost write com.apple.coreservices.useractivityd ActivityReceivingAllowed -bool no 2>/dev/null
ok "AirDrop и Handoff выключены."

# Геолокация выключить
echo "$ADMIN_PASS" | sudo -S defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool false 2>/dev/null
ok "Службы геолокации выключены."

# Аналитика выключить
defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit -bool false 2>/dev/null
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit -bool false 2>/dev/null
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
        echo "$ADMIN_PASS" | sudo -S networksetup -removenetworkservice "$WIFI_SVC" &>/dev/null
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
    echo "$ADMIN_PASS" | sudo -S systemsetup -settimezone "$VPN_TZ" &>/dev/null && ok "Часовой пояс: $VPN_TZ" || warn "Не смог поставить часовой пояс $VPN_TZ — задай руками в Настройках."
fi

# Bluetooth: глушим (второй канал утечки после Wi-Fi)
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.Bluetooth.plist ControllerPowerState -int 0 2>/dev/null
echo "$ADMIN_PASS" | sudo -S pkill bluetoothd 2>/dev/null
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

install_dmg() {
    local url="$1" appname="$2" fname="$3"
    [ -z "$fname" ] && fname=$(basename "$url")
    local dmg="$DL/$fname"
    echo "Скачиваю $appname..."
    curl -L -s -o "$dmg" "$url"
    if [ ! -f "$dmg" ] || [ ! -s "$dmg" ]; then
        err "$appname не скачался. Поставь вручную позже."
        return 1
    fi
    echo "Устанавливаю $appname..."
    if [[ "$fname" == *.pkg ]]; then
        echo "$ADMIN_PASS" | sudo -S installer -pkg "$dmg" -target / -quiet
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
            echo "$ADMIN_PASS" | sudo -S cp -R "$zapp" /Applications/ 2>/dev/null
            echo "$ADMIN_PASS" | sudo -S xattr -dr com.apple.quarantine "/Applications/$(basename "$zapp")" 2>/dev/null
            ok "$appname установлен."
        else
            warn "$appname: в архиве нет .app — поставь вручную."
        fi
        return 0
    fi
    local mnt
    mnt=$(echo "$ADMIN_PASS" | sudo -S hdiutil attach "$dmg" -nobrowse -quiet 2>/dev/null | tail -1 | awk -F'\t' '{print $NF}')
    if [ -z "$mnt" ]; then
        mnt=$(hdiutil attach "$dmg" -nobrowse -quiet | tail -1 | awk -F'\t' '{print $NF}')
    fi
    if [ -n "$mnt" ]; then
        app=$(find "$mnt" -maxdepth 1 -name "*.app" | head -1)
        if [ -n "$app" ]; then
            echo "$ADMIN_PASS" | sudo -S cp -R "$app" /Applications/ 2>/dev/null
            echo "$ADMIN_PASS" | sudo -S xattr -dr com.apple.quarantine "/Applications/$(basename "$app")" 2>/dev/null
            ok "$appname установлен."
        else
            pkg=$(find "$mnt" -maxdepth 1 -name "*.pkg" | head -1)
            if [ -n "$pkg" ]; then
                echo "$ADMIN_PASS" | sudo -S installer -pkg "$pkg" -target / -quiet
                ok "$appname установлен (pkg)."
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
    FV_OUT=$(echo "$ADMIN_PASS" | sudo -S fdesetup enable -user "$(stat -f%Su /dev/console)" 2>&1)
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
    CONFIRM=${CONFIRM:-да}
    if [ "$CONFIRM" != "да" ]; then
        err "Тогда вытащи лишние диски и запусти скрипт заново."
        SKIP_LINKS=1
    elif [ "$HAVE_DISK" != "да" ]; then
        FS_CHECK=$(diskutil list "$DISK_DEV" 2>/dev/null | grep -Ei 'Apple_|Microsoft|Windows_|ExFAT|HFS|APFS|FAT')
        if [ -z "$FS_CHECK" ]; then
            warn "macOS не видит на нем файловую систему — похоже, диск УЖЕ зашифрован VeraCrypt."
            read -r -p "   Это так? Тогда ничего стирать не буду, просто подключу. (да/нет) [да]: " ALREADY
            ALREADY=${ALREADY:-да}
            if [ "$ALREADY" = "да" ]; then
                HAVE_DISK="да"
                echo "   Введи СУЩЕСТВУЮЩИЙ пароль этого диска:"
                read -rs -p "   Пароль диска: " DISK_PASS; echo ""
                read -r -p "   PIM (Enter = без PIM): " DISK_PIM
                DISK_PIM=${DISK_PIM:-0}
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
    WIPE_OK=${WIPE_OK:-да}
    if [ "$WIPE_OK" != "да" ]; then
        SKIP_LINKS=1
    else
        echo "Отключаю диск и запускаю шифрование (прогресс в процентах)..."
        diskutil unmountDisk "$DISK_DEV" &>/dev/null
        # Файловая система HFS+ (Mac OS Extended) — родная для macOS. НЕ exFAT:
        # данные приложений (Telegram, Sphere и т.д.) используют права доступа,
        # расширенные атрибуты и симлинки, которые exFAT НЕ хранит — на exFAT
        # приложения ломаются. HFS+ хранит всё как надо на Apple Silicon (M1).
        echo "$ADMIN_PASS" | sudo -S "$VC" --text --non-interactive --create "$DISK_DEV" --volume-type normal --encryption AES --hash SHA-512 --filesystem "HFS+" --pim "$DISK_PIM" -k "" --password "$DISK_PASS" --random-source /dev/urandom $QUICK
        if [ $? -ne 0 ]; then
            err "VeraCrypt не смогла зашифровать диск. Запусти скрипт еще раз."
            SKIP_LINKS=1
        else
            ok "Диск зашифрован."
        fi
    fi
fi

if [ "$SKIP_LINKS" = "0" ]; then
    echo "Подключаю зашифрованный диск..."
    BEFORE_VOL=$(ls /Volumes/)
    echo "$ADMIN_PASS" | sudo -S "$VC" --text --non-interactive --pim "$DISK_PIM" -k "" --protect-hidden no --password "$DISK_PASS" "$DISK_DEV" >/dev/null 2>&1
    MOUNTED=""
    for i in $(seq 1 15); do
        sleep 2
        MOUNTED=$(comm -13 <(echo "$BEFORE_VOL" | sort) <(ls /Volumes/ | sort) | head -1)
        [ -n "$MOUNTED" ] && break
    done
    if [ -z "$MOUNTED" ]; then
        err "Диск не подключился. Либо пароль/PIM неверный, либо неверный ответ в начале («уже зашифрован?»)."
        echo "   Если диск НОВЫЙ (его никогда не шифровали) — запусти скрипт еще раз и ответь «нет»."
        SKIP_LINKS=1
    else
        if [ "$HAVE_DISK" != "да" ] && [ -n "$DISK_NAME" ]; then
            echo "$ADMIN_PASS" | sudo -S diskutil rename "/Volumes/$MOUNTED" "$DISK_NAME" &>/dev/null
            sleep 2
            [ -d "/Volumes/$DISK_NAME" ] && MOUNTED="$DISK_NAME"
        fi
        VOL_NAME="$MOUNTED"
        ok "Диск подключен: /Volumes/$VOL_NAME"
        DATA="/Volumes/$VOL_NAME/DataAPP"
        mkdir -p "$DATA"
    fi
fi

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

    # --- 0) TELEGRAM С ФЛЕШКИ: доступа к номеру нет, сессия живет только в этих файлах ---
    TG_ON_DISK="$DATA/Telegram/stable"
    TG_LOCAL="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable"
    if [ ! -d "$TG_ON_DISK" ] && [ ! -d "$TG_LOCAL" ] && [ ! -L "$TG_LOCAL" ]; then
        echo ""
        warn "Данных Telegram нет ни в системе, ни на диске."
        warn "Если доступа к номеру телефона НЕТ — без бэкапа в Telegram ты больше НЕ ВОЙДЕШЬ."
        read -r -p "Есть бэкап папки Telegram на флешке? (да/нет) [да]: " HAVE_BK
        HAVE_BK=${HAVE_BK:-да}
        if [ "$HAVE_BK" = "да" ]; then
            echo "Вставь флешку с бэкапом (секретный диск вытаскивать НЕ нужно)."
            pause
            BK_SRC=$(find /Volumes -maxdepth 4 -type d -name "6N38VWS5BX.ru.keepcoder.Telegram" 2>/dev/null | grep -v "^/Volumes/$VOL_NAME" | head -1)
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
        L=${L:-да}
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

echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true 2>/dev/null
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true 2>/dev/null
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true 2>/dev/null
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true 2>/dev/null
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true 2>/dev/null
echo "$ADMIN_PASS" | sudo -S defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true 2>/dev/null
ok "Автообновления включены (система и App Store)."

echo "Проверяю и ставлю обновления macOS — может занять ДОЛГО (не закрывай окно, Mac не трогай)..."
if echo "$ADMIN_PASS" | sudo -S softwareupdate --install --all --agree-to-license 2>&1 | grep -qi "restart"; then
    warn "Обновления скачаны, но требуют перезагрузки — она и так будет в конце проверки."
else
    ok "Обновления macOS установлены (или их не было)."
fi

# ------------------------------------------------------------
# ФИНАЛ
# ------------------------------------------------------------
step "ГОТОВО"

echo "Что осталось сделать РУКАМИ (2 минуты):"
echo ""
echo "  1. Если Tukan не перенесся — запусти его 1 раз, потом запусти этот скрипт еще раз."
echo "  2. Настройки -> Bluetooth -> должен быть ВЫКЛ (если включен — выключи)."
echo "  3. Настройки -> Экран блокировки -> «Запрашивать пароль после включения заставки» = СРАЗУ."
echo "  4. TUKAN: задай ДВА пароля — один для входа, ВТОРОЙ на удаление данных (аварийный)."
echo "     Второй пароль стирает всё при вводе — никому не говори и не проверяй ради интереса."
echo ""
echo -e "  ${BOLD}ГЛАВНОЕ ПРАВИЛО:${NC} ничего не храни в системе Mac и на Рабочем столе —"
echo "  все файлы ТОЛЬКО на подключенном секретном диске. Что попало в систему,"
echo "  можно восстановить даже после удаления. Отключил диск -> на Mac ноль твоих файлов."
echo ""
echo "  ВАЖНО: Wi-Fi выключен насовсем (работа только по кабелю)."
echo "  Вернуть, если вдруг надо: Настройки -> Сеть -> кнопка ... -> Добавить службу -> Wi-Fi."
if [ "$CREATE_USER" = "да" ]; then
    echo ""
    echo "  УЧЕТКИ: работай под «$NEW_USER» (её пароль). Основная (админ) — только для установки программ."
fi
echo ""
echo "ПРОВЕРКА, ЧТО ВСЁ РАБОТАЕТ (обязательно, 3 минуты):"
echo "  0. После перезагрузки запусти ПРОВЕРИТЬ.command (лежит рядом с этим скриптом) —"
echo "     он сам проверит все настройки и покажет зеленый/красный список."
echo "  1. Яблоко -> Перезагрузить."
echo "  2. После входа открой VeraCrypt (Программы -> VeraCrypt):"
echo "     - кнопка Select Device -> выбери свою флешку/диск (строка целиком) -> OK"
echo "     - кнопка Mount -> введи пароль диска (и PIM, если задавал)"
echo "     - если спросит пароль от Mac — введи"
echo "     - диск появится в Finder"
echo "  3. Открой Telegram — чаты должны быть на месте."
echo "  4. В VeraCrypt нажми Dismount, ВЫТАЩИ диск и снова открой Telegram — он должен быть ПУСТОЙ."
echo "     Пустой = данные живут только на диске. Это и была цель."
echo "  5. Подключи диск обратно (пункт 2) — чаты вернутся."
echo "  6. Настройки -> Сеть: Wi-Fi в списке быть не должно."
echo "  7. Если бэкап Telegram был на обычной флешке — УДАЛИ его с неё (это полный доступ к телеге)."
echo ""
ok "Технический лог (на всякий случай): $LOG"
echo ""
echo -e "${GREEN}${BOLD}НАСТРОЙКА ЗАВЕРШЕНА. Можно закрыть окно.${NC}"

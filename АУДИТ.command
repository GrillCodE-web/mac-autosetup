#!/bin/bash

# ============================================================
#  АУДИТ ЗАШИФРОВАННОГО ДИСКА И СИСТЕМЫ — v1
#  ТОЛЬКО ЧИТАЕТ. Ничего не меняет, ничего не удаляет,
#  ничего не устанавливает. Пароли не спрашивает.
#  Запуск: двойной клик. Диск должен быть вставлен;
#  если не смонтирован — скрипт подождет, пока смонтируешь
#  через VeraCrypt сам.
#  В конце: выдели весь вывод (Cmd+A, Cmd+C) и скинь разработчику.
# ============================================================

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GREY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

hdr()  { echo ""; echo -e "${CYAN}${BOLD}=== $1 ===${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
warn() { echo -e "  ${YELLOW}▲${NC}  $1"; }
err()  { echo -e "  ${RED}✗${NC}  $1"; }
line() { echo -e "  $1"; }

if [ "$(uname)" != "Darwin" ]; then
    echo "Этот скрипт работает только на macOS."
    exit 1
fi

clear
echo -e "${BOLD}АУДИТ ДИСКА И СИСТЕМЫ — только чтение, ничего не меняется${NC}"
echo -e "${GREY}$(date '+%d.%m.%Y %H:%M:%S')${NC}"

# ------------------------------------------------------------
hdr "0) СИСТЕМА"
# ------------------------------------------------------------
line "macOS: $(sw_vers -productVersion 2>/dev/null) (build $(sw_vers -buildVersion 2>/dev/null))"
line "Модель: $(sysctl -n hw.model 2>/dev/null) · CPU: $(uname -m)"
line "Пользователь: $(id -un) · HOME: $HOME"

# ------------------------------------------------------------
hdr "1) ПОИСК ЗАШИФРОВАННОГО ДИСКА"
# ------------------------------------------------------------
VC="/Applications/VeraCrypt.app/Contents/MacOS/VeraCrypt"

vc_cli_vol() {
    [ -x "$VC" ] || return 1
    local out
    out=$("$VC" --text --list 2>/dev/null | grep -o '/Volumes/.*' | head -1)
    [ -n "$out" ] && [ -d "$out" ] && { echo "$out"; return 0; }
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

VOL=""
VOL=$(vc_cli_vol)
if [ -n "$VOL" ]; then
    ok "VeraCrypt сообщает смонтированный том: $VOL"
else
    CANDS=$(candidate_vols)
    CNT=$(printf '%s\n' "$CANDS" | grep -c .)
    if [ "$CNT" = "1" ]; then
        VOL="$CANDS"
        warn "VeraCrypt CLI молчит, но внешний том ровно один — беру его: $VOL"
    elif [ "$CNT" -gt 1 ]; then
        warn "Внешних томов несколько — выбери, какой СЕКРЕТНЫЙ:"
        i=0
        printf '%s\n' "$CANDS" | while IFS= read -r v; do
            i=$((i + 1)); echo "    $i) $v"
        done
        read -r -p "   Номер: " CH
        VOL=$(printf '%s\n' "$CANDS" | sed -n "${CH}p")
    fi
    if [ -z "$VOL" ] || [ ! -d "$VOL" ]; then
        echo ""
        echo "  Секретный диск НЕ смонтирован. Сделай так:"
        echo "    1) Открой VeraCrypt (Программы -> VeraCrypt)"
        echo "    2) Select Device -> выбери свой диск -> Mount -> пароль (и PIM, если был)"
        echo "  Жду до 15 минут, проверяю каждые 5 секунд..."
        n=0
        while [ $n -lt 180 ]; do
            sleep 5
            VOL=$(vc_cli_vol)
            [ -z "$VOL" ] && VOL=$(candidate_vols | head -1)
            [ -n "$VOL" ] && [ -d "$VOL" ] && break
            n=$((n + 1))
        done
    fi
fi

if [ -z "$VOL" ] || [ ! -d "$VOL" ]; then
    err "Диск так и не появился. Смонтируй его через VeraCrypt и запусти аудит еще раз."
    echo ""; read -r -p "Enter — выйти."
    exit 1
fi
ok "Аудирую том: $VOL"
VOL_NAME=$(basename "$VOL")

# ------------------------------------------------------------
hdr "2) КАРТА ДИСКА (папки до глубины 3, с количеством объектов)"
# ------------------------------------------------------------
find "$VOL" -maxdepth 3 -type d \
    -not -path "*/.Trashes*" -not -path "*/.Spotlight-V100*" \
    -not -path "*/.fseventsd*" -not -path "*/.DocumentRevisions*" \
    -not -path "*/.TemporaryItems*" 2>/dev/null | sort | while IFS= read -r d; do
    [ "$d" = "$VOL" ] && continue
    depth=$(printf '%s' "${d#$VOL/}" | tr -cd '/' | wc -c | tr -d ' ')
    indent=$(printf '%*s' $((depth * 2)) '')
    cnt=$(ls -A "$d" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$cnt" = "0" ]; then
        echo -e "  ${indent}${GREY}$(basename "$d")/  (ПУСТАЯ)${NC}"
    else
        echo "  ${indent}$(basename "$d")/  ($cnt объектов)"
    fi
done

# ------------------------------------------------------------
# Отпечатки: опознание папки ПО СОДЕРЖИМОМУ, имя не важно
# ------------------------------------------------------------
fp() {
    local d="$1"
    [ -d "$d" ] || return 1
    if [ -e "$d/accounts-metadata" ]; then echo "TELEGRAM (accounts-metadata)"; return 0; fi
    if [ -d "$d/stable" ] && [ -e "$d/stable/accounts-metadata" ]; then echo "TELEGRAM (stable/accounts-metadata)"; return 0; fi
    if [ -d "$d/tdata" ]; then echo "TELEGRAM? (tdata)"; return 0; fi
    if [ -d "$d/Local" ] && [ -d "$d/Packages" ]; then echo "SUBLIME (Local + Packages)"; return 0; fi
    if find "$d" -maxdepth 1 -name "*.tox" 2>/dev/null | grep -q .; then echo "QTOX (*.tox)"; return 0; fi
    if [ -d "$d/Messages" ]; then echo "MAILMATE? (Messages)"; return 0; fi
    if [ -e "$d/.com.apple.containermanagerd.metadata.plist" ]; then
        local bid
        bid=$(grep -a -o '[a-zA-Z0-9._-]*\.[a-zA-Z0-9._-]*\.[a-zA-Z0-9._-]*' "$d/.com.apple.containermanagerd.metadata.plist" 2>/dev/null | head -1)
        echo "КОНТЕЙНЕР macOS (bundle: ${bid:-не прочитан})"; return 0
    fi
    if [ -e "$d/database.sqlite" ] && { [ -d "$d/profiles" ] || [ -e "$d/settings.json" ]; }; then echo "JOPLIN (database.sqlite)"; return 0; fi
    # Linken Sphere: корень Chromium user-data — файл Local State + профили
    # (Default или хеш-папки). Имя папки не важно: app.ls, App_LS2, Sphere...
    if [ -e "$d/Local State" ]; then
        if [ -d "$d/Default" ] || find "$d" -maxdepth 1 -type d -name "????????????????????????????????????????????????????????????????????????" 2>/dev/null | grep -q .; then
            echo "LINKEN SPHERE (Local State + профили)"; return 0
        fi
    fi
    return 1
}

preview() {
    ls -A "$1" 2>/dev/null | head -12 | while IFS= read -r e; do
        if [ -d "$1/$e" ]; then echo "      [папка]  $e"; else echo "      [файл]   $e"; fi
    done
}

hdr "3) ОПОЗНАННЫЕ ДАННЫЕ НА ДИСКЕ (по содержимому, глубина до 6)"
FOUND_ANY=0
while IFS= read -r d; do
    key=$(fp "$d")
    [ -z "$key" ] && continue
    FOUND_ANY=1
    echo -e "  ${GREEN}${BOLD}$key${NC}"
    echo "    путь: $d"
    echo "    объектов внутри: $(ls -A "$d" 2>/dev/null | wc -l | tr -d ' ')"
    preview "$d"
done < <(find "$VOL" -maxdepth 6 -type d \
    -not -path "*/.Trashes*" -not -path "*/.Spotlight-V100*" \
    -not -path "*/.fseventsd*" -not -path "*/.DocumentRevisions*" \
    -not -path "*/.TemporaryItems*" 2>/dev/null | sort)
[ "$FOUND_ANY" = "0" ] && warn "По известным отпечаткам ничего не опознано."

hdr "4) ПАПКИ С ГОВОРЯЩИМИ ИМЕНАМИ (поиск по имени, глубина до 6)"
find "$VOL" -maxdepth 6 -type d \( \
    -iname "*keepcoder*" -o -iname "stable" -o \
    -iname "app.ls" -o -iname "app_ls*" -o -iname "*sphere*" -o -iname "ls*.app" -o -iname "ls2*" \
    -o -iname "*tukan*" -o -iname "Tox" -o -iname "*mailmate*" \
    -o -iname "*sublime*" -o -iname "*joplin*" -o -iname "*telegram*" \
    -o -iname "DataAPP" -o -iname "AppData" -o -iname "*_Data" \
    \) -not -path "*/.Trashes*" -not -path "*/.Spotlight-V100*" \
    -not -path "*/.fseventsd*" 2>/dev/null | sort | while IFS= read -r d; do
    cnt=$(ls -A "$d" 2>/dev/null | wc -l | tr -d ' ')
    echo "  $d  ($cnt объектов)"
done

hdr "5) НЕОПОЗНАННЫЕ НЕПУСТЫЕ ПАПКИ (глубина до 3, первые 40)"
SHOWN=0
while IFS= read -r d; do
    [ "$d" = "$VOL" ] && continue
    [ -z "$(ls -A "$d" 2>/dev/null)" ] && continue
    [ -n "$(fp "$d")" ] && continue
    echo "  $d"
    preview "$d"
    SHOWN=$((SHOWN + 1))
    [ $SHOWN -ge 40 ] && break
done < <(find "$VOL" -maxdepth 3 -type d \
    -not -path "*/.Trashes*" -not -path "*/.Spotlight-V100*" \
    -not -path "*/.fseventsd*" -not -path "*/.DocumentRevisions*" \
    -not -path "*/.TemporaryItems*" 2>/dev/null | sort)

# ------------------------------------------------------------
hdr "6) СИСТЕМНАЯ СТОРОНА: куда смотрят приложения СЕЙЧАС"
# ------------------------------------------------------------
show_target() {
    local label="$1" p="$2"
    if [ -L "$p" ]; then
        local tgt state
        tgt=$(readlink "$p")
        if [ -d "$tgt" ] && [ -n "$(ls -A "$tgt" 2>/dev/null)" ]; then state="цель ЖИВАЯ ($(ls -A "$tgt" 2>/dev/null | wc -l | tr -d ' ') объектов)"
        elif [ -d "$tgt" ]; then state="цель ПУСТАЯ — мёртвая ссылка!"
        else state="цель НЕ СУЩЕСТВУЕТ — мёртвая ссылка!"; fi
        line "$(printf '%-14s' "$label") СИМЛИНК -> $tgt  [$state]"
    elif [ -d "$p" ]; then
        line "$(printf '%-14s' "$label") ОБЫЧНАЯ ПАПКА в системе ($(ls -A "$p" 2>/dev/null | wc -l | tr -d ' ') объектов) — НЕ на диске!"
    else
        line "$(printf '%-14s' "$label") нет (ни папки, ни симлинка)"
    fi
}

TG_DIR=$(find "$HOME/Library/Group Containers" -maxdepth 1 -iname "*keepcoder.Telegram" 2>/dev/null | head -1)
show_target "Telegram"   "${TG_DIR:-$HOME/Library/Group Containers/(не найден контейнер)}/stable"
show_target "Sublime"    "$HOME/Library/Application Support/Sublime Text"
show_target "Sphere"     "$HOME/Library/Application Support/app.ls"
show_target "MailMate"   "$HOME/Library/Application Support/MailMate"
show_target "qTox"       "$HOME/Library/Application Support/Tox"
show_target "Tukan"      "$HOME/Library/Containers/me.tukan.tukan"

echo ""
line "Другие папки со «сферными» именами в системе (если LS2 пишет не в app.ls):"
find "$HOME/Library/Application Support" "$HOME/Library/Containers" "$HOME/Library/Group Containers" \
    -maxdepth 1 \( -iname "*sphere*" -o -iname "*app*ls*" -o -iname "ls2*" \) 2>/dev/null | while IFS= read -r d; do
    line "    $d ($(ls -A "$d" 2>/dev/null | wc -l | tr -d ' ') объектов)"
done

# ------------------------------------------------------------
hdr "7) УСТАНОВЛЕННЫЕ ПРИЛОЖЕНИЯ (/Applications)"
# ------------------------------------------------------------
ls -A /Applications 2>/dev/null | while IFS= read -r a; do echo "  $a"; done

# ------------------------------------------------------------
hdr "8) ПРАВА ТЕРМИНАЛА (Full Disk Access)"
# ------------------------------------------------------------
if ls "$HOME/Library/Safari" >/dev/null 2>&1; then
    ok "Полный доступ к диску у Терминала ЕСТЬ."
else
    warn "Полного доступа к диску у Терминала НЕТ (чтение защищённых папок запрещено)."
fi

# ------------------------------------------------------------
hdr "9) СОСТОЯНИЕ VeraCrypt"
# ------------------------------------------------------------
if [ -d "/Applications/VeraCrypt.app" ]; then
    ok "VeraCrypt установлен: $(defaults read /Applications/VeraCrypt.app/Contents/Info CFBundleShortVersionString 2>/dev/null)"
else
    err "VeraCrypt НЕ установлен."
fi
if pkgutil --pkgs 2>/dev/null | grep -qi "fuse-t"; then
    ok "FUSE-T установлен."
else
    warn "FUSE-T не найден через pkgutil."
fi

echo ""
echo -e "${GREEN}${BOLD}АУДИТ ЗАВЕРШЁН — ничего не изменено.${NC}"
echo ""
echo "  Теперь: Cmd+A (выделить всё), Cmd+C (скопировать) и скинь разработчику."
echo ""
read -r -p "Enter — закрыть."

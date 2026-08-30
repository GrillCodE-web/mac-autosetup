#!/bin/bash

# ============================================================
#  PREINSTALL AUDIT — АУДИТ ДИСКА И СИСТЕМЫ — v3
#  v3: чистый вывод — без простыней: app.ls показывается ОДИН раз,
#  внутрь опознанных папок не лезем, Apple-контейнеры не светятся.
#  ТОЛЬКО ЧИТАЕТ. Ничего не меняет, ничего не удаляет,
#  ничего не устанавливает. Пароли не спрашивает.
#  Запуск: двойной клик. Диск должен быть вставлен;
#  если не смонтирован — скрипт подождет, пока смонтируешь
#  через VeraCrypt сам.
#  Отпечатки папок совпадают с AutoInstaller.command v12.6+.
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
hdr "2) КАРТА ДИСКА (верхний уровень: объекты + размер)"
# ------------------------------------------------------------
for d in "$VOL"/*/; do
    [ -d "$d" ] || continue
    base=$(basename "$d")
    case "$base" in .Trashes|.Spotlight-V100|.fseventsd|.DocumentRevisions-V100|.TemporaryItems) continue ;; esac
    cnt=$(ls -A "$d" 2>/dev/null | wc -l | tr -d ' ')
    sz=$(du -sh "$d" 2>/dev/null | awk '{print $1}')
    if [ "$cnt" = "0" ]; then
        echo -e "  ${GREY}$base/  (ПУСТАЯ)${NC}"
    else
        echo "  ${BOLD}$base/${NC}  ($cnt объектов, ${sz:-?})"
        ls -A "$d" 2>/dev/null | head -8 | while IFS= read -r e; do
            if [ -d "$d$e" ]; then echo "      $e/"; else echo "      $e"; fi
        done
        [ "$cnt" -gt 8 ] && echo -e "      ${GREY}... еще $((cnt - 8))${NC}"
    fi
done
# Файлы в корне тома (не папки) — тоже показываем
find "$VOL" -maxdepth 1 -type f -not -name ".*" 2>/dev/null | while IFS= read -r f; do
    echo -e "  ${GREY}$(basename "$f")  (файл в корне)${NC}"
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
    if [ -d "$d/Messages" ]; then echo "MAILMATE (Messages)"; return 0; fi
    # Tukan: контейнер macOS с bundle id me.tukan.tukan (как fp_tukan в AutoInstaller)
    if [ -e "$d/.com.apple.containermanagerd.metadata.plist" ]; then
        if grep -qa "me.tukan.tukan" "$d/.com.apple.containermanagerd.metadata.plist" 2>/dev/null; then
            echo "TUKAN (контейнер me.tukan.tukan)"; return 0
        fi
        local bid
        bid=$(grep -a -o '[a-zA-Z0-9._-]*\.[a-zA-Z0-9._-]*\.[a-zA-Z0-9._-]*' "$d/.com.apple.containermanagerd.metadata.plist" 2>/dev/null | head -1)
        echo "КОНТЕЙНЕР macOS (bundle: ${bid:-не прочитан})"; return 0
    fi
    if [ -e "$d/database.sqlite" ] && { [ -d "$d/profiles" ] || [ -e "$d/settings.json" ]; }; then echo "JOPLIN (database.sqlite)"; return 0; fi
    # Linken Sphere: корень Chromium user-data — файл Local State + профили
    # (Default или хеш-папки). Имя папки не важно: app.ls, App_LS2, Sphere...
    if [ -e "$d/Local State" ]; then
        local s b re='^[0-9a-fA-F]{24,64}$' hit=1
        [ -d "$d/Default" ] && hit=0
        if [ $hit -ne 0 ]; then
            for s in "$d"/*/; do
                [ -d "$s" ] || continue
                b=$(basename "$s")
                [[ "$b" =~ $re ]] && { hit=0; break; }
            done
        fi
        [ $hit -eq 0 ] && { echo "LINKEN SPHERE (Local State + профили)"; return 0; }
    fi
    return 1
}

preview() {
    ls -A "$1" 2>/dev/null | head -12 | while IFS= read -r e; do
        if [ -d "$1/$e" ]; then echo "      [папка]  $e"; else echo "      [файл]   $e"; fi
    done
}

hdr "3) ОПОЗНАННЫЕ ДАННЫЕ НА ДИСКЕ (каждое приложение — один раз)"
FOUND_ANY=0
MATCHED=""
while IFS= read -r d; do
    # Внутрь уже опознанной папки НЕ лезем: app.ls — это ОДИН Sphere,
    # а не 14 отдельных hex-профилей. Проверяем, что d не внутри опознанного.
    skip=0
    while IFS= read -r m; do
        [ -n "$m" ] && case "$d/" in "$m/"*) skip=1; break ;; esac
    done <<EOF
$MATCHED
EOF
    [ $skip -eq 1 ] && continue
    key=$(fp "$d")
    [ -z "$key" ] && continue
    FOUND_ANY=1
    MATCHED="$MATCHED$d
"
    sz=$(du -sh "$d" 2>/dev/null | awk '{print $1}')
    echo -e "  ${GREEN}${BOLD}$key${NC}"
    echo "    путь: $d"
    echo "    объектов внутри: $(ls -A "$d" 2>/dev/null | wc -l | tr -d ' '), размер: ${sz:-?}"
    preview "$d"
done < <(find "$VOL" -maxdepth 4 -type d \
    -not -path "*/.Trashes*" -not -path "*/.Spotlight-V100*" \
    -not -path "*/.fseventsd*" -not -path "*/.DocumentRevisions*" \
    -not -path "*/.TemporaryItems*" 2>/dev/null | sort)
[ "$FOUND_ANY" = "0" ] && warn "По известным отпечаткам ничего не опознано."

hdr "4) ПАПКИ С ГОВОРЯЩИМИ ИМЕНАМИ (поиск по имени, глубина до 6)"
find "$VOL" -maxdepth 6 -type d \( \
    -iname "*keepcoder*" -o -iname "stable" -o \
    -iname "app.ls" -o -iname "app_ls*" -o -iname "*sphere*" -o -iname "ls*.app" -o -iname "ls2*" \
    -o     -iname "*tukan*" -o -iname "Tox" -o -iname "*mailmate*" \
    -o -iname "*sublime*" -o -iname "*joplin*" -o -iname "*telegram*" \
    -o -iname "DataAPP" -o -iname "AppData" -o -iname "*_Data" \
    \) -not -path "*/.Trashes*" -not -path "*/.Spotlight-V100*" \
    -not -path "*/.fseventsd*" -not -path "*/app.ls/*" 2>/dev/null | sort | while IFS= read -r d; do
    cnt=$(ls -A "$d" 2>/dev/null | wc -l | tr -d ' ')
    echo "  $d  ($cnt объектов)"
done

hdr "5) НЕОПОЗНАННЫЕ НЕПУСТЫЕ ПАПКИ (верхние уровни, первые 25)"
SHOWN=0
while IFS= read -r d; do
    [ "$d" = "$VOL" ] && continue
    [ -z "$(ls -A "$d" 2>/dev/null)" ] && continue
    [ -n "$(fp "$d")" ] && continue
    # Внутрь опознанных в секции 3 папок не лезем
    skip=0
    while IFS= read -r m; do
        [ -n "$m" ] && case "$d/" in "$m/"*) skip=1; break ;; esac
    done <<EOF
$MATCHED
EOF
    [ $skip -eq 1 ] && continue
    # Служебные/тяжелые директории проектов — не интересны
    case "$(basename "$d")" in .git|node_modules|vendor|dist) continue ;; esac
    cnt=$(ls -A "$d" 2>/dev/null | wc -l | tr -d ' ')
    echo "  $d  ($cnt объектов)"
    SHOWN=$((SHOWN + 1))
    [ $SHOWN -ge 25 ] && break
done < <(find "$VOL" -maxdepth 2 -type d \
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

# ------------------------------------------------------------
hdr "10) ГИГИЕНА ТОМА (Spotlight / Time Machine)"
# ------------------------------------------------------------
if mdutil -s "$VOL" 2>/dev/null | grep -qi "disabled"; then
    ok "Индексация Spotlight на секретном томе ВЫКЛЮЧЕНА."
else
    warn "Spotlight на томе ВКЛЮЧЕН (имена файлов попадают в системный индекс) — прогони AutoInstaller или: sudo mdutil -i off \"$VOL\""
fi
if tmutil isexcluded "$VOL" 2>/dev/null | grep -qi "\[Excluded\]"; then
    ok "Том исключен из Time Machine."
else
    warn "Том НЕ исключен из Time Machine — sudo tmutil addexclusion -p \"$VOL\""
fi

echo ""
echo -e "${GREEN}${BOLD}АУДИТ ЗАВЕРШЁН — ничего не изменено.${NC}"
echo ""
echo "  Теперь: Cmd+A (выделить всё), Cmd+C (скопировать) и скинь разработчику."
echo ""
read -r -p "Enter — закрыть."

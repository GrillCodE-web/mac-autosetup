#!/bin/bash
# Тесты фазы данных MacForge.command.
#
# Зачем: логика переноса данных раньше проверялась только на живом маке с
# реальным секретным диском — то есть ровно тогда, когда ошибка стоит дороже
# всего. Баг с вложенностью cp -R (коммит a112e26) тихо ломал профиль
# приложения, и заметить это можно было только постфактум.
#
# Как: из MacForge.command вырезаются области между маркерами
# "# >>> TESTABLE <имя>" и "# <<< TESTABLE <имя>" и выполняются здесь как есть.
# Тестируется НАСТОЯЩИЙ код скрипта, а не его копия.
#
# Запуск:  bash tests/run_tests.sh
# Работает без sudo, без macOS и без секретного диска.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET="$SCRIPT_DIR/../MacForge.command"
[ -f "$TARGET" ] || { echo "не найден $TARGET"; exit 1; }

# --- заглушки вывода: тестируемые функции зовут err/warn/ok/info/dim ---------
LAST_MSG=""
err()  { LAST_MSG="$*"; [ -n "${VERBOSE:-}" ] && echo "    err:  $*"; return 0; }
warn() { LAST_MSG="$*"; [ -n "${VERBOSE:-}" ] && echo "    warn: $*"; return 0; }
ok()   { LAST_MSG="$*"; [ -n "${VERBOSE:-}" ] && echo "    ok:   $*"; return 0; }
info() { LAST_MSG="$*"; [ -n "${VERBOSE:-}" ] && echo "    info: $*"; return 0; }
dim()  { LAST_MSG="$*"; return 0; }

# --- подключаем реальный код -------------------------------------------------
extract() { # extract <имя области>
    sed -n "/^# >>> TESTABLE $1/,/^# <<< TESTABLE $1/p" "$TARGET"
}
REGISTRY=$(extract registry)
MIGRATE=$(extract migrate)
[ -n "$REGISTRY" ] || { echo "область TESTABLE registry не найдена"; exit 1; }
[ -n "$MIGRATE" ]  || { echo "область TESTABLE migrate не найдена"; exit 1; }
eval "$REGISTRY"
eval "$MIGRATE"

# --- микро-фреймворк ---------------------------------------------------------
PASS=0; FAIL=0; CURRENT=""
GREEN=$(printf '\033[32m'); RED=$(printf '\033[31m'); NC=$(printf '\033[0m')
it() { CURRENT="$1"; }
assert() { # assert <условие-как-строка> <что проверяем>
    if eval "$1"; then
        PASS=$((PASS + 1)); printf '  %sok%s   %s: %s\n' "$GREEN" "$NC" "$CURRENT" "$2"
    else
        FAIL=$((FAIL + 1)); printf '  %sFAIL%s %s: %s\n' "$RED" "$NC" "$CURRENT" "$2"
        printf '       условие: %s\n' "$1"
    fi
}

SANDBOX=$(mktemp -d 2>/dev/null || mktemp -d -t macforge)
cleanup() { chmod -R u+w "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"; }
trap cleanup EXIT
fresh() { # fresh <имя> -> печатает путь к чистому каталогу
    local d="$SANDBOX/$1.$RANDOM"
    rm -rf "$d"; mkdir -p "$d"; echo "$d"
}
count_files() { find "$1" -mindepth 1 2>/dev/null | wc -l | tr -d ' '; }

# Git Bash под Windows на "ln -s" молча делает КОПИЮ и возвращает 0. Проверки
# симлинков там бессмысленны — определяем это заранее и помечаем как пропуск.
CAN_SYMLINK=0
_probe=$(fresh probe); mkdir -p "$_probe/t"
ln -s "$_probe/t" "$_probe/l" 2>/dev/null
[ -L "$_probe/l" ] && CAN_SYMLINK=1
skip_link() { # печатает причину пропуска и возвращает 0, если ссылок нет
    [ "$CAN_SYMLINK" = "1" ] && return 1
    printf '  --   %s: пропуск (эта ОС не умеет симлинки)\n' "$CURRENT"
    return 0
}

echo ""
echo "ОТПЕЧАТКИ (опознание папки по содержимому)"

W=$(fresh fp)
mkdir -p "$W/tg/stable"; touch "$W/tg/stable/accounts-metadata"
mkdir -p "$W/tg2"; touch "$W/tg2/accounts-metadata"
it "fp_telegram"
assert 'fp_telegram "$W/tg"'  "контейнер с подпапкой stable опознан"
assert 'fp_telegram "$W/tg2"' "папка stable опознана напрямую"
assert '! fp_telegram "$W"'   "посторонняя папка не опознана"

mkdir -p "$W/st/Local" "$W/st/Packages"
mkdir -p "$W/st_bad/Local"
it "fp_sublime"
assert 'fp_sublime "$W/st"'      "Local + Packages опознаны"
assert '! fp_sublime "$W/st_bad"' "только Local — не опознано"

mkdir -p "$W/ls/0123456789abcdef01234567"; touch "$W/ls/Local State"
mkdir -p "$W/ls2/Default"; touch "$W/ls2/Local State"
mkdir -p "$W/ls_bad/Profile"; touch "$W/ls_bad/Local State"
it "fp_sphere"
assert 'fp_sphere "$W/ls"'      "Local State + hex-профиль опознаны"
assert 'fp_sphere "$W/ls2"'     "Local State + Default опознаны"
assert '! fp_sphere "$W/ls_bad"' "Local State без профиля — не опознано"

mkdir -p "$W/mm/Messages"
mkdir -p "$W/tox"; touch "$W/tox/profile.tox"
it "fp_mailmate / fp_qtox"
assert 'fp_mailmate "$W/mm"' "папка Messages опознана"
assert 'fp_qtox "$W/tox"'    "файл *.tox опознан"

it "fp_any"
assert '[ "$(fp_any "$W/st")" = sublime ]' "sublime определён по содержимому"
assert '[ "$(fp_any "$W/mm")" = mailmate ]' "mailmate определён по содержимому"
assert '! fp_any "$W" >/dev/null'          "неопознанная папка возвращает ошибку"

echo ""
echo "ЦЕЛОСТНОСТЬ КОПИИ (copy_matches)"

W=$(fresh cm)
mkdir -p "$W/src/sub"; echo aaa > "$W/src/a.txt"; echo bbb > "$W/src/sub/b.txt"
cp -R "$W/src" "$W/full"
mkdir -p "$W/part"; echo aaa > "$W/part/a.txt"
it "copy_matches"
assert 'copy_matches "$W/src" "$W/full"'   "полная копия принята"
assert '! copy_matches "$W/src" "$W/part"' "оборванная копия отвергнута"

echo ""
echo "ПЕРЕНОС НА ДИСК (migrate_to_disk)"

# 1. Обычный перенос
W=$(fresh mig)
mkdir -p "$W/home/App/inner"; echo data > "$W/home/App/file.txt"; echo x > "$W/home/App/inner/y.txt"
BEFORE=$(count_files "$W/home/App")
it "обычный перенос"
assert 'migrate_to_disk "$W/home/App" "$W/vol/App" "App"' "перенос завершился успешно"
if ! skip_link; then
assert '[ -L "$W/home/App" ]'                             "на месте оригинала появился симлинк"
assert '[ "$(readlink "$W/home/App")" = "$W/vol/App" ]'   "симлинк указывает на диск"
fi
assert '[ -f "$W/vol/App/file.txt" ]'                     "файл лежит на диске БЕЗ лишней вложенности"
assert '[ ! -e "$W/vol/App/App" ]'                        "вложенной папки App/App нет (регрессия a112e26)"
assert '[ "$(count_files "$W/vol/App")" = "$BEFORE" ]'    "число объектов совпало с исходным"
assert '[ -z "$(ls -d "$W"/home/App.bak.* 2>/dev/null)" ]' ".bak убран после успеха"

# 2. Цель уже существует пустая — главный сценарий бага a112e26
W=$(fresh mig2)
mkdir -p "$W/home/App"; echo data > "$W/home/App/file.txt"
mkdir -p "$W/vol/App"
it "цель существует и пуста"
assert 'migrate_to_disk "$W/home/App" "$W/vol/App" "App"' "перенос завершился успешно"
assert '[ -f "$W/vol/App/file.txt" ]'                     "данные на верхнем уровне цели"
assert '[ ! -e "$W/vol/App/App" ]'                        "вложенности не возникло"

# 3. Цель существует и НЕ пуста — трогать нельзя
W=$(fresh mig3)
mkdir -p "$W/home/App"; echo new > "$W/home/App/file.txt"
mkdir -p "$W/vol/App"; echo old > "$W/vol/App/existing.txt"
it "цель существует и непуста"
assert '! migrate_to_disk "$W/home/App" "$W/vol/App" "App"' "перенос отклонён"
assert '[ -f "$W/home/App/file.txt" ]'                      "локальные данные не тронуты"
assert '[ ! -L "$W/home/App" ]'                             "симлинк не создан"
assert '[ "$(cat "$W/vol/App/existing.txt")" = old ]'       "чужие данные на диске целы"

# 4. Диск недоступен для записи — данные обязаны остаться на месте
W=$(fresh mig4)
mkdir -p "$W/home/App"; echo data > "$W/home/App/file.txt"
mkdir -p "$W/vol"; chmod 500 "$W/vol"
it "диск не пишется"
if [ -w "$W/vol" ]; then
    echo "  --   пропуск: тест бесполезен под root (каталог всё равно пишется)"
else
    assert '! migrate_to_disk "$W/home/App" "$W/vol/App" "App"' "перенос отклонён"
    assert '[ -f "$W/home/App/file.txt" ]'                      "данные остались локально"
    assert '[ ! -L "$W/home/App" ]'                             "битого симлинка нет"
fi
chmod 700 "$W/vol" 2>/dev/null

# 5. Никакого состояния "данных нет нигде"
W=$(fresh mig5)
mkdir -p "$W/home/App"; echo data > "$W/home/App/file.txt"
migrate_to_disk "$W/home/App" "$W/vol/App" "App" >/dev/null 2>&1
it "инвариант"
assert '[ -e "$W/home/App" ] || [ -e "$W/vol/App" ]' "данные всегда существуют хотя бы в одном месте"
assert '[ -z "$(ls -d "$W"/vol/*.partial.* 2>/dev/null)" ]' "временных .partial не осталось"

echo ""
echo "КОРЕНЬ ДАННЫХ НА ДИСКЕ (resolve_data_dir)"

W=$(fresh rdd)
mkdir -p "$W/vol/MyStuff/Sublime Text/Local" "$W/vol/MyStuff/Sublime Text/Packages"
mkdir -p "$W/vol/MyStuff/MailMate/Messages"
it "голосование"
assert '[ "$(resolve_data_dir "$W/vol")" = "$W/vol/MyStuff" ]' "корень найден по большинству голосов"

# Имя вида "*_Data" срезается намеренно: на диске данные Tukan лежат как
# Tukan_Data/me.tukan.tukan, и корнем должен стать уровень НАД Tukan_Data.
W=$(fresh rdd3)
mkdir -p "$W/vol/Store/Tukan_Data/me.tukan.tukan"
printf 'me.tukan.tukan' > "$W/vol/Store/Tukan_Data/me.tukan.tukan/.com.apple.containermanagerd.metadata.plist"
it "суффикс _Data"
assert '[ "$(resolve_data_dir "$W/vol")" = "$W/vol/Store" ]' "Tukan_Data срезан, корень на уровень выше"

W=$(fresh rdd2)
mkdir -p "$W/vol/Empty"
it "пустой диск"
assert '[ "$(resolve_data_dir "$W/vol")" = "$W/vol/DataAPP" ]' "без опознанных папок создаётся DataAPP"

echo ""
if [ "$FAIL" = "0" ]; then
    printf '%sВСЕ ТЕСТЫ ПРОШЛИ: %d%s\n\n' "$GREEN" "$PASS" "$NC"
    exit 0
else
    printf '%sПРОВАЛЕНО: %d, прошло: %d%s\n\n' "$RED" "$FAIL" "$PASS" "$NC"
    exit 1
fi

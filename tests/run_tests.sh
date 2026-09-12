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
# Покрытие: 32 сценария — атомарный перенос и откаты, опознание папок
# по содержимому (отпечатки), голосование за корень данных на диске.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET="$SCRIPT_DIR/../MacForge.command"
[ -f "$TARGET" ] || { echo "не найден $TARGET"; exit 1; }

if [ "${1:-}" = "--sublime" ]; then
    node - "$TARGET" <<'SUBLIME_TEST'
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const source = fs.readFileSync(process.argv[2], 'utf8');
const match = source.match(/<<'SUBLIME_JXA'\r?\n([\s\S]*?)\r?\nSUBLIME_JXA/);
assert(match, 'Не найден настоящий код настройки LaunchServices');
const extensions = source.match(/^LS_EXTENSIONS="([^"]+)"/m)[1].split(/\s+/);
const bundle = 'com.sublimetext.4';
let passed = 0;
function test(name, check) {
    check();
    console.log('  ok: ' + name);
    passed++;
}
function execute(options = {}, list = extensions, app = bundle) {
    const calls = [], logs = [];
    const bridge = value => value;
    Object.assign(bridge, {
        kUTTagClassFilenameExtension: 'public.filename-extension', kLSRolesAll: 0xffffffff,
        UTTypeCreatePreferredIdentifierForTag(tag, ext, parent) {
            assert.strictEqual(tag, 'public.filename-extension');
            assert.strictEqual(parent, null);
            calls.push(['type', ext]);
            return options.noType ? null : ext === 'txt' ? 'public.plain-text' : 'test.' + ext;
        },
        LSSetDefaultRoleHandlerForContentType(uti, roles, handler) {
            assert(uti.includes('.'), 'Расширение передано вместо UTI');
            assert.strictEqual(roles, 0xffffffff);
            assert.strictEqual(handler, app);
            calls.push(['set', uti]);
            return options.status || 0;
        },
        LSCopyDefaultRoleHandlerForContentType(uti, roles) {
            assert.strictEqual(roles, 0xffffffff);
            calls.push(['get', uti]);
            if (options.queryError) throw new Error('Ошибка чтения LaunchServices');
            return Object.hasOwn(options, 'handler') ? options.handler : app;
        }
    });
    const context = { $: bridge, ObjC: { import() {}, unwrap: value => value }, console: { log: line => logs.push(line) } };
    vm.createContext(context);
    vm.runInContext(match[1], context);
    let result, error;
    try { result = context.run([app, ...list]); } catch (e) { error = e; }
    return { calls, logs, result, error };
}
test('.txt назначается по public.plain-text и перечитывается через LaunchServices', () => {
    const out = execute({}, ['txt']);
    assert(!out.error);
    assert.deepStrictEqual(out.calls, [['type', 'txt'], ['set', 'public.plain-text'], ['get', 'public.plain-text']]);
});
test('проверяется каждое настроенное расширение', () => {
    const out = execute();
    assert(!out.error);
    assert.strictEqual(out.calls.filter(c => c[0] === 'get').length, extensions.length);
});
test('ошибка назначения не считается успехом', () => {
    const out = execute({ status: -50 }, ['txt']);
    assert(out.error && out.logs[0].includes('-50'));
    assert(!out.calls.some(c => c[0] === 'get'));
});
test('оставшийся TextEdit обнаруживается', () => assert(execute({ handler: 'com.apple.TextEdit' }, ['txt']).error));
test('отсутствующий обработчик обнаруживается', () => assert(execute({ handler: null }, ['txt']).error));
test('ошибка системного запроса обнаруживается', () => assert(execute({ queryError: true }, ['txt']).error));
test('неопределённый UTI не передаётся на запись', () => {
    const out = execute({ noType: true }, ['txt']);
    assert(out.error && !out.calls.some(c => c[0] === 'set'));
});
test('регистр bundle ID не вызывает ложную ошибку', () => assert(!execute({ handler: bundle.toUpperCase() }, ['txt']).error));
test('нет расширений — нет ложного успеха', () => assert(execute({}, []).error));
test('нет bundle ID — нет ложного успеха', () => assert(execute({}, ['txt'], '').error));
console.log('Проверок с заглушками LaunchServices прошло: ' + passed);
SUBLIME_TEST
    exit $?
fi

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
VC_CODE=$(awk '/^vc_parse_list\(\)|^vc_mounted_vol\(\)/ {take=1} /^if ! stage_done disk; then/ {exit} take {print}' "$TARGET")
[ -n "$VC_CODE" ] || { echo "код определения тома VeraCrypt не найден"; exit 1; }
eval "$VC_CODE"

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
echo "VERACRYPT (определение тома и ожидание)"

VC_W=$(fresh vc)
mkdir -p "$VC_W/Первый том" "$VC_W/second" "$VC_W/unrelated"
it "парсер VeraCrypt"
assert 'declare -F vc_parse_list >/dev/null' "есть отдельный парсер CLI"
if declare -F vc_parse_list >/dev/null; then
    VC_LIST=$(printf '1: "/containers/Мой диск.vc" /dev/disk9 "%s/Первый том"\n2: /containers/second.vc - %s/second\n' "$VC_W" "$VC_W")
    VC_EXPECTED=$(printf '%s/Первый том\n%s/second\n' "$VC_W" "$VC_W")
    assert '[ "$(printf "%s\n" "$VC_LIST" | vc_parse_list)" = "$VC_EXPECTED" ]' "пробелы, кириллица, несколько томов и устройство-заглушка"
    assert '[ -z "$(printf "3: /containers/raw.vc /dev/disk8 -\n" | vc_parse_list)" ]' "том без точки монтирования не выбирается"
    assert '! printf "неизвестный формат\n" | vc_parse_list' "неизвестный формат отклоняется"
    assert '! printf "1: /container /dev/disk8 /\n" | vc_parse_list' "корень системы отклоняется"
    assert '! printf "1: /container /dev/disk8 /Volumes/not quoted\n" | vc_parse_list' "неоднозначные поля отклоняются"
fi

VC=/bin/sh
/bin/sh() {
    [ "$*" = "--text --non-interactive --list" ] || return 9
    [ "${VC_RC:-0}" = "0" ] || return "$VC_RC"
    printf '%s\n' "$VC_LIST"
}
VC_RC=0
VC_LIST=$(printf '1: /container /dev/disk9 "%s/Первый том"\n' "$VC_W")
it "выбор VeraCrypt"
assert '[ "$(vc_mounted_vol)" = "$VC_W/Первый том" ]' "выбирается единственный подтверждённый CLI том"
VC_LIST=$(printf '1: /first /dev/disk9 "%s/Первый том"\n2: /second /dev/disk10 %s/second\n' "$VC_W" "$VC_W")
assert '[ "$(vc_mounted_vol <<< 2)" = "$VC_W/second" ]' "из нескольких томов выбирает пользователь"
assert '[ "$(vc_mounted_vol "$VC_W/second" </dev/null)" = "$VC_W/second" ]' "повторная проверка сохраняет выбор"
assert '! vc_mounted_vol "$VC_W/missing" </dev/null' "пропавший выбранный том не заменяется другим"
assert '! vc_mounted_vol <<< 9' "неверный номер не выбирает первый том"
assert '! vc_mounted_vol </dev/null' "EOF отменяет выбор"
VC_RC=1
assert '! vc_mounted_vol "$VC_W/unrelated" </dev/null' "при ошибке CLI обычный каталог не становится VeraCrypt-томом"
VC_RC=0
VC_LIST=""
assert '! vc_mounted_vol </dev/null' "пустой список не подменяется каталогом"
unset -f /bin/sh

VC_PHASE=$(awk '/^if ! stage_done disk; then/ {take=1} /^# Сверка тома с прошлым прогоном/ {exit} take {print}' "$TARGET")
it "сценарий GUI → CLI"
(
    HAVE_DISK=да; BOLD=""; NC=""; MOUNT_WAIT_MIN=30; VOL_NAME=""
    STAGE_FILE="$VC_W/stages"; GUI_OPENED=0
    stage_done() { return 1; }; stage_mark() { printf '%s\n' "$1" >> "$STAGE_FILE"; }
    stage_val() { return 0; }; vol_uuid_of() { return 0; }
    step() { :; }; phase_begin() { :; }; phase_end() { :; }
    sub() { :; }; ding() { :; }; spin() { :; }; spin_end() { :; }
    list_external() { printf 'diskutil вызван\n' >> "$VC_W/unexpected"; return 1; }
    net_wait() { printf 'сеть вызвана\n' >> "$VC_W/unexpected"; return 1; }
    open() { [ "$*" = "-a VeraCrypt" ] || return 1; GUI_OPENED=1; }
    /bin/sh() {
        [ "$GUI_OPENED" = "1" ] || return 1
        [ "$*" = "--text --non-interactive --list" ] || return 1
        printf '1: /first /dev/disk9 "%s/Первый том"\n2: /second /dev/disk10 %s/second\n' "$VC_W" "$VC_W"
    }
    eval "$VC_PHASE"
    [ "$VOL_NAME" = "$VC_W/second" ] && grep -Fxq "vc_mount=$VC_W/second" "$STAGE_FILE"
) <<< 2
VC_PHASE_RC=$?
assert '[ "$VC_PHASE_RC" = "0" ]' "GUI открывается до CLI, выбор второго тома сохраняется до фазы данных"
assert '[ ! -e "$VC_W/unexpected" ]' "готовый диск не требует diskutil и сети"

it "таймер VeraCrypt"
(
    spin() { :; }; spin_end() { :; }; L() { printf '%s' "$1"; }
    vc_mounted_vol() { return 1; }
    list_external() { return 0; }
    clock=0
    date() { printf '%s\n' "$clock"; }
    sleep() { clock=$((clock + $1)); }
    MOUNT_WAIT_MIN=1
    wait_vc_mount >/dev/null 2>&1
    [ "$clock" = "60" ]
)
VC_TIMER_RC=$?
assert '[ "$VC_TIMER_RC" = "0" ]' "минута ожидания равна 60 секундам, а не 10"

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

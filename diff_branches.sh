#!/usr/bin/env bash

# При ошибке завершаем скрипт; ошибки в конвейерах тоже учитываются.
set -euo pipefail

# 1. Проверяем аргументы.
if [ "$#" -ne 3 ]; then
    echo "Использование: bash $0 <репозиторий> <ветка_1> <ветка_2>" >&2
    exit 1
fi

repo_url="$1"
branch_1="$2"
branch_2="$3"

if [ -z "$repo_url" ] || [ -z "$branch_1" ] || [ -z "$branch_2" ]; then
    echo "Ошибка: аргументы не должны быть пустыми." >&2
    exit 1
fi

if ! command -v git > /dev/null 2>&1; then
    echo "Ошибка: Git не установлен." >&2
    exit 1
fi

# 2. Создаем временную папку и удаляем ее при завершении скрипта.
temp_dir=$(mktemp -d)
trap 'rm -rf -- "$temp_dir"' EXIT

# Загружаем репозиторий, не распаковывая рабочие файлы.
git clone --quiet --no-checkout -- "$repo_url" "$temp_dir/repo"

# 3. Проверяем, что обе ветки существуют в удаленном репозитории.
for branch in "$branch_1" "$branch_2"; do
    if ! git -C "$temp_dir/repo" rev-parse --verify --quiet \
        "refs/remotes/origin/$branch^{commit}" > /dev/null; then
        echo "Ошибка: ветка '$branch' не найдена." >&2
        exit 1
    fi
done

# 4. Получаем различия: A — добавлено, D — удалено, M — изменено.
# Переименование показываем как удаление и добавление.
# Изменение типа файла (T), например на символьную ссылку, считаем M.
diff_file="$temp_dir/changes.txt"

git -C "$temp_dir/repo" diff --no-ext-diff --name-status --no-renames \
    "refs/remotes/origin/$branch_1" "refs/remotes/origin/$branch_2" -- \
    | awk '{ sub(/^T\t/, "M\t"); print }' > "$diff_file"

# Заменяем / в именах веток, чтобы не создавать вложенные папки.
safe_branch_1="${branch_1//\//_}"
safe_branch_2="${branch_2//\//_}"
report_file="diff_report_${safe_branch_1}_vs_${safe_branch_2}.txt"

# 5. Записываем заголовок, список файлов и статистику в один отчет.
{
    echo "Отчет о различиях между ветками"
    echo
    echo "================================"
    printf 'Репозиторий:    %s\n' "$repo_url"
    printf 'Ветка 1:        %s\n' "$branch_1"
    printf 'Ветка 2:        %s\n' "$branch_2"
    printf 'Дата генерации: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================"
    echo
    echo "СПИСОК ИЗМЕНЕННЫХ ФАЙЛОВ:"

    if [ -s "$diff_file" ]; then
        cat "$diff_file"
    else
        echo "Различий нет."
    fi

    echo
    echo "СТАТИСТИКА:"

    awk '
        $1 == "A" { added++ }
        $1 == "D" { deleted++ }
        $1 == "M" { modified++ }
        END {
            printf "Всего измененных файлов: %d\n", NR
            printf "Добавлено (A):    %d\n", added + 0
            printf "Удалено (D):      %d\n", deleted + 0
            printf "Изменено (M):     %d\n", modified + 0
        }
    ' "$diff_file"
} > "$report_file"

printf 'Отчет сохранен: %s\n' "$report_file"

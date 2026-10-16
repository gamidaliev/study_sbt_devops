#!/usr/bin/env bash
set -euo pipefail

# 1. Проверяем аргументы.
if [ "$#" -ne 2 ]; then
    echo "Использование: bash $0 <лог-файл> <ключевое_слово>" >&2
    exit 1
fi

log_file="$1"
keyword="$2"

if [ ! -f "$log_file" ] || [ ! -r "$log_file" ]; then
    echo "Ошибка: лог-файл не существует или недоступен для чтения." >&2
    exit 1
fi

if [ -z "$keyword" ]; then
    echo "Ошибка: ключевое слово не должно быть пустым." >&2
    exit 1
fi

# 2. Формируем имена двух выходных файлов.
base_name=$(basename -- "$log_file")
file_name="${base_name%.*}"
errors_file="${file_name}_errors.txt"
count_file="${file_name}_count.txt"

if [ "$log_file" -ef "$errors_file" ] || [ "$log_file" -ef "$count_file" ]; then
    echo "Ошибка: выходной файл совпадает с исходным логом." >&2
    exit 1
fi

# 3. Сохраняем строки с ключевым словом.
grep_status=0
grep -F -- "$keyword" "$log_file" > "$errors_file" || grep_status=$?

# Код 1 означает отсутствие совпадений; код больше 1 — ошибку.
if [ "$grep_status" -gt 1 ]; then
    echo "Ошибка при поиске в лог-файле." >&2
    exit "$grep_status"
fi

# 4. Подсчитываем строки и сохраняем отчет.
count=$(wc -l < "$errors_file")

{
    printf 'Лог-файл: %s\n' "$log_file"
    printf 'Ключевое слово: %s\n' "$keyword"
    printf 'Найдено строк: %s\n' "$count"
} > "$count_file"

printf 'Найдено строк: %s\n' "$count"
printf 'Найденные строки сохранены в: %s\n' "$errors_file"
printf 'Отчет о количестве сохранен в: %s\n' "$count_file"

#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Скрипт предназначен для Linux, в том числе Ubuntu в WSL.
if [ "$(uname -s)" != "Linux" ]; then
    echo "Ошибка: нужен Linux. На Windows запускайте скрипт через WSL." >&2
    exit 1
fi

if [ "$#" -ne 1 ]; then
    echo "Использование: bash $0 START|STOP|STATUS" >&2
    exit 1
fi

script_path=$(readlink -f -- "$0")
report_dir=$(dirname -- "$script_path")
pid_file="$report_dir/.system_monitor.pid"
lock_file="$report_dir/.system_monitor.lock"
control_lock="$report_dir/.system_monitor.control.lock"
log_file="$report_dir/system_monitor.log"
interval=600
pid=""
sleep_pid=""

# Проверяем не только наличие PID, но и то, что это наш процесс.
is_running() {
    local -a process_args=()
    [ -r "$pid_file" ] || return 1
    read -r pid < "$pid_file" || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    mapfile -d '' -t process_args < "/proc/$pid/cmdline" 2>/dev/null || return 1
    [ "${process_args[1]:-}" = "$script_path" ] &&
        [ "${process_args[2]:-}" = "__RUN" ]
}

# Ожидание в фоне позволяет обработать STOP, не дожидаясь конца sleep.
pause() {
    sleep "$1" 9>&- &
    sleep_pid=$!
    wait "$sleep_pid"
    sleep_pid=""
}

cleanup() {
    if [ -n "$sleep_pid" ]; then
        kill "$sleep_pid" 2>/dev/null || true
        wait "$sleep_pid" 2>/dev/null || true
    fi
    # Удаляем только собственный PID-файл.
    if [ -r "$pid_file" ] && [ "$(cat "$pid_file")" = "$$" ]; then
        rm -f -- "$pid_file"
    fi
}

# Суммарные тики всех ядер и тики простоя (idle + iowait).
cpu_snapshot() {
    awk '/^cpu / {
        total = 0
        for (i = 2; i <= 9; i++) total += $i
        printf "%.0f %.0f\n", total, $5 + $6
        exit
    }' /proc/stat
}

collect_metrics() {
    local total_1 idle_1 total_2 idle_2 cpu_used
    local all_memory free_memory memory_used disk_used load_average timestamp csv_file

    read -r total_1 idle_1 < <(cpu_snapshot)
    pause 1
    read -r total_2 idle_2 < <(cpu_snapshot)

    cpu_used=$(awk -v total="$((total_2 - total_1))" \
        -v idle="$((idle_2 - idle_1))" 'BEGIN {
        if (total > 0) printf "%.2f", 100 * (total - idle) / total
        else printf "0.00"
    }')

    # /proc/meminfo хранит память в КиБ; переводим в МиБ.
    read -r all_memory free_memory memory_used < <(
        awk '
            /^MemTotal:/ { total = $2 }
            /^MemFree:/  { free = $2 }
            END {
                printf "%.2f %.2f %.2f\n", total / 1024, free / 1024,
                    100 * (total - free) / total
            }
        ' /proc/meminfo
    )

    disk_used=$(df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')
    read -r load_average _ < /proc/loadavg
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    csv_file="$report_dir/system_report_${timestamp:0:10}.csv"

    if [ ! -s "$csv_file" ]; then
        printf '%s\n' 'timestamp;all_memory;free_memory;%memory_used;%cpu_used;%disk_used;load_average_1m' \
            > "$csv_file"
    fi

    printf '%s;%s;%s;%s;%s;%s;%s\n' \
        "$timestamp" "$all_memory" "$free_memory" "$memory_used" \
        "$cpu_used" "$disk_used" "$load_average" >> "$csv_file"
}

# Внутренний режим: его запускает команда START.
if [ "$1" = "__RUN" ]; then
    exec 9> "$lock_file"
    flock -n 9 || exit 1
    trap cleanup EXIT
    trap 'exit 0' TERM INT
    printf '%s\n' "$$" > "$pid_file"

    while true; do
        cycle_start=$(date +%s)
        collect_metrics
        # Учитываем время самого замера в интервале 600 секунд.
        delay=$((interval - ($(date +%s) - cycle_start)))
        if [ "$delay" -gt 0 ]; then
            pause "$delay"
        fi
    done
fi

# Сериализуем команды управления, чтобы два START не запустились одновременно.
exec 8> "$control_lock"
flock -x 8

case "$1" in
    START)
        if is_running; then
            echo "Мониторинг уже запущен. PID: $pid"
            exit 0
        fi

        nohup bash "$script_path" __RUN </dev/null >> "$log_file" 2>&1 8>&- &
        new_pid=$!

        # Дожидаемся, пока фоновый процесс запишет свой PID.
        for ((i = 0; i < 50; i++)); do
            if is_running && [ "$pid" = "$new_pid" ]; then
                echo "Мониторинг запущен. PID: $pid"
                exit 0
            fi
            sleep 0.1
        done
        echo "Ошибка запуска. Подробности: $log_file" >&2
        exit 1
        ;;
    STOP)
        if ! is_running; then
            echo "Мониторинг не запущен."
            exit 0
        fi

        stopped_pid="$pid"
        kill "$pid"
        for ((i = 0; i < 50; i++)); do
            if ! is_running; then
                echo "Мониторинг остановлен. PID: $stopped_pid"
                exit 0
            fi
            sleep 0.1
        done
        echo "Процесс $stopped_pid еще завершается; проверьте STATUS." >&2
        exit 1
        ;;
    STATUS)
        if is_running; then
            echo "Мониторинг запущен. PID: $pid"
        else
            echo "Мониторинг не запущен."
        fi
        ;;
    *)
        echo "Ошибка: используйте START, STOP или STATUS." >&2
        exit 1
        ;;
esac

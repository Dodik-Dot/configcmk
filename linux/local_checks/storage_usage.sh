#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: Daily Storage Usage (Robust Multi-Platform)
# Scheduled to run once a day at 16:00
# ==============================================================================
CACHE_DIR="/var/lib/check_mk_agent/cache"
mkdir -p "$CACHE_DIR" 2>/dev/null
CACHE_FILE="$CACHE_DIR/cache_storage_usage.txt"

# Hitung batas jadwal jam 16:00
CURRENT_HOUR=$(date +%H)
TODAY_16=$(date -d "16:00:00" +%s 2>/dev/null || date +%s -d "16:00:00" 2>/dev/null)

if [ "$CURRENT_HOUR" -lt 16 ]; then
    LAST_16=$(date -d "yesterday 16:00:00" +%s 2>/dev/null || echo $(( TODAY_16 - 86400 )))
else
    LAST_16=$TODAY_16
fi

need_update() {
    local file=$1
    local threshold=$2
    # Jika file tidak ada ATAU berukuran 0 byte (kosong), wajib perbarui
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        return 0
    fi
    local file_ts
    file_ts=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    if [ "$file_ts" -lt "$threshold" ]; then
        return 0
    fi
    return 1
}

if need_update "$CACHE_FILE" "$LAST_16"; then
    TMP_FILE=$(mktemp /tmp/storage_usage.XXXXXX 2>/dev/null || echo "/tmp/cmk_storage_tmp")
    > "$TMP_FILE"

    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    df_output=$(df -PT 2>/dev/null || df -T 2>/dev/null || df 2>/dev/null)

    echo "$df_output" | tail -n +2 | while read -r fs type total used avail pct mount; do
        [ -z "$fs" ] && continue

        # 1. Kecualikan sistem berkas virtual/semu
        case "$type" in
            tmpfs|devtmpfs|devfs|sysfs|proc|udev|cgroup*|squashfs|configfs|pstore|bpf|autofs|securityfs|hugetlbfs|mqueue|devpts|fusectl|nsfs|overlay)
                continue
                ;;
        esac

        # 2. Kecualikan direktori sistem virtual/container
        case "$mount" in
            /proc*|/sys*|/dev*|/run*|/var/lib/docker*|/var/lib/kubelet*|/snap*)
                continue
                ;;
        esac

        # 3. Bersihkan tanda persen
        used_pct=$(echo "$pct" | tr -d '%')
        if ! [[ "$used_pct" =~ ^[0-9]+$ ]]; then
            continue
        fi

        # 4. Konversi ukuran ke GB
        total_gb=$(awk "BEGIN {printf \"%.2f\", $total / 1048576}")
        free_gb=$(awk "BEGIN {printf \"%.2f\", $avail / 1048576}")

        # 5. Format nama mount point untuk Checkmk service
        mount_clean=$(echo "$mount" | sed 's|/$|root|' | sed 's|^/||' | sed 's|/|_|g')
        [ -z "$mount_clean" ] && mount_clean="root"
        service_name="Storage_Usage_${mount_clean}"

        # 6. Ambang Batas: OK < 85%, WARNING >= 85%, CRITICAL >= 95%
        status=0
        status_label="OK"
        if [ "$used_pct" -ge 95 ]; then
            status=2
            status_label="Critical"
        elif [ "$used_pct" -ge 85 ]; then
            status=1
            status_label="Warning"
        fi

        echo "$status \"$service_name\" - Status : $status_label | Partition: $mount | Used: ${used_pct}% | Free: ${free_gb} GB | Total: ${total_gb} GB" >> "$TMP_FILE"
    done

    # Simpan hanya jika file sementara berhasil terisi data
    if [ -s "$TMP_FILE" ]; then
        mv "$TMP_FILE" "$CACHE_FILE"
        chmod 644 "$CACHE_FILE"
    else
        rm -f "$TMP_FILE"
    fi
fi

cat "$CACHE_FILE" 2>/dev/null

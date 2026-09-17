#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: Physical Disk & NVMe Health Monitor (Linux)
# Scheduled to run once a day at 16:00
# ==============================================================================
CACHE_DIR="/var/lib/check_mk_agent/cache"
mkdir -p "$CACHE_DIR" 2>/dev/null
CACHE_FILE="$CACHE_DIR/cache_disk_nvme_health.txt"

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
    if [ ! -f "$file" ]; then return 0; fi
    local file_ts
    file_ts=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    if [ "$file_ts" -lt "$threshold" ]; then return 0; fi
    return 1
}

if need_update "$CACHE_FILE" "$LAST_16"; then
    > "$CACHE_FILE"

    # Pastikan smartctl terpasang
    if ! command -v smartctl &>/dev/null; then
        echo "1 \"Health_Storage\" - smartmontools tidak terpasang di sistem | Status: WARNING" >> "$CACHE_FILE"
        cat "$CACHE_FILE"
        exit 0
    fi

    # Pindai semua disk fisik utama (sda, sdb, nvme0n1, dll)
    for dev_path in /sys/block/sd* /sys/block/nvme*n1; do
        [ -e "$dev_path" ] || continue
        dev_name=$(basename "$dev_path")

        # Lewati loop device / virtual
        case "$dev_name" in
            loop*|ram*|dm-*|sr*) continue ;;
        esac

        disk_dev="/dev/$dev_name"
        [ -b "$disk_dev" ] || continue

        # 1. Ambil Informasi Model & Kapasitas
        info_out=$(smartctl -i "$disk_dev" 2>/dev/null)
        model=$(echo "$info_out" | grep -E "Device Model|Model Number" | head -n 1 | awk -F: '{print $2}' | sed 's/^[ \t]*//')
        [ -z "$model" ] && model=$(lsblk -d -n -o MODEL "$disk_dev" 2>/dev/null | sed 's/^[ \t]*//')
        [ -z "$model" ] && model="$dev_name"

        # Kapasitas GB
        size_bytes=$(cat "$dev_path/size" 2>/dev/null || echo 0)
        size_gb=$(( size_bytes * 512 / 1073741824 ))
        [ "$size_gb" -eq 0 ] && size_gb=$(lsblk -b -d -n -o SIZE "$disk_dev" 2>/dev/null | awk '{printf "%.0f", $1/1073741824}')

        # 2. Deteksi Akurat: NVMe vs HDD (Mekanik) vs SSD SATA
        is_rotational=$(cat "$dev_path/queue/rotational" 2>/dev/null || echo 1)

        if [[ "$dev_name" =~ ^nvme ]]; then
            disk_type="NVMe"
        elif [ "$is_rotational" -eq 1 ]; then
            disk_type="HDD (Mekanik)"
        else
            disk_type="SSD Sata"
        fi

        # 3. Status Kesehatan SMART
        smart_health=$(smartctl -H "$disk_dev" 2>/dev/null)
        if echo "$smart_health" | grep -Eq "PASSED|OK"; then
            status_code=0
            status_label="OK"
            smart_status="PASSED"
        else
            status_code=2
            status_label="Critical"
            smart_status="FAILED"
        fi

        # 4. Suhu
        temp_val=$(smartctl -A "$disk_dev" 2>/dev/null | awk '/Temperature_Celsius|Current Drive Temperature|Airflow_Temperature_Cel/{print $10}' | head -n 1)
        if [ -z "$temp_val" ]; then
            temp_val=$(smartctl -a "$disk_dev" 2>/dev/null | grep -i "Temperature:" | head -n 1 | awk '{print $2}')
        fi
        [ -z "$temp_val" ] && temp_str="N/A" || temp_str="${temp_val}C"

        # 5. Persentase Health & Statistik Read/Write
        health_pct="100%"
        read_tb="0.0 TB"
        written_tb="0.0 TB"
        write_per_day="0.00 GB"

        if [ "$disk_type" = "NVMe" ]; then
            nvme_log=$(smartctl -a "$disk_dev" 2>/dev/null)
            wear=$(echo "$nvme_log" | grep -i "Percentage Used:" | awk '{print $3}' | tr -d '%')
            if [ -n "$wear" ]; then
                calc_health=$(( 100 - wear ))
                health_pct="${calc_health}%"
                [ "$calc_health" -le 20 ] && status_code=2
            fi

            # Hitung TBW
            data_w=$(echo "$nvme_log" | grep -i "Data Units Written:" | awk '{print $4}' | tr -d ',\.')
            if [ -n "$data_w" ]; then
                written_tb=$(awk "BEGIN {printf \"%.1f TB\", ($data_w * 512000) / 1099511627776}")
            fi
        elif [ "$disk_type" = "HDD (Mekanik)" ]; then
            # Pengecekan Bad Sector / Sektor Rusak pada Hardisk
            bad_sectors=$(smartctl -A "$disk_dev" 2>/dev/null | awk '/Reallocated_Sector_Ct|Current_Pending_Sector|Offline_Uncorrectable/{sum+=$10} END {print sum}')
            if [ -n "$bad_sectors" ] && [ "$bad_sectors" -gt 0 ]; then
                health_pct="WARNING ($bad_sectors Bad Sector)"
                status_code=1
                status_label="Warning"
            else
                health_pct="100% (0 Bad Sector)"
            fi
            read_tb="N/A"
            written_tb="N/A"
            write_per_day="N/A"
        fi

        service_name="Health_Storage ($model)"
        echo "$status_code \"$service_name\" - Status : $status_label | Type: $disk_type (${size_gb} GB) | Status: $smart_status | Temp: $temp_str | Health: $health_pct | Read: $read_tb | Written: $written_tb | Write/Day: $write_per_day" >> "$CACHE_FILE"
    done
fi

cat "$CACHE_FILE" 2>/dev/null

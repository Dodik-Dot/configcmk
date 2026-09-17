#!/usr/bin/env python3
# ==============================================================================
# Local Check Checkmk: Hybrid Storage Health (smartctl + HDSentinel Linux)
# Scheduled to run once a day at 16:00 via built-in cache
# ==============================================================================
import datetime
import glob
import os
import re
import shutil
import subprocess
import sys
import time

CACHE_DIR = "/var/lib/check_mk_agent/cache"
CACHE_FILE = os.path.join(CACHE_DIR, "cache_storage_health.txt")


def check_cache_valid():
  """Memeriksa apakah cache masih berlaku berdasarkan threshold jam 16:00"""
  if not os.path.exists(CACHE_FILE) or os.path.getsize(CACHE_FILE) == 0:
    return False

  now = datetime.datetime.now()
  today_16 = now.replace(hour=16, minute=0, second=0, microsecond=0)
  last_16 = today_16 if now >= today_16 else today_16 - datetime.timedelta(days=1)
  threshold_ts = last_16.timestamp()

  file_ts = os.path.getmtime(CACHE_FILE)
  return file_ts >= threshold_ts


def get_hdsentinel_data():
  """Memindai seluruh drive menggunakan HDSentinel Linux jika terpasang"""
  hds_bin = shutil.which("hdsentinel")
  if not hds_bin:
    for p in [
        "/usr/local/bin/hdsentinel",
        "/usr/bin/hdsentinel",
        "/opt/hdsentinel/hdsentinel",
    ]:
      if os.path.exists(p) and os.access(p, os.X_OK):
        hds_bin = p
        break

  if not hds_bin:
    return {}

  try:
    res = subprocess.run(
        ["sudo", hds_bin, "-s"], capture_output=True, text=True, check=False
    )
    out = res.stdout or ""
    if not out:
      res = subprocess.run(
          ["sudo", hds_bin], capture_output=True, text=True, check=False
      )
      out = res.stdout or ""

    drives = {}
    cur_dev = None

    for line in out.split("\n"):
      line_str = line.strip()
      dev_match = re.search(
          r"HDD Device\s+\d+:\s+(\S+)", line_str, re.IGNORECASE
      )
      if dev_match:
        cur_dev = dev_match.group(1).strip()
        drives[cur_dev] = {}
        continue

      if cur_dev:
        if line_str.startswith("Health"):
          m = re.search(r"(\d+)\s*%", line_str)
          if m:
            drives[cur_dev]["health"] = int(m.group(1))
        elif line_str.startswith("Performance"):
          m = re.search(r"(\d+)\s*%", line_str)
          if m:
            drives[cur_dev]["perf"] = int(m.group(1))
        elif "Est. lifetime" in line_str or "lifetime" in line_str.lower():
          parts = line_str.split(":", 1)
          if len(parts) > 1:
            drives[cur_dev]["est_life"] = parts[1].strip()

    return drives
  except Exception:
    return {}


def run_smartctl(device):
  try:
    result = subprocess.run(
        ["sudo", "smartctl", "-a", device],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout
  except Exception:
    return ""


def parse_smartctl_output(text, device_name, hds_info=None):
  model = "Unknown Model"
  capacity_bytes = 0
  cap_bracket = "Unknown"
  is_nvme = False
  is_ssd = False
  is_hdd = False
  rotation_rate = ""
  smart_status = "PASSED"
  attributes = {}
  dev_base = os.path.basename(device_name).lower()

  if "nvme" in dev_base:
    is_nvme = True

  lines = text.split("\n")
  for line in lines:
    line_strip = line.strip()
    if not line_strip:
      continue

    if line_strip.startswith("Model Number:") or line_strip.startswith(
        "Device Model:"
    ):
      model = line_strip.split(":", 1)[1].strip()

    if line_strip.startswith("User Capacity:") or line_strip.startswith(
        "Total NVM Capacity:"
    ):
      cap_match = re.search(r"([\d,]+)\s+bytes", line_strip)
      if cap_match:
        capacity_bytes = int(cap_match.group(1).replace(",", ""))
      cap_bracket_match = re.search(r"\[([^\]]+)\]", line_strip)
      if cap_bracket_match:
        cap_bracket = cap_bracket_match.group(1).strip()

    if line_strip.startswith("Rotation Rate:"):
      rotation_rate = line_strip.split(":", 1)[1].strip()

    if (
        "NVM Express" in line_strip
        or "Total NVM Capacity" in line_strip
        or "NVMe Version" in line_strip
    ):
      is_nvme = True

    if "SMART overall-health self-assessment test result:" in line_strip:
      smart_status = line_strip.split(":", 1)[1].strip()
    elif "SMART overall-health self-assessment test result" in line_strip:
      parts = line_strip.split()
      if parts:
        smart_status = parts[-1]

    match = re.match(r"^\s*(\d+)\s+([a-zA-Z0-9_-]+)\s+", line)
    if match:
      attr_id = int(match.group(1))
      attr_name = match.group(2)
      rest = line[match.end() :]
      dash_match = re.search(r"-\s+(\d+)", rest)
      if dash_match:
        raw_val = int(dash_match.group(1))
      else:
        clean_rest = re.sub(r"\(.*\)", "", rest)
        nums = re.findall(r"\d+", clean_rest)
        raw_val = int(nums[-1]) if nums else 0
      attributes[attr_id] = (attr_name, raw_val)

  # =========================================================================
  # 1. Prioritas Klasifikasi Tipe Drive (Fix SSD Terbaca HDD)
  # =========================================================================
  model_upper = model.upper()
  rot_lower = rotation_rate.lower()

  if not is_nvme:
    # A. Cek eksplisit Solid State / SSD
    if (
        "solid state" in rot_lower
        or "ssd" in rot_lower
        or "SSD" in model_upper
        or "SATA3 128GB" in model_upper
    ):
      is_ssd = True
      is_hdd = False
    # B. Cek RPM (HDD Mekanik)
    elif "rpm" in rot_lower or (
        rot_lower and any(c.isdigit() for c in rotation_rate)
    ):
      is_hdd = True
      is_ssd = False

  # =========================================================================
  # 2. Deteksi Heuristik Cadangan (Jika belum terklasifikasi)
  # =========================================================================
  if not is_nvme and not is_ssd and not is_hdd:
    hdd_brands = [
        "WDC",
        "WD500",
        "WD10",
        "WD20",
        "WD30",
        "WD40",
        "ST500",
        "ST1000",
        "ST2000",
        "BARRACUDA",
        "TOSHIBA DT",
        "HITACHI",
        "HGST",
    ]
    if any(k in model_upper for k in hdd_brands):
      is_hdd = True

    if not is_hdd:
      rot_path = f"/sys/block/{dev_base}/queue/rotational"
      if os.path.exists(rot_path):
        try:
          with open(rot_path, "r") as f:
            val = f.read().strip()
            if val == "1":
              is_hdd = True
            elif val == "0":
              is_ssd = True
        except Exception:
          pass

    if not is_ssd and not is_hdd:
      if 3 in attributes or 10 in attributes:
        is_hdd = True
      elif any(x in attributes for x in [231, 233, 177, 202, 169]):
        is_ssd = True
      else:
        is_hdd = True

  disk_type = "NVME" if is_nvme else ("HDD (Mekanik)" if is_hdd else "SSD Sata")

  # Suhu & POH
  temp = 0
  if 194 in attributes:
    temp = attributes[194][1]
  elif 190 in attributes:
    temp = attributes[190][1]
  else:
    temp_match = re.search(r"Temperature:\s+(\d+)\s+Celsius", text, re.IGNORECASE)
    temp = int(temp_match.group(1)) if temp_match else 0

  poh = 0
  if 9 in attributes:
    poh = attributes[9][1]
  else:
    poh_match = re.search(
        r"Power\s+On\s+Hours:\s+([\d,]+)", text, re.IGNORECASE
    )
    poh = int(poh_match.group(1).replace(",", "")) if poh_match else 0

  model_clean = model.strip()
  if cap_bracket == "Unknown" and capacity_bytes > 0:
    gb = capacity_bytes / (1000**3)
    cap_bracket = (
        f"{gb / 1000.0:.2f} TB" if gb >= 900 else f"{int(round(gb))} GB"
    )

  # Perhitungan Health (Prioritaskan HDSentinel jika tersedia)
  health = 100
  hds_perf_str = ""
  hds_life_str = ""

  if hds_info and "health" in hds_info:
    health = hds_info["health"]
    if "perf" in hds_info:
      hds_perf_str = f" | HDS Perf: {hds_info['perf']}%"
    if "est_life" in hds_info:
      hds_life_str = f" | Est. Life: {hds_info['est_life']}"
  else:
    if is_nvme:
      percent_used_match = re.search(
          r"Percentage\s+Used:\s+(\d+)", text, re.IGNORECASE
      )
      if percent_used_match:
        health = 100 - int(percent_used_match.group(1))
    elif is_ssd:
      for attr_key in [231, 202, 169]:
        if attr_key in attributes:
          health = attributes[attr_key][1]
          break

  status_code = 0
  status_word = "OK"
  if health <= 50:
    status_code = 2
    status_word = "CRITICAL"
  elif health <= 80:
    status_code = 1
    status_word = "WARNING"

  if smart_status != "PASSED":
    status_code = 2
    status_word = "CRITICAL"

  if disk_type in ["NVME", "SSD Sata"]:
    read_tb = 0.0
    write_tb = 0.0
    if is_nvme:
      write_match = re.search(
          r"Data\s+Units\s+Written:\s+[\d,]+\s+\[([\d.]+)\s+TB\]",
          text,
          re.IGNORECASE,
      )
      write_tb = float(write_match.group(1)) if write_match else 0.0
      read_match = re.search(
          r"Data\s+Units\s+Read:\s+[\d,]+\s+\[([\d.]+)\s+TB\]",
          text,
          re.IGNORECASE,
      )
      read_tb = float(read_match.group(1)) if read_match else 0.0
    else:
      raw_w = attributes.get(241)[1] if attributes.get(241) else 0
      raw_r = attributes.get(242)[1] if attributes.get(242) else 0
      is_gb = any(
          b in model.upper()
          for b in ["APACER", "CS900", "V-GEN", "PATRIOT", "ADATA"]
      )
      write_tb = raw_w / 1000.0 if is_gb else (raw_w * 512 / (10**12))
      read_tb = raw_r / 1000.0 if is_gb else (raw_r * 512 / (10**12))

    days_active = poh / 24.0
    write_day = (write_tb * 1000.0) / days_active if days_active > 0 else 0.0

    output_line = (
        f'{status_code} "Health_Storage ({model_clean})" - Status :'
        f" {status_word} | Type: {disk_type} ({cap_bracket}) | Health:"
        f" {health}%{hds_perf_str}{hds_life_str} | Status: {smart_status} |"
        f" Temp: {temp}C | Read: {read_tb:.1f} TB | Written: {write_tb:.1f} TB"
        f" | Write/Day: {write_day:.2f} GB"
    )
  else:
    # HDD Mekanik
    reallocated = attributes.get(5)[1] if attributes.get(5) else 0
    pending = attributes.get(197)[1] if attributes.get(197) else 0
    rot_clean = (
        rotation_rate.replace(" ", "").replace("RPM", "rpm")
        if rotation_rate
        else "5400/7200 rpm"
    )

    remark = "Kondisi Sehat (0 Bad Sector)"
    if reallocated > 0 or pending > 0:
      if status_code == 0:
        status_code = 1
        status_word = "WARNING"
      remark = (
          f"Waspada: {reallocated} Reallocated / {pending} Pending Sector"
      )

    output_line = (
        f'{status_code} "Health_Storage ({model_clean})" - Status :'
        f" {status_word} | Type: {disk_type} ({cap_bracket}) | Health:"
        f" {health}%{hds_perf_str}{hds_life_str} | Status: {smart_status} |"
        f" Temp: {temp}C | Rotation: {rot_clean} | Bad Sector: {reallocated} |"
        f" POH: {poh} Jam | Remark: {remark}"
    )

  return output_line


def get_block_devices():
  devices = []
  for path in glob.glob("/sys/block/sd*"):
    devices.append("/dev/" + os.path.basename(path))
  for path in glob.glob("/sys/block/nvme*n*"):
    devices.append("/dev/" + os.path.basename(path))
  return sorted(devices)


def main():
  # 1. Gunakan cache jika masih valid
  if check_cache_valid():
    try:
      with open(CACHE_FILE, "r") as f:
        print(f.read(), end="")
      return
    except Exception:
      pass

  # 2. Pemindaian baru jika cache kedaluwarsa
  if not shutil.which("smartctl"):
    print('3 "Health_Storage" - UNKNOWN: smartctl tidak ditemukan.')
    return

  devices = get_block_devices()
  if not devices:
    print('0 "Health_Storage" - Status : OK | Tidak ada drive terdeteksi.')
    return

  hds_map = get_hdsentinel_data()
  results = []

  for dev in devices:
    raw_out = run_smartctl(dev)
    if not raw_out:
      continue
    if "Device Model:" not in raw_out and "Model Number:" not in raw_out:
      continue
    try:
      hds_dev_info = hds_map.get(dev, None)
      line = parse_smartctl_output(raw_out, dev, hds_info=hds_dev_info)
      results.append(line)
    except Exception as e:
      results.append(
          f'3 "Health_Storage ({os.path.basename(dev)})" - UNKNOWN: Error'
          f" parsing: {str(e)}"
      )

  output_text = "\n".join(results) + "\n"
  print(output_text, end="")

  # 3. Tulis ke cache file
  os.makedirs(CACHE_DIR, exist_ok=True)
  try:
    with open(CACHE_FILE, "w") as f:
      f.write(output_text)
  except Exception:
    pass


if __name__ == "__main__":
  main()

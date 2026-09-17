#!/usr/bin/env python3
# ==============================================================================
# Local Check Checkmk: Storage Health (SATA SSD, SATA HDD, NVMe)
# ==============================================================================
import glob
import os
import re
import shutil
import subprocess
import sys


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


def parse_smartctl_output(text, device_name):
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

    # Parse Model
    if line_strip.startswith("Model Number:") or line_strip.startswith(
        "Device Model:"
    ):
      model = line_strip.split(":", 1)[1].strip()

    # Parse Kapasitas
    if line_strip.startswith("User Capacity:") or line_strip.startswith(
        "Total NVM Capacity:"
    ):
      cap_match = re.search(r"([\d,]+)\s+bytes", line_strip)
      if cap_match:
        capacity_bytes = int(cap_match.group(1).replace(",", ""))
      cap_bracket_match = re.search(r"\[([^\]]+)\]", line_strip)
      if cap_bracket_match:
        cap_bracket = cap_bracket_match.group(1).strip()

    # 1. Pengecekan Rotation Rate dari teks SMART
    if line_strip.startswith("Rotation Rate:"):
      rotation_rate = line_strip.split(":", 1)[1].strip()
      if "solid state" in rotation_rate.lower() or "ssd" in rotation_rate.lower():
        is_ssd = True
      elif "rpm" in rotation_rate.lower() or any(
          c.isdigit() for c in rotation_rate
      ):
        is_hdd = True

    # Pengecekan Protokol NVMe Resmi
    if (
        "NVM Express" in line_strip
        or "Total NVM Capacity" in line_strip
        or "NVMe Version" in line_strip
    ):
      is_nvme = True

    # Parse Status SMART
    if "SMART overall-health self-assessment test result:" in line_strip:
      smart_status = line_strip.split(":", 1)[1].strip()
    elif "SMART overall-health self-assessment test result" in line_strip:
      parts = line_strip.split()
      if parts:
        smart_status = parts[-1]

    # Parse Atribut Tabel SATA
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

  # 2. Deteksi Berlapis Tambahan Jika Drive SATA Belum Terklasifikasi
  if not is_nvme:
    # A. Cek kernel Linux /sys/block/<dev>/queue/rotational (1 = HDD, 0 = SSD)
    rot_path = f"/sys/block/{dev_base}/queue/rotational"
    if os.path.exists(rot_path):
      try:
        with open(rot_path, "r") as f:
          val = f.read().strip()
          if val == "1":
            is_hdd = True
          elif val == "0" and not is_hdd:
            is_ssd = True
      except Exception:
        pass

    # B. Cek Atribut Fisik Motor Piringan (ID 3 Spin_Up_Time & ID 10 Spin_Retry_Count hanya milik HDD)
    if 3 in attributes or 10 in attributes:
      is_hdd = True
      is_ssd = False

    # C. Cek Heuristik Model HDD Terkenal (WDC, Seagate Barracuda, Toshiba DT, HGST)
    model_upper = model.upper()
    if any(
        k in model_upper
        for k in [
            "WDC",
            "WD500",
            "WD10",
            "WD20",
            "WD30",
            "WD40",
            "ST500",
            "ST1000",
            "BARRACUDA",
            "TOSHIBA DT",
            "HITACHI",
            "HGST",
        ]
    ):
      if "SSD" not in model_upper:
        is_hdd = True
        is_ssd = False

    # Fallback jika model tidak dikenal
    if not is_hdd and not is_ssd:
      if any(x in attributes for x in [231, 233, 177, 202, 169]):
        is_ssd = True
      else:
        is_hdd = True

  # Penentuan Label Disk
  if is_nvme:
    disk_type = "NVME"
  elif is_hdd:
    disk_type = "HDD (Mekanik)"
  else:
    disk_type = "SSD Sata"

  # Pembacaan Suhu
  temp = 0
  if 194 in attributes:
    temp = attributes[194][1]
  elif 190 in attributes:
    temp = attributes[190][1]
  else:
    temp_match = re.search(r"Temperature:\s+(\d+)\s+Celsius", text, re.IGNORECASE)
    temp = int(temp_match.group(1)) if temp_match else 0

  # Power On Hours
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

  status_code = 0
  status_word = "OK"

  if disk_type in ["NVME", "SSD Sata"]:
    health = 100
    if is_nvme:
      percent_used_match = re.search(
          r"Percentage\s+Used:\s+(\d+)", text, re.IGNORECASE
      )
      if percent_used_match:
        health = 100 - int(percent_used_match.group(1))
    else:
      for attr_key in [231, 202, 169]:
        if attr_key in attributes:
          health = attributes[attr_key][1]
          break

    if health <= 80:
      status_code = 2
      status_word = "CRITICAL"
    elif health <= 90:
      status_code = 1
      status_word = "WARNING"

    if smart_status != "PASSED":
      status_code = 2
      status_word = "CRITICAL"

    read_tb = 0.0
    write_tb = 0.0

    if is_nvme:
      read_match = re.search(
          r"Data\s+Units\s+Read:\s+[\d,]+\s+\[([\d.]+)\s+TB\]",
          text,
          re.IGNORECASE,
      )
      if read_match:
        read_tb = float(read_match.group(1))
      else:
        raw_r = re.search(
            r"Data\s+Units\s+Read:\s+([\d,]+)", text, re.IGNORECASE
        )
        if raw_r:
          read_tb = int(raw_r.group(1).replace(",", "")) * 512000 / (10**12)

      write_match = re.search(
          r"Data\s+Units\s+Written:\s+[\d,]+\s+\[([\d.]+)\s+TB\]",
          text,
          re.IGNORECASE,
      )
      if write_match:
        write_tb = float(write_match.group(1))
      else:
        raw_w = re.search(
            r"Data\s+Units\s+Written:\s+([\d,]+)", text, re.IGNORECASE
        )
        if raw_w:
          write_tb = int(raw_w.group(1).replace(",", "")) * 512000 / (10**12)
    else:
      raw_write = attributes.get(241)[1] if attributes.get(241) else 0
      raw_read = attributes.get(242)[1] if attributes.get(242) else 0

      is_gb_scale = any(
          b in model.upper()
          for b in [
              "APACER",
              "CS900",
              "V-GEN",
              "PATRIOT",
              "ADATA",
              "KINGMAX",
              "PHISON",
              "SMI",
          ]
      )
      if raw_write < 5000000 and poh > 100 and (raw_write / (poh + 1)) > 0.01:
        is_gb_scale = True

      write_tb = (
          raw_write / 1000.0 if is_gb_scale else raw_write * 512 / (10**12)
      )
      read_tb = raw_read / 1000.0 if is_gb_scale else raw_read * 512 / (10**12)

    days_active = poh / 24.0
    write_day_gb = (write_tb * 1000.0) / days_active if days_active > 0 else 0.0

    output_line = (
        f'{status_code} "Health_Storage ({model_clean})" - Status :'
        f" {status_word} | Type: {disk_type} ({cap_bracket}) | Status:"
        f" {smart_status} | Temp: {temp}C | Health: {health}% | Read:"
        f" {read_tb:.1f} TB | Written: {write_tb:.1f} TB | Write/Day:"
        f" {write_day_gb:.2f} GB"
    )
  else:
    # 3. Output Khusus HDD Mekanik (Memantau Bad Sector & Jam Operasional)
    reallocated = attributes.get(5)[1] if attributes.get(5) else 0
    pending = attributes.get(197)[1] if attributes.get(197) else 0

    remark = "Masih Sangat Sehat (0 Bad Sector)"
    if smart_status != "PASSED" or reallocated >= 50 or pending > 10:
      status_code = 2
      status_word = "CRITICAL"
      remark = "Kritis, bad sector tinggi / SMART failed!"
    elif reallocated > 0 or pending > 0:
      status_code = 1
      status_word = "WARNING"
      remark = (
          f"Perhatian, terdeteksi {reallocated} Reallocated / {pending} Pending"
          " Sector!"
      )

    rot_clean = (
        rotation_rate.replace(" ", "").replace("RPM", "rpm")
        if rotation_rate
        else "5400/7200 rpm"
    )

    output_line = (
        f'{status_code} "Health_Storage ({model_clean})" - Status :'
        f" {status_word} | Type: {disk_type} ({cap_bracket}) | Status:"
        f" {smart_status} | Temp: {temp}C | Rotation Rate: {rot_clean} |"
        f" Reallocated Sector: {reallocated} | Pending Sector: {pending} |"
        f" Power On Hours: {poh} Jam | Remark: {remark}"
    )

  return output_line


def get_block_devices():
  devices = []
  for path in glob.glob("/sys/block/sd*"):
    dev = "/dev/" + os.path.basename(path)
    devices.append(dev)
  for path in glob.glob("/sys/block/nvme*n*"):
    dev = "/dev/" + os.path.basename(path)
    devices.append(dev)
  return sorted(devices)


def main():
  if not shutil.which("smartctl"):
    print(
        '3 "Health_Storage" - UNKNOWN: smartctl is not installed on this'
        " system."
    )
    sys.exit(0)

  devices = get_block_devices()
  if not devices:
    print('0 "Health_Storage" - Status : OK | No storage devices detected.')
    sys.exit(0)

  for dev in devices:
    raw_out = run_smartctl(dev)
    if not raw_out:
      continue
    if "Device Model:" not in raw_out and "Model Number:" not in raw_out:
      continue
    try:
      line = parse_smartctl_output(raw_out, dev)
      print(line)
    except Exception as e:
      print(
          f'3 "Health_Storage ({os.path.basename(dev)})" - UNKNOWN: Error'
          f" parsing SMART data: {str(e)}"
      )


if __name__ == "__main__":
  main()

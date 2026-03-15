#!/bin/bash
# ============================================================
# Republic AI Testnet — GPU Multi-Slot Worker (Laptop/Local)
# Author: 0xDarkSeidBull | https://github.com/0xDarkSeidBull
# ============================================================
# CONFIGURATION — PUT YOUR DETAILS HERE
VPS="YOUR_VPS_IP"                       
SLOTS=${1:-5}
JOB_DIR=/var/lib/republic/jobs
# ============================================================

echo "GPU Multi-Slot Worker | Slots: $SLOTS"
echo "VPS: $VPS"

gpu_slot() {
  local SLOT=$1
  local SLOG="$JOB_DIR/gpu_slot_${SLOT}.log"

  echo "[GPU${SLOT}] Started" | tee -a $SLOG

  while true; do
    JOB_ID=$(ssh -o ConnectTimeout=5 root@$VPS \
      "[ -f /root/job_${SLOT}.txt ] && cat /root/job_${SLOT}.txt" 2>/dev/null)

    if [ -z "$JOB_ID" ]; then
      sleep 5
      continue
    fi

    echo "[GPU${SLOT}] Got job: $JOB_ID" | tee -a $SLOG
    mkdir -p "$JOB_DIR/$JOB_ID"

    docker run --rm --gpus all \
      -e JOB_ID=$JOB_ID \
      -v "$JOB_DIR/$JOB_ID:/output" \
      republic-llm-inference:latest >> $SLOG 2>&1

    RESULT="$JOB_DIR/$JOB_ID/result_${JOB_ID}.json"
    if [ ! -f "$RESULT" ]; then
      echo "[GPU${SLOT}] Result missing!" | tee -a $SLOG
      sleep 5
      continue
    fi

    echo "[GPU${SLOT}] Uploading result..." | tee -a $SLOG
    scp "$RESULT" root@$VPS:/root/result_${JOB_ID}.json >> $SLOG 2>&1
    echo "[GPU${SLOT}] ✅ Done: $JOB_ID" | tee -a $SLOG
    sleep 2
  done
}

for i in $(seq 1 $SLOTS); do
  sleep 2
  gpu_slot $i &
  echo "Launched GPU Slot $i (PID: $!)"
done

echo "All $SLOTS GPU slots running!"

while true; do
  sleep 30
  nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
done

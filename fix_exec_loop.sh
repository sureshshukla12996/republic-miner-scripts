cat > /root/fix_exec_loop.sh << 'EOF'
#!/bin/bash
WALLET="YOUR_WALLE"
CHAIN_ID="raitestnet_77701-1"
FEES="200000000000000arai"
VALOPER=$(republicd keys show $WALLET --bech val -a)
LOCKFILE="/tmp/republic_tx.lock"
LOG="/root/worker_logs/fix_exec.log"

mkdir -p /root/worker_logs
echo "$(date '+%H:%M:%S') Fix Exec Loop Started" | tee -a $LOG

while true; do
  JOBS=$(republicd query computevalidation list-job -o json --limit 120000 2>/dev/null | \
    jq -r '.jobs[] | select(.status == "PendingExecution" and .target_validator == "'$VALOPER'") | .id')

  TOTAL=$(echo "$JOBS" | grep -c '[0-9]' 2>/dev/null || echo 0)
  echo "$(date '+%H:%M:%S') PendingExecution: $TOTAL" | tee -a $LOG

  for JOB_ID in $JOBS; do
    RESULT="/root/result_${JOB_ID}.json"
    BACKUP="/root/results_backup/result_${JOB_ID}.json"

    if [ -f "$RESULT" ]; then
      FILE="$RESULT"
    elif [ -f "$BACKUP" ]; then
      cp "$BACKUP" "$RESULT"
      FILE="$RESULT"
    else
      continue
    fi

    SHA256=$(sha256sum "$FILE" | awk '{print $1}')

    (
      flock -x 200
      republicd tx computevalidation submit-job-result \
        "$JOB_ID" \
        "http://YOUR_SERVER_IP:8080/result_${JOB_ID}.json \
        "example-verification:latest" \
        "$SHA256" \
        --from "$WALLET" \
        --chain-id "$CHAIN_ID" \
        --fees "$FEES" \
        --generate-only > /tmp/fe_u.json 2>>$LOG

      [ ! -s /tmp/fe_u.json ] && exit 0

      python3 -c "
import json
tx=json.load(open('/tmp/fe_u.json'))
tx['body']['messages'][0]['validator']='$VALOPER'
json.dump(tx,open('/tmp/fe_f.json','w'))
" 2>>$LOG

      republicd tx sign /tmp/fe_f.json \
        --from "$WALLET" \
        --chain-id "$CHAIN_ID" \
        --output-document /tmp/fe_s.json 2>>$LOG

      TX=$(republicd tx broadcast /tmp/fe_s.json \
        --node tcp://localhost:26657 -o json 2>>$LOG | jq -r '.txhash')
      echo "$(date '+%H:%M:%S') [$JOB_ID] ✅ TX: $TX" | tee -a $LOG
      sleep 7
    ) 200>$LOCKFILE
  done

  echo "$(date '+%H:%M:%S') Cycle done — sleeping 5min" | tee -a $LOG
  sleep 300
done
EOF

chmod +x /root/fix_exec_loop.sh
screen -dmS fix-exec bash /root/fix_exec_loop.sh
sleep 3
screen -ls | grep fix

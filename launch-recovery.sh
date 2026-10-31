#!/system/bin/sh
MODDIR=${0%/*}
# Detach from ksud's blocking boot stage and script timeout/process group.
if [ -x /data/adb/ksu/bin/busybox ]; then
  ASH_STANDALONE=1 /data/adb/ksu/bin/busybox setsid \
    /data/adb/ksu/bin/busybox sh "$MODDIR/recover-radio.sh" --auto \
    </dev/null >> "$MODDIR/radio-recovery.log" 2>&1 &
elif command -v setsid >/dev/null 2>&1; then
  setsid sh "$MODDIR/recover-radio.sh" --auto \
    </dev/null >> "$MODDIR/radio-recovery.log" 2>&1 &
else
  echo 'ERROR: setsid unavailable; use Action to run recovery manually.' >> "$MODDIR/radio-recovery.log"
fi

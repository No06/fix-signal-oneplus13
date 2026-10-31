#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/radio-common.sh"
FSO_RUN_MODE=${1:---auto}
case "$FSO_RUN_MODE" in --auto|--manual|--check) ;; *) echo 'Usage: recover-radio.sh [--auto|--manual|--check]'; exit 1 ;; esac

if [ "$FSO_RUN_MODE" = --check ]; then
  fso_check_device && fso_prepare_paths && fso_find_modem || exit 1
  fso_log "Read-only check: slot=$FSO_SLOT, NV=$(readlink -f "$FSO_LINK")"
  fso_log "Storage view=$(fso_storage_view), modem=$(fso_modem_state), SELinux=$(getenforce)"
  exit 0
fi

exec >> "$MODDIR/radio-recovery.log" 2>&1
fso_log "Recovery worker started: $FSO_RUN_MODE"
FSO_WAIT=0
while [ "$(getprop sys.boot_completed)" != 1 ]; do
  [ "$FSO_WAIT" -lt 120 ] || { fso_error 'Boot did not finish; recovery deferred.'; exit 1; }
  [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || exit 0
  sleep 2
  FSO_WAIT=$((FSO_WAIT + 2))
done
FSO_WAIT=0
until fso_lock; do
  [ "$FSO_WAIT" -lt 10 ] || exit 0
  sleep 1
  FSO_WAIT=$((FSO_WAIT + 1))
done
fso_cleanup() {
  FSO_RESULT=$?
  fso_restore_modem
  fso_unlock
  fso_log "Worker finished: exit=$FSO_RESULT"
}
trap fso_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
fso_check_device && fso_prepare_paths && fso_apply_policy && fso_set_sar &&
  fso_map_nv && fso_recover_radio

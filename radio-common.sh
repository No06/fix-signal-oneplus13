#!/system/bin/sh
# NV redirection adapted from rapperskull's Apache-2.0 implementation.
# This file is sourced by the boot scripts and recovery worker.
PATH=/data/adb/ksu/bin:/data/adb/magisk:/system/bin:/system/xbin:/vendor/bin:$PATH
export PATH
FSO_BLOCK_ROOT=/dev/block
FSO_SYS_ROOT=/sys
FSO_PROC_ROOT=/proc
FSO_LOCK=/dev/fix-signal-oneplus13.lock
FSO_LOCKED=0
FSO_MODEM_TOUCHED=0

fso_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fso_error() { fso_log "ERROR: $*"; return 1; }

fso_lock() {
  if ! mkdir "$FSO_LOCK" 2>/dev/null; then
    # A missing PID can mean another process has just acquired the lock.
    if [ -r "$FSO_LOCK/pid" ]; then
      FSO_OWNER=$(cat "$FSO_LOCK/pid")
      case "$FSO_OWNER" in ''|*[!0-9]*) return 1 ;; esac
      if ! kill -0 "$FSO_OWNER" 2>/dev/null; then
        rm -f "$FSO_LOCK/pid"
        rmdir "$FSO_LOCK" 2>/dev/null || return 1
        mkdir "$FSO_LOCK" 2>/dev/null || return 1
      else
        fso_log "Another module task is running; skipping."
        return 1
      fi
    else
      return 1
    fi
  fi
  echo "$$" > "$FSO_LOCK/pid"
  FSO_LOCKED=1
}

fso_unlock() {
  if [ "$FSO_LOCKED" = 1 ]; then
    rm -f "$FSO_LOCK/pid"
    rmdir "$FSO_LOCK" 2>/dev/null
    FSO_LOCKED=0
  fi
}

fso_check_device() {
  [ "$(id -u)" = 0 ] || { fso_error 'Root is required.'; return 1; }
  [ "$(getprop ro.boot.prjname)" = 23821 ] || {
    fso_error 'Only OnePlus 13 CN (project 23821) is supported.'; return 1;
  }
  [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || {
    fso_error 'Module is disabled or pending removal.'; return 1;
  }
}

fso_prepare_paths() {
  FSO_SLOT=$(getprop ro.boot.slot_suffix)
  case "$FSO_SLOT" in _a|_b) ;; *) fso_error 'Invalid boot slot.'; return 1 ;; esac
  FSO_LINK="$FSO_BLOCK_ROOT/bootdevice/by-name/oplusstanvbk$FSO_SLOT"
  [ -L "$FSO_LINK" ] || { fso_error 'NV partition link is missing.'; return 1; }
  FSO_ORIGINAL=$(readlink -f "$FSO_LINK")
  FSO_ORIGINAL=${FSO_ORIGINAL%_mod}
  case "$FSO_ORIGINAL" in "$FSO_BLOCK_ROOT"/sd*) ;; *)
    fso_error 'Unexpected NV block device.'; return 1 ;;
  esac
  case "$FSO_ORIGINAL" in *_mod*) fso_error 'Nested legacy mapping; reboot first.'; return 1 ;; esac
  [ -b "$FSO_ORIGINAL" ] || { fso_error 'Original NV block device is missing.'; return 1; }
  FSO_DEVICE="${FSO_ORIGINAL}_mod"
  FSO_IMAGE="$MODDIR/nvbk/oplusstanvbk.img"
  FSO_BACKING="$MODDIR/nvbk/mounted"
  [ -s "$FSO_IMAGE" ] || { fso_error 'Module NV image is missing or empty.'; return 1; }
  FSO_BOOT=$(cat "$FSO_PROC_ROOT/sys/kernel/random/boot_id")
  [ -n "$FSO_BOOT" ] || { fso_error 'Cannot identify this boot.'; return 1; }
}

fso_loop_backing() {
  FSO_MAJOR=$(stat -Lc '%t' "$1") || return 1
  FSO_MINOR=$(stat -Lc '%T' "$1") || return 1
  [ "$FSO_MAJOR" = 7 ] || return 1
  cat "$FSO_SYS_ROOT/dev/block/7:$((0x$FSO_MINOR))/loop/backing_file"
}

fso_loop_create() { /system/bin/losetup -sf "$FSO_BACKING"; }
fso_loop_detach() { /system/bin/losetup -d "$1"; }

fso_map_nv() {
  if [ -e "$FSO_DEVICE" ]; then
    FSO_EXISTING_BACKING=$(fso_loop_backing "$FSO_DEVICE") || {
      fso_error 'Existing replacement is not a loop device.'; return 1;
    }
    [ "$FSO_EXISTING_BACKING" = "$(readlink -f "$FSO_BACKING")" ] &&
      cmp -s "$FSO_IMAGE" "$FSO_BACKING" || {
      fso_error 'Existing loop belongs to another image/update; reboot before retrying.'; return 1;
    }
    fso_log "Reusing $FSO_DEVICE; leaving its backing file intact."
  else
    [ "$(readlink -f "$FSO_LINK")" = "$FSO_ORIGINAL" ] || {
      fso_error 'NV link is already redirected to an unknown device.'; return 1;
    }
    cp "$FSO_IMAGE" "$FSO_BACKING.new" &&
      mv -f "$FSO_BACKING.new" "$FSO_BACKING" || return 1
    FSO_LOOP=$(fso_loop_create) || return 1
    [ -n "$FSO_LOOP" ] || { fso_error 'Cannot create loop device.'; return 1; }
    # Preserve the UFS-style name required by gpt-utils; never write physical NV.
    if ! mv "$FSO_LOOP" "$FSO_DEVICE"; then
      fso_loop_detach "$FSO_LOOP"
      fso_error 'Cannot name the replacement loop device.'; return 1
    fi
  fi
  chcon u:object_r:vendor_custom_ab_block_device:s0 "$FSO_DEVICE" || return 1
  if [ "$(readlink -f "$FSO_LINK")" != "$FSO_DEVICE" ]; then
    ln -sf "$FSO_DEVICE" "$FSO_LINK" || return 1
  fi
  chcon -h u:object_r:vendor_custom_ab_block_device:s0 "$FSO_LINK" || return 1
  fso_log "NV mapping: $FSO_LINK -> $FSO_DEVICE"
}

fso_apply_policy() {
  if [ -x /data/adb/ksud ]; then
    /data/adb/ksud sepolicy apply "$MODDIR/sepolicy.rule" || return 1
  elif command -v magiskpolicy >/dev/null 2>&1; then
    magiskpolicy --live --apply "$MODDIR/sepolicy.rule" || return 1
  else
    fso_error 'No supported live policy tool; aborting recovery.'; return 1
  fi
  fso_log "Network policy applied; SELinux remains $(getenforce)."
}

fso_set_sar() {
  if command -v resetprop >/dev/null 2>&1; then
    resetprop -n ro.vendor.oplus.radio.sar_regionmark ''
  else
    fso_error 'resetprop is unavailable.'; return 1
  fi
}

fso_find_modem() {
  FSO_MODEM=
  for FSO_CANDIDATE in "$FSO_SYS_ROOT"/class/remoteproc/remoteproc*; do
    if [ "$(cat "$FSO_CANDIDATE/name" 2>/dev/null)" = 4080000.remoteproc-mss ]; then
      FSO_MODEM=$FSO_CANDIDATE
      break
    fi
  done
  [ -n "$FSO_MODEM" ] && [ -w "$FSO_MODEM/state" ] || {
    fso_error 'Supported modem control interface is unavailable.'; return 1;
  }
}

fso_storage_pid() { pidof rmt_storage; }
fso_storage_view() {
  FSO_PID=$(fso_storage_pid)
  case "$FSO_PID" in ''|*' '*) echo unknown; return ;; esac
  FSO_SAW_NEW=0
  for FSO_FD in "$FSO_PROC_ROOT/$FSO_PID"/fd/*; do
    FSO_FD_TARGET=$(readlink "$FSO_FD" 2>/dev/null)
    if [ "$FSO_FD_TARGET" = "$FSO_ORIGINAL" ]; then echo original; return; fi
    [ "$FSO_FD_TARGET" != "$FSO_DEVICE" ] || FSO_SAW_NEW=1
  done
  if [ "$FSO_SAW_NEW" = 1 ]; then echo mapped; else echo unknown; fi
}

fso_radio_on() {
  # Consume the full dump so Android does not log a misleading broken-pipe error.
  dumpsys telephony.registry | awk '
    /^ *mRadioPowerState=1$/ { on=1 }
    END { exit !on }'
}

fso_call_idle() {
  dumpsys telephony.registry | awk '
    /^ *mCallState=/ { seen=1; if ($0 !~ /=0$/) busy=1 }
    END { exit !(seen && !busy) }'
}

fso_wait_storage() {
  FSO_WAIT=0
  while [ "$FSO_WAIT" -lt 10 ]; do
    if [ "$(getprop init.svc.vendor.rmt_storage)" = running ] &&
       [ "$(fso_storage_view)" = mapped ]; then return 0; fi
    sleep 1
    FSO_WAIT=$((FSO_WAIT + 1))
  done
  fso_error 'Storage service did not open the replacement; modem left untouched.'
}

fso_modem_state() { cat "$FSO_MODEM/state"; }
fso_modem_write() {
  timeout 25 sh -c 'printf "%s\n" "$1" > "$2/state"' sh "$1" "$FSO_MODEM"
}

fso_restore_modem() {
  if [ "$FSO_MODEM_TOUCHED" = 1 ] && [ "$(fso_modem_state)" = offline ]; then
    fso_log 'Recovery: starting modem after an interrupted/failed operation.'
    fso_modem_write start || fso_log 'ERROR: modem restart failed; inspect radio-recovery.log.'
  fi
}

fso_restart_modem() {
  [ "$(fso_modem_state)" = running ] || {
    fso_error 'Modem was not running; refusing an automatic state change.'; return 1;
  }
  FSO_MODEM_TOUCHED=1
  fso_modem_write stop || { fso_error 'Modem stop request failed.'; return 1; }
  FSO_STOPPED_STATE=$(fso_modem_state)
  fso_log "Modem state after stop: $FSO_STOPPED_STATE"
  if [ "$FSO_STOPPED_STATE" != offline ]; then
    fso_modem_write start || { fso_error 'Cannot restore the remoteproc reference.'; return 1; }
    [ "$(fso_modem_state)" = running ] || return 1
    FSO_MODEM_TOUCHED=0
    fso_error 'No offline transition; restored the remoteproc reference.'; return 1
  fi
  sleep 2
  fso_modem_write start || { fso_error 'Modem start request failed.'; return 1; }
  [ "$(fso_modem_state)" = running ] || { fso_error 'Modem did not return to running.'; return 1; }
  FSO_MODEM_TOUCHED=0
  fso_log 'Verified modem transition: running -> offline -> running.'
}

fso_recover_radio() {
  [ "$(getprop ro.build.version.release)" = 16 ] || {
    fso_log 'Automatic modem recovery is limited to Android/OxygenOS 16.'; return 0;
  }
  fso_find_modem || return 1
  FSO_VIEW=$(fso_storage_view)
  if [ "$FSO_VIEW" = mapped ] && fso_radio_on; then
    fso_log 'Storage already uses the mapped image and radio is on; no restart needed.'
    return 0
  fi
  [ "$(settings get global airplane_mode_on)" != 1 ] || {
    fso_log 'Airplane mode enabled; recovery deferred.'; return 0;
  }
  case "$(getprop gsm.sim.state)" in *LOADED*|*READY*) ;; *)
    fso_log 'No ready SIM; recovery deferred.'; return 0 ;;
  esac
  if [ "$FSO_RUN_MODE" != --manual ] &&
     [ "$(cat "$MODDIR/.radio-attempt.boot" 2>/dev/null)" = "$FSO_BOOT" ]; then
    fso_log 'Recovery was already attempted this boot; use Action for a manual retry.'
    return 0
  fi
  FSO_WAIT=0
  until fso_call_idle; do
    [ "$FSO_WAIT" -lt 60 ] || { fso_error 'Call active/state unavailable; recovery deferred.'; return 1; }
    sleep 5
    FSO_WAIT=$((FSO_WAIT + 5))
  done
  fso_check_device || return 1
  echo "$FSO_BOOT" > "$MODDIR/.radio-attempt.boot" || return 1
  fso_log "Restarting vendor.rmt_storage (previous view: $FSO_VIEW)."
  setprop ctl.restart vendor.rmt_storage || return 1
  fso_wait_storage || return 1
  fso_log 'Storage has opened the mapped loop device.'
  fso_call_idle || { fso_error 'Call started; modem restart deferred.'; return 1; }
  [ "$(settings get global airplane_mode_on)" != 1 ] || return 0
  fso_check_device || return 1
  fso_restart_modem || return 1
  echo "$FSO_BOOT" > "$MODDIR/.radio-recovered.boot"
}

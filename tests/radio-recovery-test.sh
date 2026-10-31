#!/bin/sh
# Runs without root. All Android commands, block devices and modem writes are mocked.
set -eu
TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SOURCE_ROOT=$(dirname "$TEST_ROOT")
COUNT=0

assert_equal() {
  [ "$1" = "$2" ] || { echo "Expected '$1', got '$2'" >&2; exit 1; }
}
assert_empty() { [ ! -s "$1" ] || { cat "$1" >&2; exit 1; }; }
expect_failure() { if "$@"; then echo "Unexpected success: $*" >&2; exit 1; fi; }

setup_case() {
  . "$SOURCE_ROOT/radio-common.sh"
  CASE_DIR=$(mktemp -d "$TEST_ROOT/.tmp.XXXXXX")
  CASE_DIR=$(CDPATH= cd -- "$CASE_DIR" && pwd -P)
  cleanup_case() {
    case "$CASE_DIR" in "$TEST_ROOT"/.tmp.*) rm -rf -- "$CASE_DIR" ;; *) exit 1 ;; esac
  }
  trap cleanup_case EXIT
  MODDIR=$CASE_DIR
  mkdir "$MODDIR/nvbk"
  FSO_IMAGE="$MODDIR/nvbk/oplusstanvbk.img"
  FSO_BACKING="$MODDIR/nvbk/mounted"
  FSO_ORIGINAL="$CASE_DIR/sdf9"
  FSO_DEVICE="${FSO_ORIGINAL}_mod"
  FSO_LINK="$CASE_DIR/partition-link"
  FSO_BOOT=test-boot
  FSO_RUN_MODE=--auto
  FSO_LOCK="$CASE_DIR/lock"
  printf 'NV image\n' > "$FSO_IMAGE"
  : > "$FSO_ORIGINAL"
  echo "$FSO_ORIGINAL" > "$FSO_LINK"
  echo original > "$CASE_DIR/storage"
  echo mapped > "$CASE_DIR/storage.next"
  echo running > "$CASE_DIR/modem"
  : > "$CASE_DIR/operations"
  MOCK_BACKING=$FSO_BACKING
  MOCK_STOP=offline
  MOCK_START_FAIL=no
  MOCK_AIRPLANE=0
  MOCK_CALL=0
  MOCK_STORAGE_FAIL=no
  MOCK_RADIO_ON=no
  MOCK_VERSION=16
  MOCK_PROJECT=23821
  MOCK_SUPPORTED=yes

  id() { echo 0; }
  sleep() { :; }
  chcon() { :; }
  getprop() {
    case "$1" in
      ro.build.version.release) echo "$MOCK_VERSION" ;;
      ro.boot.prjname) echo "$MOCK_PROJECT" ;;
      gsm.sim.state) echo LOADED,ABSENT ;;
      init.svc.vendor.rmt_storage) echo running ;;
    esac
  }
  settings() { echo "$MOCK_AIRPLANE"; }
  dumpsys() { echo "    mCallState=$MOCK_CALL"; }
  readlink() {
    for arg in "$@"; do last_arg=$arg; done
    if [ "$last_arg" = "$FSO_LINK" ]; then cat "$FSO_LINK"; else command readlink "$@"; fi
  }
  ln() { echo "$2" > "$3"; }
  fso_loop_create() {
    echo loop-create >> "$CASE_DIR/operations"
    : > "$CASE_DIR/loop0"
    echo "$CASE_DIR/loop0"
  }
  fso_loop_backing() { echo "$MOCK_BACKING"; }
  fso_loop_detach() { echo loop-detach >> "$CASE_DIR/operations"; }
  fso_find_modem() { [ "$MOCK_SUPPORTED" = yes ]; }
  fso_storage_view() { cat "$CASE_DIR/storage"; }
  fso_radio_on() { [ "$MOCK_RADIO_ON" = yes ]; }
  setprop() {
    echo storage-restart >> "$CASE_DIR/operations"
    if [ "$MOCK_STORAGE_FAIL" = no ]; then cp "$CASE_DIR/storage.next" "$CASE_DIR/storage"; fi
  }
  fso_modem_state() { cat "$CASE_DIR/modem"; }
  fso_modem_write() {
    echo "$1" >> "$CASE_DIR/operations"
    case "$1" in
      stop)
        if [ "$MOCK_STOP" = fail-offline ]; then echo offline > "$CASE_DIR/modem"; return 1; fi
        echo "$MOCK_STOP" > "$CASE_DIR/modem"
        ;;
      start)
        if [ "$MOCK_START_FAIL" = yes ]; then MOCK_START_FAIL=no; return 1; fi
        echo running > "$CASE_DIR/modem"
        ;;
    esac
  }
}

run_case() {
  COUNT=$((COUNT + 1))
  (setup_case; "$@") || { echo "FAIL: $*"; exit 1; }
  echo "PASS: $*"
}

map_twice() {
  fso_map_nv
  fso_map_nv
  assert_equal "$FSO_DEVICE" "$(cat "$FSO_LINK")"
  assert_equal loop-create "$(cat "$CASE_DIR/operations")"
  cmp -s "$FSO_IMAGE" "$FSO_BACKING"
  [ ! -e "${FSO_DEVICE}_mod" ]
}
foreign_loop() {
  : > "$FSO_DEVICE"
  MOCK_BACKING=/another/module/image
  expect_failure fso_map_nv
  assert_equal "$FSO_ORIGINAL" "$(cat "$FSO_LINK")"
  assert_empty "$CASE_DIR/operations"
}
changed_image() {
  fso_map_nv
  cp "$FSO_BACKING" "$CASE_DIR/before"
  echo changed > "$FSO_IMAGE"
  expect_failure fso_map_nv
  cmp -s "$CASE_DIR/before" "$FSO_BACKING"
  assert_equal loop-create "$(cat "$CASE_DIR/operations")"
}
full_recovery() {
  fso_recover_radio
  assert_equal 'storage-restart
stop
start' "$(cat "$CASE_DIR/operations")"
  assert_equal running "$(fso_modem_state)"
  assert_equal "$FSO_BOOT" "$(cat "$MODDIR/.radio-recovered.boot")"
  fso_recover_radio
  assert_equal 3 "$(wc -l < "$CASE_DIR/operations" | tr -d ' ')"
}
healthy_skip() {
  echo mapped > "$CASE_DIR/storage"
  MOCK_RADIO_ON=yes
  fso_recover_radio
  assert_empty "$CASE_DIR/operations"
}
airplane_skip() { MOCK_AIRPLANE=1; fso_recover_radio; assert_empty "$CASE_DIR/operations"; }
busy_call() { MOCK_CALL=2; expect_failure fso_recover_radio; assert_empty "$CASE_DIR/operations"; }
missing_call_state() {
  dumpsys() { :; }
  expect_failure fso_recover_radio
  assert_empty "$CASE_DIR/operations"
}
storage_failure() {
  MOCK_STORAGE_FAIL=yes
  expect_failure fso_recover_radio
  assert_equal storage-restart "$(cat "$CASE_DIR/operations")"
  assert_equal running "$(fso_modem_state)"
}
failed_stop_restore() {
  MOCK_STOP=fail-offline
  expect_failure fso_restart_modem
  fso_restore_modem
  assert_equal running "$(fso_modem_state)"
  assert_equal 'stop
start' "$(cat "$CASE_DIR/operations")"
}
failed_start_restore() {
  MOCK_START_FAIL=yes
  expect_failure fso_restart_modem
  fso_restore_modem
  assert_equal running "$(fso_modem_state)"
  assert_equal 'stop
start
start' "$(cat "$CASE_DIR/operations")"
}
extra_remoteproc_reference() {
  MOCK_STOP=running
  expect_failure fso_restart_modem
  assert_equal 'stop
start' "$(cat "$CASE_DIR/operations")"
  assert_equal running "$(fso_modem_state)"
}
offline_modem_skip() {
  echo offline > "$CASE_DIR/modem"
  expect_failure fso_restart_modem
  assert_empty "$CASE_DIR/operations"
}
manual_retry() {
  echo "$FSO_BOOT" > "$MODDIR/.radio-attempt.boot"
  fso_recover_radio
  assert_empty "$CASE_DIR/operations"
  FSO_RUN_MODE=--manual
  fso_recover_radio
  assert_equal running "$(fso_modem_state)"
  assert_equal 3 "$(wc -l < "$CASE_DIR/operations" | tr -d ' ')"
}
android15_skip() { MOCK_VERSION=15; fso_recover_radio; assert_empty "$CASE_DIR/operations"; }
unsupported_modem() { MOCK_SUPPORTED=no; expect_failure fso_recover_radio; assert_empty "$CASE_DIR/operations"; }
wrong_device() { MOCK_PROJECT=other; expect_failure fso_check_device; assert_empty "$CASE_DIR/operations"; }
disabled_module() { : > "$MODDIR/disable"; expect_failure fso_recover_radio; assert_empty "$CASE_DIR/operations"; }
concurrent_lock() {
  fso_lock
  expect_failure fso_lock
  fso_unlock
  [ ! -d "$FSO_LOCK" ]
}
locked_android15_action() {
  mkdir "$CASE_DIR/bin"
  printf '#!/bin/sh\ncase "$1" in ro.build.version.release) echo 15;; ro.boot.flash.locked) echo 1;; esac\n' > "$CASE_DIR/bin/getprop"
  chmod +x "$CASE_DIR/bin/getprop"
  if PATH="$CASE_DIR/bin:$PATH" command sh "$SOURCE_ROOT/action.sh" > "$CASE_DIR/action-result" 2>&1; then
    echo 'Locked Android 15 action unexpectedly succeeded'; exit 1
  fi
  grep -q 'requires an unlocked bootloader' "$CASE_DIR/action-result"
}

for scenario in map_twice foreign_loop changed_image full_recovery healthy_skip airplane_skip \
  busy_call missing_call_state storage_failure failed_stop_restore failed_start_restore \
  extra_remoteproc_reference offline_modem_skip manual_retry android15_skip \
  unsupported_modem wrong_device disabled_module concurrent_lock locked_android15_action; do
  run_case "$scenario"
done
echo "$COUNT recovery scenarios passed."

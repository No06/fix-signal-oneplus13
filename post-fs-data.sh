#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/radio-common.sh"
exec >> "$MODDIR/post-fs-data.log" 2>&1
fso_lock || exit 0
trap fso_unlock EXIT
fso_check_device && fso_prepare_paths && fso_map_nv

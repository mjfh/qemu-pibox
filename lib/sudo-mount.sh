#! /bin/sh
#
# Include file to be sourced by qemu-pibox scripts
#
# SPDX-License-Identifier: Unlicense
#
# Blame: Jordan Hrycaj <jordan@teddy-net.com>

#     =========================================================
#     Commands that escalate root privilege -- THERE BE DRAGONS
#     =========================================================

# -----------------------------------------------------------------------------
# Managing raw disk image mount
# -----------------------------------------------------------------------------

doadm_qimg_loop_import () {
    local img=`instance_disk_realpath "0"`

    ([ -z "$NOISY" ] || set -x;	$RUNPFX $SUDO losetup -P -f "$img")
}

doadm_qimg_loop_release () {
    local dev=`qimg_loop_device`

    # might automatically remove the loop device when the last dependent
    # parition is unmounted
    [ -z "$dev" ] ||
	([ -z "$NOISY" ] || set -x; $RUNPFX $SUDO losetup -d "$dev")
}

# ------------

doadm_qimg_boot_mount () { # syntax: <device>
    local dev=`qboot_device`
    local dir=`qboot_mount_realpath`

    ([ -z "$NOISY" ] || set -x; $RUNPFX $SUDO mount -oro "$dev" "$dir")
}

doadm_qimg_boot_unmount () {
    local dir=`qboot_mount_realpath`

    if qboot_mount_is_active_fuser_ok
    then
	runcmd fusermount -u "$dir"
    else
	([ -z "$NOISY" ] || set -x; $RUNPFX $SUDO umount "$dir")
    fi
}

# ------------

doadm_qimg_root_mount () {
    local dev=`qroot_device`
    local dir=`qroot_mount_realpath`

    ([ -z "$NOISY" ] || set -x; $RUNPFX $SUDO mount -oro "$dev" "$dir")
}

doadm_qimg_root_remount_rw () {
    local dir=`qroot_mount_realpath`

    ([ -z "$NOISY" ] || set -x; $RUNPFX $SUDO mount -orw,remount "$dir")
}

doadm_qimg_root_unmount () {
    local dir=`qroot_mount_realpath`

    if qroot_mount_is_active_fuser_ok
    then
	runcmd fusermount -u "$dir"
    else
	([ -z "$NOISY" ] || set -x; $RUNPFX $SUDO umount "$dir")
    fi
}

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

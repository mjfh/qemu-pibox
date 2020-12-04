#! /bin/sh
#
# Include file to be sourced by qemu-pibox scripts (userland version)
#
# SPDX-License-Identifier: Unlicense
#
# Blame: Jordan Hrycaj <jordan@teddy-net.com>

# -----------------------------------------------------------------------------
# Managing raw disk image mount
# -----------------------------------------------------------------------------

doadm_qimg_loop_import () {
    true
}

doadm_qimg_loop_release () {
    true
}

# ------------

doadm_qimg_boot_mount () { # syntax: <device>
    local dir=`qboot_mount_realpath`
    local img=`instance_disk "$0"`

    runcmd guestmount -a "$img" -m /dev/sda1 --ro "$dir"
}

doadm_qimg_boot_unmount () {
    local dir=`qboot_mount_realpath`

    qboot_mount_is_active_fuser_ok ||
	fatal "Not mounted in use space: $dir"

    runcmd fusermount -u "$dir"
}

# ------------

doadm_qimg_root_mount () {
    local dir=`qroot_mount_realpath`
    local img=`instance_disk "$0"`

    runcmd guestmount -a "$img" -m /dev/sda2 "$dir"
}

doadm_qimg_root_remount_rw () {
    local dir=`qroot_mount_realpath`
    local img=`instance_disk "$0"`

    runcmd umount "$dir"
    runcmd guestmount -a "$img" -m /dev/sda2 "$dir"
}

doadm_qimg_root_unmount () {
    local dir=`qroot_mount_realpath`
    local img=`instance_disk "$0"`

    qroot_mount_is_active_fuser_ok ||
	fatal "Not mounted in use space: $dir"

    runcmd fusermount -u "$dir"
}

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

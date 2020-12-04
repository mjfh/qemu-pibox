#! /bin/sh
#
# Include file to be sourced by qemu-pibox scripts
#
# SPDX-License-Identifier: Unlicense
#
# Blame: Jordan Hrycaj <jordan@teddy-net.com>

# -----------------------------------------------------------------------------
# Configuration variables used but initialised somewhere else
# -----------------------------------------------------------------------------

# Command line arguments usage message printed by helper functions.
## ARGSUSAGE

# -----------------------------------------------------------------------------
# Preset variables that can be overloaded
# -----------------------------------------------------------------------------

# Various programs that can be ignored. Setting these variables also
# suppresses warnings aboutthat a tool is missing.
#  NOFATCAT        -- fatcat,        for extracting files from DOS partition
#  NOREMOTE_VIEWER -- remote-viewer, VNC gui
#  NOGUESTMOUNT    -- guestmount,    user mode mounting tool
unset NOGUESTMOUNT NOFATCAT NOREMOTE_VIEWER

# List of known systems in /etc/hosts format, expecting entries
#
#   <lan-ip> <lan-node> ..
#   <wan-ip> <wan-node> <alias-name> ..
#
# where for some given instance number <QID>
#
#    <wan-ip>:	    <ip-prefix>.15
#    <wan-node:     n<QID>.wan
#
#    <lan-ip>:	    <any-ip-address>
#    <lan-node>:    n<QID>.lan
#    <alias-name>:  <text,not-all-digits>
#
# There must be at least an entry for the 0 instance which serves as
# default.
#
ETC_HOSTS=$prefix/raspios/base/etc/hosts

# Network interface table based on MAC addresses, applicable to hardware
# Raspberry PI system.
ETC_IFTAB=$prefix/raspios/base/etc/iftab

# Wifi configuration table /etc/wifitab, expecting entries
#
#   <alias-name> <channel#> <ssid>
#
# where <alias-name> corresponds to a hostname entry in /etc/hosts.
#
ETC_WIFITAB=$prefix/raspios/wifi/etc/wifitab

# Directory with clone images of the instance <0> raw disk file. Clones will
# be generated as qcow2 files an can need some. Unless it exists, the
# directory is created with user credentials. There will also be copies of
# boot kernels for each clone (including instance <0>).)
PIBOX_CACHE=$PREFIX/cache

# Root command escalator
SUDO=sudo

# The SUDO_UNQOTED_ARGS flag needs to be set "yes" if SUDO is set to
# something else than "sudo" which behaves exactly like "sudo" in the sense
# that command line arguments are interpreted as-is. An example for SUDO
# which needs SUDO_UNQOTED_ARGS=yes would be "sudo -uroot".
#
# This would not work with something like "ssh -X root@localhost" in place
# of "sudo" where command arguments need to be extra quoted. The current
# setting works with both, "sudo" and "ssh -X root@localhost".
SUDO_UNQOTED_ARGS=no

# List of passwords to try for login hijacking the "pi" user. This feature
# needs the "sshpass" command installed. Note that RaspiOS is provided with
# the password "raspberry" for the user "pi".
PI_USER_PASSWORDS="raspberry raspberrypi"

# When expanding a disk image to a 4, 8, or 16GiB size do not extend the root
# partition to the full size. Rather reserve some space at the end so that
# copying to an SD card which is slightly smaller will not chop off the root
# partition. Nevertheless, after copying an image it should be verified with
# any of s/fdisk or g/parted.
#
# The reserved space at the end is given in percent. So a value of 6 will
# reserve short of ona GiB for a 16GiB partition and about a quarter GiB
# for a 4GiB partition.
DISK_MARGIN_RESERVE=6

# Folder containing a guest application software file system to copy/install
# onto the virtual QEMU guest system.
#
# There is a file "$GUEST_INSTALL.apt-packages" which contains a list of APT
# packages to install with the --update-primary option of the "pijack" tool.
# In addition there are optional files
#
#  "$GUEST_INSTALL.apt-packages" -- list of apt packages
#  "$GUEST_INSTALL.permissions"  -- selected permission settings
#  "$GUEST_INSTALL.post-install" -- script to run on guest after installation
#
# related to this software folder.
GUEST_INSTALL=

# -----------------------------------------------------------------------------
# Allow local configuration for variable update
# -----------------------------------------------------------------------------

[ -s $prefix/config.sh ] && . $prefix/config.sh

# -----------------------------------------------------------------------------
# Reset/initalise commonly used global variables
# -----------------------------------------------------------------------------

unset QID HELP DEBUG NOISY RUNPFX QIMAGE OPTIONS

# -----------------------------------------------------------------------------
# Immutable configuration settings, pseudo contstants
# -----------------------------------------------------------------------------

# Wait some seconds for QEMU to start
readonly wait_qemu=1

# Various images files needed to boot qemu. These images are found inside the
# boot partition of the disk base image.
readonly boot_kernel_img="kernel8.img"
readonly boot_dtb_img="bcm2710-rpi-3-b-plus.dtb"

# Acceptable image sizes in GiB
readonly raw_image_sizes_GiB="4 8 16"

# File template to generate clone images of the primary disk image file. These
# clones will be generated as compressed qcow2 files. Use the printf format
# %d to be substituted by the node ID (must occur twice!)
readonly clone_tmpl_prefix="$PIBOX_CACHE/clones/raspi-clone-%d/clone-%d"

# This QEMU variant emulates the Raspbery PI version 3
readonly qemu_system_cmd="qemu-system-aarch64 -M raspi3 -m 1G -smp 4"

# Mount points for root and boot partitions (is used, at all.)
readonly mnt_boot_d="$PIBOX_CACHE/mnt/boot"
readonly mnt_root_d="$PIBOX_CACHE/mnt/root"

# Remember to have shown the disclaimer already. This directory keeps some
# flag files for the interactive scripts.
readonly disclaimer_d="$PIBOX_CACHE/conf"

# Folder containing the case file system with the boot configuration logic to
# copy/install onto the virtual QEMU guest system. In addition there are files
#
#  "$raspios_base_d.apt-packages"  -- list of APT packages
#  "$raspios_base_d.permissions"   -- selected permission settings
#  "$raspios_base.d.post-install"  -- script to run on guest after installation
#
# related to this software folder. The APT packages will be installed with
# the --update-primary option of the "pijack" tool.
readonly raspios_base_d="$prefix/raspios/base"

# Folder containing an application software file system to copy/install onto
# the virtual QEMU guest system. This will be merged with the $GUEST_INSTALL
# software file system. In addition there are files
#
#  "$raspios_local_d.apt-packages" -- list of APT packages
#  "$raspios_local_d.permissions"  -- selected permission settings
#  "$raspios_base.d.post-install"  -- script to run on guest after installation
#
# related to this software folder. The APT packages will be installed with
# the --update-primary option of the "pijack" tool.
readonly raspios_local_d="$prefix/raspios/local"

# Required executables, equivalent of ${qemu_system_cmd[0]} implicitely added
readonly required_commands="sudo realpath ssh sshpass socat truncate md5sum
                            dd qemu-img"

# Required executables from /sbin or /usr/sbin
readonly required_sbin_commands="losetup sfdisk chat"

# Optional executables, missing entries imply warning
readonly important_commands="remote-viewer guestmount fatcat"

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

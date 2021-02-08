#! /bin/sh
#
# Manage partition mounting for Raspberry PI emulator
#
# SPDX-License-Identifier: Unlicense
#
# Blame: Jordan Hrycaj <jordan@teddy-net.com>

readonly self=`basename $0 .sh`
readonly prefix=`dirname $0`

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

set -e

# Command line usage message
ARGSUSAGE="[options] [--] [instance]"
which fatcat >/dev/null ||
    ARGSUSAGE="[options] [--]"

. $prefix/lib/variables.sh
. $prefix/lib/functions.sh

# Reset global variables
unset BUMOUNT RUMOUNT BMOUNT RMOUNT ULANDMNT IKERNEL SUDOMNT
unset EXP2PWR SHOWSTAT CHKIMG

readonly short_stdopts="i:Ddvh"
readonly long_stdopts="disk-image:,dry-run,debug,verbose,help"

readonly        cannot_expand="Cannot expand/pad image"
readonly    some_inst_running="while some QEMU instance is running"
readonly   part_while_running="partition $some_inst_running"
readonly     part_not_mounted="partition was not mounted"
readonly     part_was_mounted="partition was mounted already"
readonly part_mounted_already="$part_was_mounted already"

# check for user mode mount, may be disabled by command option
which guestmount >/dev/null || NOGUESTMOUNT=set
which fatcat     >/dev/null || NOFATCAT=set

set +e

# -----------------------------------------------------------------------------
# Command line helper functions
# -----------------------------------------------------------------------------

pimage_debug_vardump () {
    [ -z "$DEBUG" ] ||
	mesg `dump_vars \
		QID HELP DEBUG NOISY RUNPFX QIMAGE OPTIONS \
		BUMOUNT RUMOUNT BMOUNT RMOUNT ULANDMNT IKERNEL \
		SUDOMNT NOGUESTMOUNT EXP2PWR SHOWSTAT CHKIMG NOFATCAT`
}

pimage_info () {
    local run_self="$self"
    case "$prefix" in /*/bin);;*)run_self="sh $self.sh";esac

    cat <<EOF

  The tool prepares a RaspiOS disk image for use with QEMU. It will extract a
  copy of RaspiOS boot files needed by QEMU to start on the guest disk image.
  It registers the location of the argument disk image file path to be used
  by subsequent invocations. The tool works with "raw" images only, e.g.
  extracted with "dd if=/dev/sda of=disk.img" (as opposed to the "qcow2"
  virtual machine format.)

  Adminstator Privilege
    Unless the "guestmount" command is installed and available, this "$self"
    tool will execute "sudo" in order to escalate administrator privileges for
    running the commands "losetup" and "mount" when extracting the boot kernel
    or when un/mounting RaspiOS disk image partitions.

  Example usage
    Visit "https://downloads.raspberrypi.org/raspios_lite_armhf/images/" and
    download a RaspiOS disk image. Unzip a copy of the downloaded image (always
    work on a copy!) and name it "raspios.img". Run

       sh $self --provide-qboot --disk-image=raspios.img --expand-image

    This will extract boot partition data for QEMU to boot. It will also
    expanded the RaspiOS image file to the least of the sizes 4, 8, or 16GiB
    and update the MBR partition table.

  Other considerations
    This tool provides a facility to mount the boot and root partitions of the
    disk image for inspection. The boot image is always mounted read-only.

    Accessing the root partition as a file system can help fixing access
    problems (e.g. lost password or missing SSH access.)
EOF
}


pimage_help () {
    echo "Disk image maintenance tool"

    [ -z "$NOISY" ] ||
	pimage_info

    disclaimer_once

    local cmdl_arg="use particular instance (default <0>)"

    # use readonly for checking option letter uniqness
    readonly _q="extract kernel and update cache for QEMU boot"
    readonly _x="expand disk for use with QEMU"
    readonly _y="read-only mount kernel boot partition"
    readonly _Y="umount kernel boot partition"
    readonly _z="read-write mount root partition"
    readonly _Z="umount root partition"
    readonly _P="force privileged mount operation (invokes \"sudo\")"

    local n=15
    local f="%8s -%s, --%-${n}s -- %s\n"

    echo
    echo "Usage: $self $ARGSUSAGE"
    echo
    [ -n "$NOFATCAT" ] || {
    echo "Instance: <id> or <alias>      -- $cmdl_arg"
    echo
    }

    printf "$f" Options: q provide-qboot   "$_q"
    printf "$f" ""       x expand-image    "$_x"
    echo
    printf "$f" ""       y mount-boot      "$_y"
    printf "$f" ""       Y umount-boot     "$_Y"
    printf "$f" ""       z mount-root      "$_z"
    printf "$f" ""       Z umount-root     "$_Z"

    [ -n "$NOGUESTMOUNT" ] ||
	printf "$f" ""   P sudo-mount      "$_P"

    echo
    stdopts_help "$short_stdopts" "$n"

    [ -z "$NOISY" ] ||
	echo
    exit
}

pimage_parse_options () {
    local lo so

    so="${short_stdopts}qxyYzZ"
    lo="${long_stdopts},mount-boot,umount-boot,mount-root,umount-root"
    lo="${lo},provide-qboot,expand-image"

    [ -n "$NOGUESTMOUNT" ] || {
	so="${so}P"
	lo="${lo},sudo-mount"
    }

    getopt -Q -o "$so" -l "$lo" -n "$self" -s sh -- "$@" || usage
    eval set -- `getopt -o "$so" -l "$lo" -n"$self" -s sh -- "$@"`

    stdopts_filter "$@"
    eval set -- $OPTIONS

    local kinstall=

    # parse remaining option arguments
    while true
    do
	case "$1" in
	    -q|--provide-qboot) kinstall=set; shift ; continue ;;
	    -x|--expand-image)  EXP2PWR=set ; shift ; continue ;;

	    -y|--mount-boot)    BMOUNT=set  ; shift ; continue ;;
	    -Y|--umount-boot)   BUMOUNT=set ; shift ; continue ;;
	    -z|--mount-root)    RMOUNT=set  ; shift ; continue ;;
	    -Z|--umount-root)   RUMOUNT=set ; shift ; continue ;;

	    -P|--sudo-mount)    SUDOMNT=set ; shift ; continue ;;

	    --)	shift; break ;;
	    *)	fatal "parse_options: unexpected case \"$1\""
	esac
    done

    [ -z "$HELP" ] ||
	pimage_help

    [ -z "$NOFATCAT" -o 0 -eq $# ] ||
	usage "No more commands line arguments"

    # set QID variable
    verify_set_instance "$@"

    # implied options for set expressions
    [ -z "$kinstall" -o -z "$NOFATCAT" ] || IKERNEL=set
    [ -z "$kinstall" -o -n "$IKERNEL"  ] || XKERNEL=set

    # implied options for unset expressions
    [ -n "$NOGUESTMOUNT$SUDOMNT"                   ] || ULANDMNT=set
    [ -n "$kinstall$BMOUNT$BUMOUNT$RMOUNT$RUMOUNT" ] || SHOWSTAT=set
    [ -n "$EXP2PWR"                                ] || CHKIMG=set

    # imcompatible option combinations
    [ -z "$BMOUNT$BUMOUNT$RMOUNT$RUMOUNT" -o 0 -eq $# ] ||
	usage "No instance argument <$QID> with mount/umount options"

    [ -z "$EXP2PWR"                       -o 0 -eq $# ] ||
	usage "No instance argument <$QID> with option --expand-image"

    [ -n "$kinstall"                      -o 0 -eq $# ] ||
	usage "Unsupported instance argument <$QID> without option"

    [ -z "$SUDOMNT" -o -n "$BMOUNT$BUMOUNT$RMOUNT$RUMOUNT" ] ||
	usage "Option --sudo-mount requires mount/umount option"

}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

verify_not_root_user

pimage_parse_options "$@"

pimage_debug_vardump

verify_required_commands
verify_important_commands
verify_qimage_symlink

# -----------------------------------------------------------------------------
# Examine the raw image, bail out unless proper size
# -----------------------------------------------------------------------------

if [ -n "$CHKIMG" ]
then
    if qimg_file_size_p2ok
    then
	true
    else
	have=`qimg_file_size`
	mibs=`expr "$have" / 1048576`
	need=`qimg_file_size_p2ceil | sed 's/G$//'`
	img=`instance_disk_realpath 0`

	case "$need" in
        [!1-9]*)
	    info="To big to work as a raw disk image: \"$img\""
	    imax=`list_last $raw_image_sizes_GiB`

	    warn "$info"
	    printf "%11s Current size:       %6d MiB\n" "" $mibs
	    printf "%11s Maximal supported size: %2d GiB\n" "" $imax
	    ;;

	*)  info="You need to expand the raw disk image: \"$img\""

	    listen "$info"
	    printf "%11s Current size:    %4d MiB\n" "" $mibs
	    printf "%11s Need to expand to: %2d GiB\n" "" $need
	    ;;
	esac

	unset SHOWSTAT
    fi
fi

# -----------------------------------------------------------------------------
# Check whether padding was requested
# -----------------------------------------------------------------------------

if [ -n "$EXP2PWR" ]
then
    allocated=`qimg_mbr_print_num_blocks`
    available=`qimg_file_print_num_blocks_usable`
    img=`instance_disk_realpath 0`

    if qimg_file_size_p2ok && [ "$available" -le "$allocated" ]
    then
	mesg "No need to expand raw disk image \"$img\""
	unset SHOWSTAT
    elif qemu_instance_is_running_ok
    then
	mesg "$cannot_expand $some_inst_running"
	unset SHOWSTAT
    elif qboot_mount_is_active_ok
    then
	mesg "$cannot_expand boot $part_was_mounted"
	unset SHOWSTAT
    elif qroot_mount_is_active_ok
    then
	mesg "$cannot_expand root $part_was_mounted"
	unset SHOWSTAT
    else
	verify_qimage_partition_table
	need_size_GiB=`qimg_file_size_p2ceil`

	case "$need" in
	[!1-9]*) croak "To big to work as a raw disk image: \"$img\""
	esac

	oops="raw disk image \"$img\" went wrong :("

	runcmd truncate -s "$need_size_GiB" "$img"
	qimg_file_size_p2ok ||
	    fatal "oops, padding $oops"

	usable=`qimg_file_print_num_blocks_usable`
	new_mbr=`qimg_mbr_print_table "$usable"`
	runcmd echo "$new_mbr" |
	    runcmd3 "$SFDISK" --quiet "$img" 3>&2 2>/dev/null ||
	    fatal "oops, updating partition table for $oops"
    fi
fi

# -----------------------------------------------------------------------------
# Pull in disk mount library
# -----------------------------------------------------------------------------

# check whether user mode mount is available
if [ -n "$ULANDMNT" ]
then
    . $prefix/lib/guest-mount.sh
else
    . $prefix/lib/sudo-mount.sh
fi

# -----------------------------------------------------------------------------
# Mount boot partition (as read only)
# -----------------------------------------------------------------------------

if [ -n "$BMOUNT$IKERNEL" ]
then
    if qemu_instance_is_running_ok
    then
	mesg "Cannot mount root $part_while_running"
	unset BMOUNT IKERNEL
    elif qboot_mount_is_active_ok
    then
	mesg "Boot $part_mounted_already"
	unset BMOUNT
    else
	qboot_device_ok ||
	    doadm_qimg_loop_import
	qboot_mount_dir_ok
	doadm_qimg_boot_mount

	[ -n "$IKERNEL$XKERNEL" ] ||
	    mesg "Boot partition mounted on \"$mnt_boot_d\""

	# no $BUMOUNT => temporarily mount for kernel install
	[ -n "$BMOUNT" ] ||
	    BUMOUNT=set
    fi
fi

# -----------------------------------------------------------------------------
# Install kernel file => boot folder
# -----------------------------------------------------------------------------

if [ -n "$XKERNEL" ]
then
    if [ 0 -eq "${QID:-0}" ] && qboot_mount_is_active_ok
    then
	IKERNEL=set
    else
	img=`instance_disk "$QID"`

        [ 0 -eq "${QID:-0}" -o \( -s "$img" -a -s "$img.sig" \) ] ||
	    croak "There is no valid clone instance <$QID>"

	mesg "Extracting QEMU boot files from instance <$QID>"
	instance_bootp_extract_files "$QID"
    fi
fi

if [ -n "$IKERNEL" ]
then
    mesg "Copying QEMU boot files from mounted partition \"$mnt_boot_d\""

    qdisk_img=`instance_disk            0`
    bootp_sig=`instance_bootp_signature 0`
    cache_dir=`dirname "$qdisk_img"`

    runcmd mkdir -p "$cache_dir"
    copy_file "$mnt_boot_d/$boot_kernel_img" "$qdisk_img.ker"
    copy_file "$mnt_boot_d/$boot_dtb_img"    "$qdisk_img.dtb"
    write_file "$qdisk_img.sig" "$bootp_sig"
fi

# -----------------------------------------------------------------------------
# Mount root partition
# -----------------------------------------------------------------------------

if [ -n "$RMOUNT" ]
then
    if qemu_instance_is_running_ok
    then
	mesg "Cannot mount root $part_while_running"
    elif qroot_mount_is_active_rw_ok
    then
	mesg "Root $part_mounted_already"
    elif qroot_mount_is_active_ok
    then
	doadm_qimg_root_remount_rw
    else
	qroot_device_ok ||
	    doadm_qimg_loop_import
	qroot_mount_dir_ok
	doadm_qimg_root_mount

	mesg "Root partition mounted on \"$mnt_root_d\""
    fi
fi

# -----------------------------------------------------------------------------
# Umount root partition
# -----------------------------------------------------------------------------

if [ -n "$RUMOUNT" ]
then
    if qroot_mount_is_active_ok
    then
	doadm_qimg_root_unmount
	doadm_qimg_loop_release
    else
	mesg "QEMU root $part_not_mounted"
    fi
fi

# -----------------------------------------------------------------------------
# Umount boot partition
# -----------------------------------------------------------------------------

if [ -n "$BUMOUNT" ]
then
    if qboot_mount_is_active_ok
    then
	if qemu_instance_is_running_ok
	then
	    mesg "Cannot un-mount boot $part_while_running"
	else
	    doadm_qimg_boot_unmount
	    doadm_qimg_loop_release
	fi
    else
	mesg "QEMU boot $part_not_mounted"
    fi
fi

# -----------------------------------------------------------------------------
# Print image status
# -----------------------------------------------------------------------------

if [ -n "$SHOWSTAT" ]
then
    use_the_tool_luke="consider --provide-qboot option"

    if ! instance_bootp_files_ok 0
    then
	warn "Missing QEMU boot files ($use_the_tool_luke)"

    elif ! instance_bootp_signature_ok 0
    then
	warn "QEMU boot files need update ($use_the_tool_luke)"
    fi

    allocated=`qimg_mbr_print_num_blocks`
    max_avail=`qimg_file_print_num_blocks`
    available=`qimg_file_print_num_blocks_usable`
    recommndd=`expr "$max_avail" - "$available"`
    realmargn=`expr "$max_avail" - "$allocated"`

    ma=`expr "$max_avail" / 2048`
    al=`expr "$allocated" / 2048`
    rm=`expr "$realmargn" / 2048`
    re=`expr "$recommndd" / 2048`
    pc="${DISK_MARGIN_RESERVE:-0}"
    cl=`qimg_file_size_p2ceil | sed 's/G//'`

    echo
    printf "Disk image file size:%6d MiB\n"    "$ma"
    printf "Used by file system: %6d MiB\n"    "$al"
    printf "Unused data margin:  %6d MiB\n"    "$rm"
    printf "Recommend margin:    %6d MiB %s\n" "$re" "(~$pc% of $cl GiB)"
    echo
fi

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

#! /bin/sh
#
# Include file to be sourced by qemu-pibox scripts
#
# SPDX-License-Identifier: Unlicense
#
# Blame: Jordan Hrycaj <jordan@teddy-net.com>

# -----------------------------------------------------------------------------
# Printing messages, command line helper
# -----------------------------------------------------------------------------

mesg () { # syntax: text ...
    echo "*** $self: $*"
}

listen () { # syntax: text ...
    echo "*** $self: LISTEN: $*"
}

warn () { # syntax: text ...
    echo "*** $self(WARNING): $*"
}

croak () { # syntax: text ...
    echo "*** $self(CROAK): $* -- STOP" >&2
    exit
}

fatal () { # syntax: text ...
    echo "*** $self(FATAL): $* -- STOP" >&2
    exit 2
}

usage () { # syntax: [error message ...]
    exec >&2
    [ -z "$1" ] || {
	mesg "$*"
        echo
    }

    echo "Usage: $self $ARGSUSAGE"
    echo "       $self --help"

    exit 1
}

disclaimer_once () {
    [ -f "$disclaimer_d/$self-disclaimer-shown" ] || {
	mkdir -p "$disclaimer_d"
	touch    "$disclaimer_d/$self-disclaimer-shown"
	cat <<EOF

  PLEASE NOTICE:
     -----------------------------------------------------------
     This script is free and unencumbered software released into
     the public domain. For the full statement visit the file
     "$prefix/UNLICENSE"
     ------------------------------------------------------------
EOF
    }
}

# dump variables, handle with care: "eval" statement used here (!)
dump_vars () { # syntax: <var> ... -> "var=<value>" ...
    local list="$*"
    local var
    for var in $list
    do
	# sanity check
	case "$var" in *[!A-Za-z0-9]*|[!A-Za-z]*) continue; esac

	# compile the value
	eval set -- x \$$var; shift
	echo "$var='$*'"
    done
}

stdopts_filter () { # syntax: <option> ...
    while true
    do
	case "$1" in
	    -h|--help)	     HELP=set           ;;
	    -d|--debug)	     DEBUG=set          ;;
	    -v|--verbose)    NOISY=set          ;;
	    -D|--dry-run)    RUNPFX=:           ;;
	    -i|--disk-image) QIMAGE="$2"; shift ;;
	    --)	             break              ;;
	    *)	             OPTIONS="$OPTIONS '$1'"
	esac
	shift
    done

    local opt
    for opt
    do
	OPTIONS="$OPTIONS '$opt'"
    done
}

stdopts_help () { # syntax: <short-opts> [<indent>]
    local f="%8s -%s, --%-${2:-15}s -- %s\n"

    # use readonly for checking option letter uniqueness
    readonly _i="set disk image file location"
    readonly _D="not really executing, combine with --verbose"
    readonly _d="script debugging support"
    readonly _v="print additional info"
    readonly _h="print this help page (combine with --verbose)"

    local o
    for o in `echo "$1" | sed -e 's/./& /g'`
    do
	case $o in
	    i) printf "$f" "" i disk-image=FILE "$_i" ;;
	    D) printf "$f" "" D dry-run         "$_D" ;;
	    d) printf "$f" "" d debug           "$_d" ;;
	    v) printf "$f" "" v verbose         "$_v" ;;
	    h) printf "$f" "" h help            "$_h" ;;
	esac
    done
}

verify_set_instance () { # syntax: [ <id> | <alias> ] -> <instance>
    QID=0

    case $# in
	0) ;;
	1) QID="$1" ;;
	*) usage "too many arguments: '$*'"
    esac

    # check for converting hostname => ID
    if name_format_ok "$QID"
    then
	local q=`name_to_instance "$QID"`
	[ -n "$q" ] ||
	    usage "argument name \"$QID\" is not a registered name"
	QID="$q"

    elif [ -n "$QID" ]
    then
	# verify that instance exists
	local q=`instance_to_name "$QID"`
	[ -n "$q" ] ||
	    usage "argument node ID <$QID> is not registered"
    fi
}

# -----------------------------------------------------------------------------
# Validity checkers
# -----------------------------------------------------------------------------

verify_required_commands () { # syntax: [<cmd> ...]
    qemu_cmd=`list_first $qemu_system_cmd`

    miss="Missing command"
    moan="-- please install"

    local cmd
    for cmd in $qemu_cmd $required_commands "$@"
    do
	which "$cmd" >/dev/null ||
	    fatal "$miss \"$cmd\" $moan"
    done

    # provide upper case command name paths for /sbin commands
    for cmd in $required_sbin_commands
    do
	local var=`echo "$cmd" | tr '[:lower:]' '[:upper:]'`

	if [ -x "/sbin/$cmd" ]
	then
	    val="/sbin/$cmd"
	elif [ -x "/usr/sbin/$cmd" ]
	then
	    val="/usr/sbin/$cmd"
	else
	    fatal "$miss \"/sbin/$cmd\" or \"/usr//sbin/$cmd\" $moan"
	fi

	eval $var=$val
    done
}

verify_important_commands () { # syntax: [<cmd> ...]
    qemu_cmd=`list_first $qemu_system_cmd`

    miss="Command"
    moan="should be installed or otherwise made available"

    local cmd
    for cmd in $important_commands
    do
	which "$cmd" >/dev/null ||
	    mesg "$miss \"$cmd\" $moan"
    done
}

verify_not_root_user () {
    local uid=`id -u`
    [ 0 -ne "$uid" ] ||
	croak "must not be run as root"
}

verify_qimage_file_size () {
    qimg_file_size_p2ok || {
	local  img=`instance_disk 0`
	local ceil=`qimg_file_size_p2ceil`
	local  rdi="raw disk image \"$img\""
	local pmnt="\"pimage\" with option --expand-image"

	case "$ceil" in
	    -*) croak "Cannot determine file size of $rdi" ;;
	    +*) croak "The $rdi has unsupported size greater than 16GiB" ;;
	    *)  croak "The $rdi needs padding, consider $pmnt"
	esac
    }
}

verify_qimage_partition_table () { # syntax: [<file-name>]
    local img_file="${1:-`instance_disk 0`}"
    local check_ok=`qimg_mbr_parse_file "$img_file" | sed q`

    if [ -z "$check_ok" ]
    then
	if [ -f "$img_file" ]
	then
	    croak "Error parsing partition table for disk image \"$img_file\""
	else
	    croak "No known disk image yet"
	fi
    fi
}

# update qimage symlink
verify_qimage_symlink () {
    local img=`instance_disk 0`
    local dir=`dirname "$img"`

    mkdir -p "$dir"

    local old=`instance_disk_realpath 0`

    if [ -n "$QIMAGE" ]
    then
	verify_qimage_partition_table "$QIMAGE"

	local new=`realpath "$QIMAGE"`

	[ "x$old" = "x$new" ] || {
	    rm -f "$img"
	    ln -sf "$new" "$old"
	    remove_files "$img.ker" "$img.dtb" "$img.sig"
	}

    elif [ -s "$old" ]
    then
	verify_qimage_partition_table
    else
	croak "Image file missing (consider --disk-image option)"
    fi
}

# -----------------------------------------------------------------------------
# List variable functions, various helpers
# -----------------------------------------------------------------------------

list_first () { # syntax: <arg1> <arg2> .. -> <arg1>
    echo "$1"
}

list_last () { # syntax: <arg1> <arg2> .. <argn> -> <argn>
    echo "$@" | awk '{a = $NF} END {if (a) print a}'
}

list_tail () { # syntax: <arg1> <arg2> .. -> <arg2> ...
    shift
    echo "$@"
}

list_quote () { # syntax: <arg1> <arg2> .. -> '<arg1>' '<arg2>' ...
    local al
    for a; do al="$al${al:+ }'$a'"; done
    echo "$al"
}

list_dblquote () { # syntax: <arg1> <arg2> .. -> '<arg1>' '<arg2>' ...
    local al
    for a; do al="$al${al:+ }\"$a\""; done
    echo "$al"
}

# compare GiB value against byte size argument
GiB_cmp_bytes_ok () { # syntax: <gib> <op> <num>
    local gib="$1"
    local  op="$2"
    local num="$3"

    # for portability, this fuctionality is not implemented in
    # vanilla AWK (or similar) due to 32 bit portability issues
    [ x != "x$gib" -a x != "x$op" -a x != "x$num" ] &&
	expr "$gib" \* 1024 \* 1024 \* 1024 "$op" "$num" >/dev/null
}

flag_is_yes () { # <text-value>
    case "$1" in y|Y|yes|Yes|YES) return 0; esac
    return 1
}
# -----------------------------------------------------------------------------
# Command wrappers with fancy debug printing
# -----------------------------------------------------------------------------

runcmd () { # syntax: cmd ...
    ([ -z "$NOISY" ] || set -x; $RUNPFX "$@")
}

runcmd3 () { # syntax: cmd ...
             # NOISY run message on channel 3
    [ -z "$NOISY" ] ||
	echo '+' $RUNPFX "$@" >&3
    $RUNPFX "$@"
}

remove_files () {  # syntax: <file> ...
    local file
    for file
    do
	[ -f "$file" ] ||
	    continue
	[ ! -f "$file~" ] ||
	    runcmd rm -f "$file~"
	runcmd mv "$file" "$file~"
    done
}

move_file () {  # syntax: <src> <trg>
    local src="$1"
    local trg="$2"

    remove_files     "$trg"
    runcmd mv "$src" "$trg"
}

copy_file () {  # syntax: <src> <trg>
    local src="$1"
    local trg="$2"

    remove_files     "$trg"
    runcmd cp "$src" "$trg"
}

write_file () {  # syntax: <file> <data> ...
    local trg="$1"
    local dir=`dirname "$trg"`
    shift

    runcmd mkdir -p "$dir"
    remove_files    "$trg"

    [ -z "$NOISY" ] ||
	(echo "+" $RUNPFX echo "$@" ">" "$trg" >&2)
    [ -n "$RUNPFX" ] ||
	(echo "$@" > "$trg")
}

# -----------------------------------------------------------------------------
# Managing raw disk image file (i.e. qclone <0>)
# -----------------------------------------------------------------------------

qimg_file_size () {
    local img=`instance_disk 0`
    find -L "$img" -printf "%s\n"
}

qimg_file_print_num_blocks () {
    local size=`qimg_file_size`
    expr "$size" / 512
}

qimg_file_print_num_blocks_usable () {
    local blocks=`qimg_file_print_num_blocks`
    expr "$blocks" \* \( 100 - ${DISK_MARGIN_RESERVE:-0} \) / 100
}

# find the padding size for the raw file image (if any)
qimg_file_size_p2ceil () {
    local size=`qimg_file_size`

    [ -n "$size" ] || {
	# argument "-0" is harmless in: truncate -2 "+0" <file>
	echo "-0"
	return
    }

    local n
    for n in $raw_image_sizes_GiB
    do
	GiB_cmp_bytes_ok "$n" '<' "$size" || {
	    echo "${n}G"
	    return
	}
    done

    # argument "+0" is harmless in: truncate -2 "+0" <file>
    echo "+0"
}

# check whether the size of the raw file image is an acceptable power of 2
qimg_file_size_p2ok () {
    local size=`qimg_file_size`

    [ -z "$size" ] || {
	local n
	for n in $raw_image_sizes_GiB
	do
	    GiB_cmp_bytes_ok "$n" '<' "$size" || {
		GiB_cmp_bytes_ok "$n" '=' "$size"
		return
	    }
	done
    }

    return 1
}

qimg_mbr_parse_file () { # syntax: <raw-disk-image>
    #                              [<#-of-data-blocks>] ->
    #                                 <total-blocks-allocated>
    #                                 <boot-part-start> <size> <end>
    #                                 updated partition table
    #                                 ...
    local    img="${1:-/dev/null}"
    local blocks="${2}"
    local    mbr=`"$SFDISK" -d "$img" 2>/dev/null`

    echo "$mbr" |
	awk 'BEGIN {
	  unit_ok     = 0
	  ssize_ok    = 0
	  part1_start = 0
	  part2_size  = 0
	  part2_start = 0
	  part2_size  = 0
	  fail_ok     = 0
	  mbr_data    = ""
	  num_blocks  = '"${blocks:-0}"'
	}
	# unit: sectors
	$1 == "unit:" && $2 == "sectors" {
	  unit_ok  = 1
	  mbr_data = mbr_data "\n" $0
	  next
	}
	# sector-size: 512
	$1 == "sector-size:" && $2 == "512" {
	  ssize_ok = 1
	  mbr_data = mbr_data "\n" $0
	  next
	}
	# raspios.img1 : start=	       8192, size=	524288, type=c
	NF == 7 && $1 ~ /1$/ && $2 == ":" && $3 == "start=" && $4 ~ /,$/ &&
					     $5 == "size="  && $6 ~ /,$/ &&
					     $7 == "type=c" {
	  part1_start = substr ($4, 1, length ($4) - 1)
	  part1_size  = substr ($6, 1, length ($6) - 1)
	  mbr_data    = mbr_data "\n" $1 " " $2 " " $3 " " $4 " " $5 " " $6
	  mbr_data    = mbr_data " " $7
	  next
	}
	# raspios.img2 : start=	     532480, size=     7856128, type=83
	NF == 7 && $1 ~ /2$/ && $2 == ":" && $3 == "start=" && $4 ~ /,$/ &&
					     $5 == "size="  && $6 ~ /,$/ &&
					     $7 == "type=83" {
	  part2_start = substr ($4, 1, length ($4) - 1)
	  part2_size  = substr ($6, 1, length ($6) - 1)
	  new_size    = part2_size
	  if (num_blocks) {
	     part2_size = num_blocks - part2_start
	  }
	  mbr_data    = mbr_data "\n" $1 " " $2 " " $3 " " $4 " " $5
	  mbr_data    = mbr_data " " part2_size ", " $7
	  next
	}
	$2 == ":" {
	  fail_ok = 1
	  exit
	}
	{
	  if (mbr_data)
	     mbr_data = mbr_data "\n"
	  mbr_data = mbr_data $0
	}
	END {
	  if (!fail_ok && unit_ok && ssize_ok &&
	      8192		       <= part1_start &&
	      part1_start + part1_size <= part2_start &&
	      0			       <  part2_size) {
	     print part2_start + part2_size
	     print part1_start,  part1_size, part1_start + part1_size
	     print mbr_data
	  }
	}'
}

qimg_mbr_print_table () { # syntax: <num-blocks>
    local num="$1"
    local img=`instance_disk 0`
    qimg_mbr_parse_file "$img" "$num" | sed -e1d -e2d
}

qimg_mbr_print_num_blocks () {
    local img=`instance_disk 0`
    qimg_mbr_parse_file "$img" | sed q
}

# -----------------------------------------------------------------------------
# Status query related to the disk image mounter
# -----------------------------------------------------------------------------

# Device name of imported disk image
qimg_loop_device () {
    local img=`instance_disk_realpath 0`
    "$LOSETUP" -l |
	awk '$0 ~ "'"$img"'" {print $1;exit}'
}

# ------------

# Boot partition device name of imported disk image
qboot_device () {
    local dev=`qimg_loop_device`
    echo $dev${dev:+p1}
}

qboot_device_ok () {
    qboot_device | grep -q .
}

qboot_mount_is_active_ok () {
    local dir=`qboot_mount_realpath`
    mount |
	grep -q " $dir "
}

qboot_mount_is_active_fuser_ok () {
    local dir=`qboot_mount_realpath`
    mount |
	grep " $dir " | grep -q "^/dev/fuse"
}

qboot_mount_dir_ok () {
    [ -d "$mnt_boot_d" ] ||
	runcmd mkdir -p "$mnt_boot_d"
}

qboot_mount_realpath () {
    [ ! -d "$mnt_boot_d" ] ||
	realpath "$mnt_boot_d"
}

# ------------

# Root partition device name of imported disk image
qroot_device () {
    local dev=`qimg_loop_device`
    echo $dev${dev:+p2}
}

qroot_device_ok () {
    qroot_device | grep -q .
}

qroot_mount_is_active_ok () {
    local dir=`qroot_mount_realpath`
    mount |
	grep -q " $dir "
}

qroot_mount_is_active_rw_ok () {
    local dir=`qroot_mount_realpath`
    mount |
	grep -q " $dir " |
	grep -q " (rw,"
}

qroot_mount_is_active_fuser_ok () {
    local dir=`qroot_mount_realpath`
    mount |
	grep " $dir " | grep -q "^/dev/fuse"
}

qroot_mount_dir_ok () {
    [ -d "$mnt_root_d" ] ||
	runcmd mkdir -p "$mnt_root_d"
}

qroot_mount_realpath () {
    [ ! -d "$mnt_root_d" ] ||
	realpath "$mnt_root_d"
}

# -----------------------------------------------------------------------------
# Clone instance related helpers
# -----------------------------------------------------------------------------

name_format_ok () { # syntax: <name>
    # is a name if it exists and has at least one non-digit
    [ -n "$1" ] && expr "$1" : '.*\([^0-9]\)' >/dev/null
}

name_to_instance () { # syntax: <name> -> [<instance>]
    local name="$1"

    awk '$2 ~ /^n[0-9][0-9]*\.lan$/ && $3 == "'"$name"'" {
            print substr ($2, 2, length ($2) - 5)
            exit
	 }' "$ETC_HOSTS"
}

instance_lan_address () { # syntax: <instance>
    # lookup address for n#.wan and replace <pfx>.15 => <pfx>.0/24
    # use entry n0.wan as default
    awk '$1 ~ /^[0-9.]*$/ && $2 == "n0.lan" {
	    a0 = $1
	 }
	 $1 ~ /^[0-9.]*$/ && $2 == "n'"$1"'.lan" {
	    a1 = $1
	    exit
	 }
	 END {
	    if (a1) print a1; else print a0
	 }' "$ETC_HOSTS"
}

instance_wan_network () { # syntax: <instance>
    # lookup address for n#.wan and replace <pfx>.15 => <pfx>.0/24
    # use entry n0.wan as default
    awk '$1 ~ /^[0-9.]*\.15$/ && $2 == "n0.wan" {
	    a0 = substr ($1, 0, length ($1) - 2) "0/24"
	 }
	 $1 ~ /^[0-9.]*\.15$/ && $2 == "n'"$1"'.wan" {
	    a1 = substr ($1, 0, length ($1) - 2) "0/24"
	    exit
	 }
	 END {
	    if (a1) print a1; else print a0
	 }' "$ETC_HOSTS"
}

instance_vnc_port () { # syntax: <instance> -> <port>
    expr 5900 + ${1:-0}
}

instance_console_port () { # syntax: <instance> -> <port>
    expr 5800 + ${1:-0}
}

instance_ssh_port () { # syntax: <instance> -> <port>
    expr 5700 + ${1:-0}
}

instance_disk () { # syntax: <instance> -> <file-path>
    local  id="${1:-0}"
    local ext=qcow2
    [ 0 -lt "$id" ] ||
	ext=raw
    printf "$clone_tmpl_prefix.%s" "$id" "$id" "$ext"
}

instance_disk_realpath () { # syntax: <instance> -> <abs-path>
    local img=`instance_disk "$1"`
    local dir=`dirname "$img"`
    [ -s "$dir" ] ||
	croak "Folder missing for clone \"$img\""
    realpath "$img"
}

instance_to_name () { # syntax: <instance> -> [<name>]
    local id="$1"

    awk '$2 == "n'"$id"'.lan" {
            print $3
            exit
	 }' "$ETC_HOSTS"
}

instance_list_all () {
    awk '$2 ~ /^n[0-9][0-9]*\.lan$/ {
            print substr ($2, 2, length ($2) - 5)
	 }' "$ETC_HOSTS" | sort
}

# Check for files needed for booting QEMU
instance_bootp_files_ok () { # syntax: [<instance>]
    local  id="${1:-0}"
    local img=`instance_disk "$id"`

    [ -s "$img.ker" -a -s "$img.dtb" ]
}

# print hash of boot partition
instance_bootp_signature () { # syntax: [<instance>]
    local  id="${1:-0}"
    local raw=`instance_disk 0`

    set -- x `qimg_mbr_parse_file "$raw" | sed -e1d -eq`

    local    img=`instance_disk "$id"`
    local    fmt=`expr "$img" : '.*\.\(.*\)'`
    local dd_tmp="$img.dd-out"

    rm -f "$dd_tmp"

    if [ xqcow2 = "x$fmt" ]
    then
	# qemu-dd reads <count> bytes
	runcmd qemu-img dd -O raw skip=$2 count=$4 if="$img" of="$dd_tmp"
    else
	# dd skips reads <count> + <skip> bytes
	runcmd3 dd skip=$2 count=$3 if="$img" of="$dd_tmp" 3>&2 2>/dev/null
    fi

    runcmd md5sum "$dd_tmp" | awk '{print $1}'
    runcmd rm -f "$dd_tmp"
}

# check hash of boot partition
instance_bootp_signature_ok () { # syntax: [<instance>]
    local  id="${1:-0}"
    local sig=`instance_bootp_signature "$id"`
    local img=`instance_disk "$id"`
    local chk=`cat "$img.sig" 2>/dev/null`

    [ -n "$chk" -a "x$sig" = "x$chk" ]
}

instance_bootp_extract_files () { # syntax: <instance>
    local  id="${1:-0}"
    local raw=`instance_disk 0`

    set -- x `qimg_mbr_parse_file "$raw" | sed -e1d -eq`

    local    img=`instance_disk "$id"`
    local    fmt=`expr "$img" : '.*\.\(.*\)'`
    local dd_tmp="$img.dd-out"
    local mv_tmp="$img.fc-out"

    if [ xqcow2 = "x$fmt" ]
    then
	# qemu-dd reads <count> bytes
	runcmd qemu-img dd -O raw skip=$2 count=$4 if="$img" of="$dd_tmp"
    else
	# dd skips reads <count> + <skip> bytes
	runcmd3 dd skip=$2 count=$3 if="$img" of="$dd_tmp" 3>&2 2>/dev/null
    fi

    rm -f                                            "$mv_tmp"
    runcmd md5sum "$dd_tmp" | awk '{print $1}'     > "$mv_tmp"
    move_file "$mv_tmp" "$img.sig"

    rm -f                                            "$mv_tmp"
    runcmd fatcat "$dd_tmp" -r "/$boot_kernel_img" > "$mv_tmp"
    move_file "$mv_tmp" "$img.ker"

    rm -f                                            "$mv_tmp"
    runcmd fatcat "$dd_tmp" -r "/$boot_dtb_img"    > "$mv_tmp"
    move_file "$mv_tmp" "$img.dtb"

    runcmd rm -f "$dd_tmp" "$mv_tmp"
}

# -----------------------------------------------------------------------------
# Status query related to the running QEMU emluator
# -----------------------------------------------------------------------------

# Find all QEMU process IDs by filtering the TAP device instance name
qemu_instance_pids () { # syntax: [<instance>] -> [<pid1> <pid2> ...]

    # no/empty function argument => select all instances
    local td="tap,id=tap0,ifname=q0tap${1:-[0-9][0-9]*}"

    ps xa |
	sed -e "\| $qemu_system_cmd |!d"       \
	    -e "\|[ ']-netdev[ '][ ']*$td,|!d"    |
	grep -v grep			       |
	awk '{print $1}'
}

qemu_instance_console_port () { # syntax: <instance> -> [<port>]
    local pid=`qemu_instance_pids "$1" | sed -eq`

    ps xp "$pid" --no-headers 2>/dev/null |
	sed -e    "/[ ']tcp:[0-9.]*:[0-9]*,server/!d" \
	    -e "s/.*[ ']tcp:[0-9.]*:\([0-9]*\),server.*/\1/" \
	    -eq
}

qemu_instance_vnc_port () { # syntax: <instance> -> [<port>]
    local pid=`qemu_instance_pids "$1" | sed -eq`

    local vnc=`ps xq "$pid" --no-headers 2>/dev/null |
		  sed -e    "/[ ']-vnc[ '][ ']*[0-9.]*:[0-9]/!d" \
		      -e "s/.*[ ']-vnc[ '][ ']*[0-9.]*:\([0-9]*\).*/\1/" \
		      -eq`
    [ -z "$vnc" ] ||
	instance_vnc_port "$vnc"
}

# check whether some or a particular QEMU instance is running
qemu_instance_is_running_ok () { # syntax: [<instance>]
    qemu_instance_pids "$@" | grep -q '[0-9]'
}

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

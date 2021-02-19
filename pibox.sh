#! /bin/sh
#
# Manage the QEMU emulator for running Raspberry PI disk images
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

. $prefix/lib/variables.sh
. $prefix/lib/functions.sh
. $prefix/lib/sudo-qemuctl.sh

# Reset global variables
unset CONSOLE QEMUGUI QSLEPTOK NEWCLONE DELCLONE CCACHECLN INSTINFO
unset PUBCON PUBVNC PUBSSH QKILL QPIRUN VNCRUN QPINFO QIRFORCE

readonly short_stdopts="i:Ddvh"
readonly long_stdopts="disk-image:,dry-run,debug,verbose,help"

which remote-viewer >/dev/null || NOREMOTE_VIEWER=set
which fatcat        >/dev/null || NOFATCAT=set

set +e

# -----------------------------------------------------------------------------
# Command line helper functions
# -----------------------------------------------------------------------------

pibox_debug_vardump () {
    [ -z "$DEBUG" ] ||
	mesg `dump_vars \
	       QID HELP DEBUG NOISY RUNPFX QIMAGE OPTIONS \
	       CONSOLE QEMUGUI QSLEPTOK NEWCLONE DELCLONE CCACHECLN INSTINFO \
	       PUBCON PUBVNC PUBSSH QKILL QPIRUN VNCRUN QPINFO \
	       NOREMOTE_VIEWER QIRFORCE NOFATCAT`
}

pibox_info () {
    local qemu_cmd=`list_first $qemu_system_cmd`

    cat <<EOF

  The tool starts and stops the virtual QEMU machine for guest disk images.
  Guest disk images are referred to as "instances" and identified by a number.
  Default is the zero instance  <0> running on the primary "raw" RaspiOS disk
  image. All other instances are "qcow2" formatted copies of the <0> instance.

  By extension, a virtual QEMU machine for instance <N> is called "the"
  instance <N> if the meaning is otherwise clear.

  Adminstator Privilege
    For starting and terminating the QEMU emulator, this tool will execute
    "sudo" for escalate administrator privileges when executing the commands
    "$qemu_cmd" or "kill". Administrative privileges are necessary
    for the vitual QEMU machine so it can allocate local TAP network interfaces
    (implying the need for privileged "kill".)

    The QEMU program "$qemu_cmd" is typically run in the background.
    Instead of running "sudo" with the --background option, "sudo" is called
    for authentication allowing "sudo" to remember this when starting the real
    QEMU program.

  Preparation
    Run the disk image maintenance tool

      sh pimage.sh --help --verbose

    and follow the instructions for the example usage.

  Graphical VNC session
    Enter

      sh $self.sh --run

    This will start the QEMU virtual machine and display a variety of options
    for accessing the virtual guest system. It will also start the VNC GUI
    "remote-viewer" program which allows to interact with the virtual guest
    through a graphical interface.

    On the VNC GUI, login as user "pi" with password "raspberry" and play
    around (e,g. try the command "lsb_release -a".) The VNC GUI will have
    captured the mouse cursor which can be released by entering the keyboard
    key combination <ctrl>-<alt>.

    Back on the command line, run

      sh pijack.sh --help --verbose

    in order to find out how to shut down the virtual guest (hint: try the
    --shutdown option.)

    Wait for the system to come down.

  Run foregound session (helpful for debugging)
    Start the QEMU virtual machine with

      sh $self.sh --console --no-start-vnc

    Never enter <ctrl>-C unless the end of the session. When the login prompt
    appears, login as "pi" with password "raspberry" and play around as before.
    When done, run

      sudo halt

    and wait for QEMU virtual machine to halt. Hit <ctrl>-C now in order to
    terminate QEMU and release the console.

  More on instance management
    Any instances different from the <0> instance refers to QEMU processes
    running on "qcow2" formatted clones of raw disk image. These clone images
    are generated on the fly when starting the instance (reminiscent of
    "vagrant") or by using the --force-clone option.
EOF
}

pibox_help () {
    echo "Virtual machine host manager"

    [ -z "$NOISY" ] ||
	pibox_info

    disclaimer_once

    local ir="implies --run"
    local not_localhost="rather than \"localhost\", $ir"
    local      cmdl_arg="use instance rather than base image (i.e. instance 0)"

    # use readonly for checking option letter uniqueness
    readonly _r="checks boot partition and runs the QEMU emulator"
    readonly _R="ignore changed boot partition, $ir"
    readonly _c="comand line console (kill QEMU with <ctl>-C), $ir"
    readonly _n="not starting VNC viewer, $ir"
    readonly _g="start qemu X11 gui, $ir and --no-start-vnc"
    readonly _G="global server IP addresses $not_localhost"
    readonly _t="kill QEMU process (prefer \"pijack\" with --shutdown option)"
    readonly _f="always create new clone, combine with --run"
    readonly _F="flush/remove clone and backup image"
    readonly _A="remove all clones and backup images"

    local n=17
    local f="%8s -%s, --%-${n}s -- %s\n"

    echo
    echo "Usage: $self $ARGSUSAGE"
    echo
    echo "Instance: <id> or <alias>        -- $cmdl_arg"
    echo

    printf "$f" Options: r run               "$_r"
    printf "$f" ""       R run-ignore-qboot  "$_R"
    printf "$f" ""       t terminate         "$_t"
    echo
    printf "$f" ""       c console           "$_c"

    [ -n "$NOREMOTE_VIEWER" ] ||
	printf "$f" ""   n no-start-vnc      "$_n"

    printf "$f" ""       g force-qemu-gui    "$_g"
    printf "$f" ""       G global-ip-bind    "$_G"
    echo
    printf "$f" ""       f force-clone       "$_f"
    printf "$f" ""       F flush-clone       "$_F"
    printf "$f" ""       A remove-all-clones "$_A"
    echo

    stdopts_help "$short_stdopts" "$n"

    [ -z "$NOISY" ] ||
	echo
    exit
}

pibox_parse_options () {
    local lo so

    so="${short_stdopts}rRtcgGfFA"
    lo="${long_stdopts},run,run-ignore-qboot,terminate,console"
    lo="${lo},force-qemu-gui,global-ip-bind,force-clone,flush-clone"
    lo="${lo},remove-all-clones"

    [ -n "$NOREMOTE_VIEWER" ] || {
	so="${so}n"
	lo="${lo},no-start-vnc"
    }

    getopt -Q -o "$so" -l "$lo" -n "$self" -s sh -- "$@" || usage
    eval set -- `getopt -o "$so" -l "$lo" -n"$self" -s sh -- "$@"`

    stdopts_filter "$@"
    eval set -- $OPTIONS

    local norunvnc=
    local gbind=

    # parse remaining option arguments
    while true
    do
	case "$1" in
	    -r|--run)               QPIRUN=set   ; shift ; continue ;;
	    -R|--run-ignore-bootp)  QIRFORCE=set ; shift ; continue ;;
	    -t|--terminate)         QKILL=set    ; shift ; continue ;;

	    -c|--console)           CONSOLE=set  ; shift ; continue ;;
	    -n|--no-start-vnc)      norunvnc=set ; shift ; continue ;;
	    -q|--force-qemu-gui)    QEMUGUI=set  ; shift ; continue ;;
	    -G|--global-ip-bind)    gbond=set    ; shift ; continue ;;

	    -f|--force-clone)       NEWCLONE=set ; shift ; continue ;;
	    -F|--flush-clone)       DELCLONE=set ; shift ; continue ;;
	    -A|--remove-all-clones) CCACHECLN=set; shift ; continue ;;

	    --)	shift; break ;;
	    *)	fatal "parse_options: unexpected case \"$1\""
	esac
    done

    [ -z "$HELP" ] ||
	pibox_help

    # set QID variable
    verify_set_instance "$@"

    # implied options for set expressions
    [ -z "$CONSOLE"                ] || norunvnc=set
    [ -z "$QEMUGUI"                ] || norunvnc=set
    [ -z "$NOREMOTE_VIEWER"        ] || norunvnc=set

    [ -z "$gbind" -o -n "$CONSOLE" ] || PUBCON=set
    [ -z "$gbind" -o -n "$QEMUGUI" ] || PUBVNC=set
    [ -z "$gbind"                  ] || PUBSSH=set

    [ -z "$QIRFORCE"               ] || QPIRUN=set
    [ -z "$norunvnc"               ] || QPIRUN=set
    [ -z "$CONSOLE"                ] || QPIRUN=set
    [ -z "$QEMUGUI"                ] || QPIRUN=set
    [ -z "$PUBVNC"                 ] || QPIRUN=set
    [ -z "$PUBSSH"                 ] || QPIRUN=set
    [ -z "$PUBCON"                 ] || QPIRUN=set

    [ -z "$QPIRUN"                 ] || QPINFO=set
    [ -z "$RUNPFX"                 ] || QSLEPTOK=set

    # implied options for unset expressions
    [ -n "$norunvnc"     -o -z "$QPIRUN"                  ] || VNCRUN=set
    [ -n "$CONSOLE"      -o -n "$QKILL"     -o 0 -eq "$#" ] || QPINFO=set
    [ -n "$QPIRUN$QKILL"                                  ] || QSLEPTOK=set

    [ -n "$QPINFO$QKILL" -o -n "$CCACHECLN" -o 0 -ne "$#" ] || INSTINFO=set

    # imcompatible option combinations
    [ -z "$PUBVNC" -o -z "$QEMUGUI" ] ||
        usage "Incompatible options --qemu-gui and --global-vnc"

    [ -z "$PUBCON" -o -z "$CONSOLE" ] ||
        usage "Incompatible options --console and --global-console"

    [ -z "$QPIRUN" -o -z "$QKILL" ] ||
	usage "Incompatible options --run-pibox and --terminate"

    [ -z "$QPIRUN" -o -z "$DELCLONE" ] ||
	usage "Incompatible options --run- and --flush-clone"

    [ -z "$QPIRUN" -o -z "$CCACHECLN" ] ||
	usage "Incompatible options --run- and --remove-all-clones"

    local not_with_gui="incomatible with other GUI/shell/console options"
    [ -z "$QKILL" -o -z "$PUBVNC$PUBSSH$PUBCON$QEMUGUI$CONSOLE" ] ||
	usage "Option --terminate is $not_with_gui"

    local needs_pos_inst_id="needs a positive clone instance <id> argument"
    [ -z "$NEWCLONE" -o 0 -lt "$QID" ] ||
	usage "Option --force-clone $needs_pos_inst_id"

    [ -z "$DELCLONE" -o 0 -lt "$QID" ] ||
	usage "Option --flush-clone $needs_pos_inst_id"

    [ -z "$CCACHECLN" -o 0 -eq "$#" ] ||
	usage "No instance argument <$QID> with option --remove-all-clones"
}

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

pibox_fatal_need_clone_id () {
    fatal "$*: function argument must be a positive clone <id>"
}

# allow some time to wait for QEMU to start
pibox_wait_for_qemu () {
    [ -z "$QSLEPTOK" ] ||
	return
    sleep $wait_qemu
    QSLEPTOK=set
}

pibox_qclone_boot_signature_ok () { # syntax: [<instance>]
    local id="${1:-0}"

    # no need to open the qcow2/clone image if the signature file is newer
    local  qcl_img=`instance_disk "$id"`
    local real_img=`realpath "$qcl_img"`
    local  qcl_sig="$qcl_img.sig"
    local    newer=`ls -dt "$qcl_sig" "$real_img" | sed q`

    if [ "x$newer" = "x$qcl_sig" ]
    then
	true
    else
	mesg "Compiling/checking signature for instance <$id>"
	instance_bootp_signature_ok "$QID"
    fi
}

pibox_qclone_exists_ok () { # syntax: <instance>
    local id="${1:-0}"

    [ 0 -lt "$id" ] ||
	pibox_fatal_need_clone_id "pibox_qclone_exists_ok"

    local qcl_img=`instance_disk "$id"`
    [ -f "$qcl_img" ]
}

pibox_qclone_create () { # syntax: <instance>
    local id=${1:-0}

    [ 0 -lt "$id" ] ||
	pibox_fatal_need_clone_id "pibox_qclone_create"

    local raw_img=`instance_disk "0"`
    local qcl_img=`instance_disk "$id"`
    local qcl_dir=`dirname "$qcl_img"`

    [ -n "$NOISY" ] ||
	if pibox_qclone_exists_ok "$id"
	then
	    mesg "Replacing \"$qcl_dir/*\" (old instance saved)"
	else
	    mesg "Creating \"$qcl_dir/*\""
	fi

    runcmd mkdir -p "$qcl_dir"

    runcmd qemu-img convert \
	   -o preallocation=off -O qcow2 "$raw_img" "$qcl_img.new"

    move_file "$qcl_img.new" "$qcl_img"
    copy_file "$raw_img.ker" "$qcl_img.ker"
    copy_file "$raw_img.dtb" "$qcl_img.dtb"
    copy_file "$raw_img.sig" "$qcl_img.sig"
}

pibox_qclone_delete () { # syntax: <instance> <quiet>
    local    id=${1:-0}
    local noisy="$2"

    [ 0 -lt "$id" ] ||
	pibox_fatal_need_clone_id "pibox_qclone_delete"

    local qcl_img=`instance_disk "$id"`
    local qcl_dir=`dirname "$qcl_img"`

    if [ -f "$qcl_img" ]
    then
	[ -n "$quiet" ] ||
	    mesg "Deleting clone \"$qcl_dir/*\" (incl. backup image)"
	runcmd rm -f "$qcl_img" "$qcl_img".*
    fi

    rmdir "$qcl_dir" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Assemble QEMU starter command line arguments
# -----------------------------------------------------------------------------

pibox_ssh_forward () { # syntax: <instance>
    local port=`instance_ssh_port $1`
    local host=127.0.0.1
    [ -z "$PUBVNC" ] || host=
    echo tcp:$host:$port-:22
}

pibox_vnc_address () { # syntax: <instance>
    local host=127.0.0.1
    [ -z "$PUBVNC" ] || host=
    echo $host:${1:-0}
}

pibox_console () { # syntax: <instance>
    if [ -n "$CONSOLE" ]
    then
	echo stdio
    else
	local port=`instance_console_port $1`
	local host=127.0.0.1
	[ -z "$PUBVNC" ] || host=
	echo tcp:$host:$port,server,nowait
    fi
}

pibox_qemu_cmdline () {
    local cmdl="rw earlyprintk loglevel=8 console=ttyAMA0,115200"
    cmdl="$cmdl dwc_otg.lpm_enable=0 root=/dev/mmcblk0p2 rootdelay=1"

    echo "$cmdl"
}

pibox_qemu_args () { # syntax: <instance>
    local  id=${1:-0}
    local img=`instance_disk "$id"`
    local fmt=`expr "$img" : '.*\.\(.*\)'`

    local  user0=user,id=user0,ipv6=off
    user0=$user0,net=`    instance_wan_network "$id"`
    user0=$user0,hostfwd=`pibox_ssh_forward    "$id"`

    echo   -drive   "media=disk,if=sd,format=${fmt:-raw},file=$img"
    echo   -dtb     "$img.dtb"
    echo   -kernel  "$img.ker"
    echo   -vga     std

    [ -n "$QEMUGUI" ] ||
    echo   -vnc     `pibox_vnc_address "$id"`

    echo   -serial  `pibox_console "$id"`

    echo   -netdev  $user0
    echo   -netdev  tap,id=tap0,ifname=q0tap$id,script=no,downscript=no
    echo   -netdev  tap,id=tap1,ifname=q1tap$id,script=no,downscript=no
    echo   -usb
    echo   -device  usb-mouse
    echo   -device  usb-kbd
    echo   -device  usb-net,netdev=user0
    echo   -device  usb-net,netdev=tap0
    echo   -device  usb-net,netdev=tap1
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

verify_not_root_user

pibox_parse_options "$@"

pibox_debug_vardump

verify_required_commands
verify_important_commands
verify_qimage_symlink
verify_qimage_file_size

# -----------------------------------------------------------------------------
# Create clone
# -----------------------------------------------------------------------------

# need to create clone image on-the-fly
if [ 0 -lt "$QID" -a -n "$QPIRUN" ]
then
    pibox_qclone_exists_ok "$QID" ||
	NEWCLONE=set
fi

if [ -n "$NEWCLONE" ]
then
    create_while="Not cloning <0> creating <$QID> while"
    owrite_while="Not over-cloning <$QID> while"
    use_the_tool_luke="use \"pimage\" tool with --provide-qboot option"

    if qemu_instance_is_running_ok 0
    then
	croak "$create_while instance <0> is running"

    elif qroot_mount_is_active_rw_ok
    then
	croak "$create_while root directory \"$root_d\" is mounted"

    elif qemu_instance_is_running_ok $QID
    then
	croak "$owrite_while very clone instance is running"

    elif instance_bootp_signature_ok
    then
	pibox_qclone_create "$QID"
    else
	croak "Boot kernel needs update ($use_the_tool_luke)"
    fi

    # disable process display unless run mode
    [ -n "$QPIRUN" ] ||
	unset QPINFO
fi

# -----------------------------------------------------------------------------
# Run emulator
# -----------------------------------------------------------------------------

if [ -n "$QPIRUN" ]
then
    use_the_tool_luke="use \"pimage\" tool with --provide-qboot option"
    no_way_out="backup and re-create clone"

    if qemu_instance_is_running_ok $QID
    then
	mesg "Instance <$QID> is already running"

	# disable
	unset QPIRUN VNCRUN
	QSLEPTOK=set

    elif qroot_mount_is_active_rw_ok
    then
	croak "Cannot start while root directory \"$root_d\" is mounted"

    elif instance_bootp_files_ok "$QID"
    then
	if [ -n "$QIRFORCE" ]
	then
	    blurb="Skipping boot partition check for instance <$QID>"
	    warn "$blurb (as requested)"
	else
	    blurb="Boot partition for instance <$QID>"

	    if [ -n "$NOFATCAT" -o 0 -eq "$QID" ]
	    then
		pibox_qclone_boot_signature_ok "$QID" ||
		    croak "$blurb needs update ($use_the_tool_luke)"
	    else
		pibox_qclone_boot_signature_ok "$QID" ||
		    croak "$blurb was modified ($no_way_out)"
	    fi
	fi

	cmdl=`pibox_qemu_cmdline`
	args=`pibox_qemu_args "$QID"`

	# run in background unless console flag set
	if [ -n "$CONSOLE$RUNPFX" ]
	then
	    doadm_qemu_start3 -append "$cmdl" $args 3>&2

	elif $RUNPFX $SUDO true
	then
	    # allow sudo to cache connection so it can run in the background
	    if [ -n "$DEBUG" ]
	    then
		doadm_qemu_start3 -append "$cmdl" $args 3>&2 &
	    else
		doadm_qemu_start3 -append "$cmdl" $args 3>&2 >/dev/null 2>&1 &
	    fi
	else
	    unset VNCRUN
	fi
    else
	croak "Missing boot kernel ($use_the_tool_luke)"

	# disable
	unset QKILL VNCRUN QPINFO
    fi
fi

# -----------------------------------------------------------------------------
# Terminate current instance and unmount boot partition
# -----------------------------------------------------------------------------

if [ -n "$QKILL" ]
then
    pids=`qemu_instance_pids $QID`

    if [ -n "$pids" ]
    then
	doadm_qemu_kill $pids
    else
	mesg "Instance <$QID> is not running"
    fi
fi

# -----------------------------------------------------------------------------
# Start graphical interface for current instance
# -----------------------------------------------------------------------------

# only printing info if qemu runs in background or does not run at all
if [ -n "$VNCRUN" ]
then
    pibox_wait_for_qemu
    runcmd remote-viewer vnc://localhost:`instance_vnc_port $QID` &
fi

# -----------------------------------------------------------------------------
# Delete all clones in cache
# -----------------------------------------------------------------------------

if [ -n "$CCACHECLN" ]
then
    if qemu_instance_is_running_ok
    then
	moan="Cannot delete disk images"
	croak "$moan while some instances are running"
    else
	list=`instance_list_all`
	for id in `list_tail $list`
	do
	    pibox_qclone_delete "$id" $NOISY
	done

	unset QPINFO DELCLONE
    fi
fi

# -----------------------------------------------------------------------------
# Delete clone
# -----------------------------------------------------------------------------

if [ -n "$DELCLONE" ]
then
    if qemu_instance_is_running_ok "$QID"
    then
	moan="Cannot delete disk image"
	croak "$moan while very clone instance <$QID> is running"
    else
	pibox_qclone_delete "$QID" $NOISY
	unset QPINFO
    fi
fi

# -----------------------------------------------------------------------------
# List instances
# -----------------------------------------------------------------------------

if [ -n "$INSTINFO" ]
then
    fmt="%2s %10s  %-15s %-12s %-8s\n"

    echo
    printf "$fmt" id name lan/ip allocated active/pid
    echo "------------------------------------------------------------"

    for id in `instance_list_all`
    do
	pids=`qemu_instance_pids "$id"`
	name=`instance_to_name "$id"`
	img=`instance_disk "$id"`
	lip=`instance_lan_address "$id"`

	ikd=''
	if   [ -f "$img" -a -f "$img.ker" -a -f "$img.dtb" -a -f "$img.sig" ]
	then
	    ikd='   yes'
	elif [ -f "$img" -o -f "$img.ker" -o -f "$img.dtb" -o -f "$img.sig" ]
	then
	    ikd='partially(!)'
	fi

	pid=''
	if [ -n "$pids" ]
	then
	    pid=`echo -n $pids`
	fi

	printf "$fmt" "$id" "$name" "$lip" "$ikd" "$pid"
    done
    echo
fi

# -----------------------------------------------------------------------------
# Print info about current instance
# -----------------------------------------------------------------------------

# only printing info if qemu runs in background or does not run at all
if [ -n "$QPINFO" ]
then
    pibox_wait_for_qemu

    pids=`    qemu_instance_pids         "$QID"`
    con_port=`qemu_instance_console_port "$QID"`
    vnc_port=`qemu_instance_vnc_port     "$QID"`
    ssh_port=`instance_ssh_port          "$QID"`

    [ -z "$pids$vnc_port$con_port" ] ||
	echo

    [ -z "$pids" ] ||
	echo "Qemu pids:" $pids

    [ -z "$con_port" ] || {
	echo "Console:   netcat localhost $con_port"
	echo "           socat TCP:localhost:$con_port,nodelay stdio"
    }

    [ -z "$vnc_port" ] ||
	echo "Graphics:  remote-viewer vnc://localhost:$vnc_port"

    [ -z "$pids$vnc_port$con_port" ] || {
	echo "SSH:       ssh -p$ssh_port pi@localhost"
	echo
    }
fi

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

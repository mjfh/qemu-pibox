#! /bin/sh
#
# Manage network bridge for QEMU emulator
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
ARGSUSAGE="[options] [--]"

. $prefix/lib/variables.sh
. $prefix/lib/functions.sh
. $prefix/lib/sudo-bridge.sh

# Reset global variables
unset ADDBRIDGE RMBRIDGE OUTBOUND BRINFO

readonly short_stdopts="Ddvh"
readonly long_stdopts="dry-run,debug,verbose,help"

readonly bridge=q0br
readonly tappfx=q0tap

set +e

# -----------------------------------------------------------------------------
# Command line helper functions
# -----------------------------------------------------------------------------

pibridge_debug_vardump () {
    [ -z "$DEBUG" ] ||
	mesg `dump_vars \
	       HELP DEBUG NOISY RUNPFX OPTIONS \
	       ADDBRIDGE RMBRIDGE OUTBOUND BRINFO`
}

pibridge_info () {
    local qemu_cmd=`list_first $qemu_system_cmd`

    cat <<EOF

    This tool scans the network interface table on the host system for active
    virtual QEMU guest <lan> interfaces. Then the tool adds these interfaces to
    a bridge. Seen from a virtual guest, all active interfaces are connected.

    Additional non-virtual interfaces can be added to the bridge. If this is
    an outbound interface connected to <lan> interfaces of physical Raspberry
    PIs, these systems join the virtual network.

    Adminstator Privilege
      This tool uses "sudo" for executing "ip link" commands with administrator
      privileges, needed to set up administer the bridge.
EOF
}

pibridge_help () {
    echo "Virtual bridge setup"

    [ -z "$NOISY" ] ||
	pibridge_info

    disclaimer_once

    # use readonly for checking option letter uniqueness
    readonly _a="set up bridge for active virtual QEMU <lan> interfaces"
    readonly _A="remove virtual <lan> interfaces bridge"
    readonly _o="add non-virtual interface to bridge, implies --add-bridge"

    local n=18
    local f="%8s -%s, --%-${n}s -- %s\n"

    echo
    echo "Usage: $self $ARGSUSAGE"
    echo

    printf "$f" Options: b add-bridge         "$_a"
    printf "$f" ""       B remove-bridge      "$_A"
    printf "$f" ""       o outbound-interface "$_o"
    echo

    stdopts_help "$short_stdopts" "$n"

     [ -z "$NOISY" ] ||
	echo
    exit
}

pibridge_parse_options () {
    local so="${short_stdopts}bBo:"
    local lo="${long_stdopts},add-bridge,remove-bridge,outbound-interface:"

    getopt -Q -o "$so" -l "$lo" -n "$self" -s sh -- "$@" || usage
    eval set -- `getopt -o "$so" -l "$lo" -n"$self" -s sh -- "$@"`

    stdopts_filter "$@"
    eval set -- $OPTIONS
    unset ADDBRIDGE RMBRIDGE OUTBOUND

    # parse remaining option arguments
    while true
    do
	case "$1" in
	    -b|--add-bridge)         ADDBRIDGE=set; shift  ; continue ;;
	    -B|--remove-bridge)      RMBRIDGE=set ; shift  ; continue ;;
	    -o|--outbound-interface) OUTBOUND="$2"; shift 2; continue ;;

	    --)	shift; break ;;
	    *)	fatal "parse_options: unexpected case \"$1\""
	esac
    done

    [ -z "$HELP" ] ||
	pibridge_help

    [ 0 -eq $# ] ||
	usage "No more commands line arguments"

    # implied options for set expressions
    [ -z "$OUTBOUND"           ] || ADDBRIDGE=set

    # implied options for unset expressions
    [ -n "$RMBRIDGE" ] || BRINFO=set

    # imcompatible option combinations
    [ -z "$ADDBRIDGE" -o -z "$RMBRIDGE" ] ||
	usage "Incompatible options --add-bridge and --remove-bridge"
}

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

pibridge_print_router_address () {
    instance_lan_address 0 | sed 's|\.[0-9]*$|.1/24|'
}

pibridge_print_qemu_ifcs () {
    ip link show |
	awk '$2 ~ /^'"$tappfx"'[0-9][0-9]*:$/ {
                print substr ($2, 1, length ($2) - 1)
             }'
}

pibridge_print_bridged_ifcs () {
    ip link show |
	awk '/ master '"$bridge"' / && $2 ~ /:$/ {
	        print substr ($2, 1, length ($2) - 1)
	     }'
}

pibridge_print_bridged_or_qemu () {
    {
	pibridge_print_qemu_ifcs
	pibridge_print_bridged_ifcs
    } | sort -u
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

verify_not_root_user

pibridge_parse_options "$@"

pibridge_debug_vardump

verify_required_commands
verify_important_commands

# -----------------------------------------------------------------------------
# Create bridge
# -----------------------------------------------------------------------------

if [ -n "$ADDBRIDGE" ]
then
    # create bridge and take it up
    ip link show dev "$bridge" >/dev/null 2>&1 ||
	doadm_bridge_add "$bridge"
    doadm_interface_up "$bridge"

    # add virtual TAP interfaces to the bridge
    ifc_list=`pibridge_print_qemu_ifcs`
    for ifc in $ifc_list
    do
	doadm_interface_up                   "$ifc"
	doadm_bridge_add_interface "$bridge" "$ifc"
    done

    # add additional interface
    [ -z "$OUTBOUND" ] ||
	doadm_bridge_add_interface "$bridge" "$OUTBOUND"
fi

# -----------------------------------------------------------------------------
# Remove bridge
# -----------------------------------------------------------------------------

if [ -n "$RMBRIDGE" ]
then
    doadm_bridge_flush "$bridge"
fi

# -----------------------------------------------------------------------------
# List bridge interfaces
# -----------------------------------------------------------------------------

if [ -n "$BRINFO" ]
then
    fmt="%2s %10s  %-13s %-10s %7s %8s %s\n"

    echo
    printf "$fmt" id name lan/ip interface virtual bridged " up"
    echo --------------------------------------------------------------

    ifc_list=`pibridge_print_bridged_or_qemu`
    for ifc in $ifc_list
    do
	vok=no
	vid=
	vname=
	vip=
	case "$ifc" in
	    $tappfx*)
		vok=yes
		vid=`expr "$ifc" : "$tappfx\(.*\)"`
		vname=`instance_to_name "$vid"`
		vip=`instance_lan_address "$id"`
	esac

	brok=yes
	ip link show dev "$ifc" | grep -q " master $bridge " || {
	    brok=no
	    vip=
	}

	up=yes
	ip link show dev "$ifc" | grep -q ',LOWER_UP' || {
	    up=no
	    vip=
	}

	printf "$fmt" "$vid" "$vname" "$vip" " $ifc" "$vok  " "$brok  " "$up"
    done
    echo
fi

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

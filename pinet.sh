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
unset ADDBRIDGE RMBRIDGE OUTBOUND INBOUND BRINFO

readonly short_stdopts="Ddvh"
readonly long_stdopts="dry-run,debug,verbose,help"

readonly bridge=q0br
readonly tappfx=q0tap
readonly wlanpfx=q1tap

set +e

# -----------------------------------------------------------------------------
# Command line helper functions
# -----------------------------------------------------------------------------

pinet_debug_vardump () {
    [ -z "$DEBUG" ] ||
	mesg `dump_vars \
	       HELP DEBUG NOISY RUNPFX OPTIONS \
	       ADDBRIDGE RMBRIDGE OUTBOUND INBOUND BRINFO`
}

pinet_info () {
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
      privileges, needed to set up and administer the bridge.

      Using the options --router-interface, --wlan-activate, ot --wlan-remove,
      the "ip addr" command is run with administrator privileges via "sudo".
EOF
}

pinet_help () {
    echo "Virtual bridged network setup"

    [ -z "$NOISY" ] ||
	pinet_info

    disclaimer_once

    local cmdl_arg="use particular WLAN instance"
    local      _fi="for instance <id>"

    # use readonly for checking option letter uniqueness
    readonly _a="set up bridge for active virtual QEMU <lan> interfaces"
    readonly _A="remove virtual <lan> interfaces bridge"
    readonly _o="add non-virtual interface to bridge, implies --add-bridge"
    readonly _r="add ip address to bridge, implies --add-bridge"
    readonly _w="add ip address to host end of WLAN interface $_fi"
    readonly _W="flush ip addresses from all host ends of WLAN interfaces"

    local n=18
    local f="%8s -%s, --%-${n}s -- %s\n"

    echo
    echo "Usage: $self $ARGSUSAGE"
    echo
    echo "Instance: <id> or <alias>         -- $cmdl_arg"
    echo

    printf "$f" Options: b add-bridge         "$_a"
    printf "$f" ""       B remove-bridge      "$_A"
    printf "$f" ""       r router-interface   "$_r"
    printf "$f" ""       o outbound-interface "$_o"
    echo
    printf "$f" ""       w wlan-activate      "$_w"
    printf "$f" ""       W wlan-remove        "$_W"
    echo

    stdopts_help "$short_stdopts" "$n"

     [ -z "$NOISY" ] ||
	echo
    exit
}

pinet_parse_options () {
    local so="${short_stdopts}bBo:rwW"
    local lo="${long_stdopts},add-bridge,remove-bridge"

    lo="${lo},outbound-interface:,router-interface"
    lo="${lo},wlan-activate,wlan-remove"

    getopt -Q -o "$so" -l "$lo" -n "$self" -s sh -- "$@" || usage
    eval set -- `getopt -o "$so" -l "$lo" -n"$self" -s sh -- "$@"`

    stdopts_filter "$@"
    eval set -- $OPTIONS

    # parse remaining option arguments
    while true
    do
	case "$1" in
	    -b|--add-bridge)         ADDBRIDGE=set; shift  ; continue ;;
	    -B|--remove-bridge)      RMBRIDGE=set ; shift  ; continue ;;
	    -o|--outbound-interface) OUTBOUND="$2"; shift 2; continue ;;
	    -r|--router-interface)   INBOUND=set  ; shift  ; continue ;;

	    -w|--wlan-activate)      WLANON=set   ; shift  ; continue ;;
	    -W|--wlan-remove)        WLANOFF=set  ; shift  ; continue ;;

	    --)	shift; break ;;
	    *)	fatal "parse_options: unexpected case \"$1\""
	esac
    done

    [ -z "$HELP" ] ||
	pinet_help

    # [ 0 -eq $# ] ||
    #	usage "No more commands line arguments"

    # set QID variable
    verify_set_instance "$@"

    # implied options for set expressions
    [ -z "$OUTBOUND$INBOUND" ] || ADDBRIDGE=set

    # implied options for unset expressions
    [ -n "$RMBRIDGE$WLANON$WLANOFF" ] || BRINFO=set

    # imcompatible option combinations
    [ -z "$ADDBRIDGE" -o -z "$RMBRIDGE" ] ||
	usage "Incompatible options --add-bridge and --remove-bridge"

    [ -z "$WLANON" -o -z "$WLANOFF" ] ||
	usage "Incompatible options --wlan-activate and --wlan-remove"

    [ -z "$WLANON" -o 0 -lt $# ] ||
	usage "Option --wlan-activate requries instance argument"

    [ -n "$WLANON" -o 0 -eq $# ] ||
	usage "Unsupported instance argument <$QID> without option"
}

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

pinet_print_wlan_address () {
    awk '$1 == "address" && $2 ~ /^[0-9./]*$/ {
	    split ($2, ip, ".")
            split (ip [4], wd, "/")
            ip4 = wd [1] == 1 ? 2 : 1
            print ip [1] "." ip [2] "." ip [3] "." ip4 "/" wd [2]
	 }' "$raspios_base_d/etc/network/interfaces.d/wlan"
}

pinet_print_wlan_ifcs () {
    ip link show |
	awk '$2 ~ /^'"$wlanpfx"'[0-9][0-9]*:$/ {
                print substr ($2, 1, length ($2) - 1)
             }'
}

pinet_flush_wlan_ifcs () {
    local ifc=
    for ifc in `pinet_print_wlan_ifcs`
    do
	doadm_interface_flush_ip "$ifc"
    done
}

pinet_print_router_address () {
    instance_lan_address "$id" | sed 's|\.[0-9]*$|.1/24|'
}

pinet_print_qemu_ifcs () {
    ip link show |
	awk '$2 ~ /^'"$tappfx"'[0-9][0-9]*:$/ {
                print substr ($2, 1, length ($2) - 1)
             }'
}

pinet_print_bridged_ifcs () {
    ip link show |
	awk '/ master '"$bridge"' / && $2 ~ /:$/ {
	        print substr ($2, 1, length ($2) - 1)
	     }'
}

pinet_print_bridged_or_qemu () {
    {
	pinet_print_qemu_ifcs
	pinet_print_bridged_ifcs
    } | sort -u
}

# print first ifc
pinet_print_ifc_ip () { # syntax: <interface>
    local ifc="$1"
    ip addr show dev "$ifc" | sort |
	awk '$1 == "inet" {
                 split ($2, ip, "/")
                 print ip [1]
		 exit
             }'
}

pinet_ifexists_ok () { # syntax: <interface>
    local ifc="$1"
    ip link show dev "$ifc" >/dev/null 2>&1
}

pinet_ifip_ok () { # syntax: <interface> <ip>
    local ifc="$1"
    local  ip="$2"
    ip addr show dev "$ifc" | grep -q "$ip"
}

pinet_ifup_ok () { # syntax: <interface>
    local ifc="$1"
    ip link show dev "$ifc" | grep -q ',LOWER_UP'
}

pinet_bridged_ok () { # syntax: <interface> <bridge>
    local ifc="$1"
    local  br="$2"
    ip link show dev "$ifc" | grep -q " master $br "
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

verify_not_root_user

pinet_parse_options "$@"

pinet_debug_vardump

verify_required_commands
verify_important_commands

# -----------------------------------------------------------------------------
# Add WLAN ip address
# -----------------------------------------------------------------------------

if [ -n "$WLANON" ]
then
    wifc="$wlanpfx$QID"

    if pinet_ifexists_ok "$wifc"
    then
	pinet_flush_wlan_ifcs

	ipw=`pinet_print_wlan_address`

	doadm_interface_up     "$wifc"
	doadm_interface_add_ip "$wifc" "$ipw"
    else
	croak "Cannot access WLAN interface \"$wifc\" for instance <$QID>"
    fi
fi

# -----------------------------------------------------------------------------
# Flush WLAN ip address
# -----------------------------------------------------------------------------

if [ -n "$WLANOFF" ]
then
    pinet_flush_wlan_ifcs
fi

# -----------------------------------------------------------------------------
# Create bridge
# -----------------------------------------------------------------------------

if [ -n "$ADDBRIDGE" ]
then
    # create bridge and take it up
    ip link show dev "$bridge" >/dev/null 2>&1 ||
	doadm_bridge_add "$bridge"
    doadm_interface_up "$bridge"

    if [ -n "$INBOUND" ]
    then
	ipw=`pinet_print_router_address`

	ip addr show dev "$bridge" | grep -q "$ipw" ||
	    doadm_interface_add_ip "$bridge" "$ipw"
    fi

    # add virtual TAP interfaces to the bridge
    ifc_list=`pinet_print_qemu_ifcs`
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
    if pinet_ifexists_ok "$bridge"
    then
	doadm_bridge_flush "$bridge"
    fi
fi

# -----------------------------------------------------------------------------
# List bridge interfaces
# -----------------------------------------------------------------------------

if [ -n "$BRINFO" ]
then
    ipw=`pinet_print_wlan_address`
    fmt="%2s %10s  %-13s %-10s %-4s  %7s %8s %s\n"

    echo
    printf "$fmt" id name lan/ip interface " wlan" virtual bridged " up"
    echo --------------------------------------------------------------------

    if pinet_ifexists_ok "$bridge"
    then
	ipa=`pinet_print_ifc_ip "$bridge"`

	if pinet_ifup_ok "$bridge"
	then
	    up=yes
	else
	    up=no
	fi

	printf "$fmt" \
	       "" bridge "$ipa" " $bridge" "" "no  " "" " $up"
    fi

    ifc_list=`pinet_print_bridged_or_qemu`
    for ifc in $ifc_list
    do
	vok=no
	vid=
	vname=
	ipa=
	wif=
	case "$ifc" in
	    $tappfx*)
		vok=yes
		vid=`expr "$ifc" : "$tappfx\(.*\)"`
		vname=`instance_to_name "$vid"`
		ipa=`instance_lan_address "$vid"`
		wif=`echo "$ifc" | sed "s/^$tappfx/$wlanpfx/"`
		;;
	    *)	ipa=`pinet_print_ifc_ip "$ifc"`
	esac

	if pinet_bridged_ok "$ifc" "$bridge"
	then
	    brok=yes
	else
	    brok=no
	fi

	if pinet_ifup_ok "$ifc"
	then
	    up=yes
	else
	    up=no
	    vip=
	fi

	if [ -n "$wif" ] && pinet_ifip_ok "$wif" "$ipw"
	then
	    wok=yes
	else
	    wok=
	fi

	printf "$fmt" \
	       "$vid" "$vname"    "$ipa"  " $ifc" " $wok" \
	       "$vok  " "$brok  " " $up"
    done
    echo
fi

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

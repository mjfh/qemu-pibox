#! /bin/sh
#
# no need to make this file executable
#

# Include core init functions
. /lib/lsb/init-functions

# -----------------------------------------------------------------------------
# Force fancy terminal output
# -----------------------------------------------------------------------------

export TERM=linux-basic
export TPUT=/usr/bin/tput

# this function overwrites the one from the /lib/lsb/init-functions library
log_use_fancy_output () {
    true
}

# -----------------------------------------------------------------------------
# Generic system helpers
# -----------------------------------------------------------------------------

export MISSING_LOG=/tmp/missing-apt-package

clear_missing_log () {
    rm -f "$MISSING_LOG"
}

apt_missing_log_file () {
    [ ! -s "$MISSING_LOG" ] || echo "$MISSING_LOG"
}

required_command () { # syntax: <cmd> [<package>]
    _cmd="$1"
    _pkg="${2:-$_cmd}"

    which $_cmd >/dev/null || {
	[ -f "$MISSING_LOG" ] || sleep 3
	echo "$_cmd => $_pkg" >> "$MISSING_LOG"

	log_failure_msg "Missing \"$_cmd\" command (pkg \"$_pkg\")"
    }
}

# take the red pill and check whether we are running in the matrix
redpill_ok () {
    grep '^QEMU$' /sys/bus/usb/devices/1-1/manufacturer >/dev/null 2>&1
}

first_item () { # syntax: <arg1> <arg2> .. -> <arg1>
    echo "$1"
}

shift_list () { # syntax: <arg1> <arg2> .. -> <arg2> ..
    shift
    echo "$@"
}

# -----------------------------------------------------------------------------
# Services management helpers
# -----------------------------------------------------------------------------

disable_services () { # syntax: <service> ...
    for svc
    do
	if systemctl is-enabled $svc >/dev/null
	then
	    log_action_begin_msg "Disabling $svc"
	    systemctl disable $svc
	    log_action_end_msg $?
	fi
    done
}

enable_services () { # syntax: <service> ...
    for svc
    do
	case `systemctl is-enabled $svc` in
	    enabled*)
		continue
		;;
	    masked*)
		log_action_begin_msg "Unmasking and enabling $svc"
		systemctl unmask $svc
		;;
	    *)
		log_action_begin_msg "Enabling $svc"
	esac

	systemctl enable $svc
	log_action_end_msg $?
    done
}

start_services () { # syntax: <service> ...
    for svc
    do
	systemctl is-active $svc || {
	    enable_services $svc
	    systemctl start $svc
	}
    done
}

# -----------------------------------------------------------------------------
# Helpers managing network interfaces
# -----------------------------------------------------------------------------

# list of available interfaces to be used with ifrename_setup()
available_interfaces () {
    ip link show |
	awk '/^[0-9][0-9]*: / && $2 != "lo:" {
	        print substr ($2, 1, length ($2) - 1)
	     }'
}

# set up interface
ifrename_setup () { # syntax: <target> <src>
    trg=$1
    src=$2

    log_action_begin_msg "Rename $src to $trg"
    if ifrename -i $src -n $trg >/dev/null
    then
	log_action_cont_msg "link layer"
	if ip link set dev $trg up
	then
	    log_action_cont_msg "take it up"
	    $TPUT sc
	    ifup --force $trg >/dev/null 2>&1
	    $TPUT rc
	fi
    fi

    log_action_end_msg $?
}

# -----------------------------------------------------------------------------
# Helpers managing IP addresses, node IDs, network interfaces
# -----------------------------------------------------------------------------

# extract IP address from configured argument interface
ip_address () { # syntax: <interface>
    ip addr show dev $1 2>/dev/null |
	awk '$1 == "inet" {
		print substr ($2, 1, index ($2, "/") - 1)
		exit
	     }'
}

# get node ID associated with the argument IP address
node_id () { # syntax: <ip-address>
    awk 'BEGIN {
	    nid = 0
	 }
	 $1 == "'"$1"'" && $2 ~ /^n[0-9][0-9]*\.[lw]an$/ {
	    nid = substr ($2, 2, length ($2) - 5)
	    exit
	 }
	 END {
	    print nid
	 }' /etc/hosts
}

# get IP addess associated with the argument node ID and suffix
node_addr () { # syntax: <suffix> <node-id>
    awk '$2 == "n'"$2"'.'"$1"'" {
	    nid = $1
	    exit
	 }
	 $2 == "n0.lan" {
	    nid = $1
	 }
	 END {
	    print nid
	}' /etc/hosts
}

node_mac () { # syntax: <node-id>
    lla=`printf "b8:27:eb:00:00:%02x" "$1"`
    awk 'BEGIN {
            lladdr = "'"$lla"'"
         }
	 $1 == "lan'"$1"'" && $2 == "mac" {
            lladdr = $3
            exit
        }
        END {
            print lladdr
	}' /etc/iftab
}

# get host name associated with the argument node ID
host_name () { # syntax: <node-id>
    awk 'BEGIN {
	    hostname = "loner"
	 }
	 $2 == "n'"$1"'.lan" && 2 < NF {
	     hostname = $3
	     exit
	 }
	 END {
	    print hostname
	}' /etc/hosts
}

# get least interface instance associated with argument prefix
interface_nid () { # syntax: <interface-prefix>
    ip link show |
	awk '/^[0-9][0-9]*: / && $2 ~ /^'"$1"'/ {
		pos = length ("'"$1"'") + 1
		print substr ($2, pos, length ($2) - pos)
	     }
	     END {
		if (!pos) print 0
	     }' |
	sort -n |
	sed q
}

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

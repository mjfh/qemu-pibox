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
# QEMU emulator start/stop control
# -----------------------------------------------------------------------------

doadm_qemu_start3 () { # syntax: <kernel-cmdline> <args> ...
                       # NOISY start message on channel 3
    local args=`list_quote "$@"`

    [ -z "$NOISY" ] ||
	echo '+' $RUNPFX $SUDO $qemu_system_cmd "$args" >&3

    if [ sudo = "$SUDO" ] || flag_is_yes ${SUDO_UNQOTED_ARGS:-yes}
    then
	# vanilla sudo
	$RUNPFX $SUDO $qemu_system_cmd "$@"
    else
	# applies to something like: ssh -X root@localhost
	$RUNPFX $SUDO $qemu_system_cmd "$args"
    fi
}

doadm_qemu_kill () { # syntax: <pid> ... # start message on channel 3
    local pids="$*"

    [ -n "$pids" ] ||
	return

    # double check PIDs: commands to terminate must start with this text
    local cpfx="$qemu_system_cmd "

    local p
    for p in $pids
    do
	# extract full command for this PID
	local cmd=`ps ocommand xq "$p" --no-headers 2>/dev/null`

	# accept PID if command starts with $cpfx"
	case "$cmd" in "$cpfx"*|"$SUDO $cpfx"*) continue; esac

	if [ -n "$cmd" ]
	then
	    fatal "Must not terminate pid=$p: $cmd"
	else
	    fatal "No such process to terminate: pid=$p"
	fi
    done

    [ -n "$NOISY" ] ||
	mesg Terminating $pids

    ([ -z "$NOISY" ] || set -x;	$RUNPFX $SUDO kill -TERM $pids)
}

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

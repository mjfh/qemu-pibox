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
# Managing network bridhe commands
# -----------------------------------------------------------------------------

doadm_bridge_add () { # syntax: <bridge>
    local br="$1"

    ([ -z "$NOISY" ] || set -x;

     $RUNPFX $SUDO ip link add name "$br" type bridge)
}

doadm_bridge_flush () { # syntax: <bridge>
    local br="$1"

    ([ -z "$NOISY" ] || set -x;

     # actually, the "type bridge" arguments are not really necessary
     $RUNPFX $SUDO ip link del name "$br" type bridge)
}

doadm_interface_up () { # syntax: <interface>
    local ifc="$1"

    ([ -z "$NOISY" ] || set -x;

     $RUNPFX $SUDO ip link set "$ifc" up)
}

doadm_bridge_add_interface () { # syntax: <bridge> <interface>
    local  br="$1"
    local ifc="$2"

    ([ -z "$NOISY" ] || set -x;

     $RUNPFX $SUDO ip link set "$ifc" master "$br")
}

doadm_interface_add_ip () { # syntax: <interface> <ip/width>
    local ifc="$1"
    local ipw="$2"

    ([ -z "$NOISY" ] || set -x;

     $RUNPFX $SUDO ip addr add "$ipw" dev "$ifc")
}

doadm_interface_flush_ip () { # syntax: <interface>
    local ifc="$1"

    ([ -z "$NOISY" ] || set -x;

     $RUNPFX $SUDO ip addr flush dev "$ifc")
}

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

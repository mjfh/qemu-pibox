#! /bin/sh
#
# Manage RaspiOS raw disk image for Raspberry PI emulator
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

# Reset global variables
unset ISSHPUB IBASEFS SSHPUBKEY SHUTDOWN PIPWDUSED SSHENACON
unset E2FSEXP ENROLGST APTUPDG SHOWSTAT LOCALCNF USERADD USUDOOK
unset DOSOFTW NOSUDODWN

readonly short_stdopts="Ddvh"
readonly long_stdopts="dry-run,debug,verbose,help"

readonly sxx_opts="-oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=ERROR"
readonly sxx_nopw="-oPasswordAuthentication=no"
readonly sxx_batch="-oBatchMode=yes"

readonly ssh_pwok="ssh -t $sxx_opts"
readonly ssh_term="ssh -t $sxx_opts $sxx_nopw"
readonly ssh_batch="ssh   $sxx_opts $sxx_nop $sxx_batch"
readonly scp_nopw="scp    $sxx_opts $sxx_nop $sxx_batch"

set +e

# ----------------------------------------------------------------------------
# Command line helper functions
# ----------------------------------------------------------------------------

pijack_debug_vardump () {
    [ -z "$DEBUG" ] ||
	mesg `dump_vars \
		QID HELP DEBUG NOISY RUNPFX QIMAGE OPTIONS \
		ISSHPUB IBASEFS SSHPUBKEY SHUTDOWN PIPWDUSED SSHENACON \
		E2FSEXP ENROLGST APTUPDG SHOWSTAT LOCALCNF USERADD USUDOOK \
		DOSOFTW NOSUDODWN`
}

setup_info () {
    cat <<EOF

  The tool manages a running virtual QEMU guest instance via IP network
  connection for console or SSH. Administrative commands are typically sent
  to the guest instance via SSH, authenticated by the command user's public
  key. The tool can hijack the guest instance via console login and prepare
  it for SSH with public key authentication.

  Adminstator Privilege
    None needed for this tool although the shutdown procedure will invoke
    "pibox" with the --terminate option which uses \"sudo\". For convenience,
    the --shutdown option of this tool preempts with \"sudo\" so there will
    be no password request when "pibox" is started later.

  Prerequisites
    Use some newer RaspiOS. Crucial detail is the preset password for the
    "pi" user account (assumed to be "raspberry") and its ability to execute
    "sudo" without entering a password.

  Preparing for remote administration
    Start a guest instance with the virtual machine host manager tool

      sh pibox.sh --run

    and wait for the system to come up (e.g. the VNC GUI shows a login prompt
    or a graphical dektop session.) Then run

      sh $self.sh --enrol

    The "$self" tool will login via the TCP command console and enable the SSH
    server. Then the tool will install SSH public keys and expand the root file
    system so it uses all of the partition. Finally, some boot scripts are
    installed to be run under "rc.local" control. The virtual QEMU guest can
    now be accessed via

      ssh -p5700 pi@localhost

    or

      ssh -p5700 root@localhost

    When ready, terminate the virtual QEMU guest with

      sh $self.sh --shutdown

    and wait for the toot to report that the system has terminated.

  Notes on software update
    With the --software-update option, this tool will install boot scripts on
    the guest system and start a system upgrade via APT. The latter action
    requires Internet access for the user's host system.

    Most certainly, the system upgrade will install a new kernel on the guest
    system which differs from the kernel used by QEMU. The guest instance will
    not re-start after shutdown until this is fixed using the "pimage" tool
    with the --provide-qboot option.

    The installed boot scripts on the guest system will initialise and name
    the network interfaces according to the configuration in "/etc/hosts". The
    way how to do that as a virtual QEMU guest differs considerably from the
    set up on a real Raspberry PI box. So, after installing or change between
    QEMU and hardware box there should be an extra boot-shutdown cycle for
    switching.

  Notes on creating a user account
    With the --useradd option, a system wide virtual guest account will be set
    up. The account is accessible from the QEMU host's user public SSH key.
    Between instances, the virtual guest uses its own public key to access the
    same account on another instance.
EOF
}

setup_help () {
    echo "Virtual guest manager"

    [ -z "$NOISY" ] ||
	setup_info

    disclaimer_once

    # use readonly for checking option letter uniqueness
    readonly __="use argument instance rather than base image"
    readonly _k="install users's public key on \"pi\" and \"root\" account"
    readonly _e="explicitely enable SSH via console login"
    readonly _x="expand virtual guest file system to use all of partition"
    readonly _E="shortcut for all of the three options above"

    readonly _b="install base system configuration and boot scripts"
    readonly _l="install application software file system"
    readonly _p="update RaspiOS on <0> instance (needs Internet on host)"
    readonly _W="shortcut for all of the three options above"

    readonly _U="create/update user account, access with SSH pubkey only"
    readonly _w="allow \"sudo\" from user account, combine with --useradd"
    readonly _s="send shutdown command and wait for inactivity"
    readonly _S="no preemptive \"sudo\", implies --shutdown"

    echo
    echo "Usage: $self $ARGSUSAGE"
    echo

    local n=15
    local f="%8s -%s, --%-${n}s -- %s\n"

    printf "$f" Options: e enable-ssh       "$_e"
    printf "$f" ""       k ssh-authkeys     "$_k"
    printf "$f" ""       x expand-filesys   "$_x"
    printf "$f" ""       E enrol            "$_E"
    echo
    printf "$f" ""       b base-system      "$_b"
    printf "$f" ""       p update-primary   "$_p"
    printf "$f" ""       l local-software   "$_l"
    printf "$f" ""       W software-update  "$_W"
    echo
    printf "$f" ""       u useradd=NAME     "$_U"
    printf "$f" ""       w sudo-user-ok     "$_w"
    echo
    printf "$f" ""       s shutdown         "$_s"
    printf "$f" ""       S raw-shutdown     "$_S"
    echo

    stdopts_help "$short_stdopts" "$n"

    [ -z "$NOISY" ] ||
	echo
    exit
}

setup_parse_options () {
    local so="${short_stdopts}ekxEblpWu:wsS"
    local lo="${long_stdopts},enable-ssh,ssh-authkey,expand-filesys"

    lo="${lo},enrol,base-system,local-software,update-primary"
    lo="${lo},software-update,useradd:,sudo-user-ok,shutdown"
    lo="${lo},raw-shutdown"

    getopt -Q -o "$so" -l "$lo" -n "$self" -s sh -- "$@" || usage
    eval set -- `getopt -o "$so" -l "$lo" -n"$self" -s sh -- "$@"`

    stdopts_filter "$@"
    eval set -- $OPTIONS

    local noshowstat=

    # option arguments
    while true
    do
	case "$1" in
	    -e|--enable-ssh)	  SSHENACON=set; shift  ; continue ;;
	    -k|--ssh-authkeys)	  ISSHPUB=set  ; shift  ; continue ;;
	    -x|--expand-filesys)  E2FSEXP=set  ; shift  ; continue ;;
	    -E|--enrol)	          ENROLGST=set ; shift  ; continue ;;

	    -b|--base-system)	  IBASEFS=set  ; shift  ; continue ;;
	    -l|--local-software)  LOCALCNF=set ; shift  ; continue ;;
	    -p|--update-primary)  APTUPDG=set  ; shift  ; continue ;;
	    -W|--software-update) DOSOFTW=set  ; shift  ; continue ;;

	    -u|--useradd)         USERADD="$2" ; shift 2; continue ;;
	    -w|--sudo-ok)         USUDOOK=set  ; shift  ; continue ;;

	    -s|--shutdown)	  SHUTDOWN=set ; shift  ; continue ;;
	    -S|--raw-shutdown)    NOSUDODWN=set; shift  ; continue ;;

	    --)	shift; break ;;
	    *)	fatal "parse_options: unexpected case \"$1\""
	esac
    done

    [ -z "$HELP" ] ||
	setup_help

    verify_set_instance "$@"

    # implied options for set expressions
    [ -z "$NOSUDODWN"  ] || SHUTDOWN=set

    [ -z "$ENROLGST"   ] || ISSHPUB=set
    [ -z "$ENROLGST"   ] || SSHENACON=set
    [ -z "$ENROLGST"   ] || E2FSEXP=set

    [ -z "$DOSOFTW"    ] || IBASEFS=set
    [ -z "$DOSOFTW"    ] || LOCALCNF=set
    [ -z "$DOSOFTW"    ] || APTUPDG=set

    [ -z "$IBASEFS"    ] || noshowstat=set
    [ -z "$ISSHPUB"    ] || noshowstat=set
    [ -z "$SSHENACON"  ] || noshowstat=set
    [ -z "$E2FSEXP"    ] || noshowstat=set
    [ -z "$APTUPDG"    ] || noshowstat=set
    [ -z "$SHUTDOWN"   ] || noshowstat=set
    [ -z "$LOCALCNF"   ] || noshowstat=set
    [ -z "$USERADD"    ] || noshowstat=set

    # implied options for unset expressions
    [ -n "$noshowstat" ] || SHOWSTAT=set

    # imcompatible option combinations
    [ -z "$USUDOOK" -o -n "$USERADD" ] ||
	usage "Option --sudo-ok needs --useradd=NAME option"
    [ -z "$APTUPDG" -o 0 -eq "$QID" ] ||
	usage "Option --update-primary applies to the <0> instance, only"
}

# ----------------------------------------------------------------------------
# Test and verify port availability
# ----------------------------------------------------------------------------

pijack_console_available_ok () {
    local port=`instance_console_port "$QID"`
    socat - TCP:localhost:$port,connect-timeout=5 </dev/null >/dev/null 2>&1
}

pijack_ssh_available_ok () {
    local port=`instance_ssh_port "$QID"`
    socat - TCP:localhost:$port,connect-timeout=5 </dev/null >/dev/null 2>&1
}

pijack_verify_console_available () {
    pijack_console_available_ok || {
	local port=`instance_console_port "$QID"`
	croak "Console port $port for instance <$QID> is not accessible"
    }
}

pijack_verify_ssh_available () {
    pijack_ssh_available_ok || {
	local port=`instance_ssh_port "$QID"`
	croak "SSH port $port for instance <$QID> is not accessible"
    }
}

# -----------------------------------------------------------------------------
# Hijack system by logging into the TCP console
# -----------------------------------------------------------------------------

pijack_console_dialer_script () { # syntax: <username> <password>
    local  usn="${1:-pi}"
    local  pwd="${2:-raspberry}"

    local    WS='\\\\s'
    local    NL='\\\\n'
    local    RC='RC$?'
    local   PFX="${WS}${WS}${WS}${WS}$self:${WS}"
    local START="systemctl${WS}enable${WS}ssh;systemctl${WS}start${WS}ssh"

    {
	cat <<EOF
          TIMEOUT      5
          ogin:--ogin: $usn
          assword:     $pwd
          SAY          ${PFX}Login${WS}on${WS}instance$WS<$QID>${WS}console$NL
          TIMEOUT      30
          $usn@        sudo${WS}-s
          SAY          ${PFX}Enable${WS}SSH$NL
          $usn#        ${START};exit
          TIMEOUT      40
          $usn@        systemctl${WS}is-enabled${WS}ssh;echo$WS$RC
          TIMEOUT      10
          RC0          exit
          SAY          ${PFX}Confirmed$NL
          TIMEOUT      20
          ogin:--ogin:
EOF
    } | tr '\n' ' ' | sed 's/  */ /g'
}

pijack_console_enable_ssh_ok () { # syntax: <username> <password>
    local dial=`pijack_console_dialer_script "$@"`
    local port=`instance_console_port "$QID"`
    local  tcp="TCP:localhost:$port,crlf,connect-timeout=5,nodelay"
    local  cmd="$CHAT -s${DEBUG:+v}"

    # test port and exit any open session
    (echo "exit;exit")|socat -  "$tcp" >/dev/null 2>&1 ||
	croak "Console port $port for instance $QID is not accessible"

    # run the dial script
    if [ -n "$DEBUG" ]
    then
	runcmd socat -T50 "$tcp" "exec:$cmd '$dial'",pty,echo=0,cr
    else
	runcmd socat -T50 "$tcp" "exec:$cmd '$dial'",pty,echo=0,cr >/dev/null
    fi
    local rc=$?

    # leave console in proper state
    (echo "exit;exit")|socat - "$tcp" >/dev/null 2>&1

    return $rc
}

# -----------------------------------------------------------------------------
# Hijack system by installing user's SSH public key for authentication
# -----------------------------------------------------------------------------

pijack_verify_ssh_pubkey () {
    local pub_file
    for pub_file in ~/.ssh/id_*.pub
    do
	[ -s "$pub_file" ] ||
	    continue
	SSHPUBKEY=`cat "$pub_file"`
	return
    done

    fatal "No SSH public key available for \"`id -nu`\""
}

pijack_verify_setup_sshauth () { # synlax: <pi-passwords> ...
    local pwd_list="$*"
    local     port=`instance_ssh_port "$QID"`

    pijack_verify_ssh_pubkey ## => SSHPUBKEY
    local cmd="grep -qs '^$SSHPUBKEY' ~/.ssh/authorized_keys || (
		 umask 077;
		 mkdir -p ~/.ssh;
		 echo '$SSHPUBKEY' >> ~/.ssh/authorized_keys;
	       )"

    # ----------------------------------
    # Install public key on "pi" account
    # ----------------------------------
    (
	pwd_setup="$ssh_pwok -p$port pi@localhost /bin/sh"

	# The FOR loop below runs in a sub-shell. So the EXIT directive can
	# be used to emulate a try/catch linke scenario.
	for pwd in $pwd_list
	do
	    # exit block with OK if the setup comand succeeds
	    runcmd echo "$cmd" | runcmd sshpass -p$pwd $pwd_setup && exit

	    [ -z "$NOISY" ] ||
		mesg "Password \"$pwd\" failed for ssh://pi@localhost"
	done

	# all passwords in FOR loop have been exhausted
	false
    ) || croak "Could not enrol instance <$QID>"

    # ------------------------------------
    # Install public key on "root" account
    # ------------------------------------

    local pi_error="Key based enrolment failed for ssh://pi@localhost"
    local pi_setup="$ssh_batch -p$port pi@localhost sudo -H /bin/sh"

    # Hijack "root" account by escalating from "pi" account.
    runcmd echo "$cmd" |
	if [ -n "$DEBUG" ]
	then
	    runcmd $pi_setup ||
		croak "$pi_error"
	else
	    runcmd3 $pi_setup 3>&2 >/dev/null 2>&1 ||
		croak "$pi_error"
	fi

    # ------------------------------------
    # Verify root access
    # ------------------------------------

    local root_error="Key based enrolment failed for ssh://root@localhost"
    local root_setup="$ssh_batch -p$port root@localhost true"
    if [ -n "$DEBUG" ]
    then
	runcmd $root_setup ||
	    croak "$root_error"
    else
	runcmd3 $root_setup 3>&2 >/dev/null 2>&1 ||
	    croak "$root_error"
    fi
}

# -----------------------------------------------------------------------------
# Remote shutdown support
# -----------------------------------------------------------------------------

pijack_verify_ssh_shutdown () { # syntax: <secs>
    local    secs="${1:-10}"
    local    port=`instance_ssh_port "$QID"`
    local run_ssh="$ssh_batch -oConnectTimeout=5 -p$port root@localhost"
    local     cmd="echo 'sleep 1;halt' | nohup /bin/sh >/dev/null 2>&1 &"

    if [ -n "$DEBUG" ]
    then
	runcmd $run_ssh "$cmd" ||
	    croak "Failed to invoke shutdown via ssh://root@localhost:$port"
    else
	runcmd3 $run_ssh "$cmd" 3>&2 2>/dev/null ||
	    croak "Failed to invoke shutdown via ssh://root@localhost:$port"
    fi
}

pijack_wait_halted_dialer_script () {
    local  WS='\\\\s'
    local  NL='\\\\n'
    local PFX="${WS}${WS}${WS}${WS}$self:${WS}"

    {
	cat <<EOF
          TIMEOUT 300
          SAY     ${PFX}Waiting${WS}for${WS}system${WS}to${WS}come${WS}down$NL
          topped  ""
          halt    ""
          SAY     ${PFX}Instance$WS<$QID>${WS}halted$NL
EOF
    } | tr '\n' ' ' | sed 's/  */ /g'
}

pijack_wait_console_halted () { # syntax: <inactivity-timeout>
    local secs="${1:-15}"
    local dial=`pijack_wait_halted_dialer_script`
    local port=`instance_console_port "$QID"`
    local  tcp="TCP:localhost:$port,crlf,connect-timeout=5,nodelay"
    local  cmd="$CHAT -s${DEBUG:+v}"

    pijack_verify_ssh_available

    # run the dial script
    if [ -n "$DEBUG" ]
    then
	runcmd socat -T$secs \
	       "$tcp" "exec:$cmd '$dial'",pty,echo=0,cr
    else
	runcmd socat -T$secs \
	       "$tcp" "exec:$cmd '$dial'",pty,echo=0,cr >/dev/null
    fi
    local rc=$?

    # ...

    return $rc
}

# -----------------------------------------------------------------------------
# Remote copy to guest system
# -----------------------------------------------------------------------------

pijack_verify_rcp () { # syntax: <timeout> <remote-trg-dir> <src-dir> ...
    local  secs="${1:-10}"
    local trg_d="${2}"
    local  port=`instance_ssh_port "$QID"`
    local quiet=q

    # parse remaining argument list
    local src_lst=
    shift 2
    for arg
    do
	local item=`realpath "$arg"`

	if [ -d "$item" ]
	then
	    local dirs=`ls -d "$item"/* `
	    [ -n "$dirs" ] ||
		fatal "pijack_verify_rcp: Empty source folder \"$item\""
	    src_lst="$src_lst $dirs"
	else
	    local file=`ls -d "$item" 2>/dev/null`
	    [ -n "$file" ] ||
		fatal "pijack_verify_rcp: No such file \"file\""
	    src_lst="$src_lst $file"
	fi
    done

    [ -n "$src_lst" ] ||
	fatal "Missing source files/folders"
    [ -z "$NOISY" ] ||
	quiet=

    runcmd3 $scp_nopw -oConnectTimeout=5 -P$port -r$quiet \
	    $src_lst "root@localhost:$trg_d" 3>&2 ||
	croak "Failed to copy data to scp://root@localhost:$port/$trg_d"
}

# -----------------------------------------------------------------------------
# Expand image guest file system
# -----------------------------------------------------------------------------

pijack_ssh_expand_root_filesys () {
    local    port=`instance_ssh_port "$QID"`
    local run_ssh="$ssh_batch -p$port root@localhost"
    local     cmd="resize2fs -d0 /dev/mmcblk0p2"
    local   error="Could not expand file system on virtual instance <$QID>"

    pijack_verify_ssh_available

    if [ -n "$DEBUG" ]
    then
	runcmd $run_ssh $cmd ||
	    croak "$error"
    else
	runcmd3 $run_ssh $cmd 3>&2 >/dev/null 2>&1 ||
	    croak "$error"
    fi
}

# -----------------------------------------------------------------------------
# Update/upgrade packages on guest system
# -----------------------------------------------------------------------------

pijack_ssh_apt_update_install () { # syntax: [packages] ...
    local raw_pkgs="$*"
    local     port=`instance_ssh_port "$QID"`
    local  run_ssh="$ssh_batch -t -p$port root@localhost"
    local    error="Error upgrading Debian packages on instance <$QID>"

    pijack_verify_ssh_available

    # sanitise package list
    local pkgs=`echo -n "$raw_pkgs"|tr -c '[:alnum:]:*+-' ' '|sed 's/  */ /g'`

    # needs to run as SSH command (piping through /bin/sh causes APT to
    # complain; it seems that a pseudo tty must be available)
    local cmd="killall apt 2>/dev/null;
               apt -yq update;
               apt -yqm dist-upgrade;
               ${pkgs:+apt -yqm install $pkgs;}
               apt -q clean;"

    if [ -n "$DEBUG" ]
    then
	runcmd $run_ssh $cmd ||
	    croak "$error"
    else
	runcmd3 $run_ssh $cmd 3>&2 2>&1 ||
	    croak "$error"
    fi
}

# -----------------------------------------------------------------------------
# Custom script installer
# -----------------------------------------------------------------------------

pijack_ssh_post_install () { # syntax: <script-file> ...
    local    cmds=`cat "$@"`
    local    port=`instance_ssh_port "$QID"`
    local run_ssh="$ssh_batch -t -p$port root@localhost"
    local   error="Error running post installation script on instance <$QID>"

    pijack_verify_ssh_available

    [ -z "$cmds" ] ||
	runcmd echo "$cmds" |
	    if [ -n "$DEBUG" ]
	    then
		runcmd $run_ssh $cmd /bin/sh ||
		    croak "$error"
	    else
		runcmd3 $run_ssh $cmd /bin/sh 3>&2 2>&1 ||
		    croak "$error"
	    fi
}

# -----------------------------------------------------------------------------
# Set file permissions on guest system
# -----------------------------------------------------------------------------

pijack_ssh_set_permissions () { # syntax: <permissions-file> ...
    local    args="$@"
    local    port=`instance_ssh_port "$QID"`
    local run_ssh="$ssh_batch -p$port root@localhost"
    local   error="Error setting file permissioins on instance <$QID>"
    local    cmds=`awk 'BEGIN {
                     cmds = ""
                     fail = 0
                   }
                   NF == 3 &&
                   $1 ~ /^\// &&
                   $2 ~ /^[a-z][a-z]*:[a-z][a-z]*$/ &&
                   $3 ~ /^[0-7][0-7]*/ {
                     cmds = cmds "chown " $2 " " $1 ";chmod " $3 " " $1 ";\n"
                     next
                   }
                   0 < NF &&
                   $1 !~ /^#/ {
                     fail = 1
                   }
                   END {
                     print fail ? "false" : cmds
                   }' $args`

    [ "$cmds" != false ] || {
	local files=`list_dblquote $args`
	fatal "Parse error in permission script(s): $files"
    }

    pijack_verify_ssh_available

    runcmd echo "$cmds" |
	if [ -n "$DEBUG" ]
	then
	    runcmd $run_ssh /bin/sh ||
		croak "$error"
	else
	    runcmd3 $run_ssh /bin/sh 3>&2 2>&1 ||
		croak "$error"
	fi
}

# -----------------------------------------------------------------------------
# Install user
# -----------------------------------------------------------------------------

pijack_ssh_useradd () { # syntax: <username> [<sudo-ok>]
    local    name="$1"
    local sudo_ok="$2"
    local    port=`instance_ssh_port "$QID"`
    local   error="Error updating account \"$name\" on instance <$QID>"
    local run_ssh="$ssh_batch -p$port root@localhost"
    local    file="/etc/sudoers.d/042-$name-nopasswd"
    local adm_add="(umask 337;
                    echo \"$name ALL=(ALL) NOPASSWD: ALL\" > $file);"

    pijack_verify_ssh_pubkey ## => SSHPUBKEY
    local cmd="useradd -mU $name 2>/dev/null;
               usermod -p'*' $name;
               ${sudo_ok:+$adm_add}
               home=\`awk -F: '\$1==\"$name\"{print \$6}' /etc/passwd\`;
               auth_key=\$home/.ssh/authorized_keys;
               id_ecdsa=\$home/.ssh/id_ecdsa;
               test -s \$id_ecdsa ||
                 ssh-keygen -q -t ecdsa -f \$id_ecdsa -N '';
               grep -qs '^$SSHPUBKEY' \$auth_key ||
		 echo '$SSHPUBKEY' >> \$auth_key;
               pubkey=\`cat \$id_ecdsa.pub\`;
               grep -qs \"^\$pubkey\" \$auth_key ||
                 cat \$id_ecdsa.pub >> \$auth_key;
               chmod 644 \$auth_key;
               chown -R $name:$name \$home/.ssh;"

    pijack_verify_ssh_available

    runcmd echo "$cmd" |
	if [ -n "$DEBUG" ]
	then
	    runcmd $run_ssh /bin/sh ||
		croak "$error"
	else
	    runcmd3 $run_ssh /bin/sh 3>&2 2>&1 ||
		croak "$error"
	fi
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

verify_not_root_user

setup_parse_options "$@"

pijack_debug_vardump

verify_required_commands

# -----------------------------------------------------------------------------
# Show connection status
# -----------------------------------------------------------------------------

if [ -n "$SHOWSTAT" ]
then
    con_port=
    ssh_port=
    if pijack_console_available_ok
    then
	con_port=`instance_console_port "$QID"`
    fi
    if pijack_ssh_available_ok
    then
	ssh_port=`instance_ssh_port "$QID"`
    fi

    [ -z "$con_port$ssh_port" ] ||
	echo
    [ -z "$con_port" ] || {
	echo "Console:   netcat localhost $con_port"
	echo "           socat TCP:localhost:$con_port,nodelay stdio"
    }
    [ -z "$ssh_port" ] || {
	echo "SSH:       ssh -p$ssh_port pi@localhost"
    }
    [ -z "$con_port$ssh_port" ] ||
	echo
fi

# -----------------------------------------------------------------------------
# Enable SSH service and Install SSH keys
# -----------------------------------------------------------------------------

# test whether SSH console is available
if [ -n "$ISSHPUB" ]
then
    if qemu_instance_is_running_ok $QID
    then
	if pijack_ssh_available_ok
	then
	    true
	else
	    mesg "*** SSH not available, need to enable via console login"
	    SSHENACON=set
	fi
    else
	croak "Instance <$QID> is NOT running"
    fi
fi

# enable SSH via console
if [ -n "$SSHENACON" ]
then
    n=1

    # try every password instance twice
    dbl_entries=`echo $PI_USER_PASSWORDS|tr ' ' '\n' | awk '{print $0 ORS $0}'`
    for pwd in $dbl_entries
    do
	mesg "Console login for user \"pi\", attempt ($n)"
	n=`expr $n + 1`

	pijack_console_enable_ssh_ok pi "$pwd" ||
	    continue

	PIPWDUSED="$pwd"
	break
    done

    [ -n "$PIPWDUSED" ] ||
	croak "Failed to enable SSH service via console <$QID>"
    pijack_verify_ssh_available
fi

# install keys via SSH, login with username/passwd
if [ -n "$ISSHPUB" ]
then
    mesg "Installing SSH public keys on instance <$QID> accounts"
    pijack_verify_setup_sshauth ${PIPWDUSED:-$PI_USER_PASSWORDS}
fi

# -----------------------------------------------------------------------------
# Expand file system on virtual guest
# -----------------------------------------------------------------------------

if [ -n "$E2FSEXP" ]
then
    mesg "Expanding file system for instance $QID"
    pijack_ssh_expand_root_filesys
fi

# -----------------------------------------------------------------------------
# Install base file system
# -----------------------------------------------------------------------------

if [ -n "$IBASEFS" ]
then
    mesg "Installing/updating base software for instance <$QID>"

    pijack_verify_rcp "" /    "$raspios_base_d"
    pijack_verify_rcp "" /etc "$ETC_HOSTS" "$ETC_IFTAB" "$ETC_WIFITAB"
    pijack_ssh_set_permissions "$raspios_base_d.permissions"
    pijack_ssh_post_install    "$raspios_base_d.post-install"
fi

# -----------------------------------------------------------------------------
# Update/upgrade Debian on guest
# -----------------------------------------------------------------------------

if [ -n "$APTUPDG" ]
then
    bse_pkgs=`cat "$raspios_base_d.apt-packages"`
    lcl_pkgs=`cat "$raspios_local_d.apt-packages"`
    gst_pkgs=${GUEST_INSTALL:+`cat "$GUEST_INSTALL.apt-packages" 2>/dev/null`}

    mesg "Upgrading Debian packages on instance <$QID>"
    pijack_ssh_apt_update_install $bse_pkgs $lcl_pkgs $gst_pkgs
fi

# -----------------------------------------------------------------------------
# Install application software on virtual guest
# -----------------------------------------------------------------------------

if [ -n "$LOCALCNF" ]
then
    mesg "Installing/updating application software for instance <$QID>"

    pijack_verify_rcp "" / "$raspios_local_d" $GUEST_INSTALL

    pijack_ssh_set_permissions \
	"$raspios_local_d.permissions" \
	${GUEST_INSTALL:+$GUEST_INSTALL.permissions}

    pijack_ssh_post_install \
	"$raspios_base_d.post-install" \
	${GUEST_INSTALL:+$GUEST_INSTALL.post-install}
fi

# -----------------------------------------------------------------------------
# Install/update user account virtual guest
# -----------------------------------------------------------------------------

if [ -n "$USERADD" ]
then
    mesg "Creating/updating user account \"$USERADD\" on instance <$QID>"

    pijack_ssh_useradd "$USERADD" $USUDOOK
fi

# -----------------------------------------------------------------------------
# Shut down the system
# -----------------------------------------------------------------------------

if [ -n "$SHUTDOWN" ]
then
    if [ -n "$NOSUDODWN" ] || $RUNPFX $SUDO true
    then
	pijack_verify_ssh_available
	pijack_verify_console_available

	mesg "Initiating shutdown for instance <$QID>"
	pijack_verify_ssh_shutdown
	pijack_wait_console_halted

	[ -n "$RUNPFX" ] ||
	    mesg "Telling \"pibox\" to terminate QEMU instance <$QID>"
	runcmd /bin/sh $prefix/pibox.sh --terminate \
	       ${RUNPFX:+--dry-run} ${NOISY:+--verbose} ${DEBUG:+--debug} \
	       -- $QID
    fi
fi

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------

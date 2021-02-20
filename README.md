# QEMU Supported Raspberry PI Farming

There is a set of *Bourne*-ish shell scripts supporting software development on
a farm of interconnected Raspberry PI entities. These entities can be guests of
some *QEMU virtual machine*, or physical *Raspberry PI 3 B+* hardware boxes.
All entities run on a copy of the same disk image.

The Raspberry PI entites are called *instances* when managed by the tools here.
When seen as part of the IP network, they are called
*[nodes](#na "Main Chapter")*.

# Contents

* [Quick Start](#qs                             "Main Chapter")
* [Rationale](#ra                               "Main Chapter")
  + [Development Cycle](#dc                     "Chapter Reference")
  + [Motivation to write this toolbox](#mw      "Chapter Reference")
* [Set of Shell Scripts](#so                    "Main Chapter")
  + [Provided Tools](#pt                        "Chapter Reference")
  + [Tweaking, Customising](#tc                 "Chapter Reference")
* [Node Architecture](#na                       "Main Chapter")
  + [Hardware Node](#hn                         "Chapter Reference")
  + [Virtual QEMU Guest Node](#vq               "Chapter Reference")
* [RaspiOS Hints & Helpers](#oe                 "Main Chapter")
  + [Upgrade Caveat](#uc                         "Chapter Reference")
  + [Installer Scripts](#is                     "Chapter Reference")
* [Licence](#li                                 "Main Chapter")

# <a name="qs"></a>Quick Start

In order to see something work, copy a RaspiOS disk image and name it
*raspios.img*. Prepare the image for QEMU with

      sh pimage.sh --provide-qboot --disk-image=raspios.img --expand-image

and then start the virtual guest with

      sh pibox.sh --run
	  
Make the virtual guest accessible for remote administration via

      sh pijack.sh --enrol

Finally shut down the runing application and therminate QEMU with

      sh pijack.sh --shutdown

For any of the tools, documentation can be printed with the combined options
*--help --verbose* (or *-hv* for short) as in

      sh pibox.sh --help --verbose
	  
Instructions explain how to start from a pristine *RaspiOS* disk image
downloaded from an internet repository.

# <a name="ra"></a>Rationale

In 2019, I run a Perl application which was based on a replicated data
base implemented on a set of Raspberry PI nodes. This application was exposed
to rough conditions such as power cuts, missing Internet access, etc. Having
run successfully a proof of concept at the
[Anthropos Festival](//anthroposfestival.org "Festival Website"),
the software has been developed further into a layered architecture.

## <a name="dc"></a>Development Cycle

My intened software development cycle re the virtual evironment looks something like

                                       +-----------------------------------------------------------------+
                                       |                                                                 |
                                       |                        running a virtual        test, tweak     |
                                       |                 +--->  clone <1> of the   --->   and test,  ----+
                                       |                 |     primary instance <0>       more tests     |
                                       |                 |                                               |
                                       |                 |                                               |
                                       |                 |      running a virtual        test, tweak     |
                                       |                 +--->  clone <2> of the   --->   and test,  ----+
                                       v                 |     primary instance <0>       more tests     |
                                                         |                                               |
                              enrolment, OS upgrade,     |                                               |
      stock disk image           installation of         |      running a virtual        test, tweak     |
      downloaded from  ---->  additional software on ----+--->  clone <3> of the   --->   and test,  ----+
       PI repository           primary instance <0>            primary instance <0>       more tests

                                       |                             ...                     ...
                                       |
                                       v

                               flash instance <0>
                               image copies to SD
                              cards and run them on
                                 Raspberry PIs

This was sort of how I developed my proof of concept software for the festival
events, albeit without virtual support. It involved duplicating quite a few
flash cards.

## <a name="mw"></a>Motivation for scripting

I got tired of repeatedly typing variations of commands like

      sudo qemu-system-aarch64 -M raspi3 -m 1G -smp 4 -usb \
        -append 'rw earlyprintk loglevel=8 console=ttyAMA0,115200 dwc_otg.lpm_enable=0 root=/dev/mmcblk0p2 rootdelay=1' \
        -drive  'media=disk,if=sd,format=raw,file=/qemu/raspios-armhf.img' \
        -dtb    '/qemu/bcm2710-rpi-3-b-plus.dtb' \
        -kernel '/qemu/kernel8.img' \
        -serial 'stdio' \
        -netdev 'user,id=user0,ipv6=off,net=100.64.63.0/24,hostfwd=tcp::5700-:22' \
        -netdev 'tap,id=tap0,ifname=q0tap0,script=no,downscript=no' \
        -netdev 'tap,id=tap1,ifname=q1tap0,script=no,downscript=no' \
        -device 'usb-mouse' \
        -device 'usb-kbd' \
        -device 'usb-net,netdev=user0' \
        -device 'usb-net,netdev=tap0' \
        -device 'usb-net,netdev=tap1'

Tools like *Vagrant* and *Ansible* come to mind for help, but I decided
against any of them because their of generality. I aimed for a more
lightweight solution tuned towards my particular development
[cycle](#dc "Chapter Reference") and [node](#na "Main Chapter") architecture.

# <a name="so"></a>Set of Shell Scripts

The tools are written in near *Bourne* shell syntax. Where it diverges from
the pure syntax is the use of the *local* keyword. This is used to declare
and initialise function variables with local scope. Nevertheless, the *local*
keyword feature should be supported by the following popular shells:

       ash, bash, bosh, busybox, dash, yash, zsh

This *local* keyword feature as used here is not *ksh* (i.e. *Korn* shell)
compatible.

## <a name="pt"></a>Provided Tools

* *pimage -- disk image maintenance tool*<br>
  The tool prepares a RaspiOS disk image for use with QEMU. It will extract a
  copy of RaspiOS boot files needed by QEMU to start on the guest disk image.
  It registers the location of the argument disk image file path to be used by
  subsequent invocations. The tool works with *raw* images only, e.g.
  extracted with *dd if=/dev/sda of=disk.img* (as opposed to the *qcow2*
  virtual machine format.)

* *pibox -- virtual machine host manager*<br>
  The tool starts and stops the virtual QEMU machine for guest disk images.
  Guest disk images are referred to as *instances* and identified by a number.
  Default is the *zero* instance *&lt;0&gt;* running on the primary *raw*
  RaspiOS disk image. All other instances are *qcow2* formatted copies of the
  *&lt;0&gt;* instance.<br>
  <br>
  By extension, a virtual QEMU machine for instance *&lt;N&gt;* is
  called *the* instance *&lt;N&gt;* if the meaning is otherwise clear.

* *pijack -- virtual guest manager*<br>
  The tool manages a running virtual QEMU guest instance via IP network
  connections for *console* or *SSH*. Administrative commands are typically
  sent to the guest instance via *SSH*, authenticated by the command user's
  public key. The tool can hijack the guest instance via *console* login and
  prepare it for *SSH* with public key authentication.

* *pinet -- virtual bridges network setup*<br>
  This tool scans the network interface table on the host system for
  active virtual QEMU guest *&lt;lan&gt;* interfaces. Then the tool adds these
  interfaces to a bridge. Seen from a virtual guest, all active interfaces
  are connected.<br>
  <br>
  Additional non-virtual interfaces can be added to the bridge. If this is
  an outbound interface connected to *&lt;lan&gt;* interfaces of physical
  Raspberry PIs, these systems join the virtual network.

All commands support the options combination --dry-run --verbose which have
the tools print out the shell commands that *would* be run rather than really
executing them. Apart from auditing privilege escalation via *sudo*, this
feature is intended to be used when building bespoke scripts for particular
QEMU related tasks.

The following tools do *not* need *sudo* privilege escalation

 * *pijacks* -- never (but will call *pibox* for terminating QEMU)
 * *pimage* -- never if *guestmount* is available

The other tools will do need *sudo*, see the command help pages (--help
--verbose) for details.

## <a name="tc"></a>Tweaking, Customising
Provide a file *config.sh* in the same folder where the *pibox.sh* and the
other tools reside. See the comments in the file *lib/variables.sh* for
possible settings. There is an advanced example configuration script
*examples/config.sh*.

The tools will complain if any of the following commands is unavailable

 * *fatcat* -- tool for extracting files from DOS partition images
 * *remote-viewer* -- a VNC gui and reote desktop viewer
 * *guestmount* -- user mode mounting tool for disk partition images

Complaints can be stopped by disabling any of these tools setting variables
*NOFATCAT*, *NOREMOTE_VIEWER*, or *NOGUESTMOUNT* in the *config.sh*
configuration file. For example. setting

      NOGUESTMOUNT=set

will tell the tools to ignore the particular program completely in which
case functionality is degraded unless there is a work-around (e.g. *sudo*
losetup+mount.)


# <a name="na"></a>Node Architecture

Raspberry PI entites are called *nodes* when part of an IP network. *Nodes*
are identified by a non-negative number called the node ID (which coincides
with the *instance ID*.)

So a *node* can be associated with

* a copy of a particular disk image, and
* either
  + a physical *Raspberry PI 3 B+* hardware box, or
  + a guest of a *QEMU virtual machine*

Nodes share the same disk image, still they need unique *node IDs*. For
*Raspberry PI 3 B+* hardware boxes, they differ by the MAC address of their
built-in NIC which is exploited to map the *node ID*. For the virtual guest
case, differentiation is handled by the way the QEMU machine is started.

Each node has three interfaces of type *WAN*, *LAN*, and *WLAN*. The *LAN*
interface is used for peer-to-peer communication between nodes and the *WLAN*
interface for providing outbound services. The *WAN* interface is considered
administrative, only.

## <a name="hn"></a>Hardware Node

For the Raspberry PI 3 B+ hardware, a diagram for a node &lt;id&gt; looks like

        Raspberry PI 3 B+      :      External Access
      -------------------------+---------------------------------
      ,---------------.        :
      |               |        :
      |       <wan> o----------------o USB/pluggable adaptor
      |               |        :
      |     lan<id> o----------------o internal NIC
      |               |        :
      |       wlan0 o----------------o internal WiFi access point
      |               |        :
      `---------------'        :

where &lt;id&gt; is some positive number. There is no *zero* node for the
*Raspberry PI 3 B+* hardware box. The hardware node interfaces have the
following properties:

 * &lt;wan&gt;
   + the &lt;wan&gt; interface name depends on the USB/pluggable adaptor
   + the interface need not be available, neither activated
   + when activated, the default route points to that interface
   + unpredictable IP address

 * lan&lt;id&gt; *(implies node ID)*
   + the &lt;id&gt; is implied by the MAC address of the built-in  NIC
   + the interface is activated
   + predictable IP address dependent on the node ID

 * wlan0
   + interface is activated and configured as WiFi access point
   + same IP address for all nodes

Apparently, as interface names are dependent on MAC addresses, they need to
be per-configured in the */etc/iftab* file. The node ID mapping information is
held in the */etc/host* file. If properly configured, the &lt;wan&gt;
interface name reads *wan&lt;n&gt;* for some positive number *n*.

## <a name="vq"></a>Virtual QEMU Guest Node

        Virtual Guest          :      Virtual Host
      -------------------------+---------------------------------
      ,---------------.        :
      |               |        :
      |        wan0 o----------------o QEMU user socket
      |               |        :
      |        lan0 o----------------o TAP interface q0tap<id>
      |               |        :
      |       wlan0 o----------------o TAP interface q1tap<id>
      |               |        :
      `---------------'        :

where the &lt;id&gt; stand for non-negative numbers (i.e. it can be zero). The
interfaces have the following properties:

 * wan0 *(implies node ID)*
   + interface is activated
   + the default route points to that interface
   + IP address is provided via DHCP by the QEMU virtual machine
   + &lt;id&gt; is implied by the IP address
   + accessible from virtual host via ssh://localhost:<5700+id>

 * lan0
   + interface is activated
   + predictable IP address dependent on the node ID

 * wlan0
   + interface is activated and configured as WiFi access point
   + same IP address for all nodes (the same as in the hardware case)

Here, node ID configuration is superimposed by the *QEMU virtual machine* when
configuring the WAN interface via DHCP. Nevertheless, LAN and WLAN interfaces
follow the same logic as in the hardware case.

# <a name="oe"></a>RaspiOS Hints & Helpers

## <a name="uc"></a>Upgrade Caveat

Upgrading the current *RaspiOS* with *apt update;apt upgrade* will result in
a boot image replacement that cannot be properly handled by *QEMU* (as of Feb
2021). In that case, *QEMU* just stalls and leaves the system incommunicado.
The replacement happens when running

      sh pijack.sh --software-update
or

      sh pijack.sh --apt-upgrade

As a kludge, no *apt upgrade* command must be run on the *RaspiOS* when
installing which can be accomplished with

      sh pijack.sh --base-system --apt-install --local-software

See *sh pijack.sh --help* for details.


## <a name="is"></a>Installer scripts

With the *--local-software* command line option for the *pijack.sh* tool,
the following installer scripts will be provided in the */usr/local/src*
directory of the *RaspiOS* image. See the script headers for the Debian
packages needed for compiling and running. The scripts will fetch the source
code from *github* and install into */usr/local/bin* or */usr/local/sbin*.
Invoking a script again again, it will re-compile/install only if there was
source code update.

* *ndjbdns-update.sh*<br>
  This script installs a ported version of the *DJBDNS* name server tools
  originally written by Dr. D J Bernstein. These servers are supposed to run
  under control of *runit* or *daemontools*.

* *nim-update.sh*<br>
  Installs the latest development version of the *NIM* compiler.

* *rsync-update.sh*<br>
  Compiles the latest *rsync* version. This is currently needed (as of Feb
  2021) for running an *rsync* server proxied through *NGINX* (allowing
  certificate authentication.)

# <a name="li"></a>Licence

This is free and unencumbered software released into the public domain.

See [UNLICENSE](UNLICENSE "Local Copy of Unlicense") or
[Unlicense project](http://unlicense.org/ "Web Location") for details.

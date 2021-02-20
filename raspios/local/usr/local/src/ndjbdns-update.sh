#! /bin/sh
#
# Install/update ndjbdns
#
#
# RaspiOS/Debian/Ubuntu extra packages for compiling:
#
#    autoconf automake g++ gcc
#

self=`basename "$0"`
prfx=`dirname "$0"`

ndjbdns_src="https://github.com/pjps/ndjbdns.git"
ndjbdns_trg="$prfx/ndjbdns"
ndjbdns_etc="/usr/local/src/ndjbdns-hideaway"

suffix=package-updated
ndjbdns_tag=`date +%Y%m%d%H%M%S-$suffix`


# Install or update DNJBDNS sources
if [ -d "$ndjbdns_trg/.git" ]
then
    (set -x; cd "$ndjbdns_trg" && git pull origin master)
else
    (set -x; git clone --depth 1 "$ndjbdns_src" "$ndjbdns_trg")
fi || {
    echo
    echo "*** $self: something went wrong, please install manually"
    echo
    exit 2
}


# Check the locally provided time stamp of last update
if (cd "$ndjbdns_trg" && git describe 2>/dev/null) | grep -q "$suffix\$"
then
    echo
    echo "*** $self: recently updated, already"
    echo
else
    (
	trap "set +x;echo;echo '*** Oops, unexpected exit!';echo;trap" 0
	set -ex
	cd "$ndjbdns_trg"

	# create/update configure script
	touch README
	aclocal
	autoheader
	libtoolize --automake --copy
	autoconf
	automake --add-missing --copy

	# configure and compile
	./configure --sysconfdir="$ndjbdns_etc"
	make

	# install binaries
	make install-strip

	# clean up
	make distclean
	[ -s README ] || rm -f README

	# set update time stamp
	git tag -a  -m '' "$ndjbdns_tag"
	trap 0
    )
fi

# End

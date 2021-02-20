#! /bin/sh
#
# Install/update rsync, RaspiOS version is pretty old
#
#
# RaspiOS/Debian/Ubuntu runtime packages:
#
#    acl attr liblz4-1 libnginx-mod-stream libssl1.1 libzstd1 libxxhash0
#
# RaspiOS/Debian/Ubuntu extra packages for compiling:
#
#    autoconf automake g++ gcc libacl1-dev libattr1-dev liblz4-dev libssl-dev
#    libtool libxxhash-dev libzstd-dev python3-cmarkgfm
#

self=`basename "$0"`
prfx=`dirname "$0"`

rsync_src="https://github.com/WayneD/rsync.git"
rsync_trg="$prfx/rsync"

suffix=package-updated
rsync_tag=`date +%Y%m%d%H%M%S-$suffix`


# Install or update DNJBDNS sources
if [ -d "$rsync_trg/.git" ]
then
    (set -x; cd "$rsync_trg" && git pull origin master)
else
    (set -x; git clone --depth 1 "$rsync_src" "$rsync_trg")
fi || {
    echo
    echo "*** $self: something went wrong, please install manually"
    echo
    exit 2
}


# Check the locally provided time stamp of last update
if (cd "$rsync_trg" && git describe 2>/dev/null) | grep -q "$suffix\$"
then
    echo
    echo "*** $self: recently updated, already"
    echo
else
    (
	trap "set +x;echo;echo '*** Oops, unexpected exit!';echo;trap" 0
	set -ex
	cd "$rsync_trg"

	# configure and compile
	./configure --sysconfdir=/usr/local/rsync-hideaway

	# kludge
	grep -q ZSTD_STATIC_LINKING_ONLY config.h ||
	    echo "#define ZSTD_STATIC_LINKING_ONLY" >> config.h

	make
	make check

	# install binaries
	make install-strip

	# clean up
	make distclean
	rm -rfv /usr/local/rsync-hideaway

	# set update time stamp
	git tag -a  -m '' "$rsync_tag"
	trap 0
    )
fi

# End

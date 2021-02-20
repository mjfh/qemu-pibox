#! /bin/sh
#
# Install/update nim compiler
#
# RaspiOS/Debian/Ubuntu runtime packages:
#
#    gcc (optional libssl1.1)
#
# RaspiOS/Debian/Ubuntu extra packages for compiling:
#
#    (optional libssl-dev)
#

self=`basename "$0"`
prfx=`dirname "$0"`
branch=devel

# see CPU case below: docs not needed on raspi
build_docs=yes

nim_src="https://github.com/nim-lang/Nim.git"
cso_src="https://github.com/nim-lang/csources"
nim_trg="$prfx/nim"

suffix=package-updated
nim_tag=`date +%Y%m%d%H%M%S-$suffix`
arch=`dpkg --print-architecture`

case $arch in
armhf)
   # No docs on RaspiOS/RaspberriPi
   CPU="--cpu $arch"
   build_docs=no
esac

# Install or update NIM sources
if [ -d "$nim_trg/.git" ]
then
    (set -x; cd "$nim_trg" && git pull origin $branch)
else
    (set -x; git clone --depth=1 --branch=$branch "$nim_src" "$nim_trg")
fi || {
    echo
    echo "*** $self: something went wrong, please install manually"
    echo
    exit 2
}

# Check the locally provided time stamp of last update
if (cd "$nim_trg" && git describe 2>/dev/null) | grep -q "$suffix\$"
then
    echo
    echo "*** $self: recently updated, already"
    echo
else
    (
	trap "set +x;echo;echo '*** Oops, unexpected exit!';echo;trap" 0
	set -ex
	cd "$nim_trg"

	# import C library (make it resilient against temporary hangups)
	for _ in 1 2 3
	do
	    [ ! -d csources ] ||
		mv csources csources~
	    rm -rf csources~

	    if git clone --depth=1 "$cso_src"
	    then
		break
	    fi

	    sleep 10
	done
	(cd csources && sh build.sh $CPU)

	./bin/nim c koch
	./koch boot -d:release
	./koch nimble || true
	./bin/nim c -d:release -o:bin/nimgrep tools/nimgrep.nim || true

	# clean up, save space
	find . -type d -name nimcache -print | xargs -n1 rm -rf
	rm -rf csources csources~

	# make binaries accessible
	chmod +x ./bin/nim*

	# build docs unless disabled
	if [ yes = "$build_docs" ]
	then
	   set +e
	   rm -rf web/upload/[1-9]*
	   ./koch docs
	   p=`ls -d web/upload/[1-9]*`
	   ./bin/nim --skipProjCfg buildIndex -o:$p/theindex.html $p || true
	fi

	# Install shell script stubs
	(
	    set +x
	    NIM_BIN="`pwd`/bin"
	    mkdir -p /usr/local/bin
	    for name in nim nimble nim-gdb nimgrep
	    do
		cmd="/usr/local/bin/$name"

		if [ -x "$cmd" ]
		then
	            continue
		elif [ -f "$cmd" ]
		then
		    rm -f     "$cmd~"
		    mv "$cmd" "$cmd~"
		fi

		echo "*** $self: installing $cmd"
		(
		    echo '#! /bin/sh'
		    echo
		    echo 'self=`basename $0`'
		    echo "bind=$NIM_BIN"
		    echo
		    echo 'PATH=$bind:$PATH'
		    echo
		    echo 'exec "$bind/$self" "$@"'
		) >> "$cmd"

		chmod +x "$cmd"
	    done
	)

	# set update time stamp
	git tag -a  -m '' "$nim_tag"
	trap 0
    )
fi

# End

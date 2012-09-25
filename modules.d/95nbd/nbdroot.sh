#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

PATH=/usr/sbin:/usr/bin:/sbin:/bin

# Huh? Empty $1?
[ -z "$1" ] && exit 1

# Huh? Empty $2?
[ -z "$2" ] && exit 1

# Huh? Empty $3?
[ -z "$3" ] && exit 1

# root is in the form root=nbd:srv:port[:fstype[:rootflags[:nbdopts]]]
netif="$1"
root="$2"
NEWROOT="$3"

# If it's not nbd we don't continue
[ "${root%%:*}" = "nbd" ] || return

root=${root#nbd:}
nbdserver=${root%%:*}; root=${root#*:}
nbdport=${root%%:*}; root=${root#*:}
nbdfstype=${root%%:*}; root=${root#*:}
nbdflags=${root%%:*}
nbdopts=${root#*:}

# If nbdport not an integer, then assume name based import
if [ "${nbdport%[0-9]}" = "$nbdport" ]; then
    nbdport="-N $nbdport"
fi

if [ "$nbdopts" = "$nbdflags" ]; then
    unset nbdopts
fi
if [ "$nbdflags" = "$nbdfstype" ]; then
    unset nbdflags
fi
if [ "$nbdfstype" = "$nbdport" ]; then
    unset nbdfstype
fi
if [ -z "$nbdfstype" ]; then
    nbdfstype=auto
fi

# look through the NBD options and pull out the ones that need to
# go before the host etc. Append a ',' so we know we terminate the loop
nbdopts=${nbdopts},
while [ -n "$nbdopts" ]; do
    f=${nbdopts%%,*}
    nbdopts=${nbdopts#*,}
    if [ -z "$f" ]; then
        break
    fi
    if [ -z "${f%bs=*}" -o -z "${f%timeout=*}" ]; then
        preopts="$preopts $f"
        continue
    fi
    opts="$opts $f"
done

# look through the flags and see if any are overridden by the command line
nbdflags=${nbdflags},
while [ -n "$nbdflags" ]; do
    f=${nbdflags%%,*}
    nbdflags=${nbdflags#*,}
    if [ -z "$f" ]; then
        break
    fi
    if [ "$f" = "ro" -o "$f" = "rw" ]; then
        nbdrw=$f
        continue
    fi
    fsopts=${fsopts+$fsopts,}$f
done

getarg ro && nbdrw=ro
getarg rw && nbdrw=rw
fsopts=${fsopts+$fsopts,}${nbdrw}

# XXX better way to wait for the device to be made?
i=0
while [ ! -b /dev/nbd0 ]; do
    [ $i -ge 20 ] && exit 1
    if [ $UDEVVERSION -ge 143 ]; then
        udevadm settle --exit-if-exists=/dev/nbd0
    else
        sleep 0.1
    fi
    i=$(( $i + 1))
done

nbd-client $preopts "$nbdserver" $nbdport /dev/nbd0 $opts || exit 1

# If we didn't get a root= on the command line, then we need to
# add the udev rules for mounting the nbd0 device
root=$(getarg root=)
if [ -z "$root" ] || strstr "$root" "nbd:" || strstr "$root" "dhcp"; then
    echo '[ -e /dev/root ] || { info=$(udevadm info --query=env --name=/dev/nbd0); [ -z "${info%%*ID_FS_TYPE*}" ] && { ln -s /dev/nbd0 /dev/root 2>/dev/null; :; };} && rm $job;' \
        > $hookdir/initqueue/settled/nbd.sh

    printf '/bin/mount -t %s -o %s %s %s\n' \
        "$nbdfstype" "$fsopts" /dev/nbd0 "$NEWROOT" \
        > $hookdir/mount/01-$$-nbd.sh
fi

# NBD doesn't emit uevents when it gets connected, so kick it
echo change > /sys/block/nbd0/uevent
udevadm settle
need_shutdown
exit 0

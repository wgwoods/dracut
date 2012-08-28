#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

export DRACUT_SYSTEMD=1
export NEWROOT="/sysroot"
[ -d $NEWROOT ] || mkdir -p -m 0755 $NEWROOT
[ -d /run/initramfs ] || mkdir -p -m 0755 /run/initramfs
[ -d /run/lock ] || mkdir -p -m 0755 /run/lock

if [ -f /dracut-state.sh ]; then
    . /dracut-state.sh 2>/dev/null
fi
type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

[ -f /etc/initrd-release ] && . /etc/initrd-release
[ -n "$VERSION" ] && info "dracut-$VERSION"

source_conf /etc/conf.d

# run scriptlets to parse the command line
getarg 'rd.break=cmdline' -d 'rdbreak=cmdline' && debug_shell -n cmdline "Break before cmdline"
source_hook cmdline

[ -z "$root" ] && die "No or empty root= argument"
[ -z "$rootok" ] && die "Don't know how to handle 'root=$root'"

export root rflags fstype netroot NEWROOT

export -p > /dracut-state.sh
exit 0

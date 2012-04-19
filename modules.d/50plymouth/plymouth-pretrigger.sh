#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

if [ -x /bin/plymouthd ]; then
    if getargbool 1 plymouth.enable && getargbool 1 rd.plymouth -n rd_NO_PLYMOUTH; then
        [ -c /dev/null ] || mknod -m 0666 /dev/null c 1 3
        # first trigger graphics subsystem
        udevadm trigger --action=add --attr-match=class=0x030000 >/dev/null 2>&1
        # first trigger graphics and tty subsystem
        udevadm trigger --action=add --subsystem-match=graphics --subsystem-match=drm --subsystem-match=tty >/dev/null 2>&1

        udevadm settle --timeout=30 2>&1 | vinfo
        [ -c /dev/zero ] || mknod -m 0666 /dev/zero c 1 5
        [ -c /dev/tty0 ] || mknod -m 0620 /dev/tty0 c 4 0
        [ -e /dev/systty ] || ln -s tty0 /dev/systty
        [ -c /dev/fb0 ] || mknod -m 0660 /dev/fb0 c 29 0
        [ -e /dev/fb ] || ln -s fb0 /dev/fb

        info "Starting plymouth daemon"
        mkdir -m 0755 /run/plymouth
        consoledev=$(getarg console= | sed -e 's/,.*//')
        consoledev=${consoledev:-tty0}
        [ -x /lib/udev/console_init ] && /lib/udev/console_init "/dev/$consoledev"
        [ -x /bin/plymouthd ] && /bin/plymouthd --attach-to-session --pid-file /run/plymouth/pid
        /bin/plymouth --show-splash 2>&1 | vinfo
        # reset tty after plymouth messed with it
        [ -x /lib/udev/console_init ] && /lib/udev/console_init /dev/tty0
    fi
fi

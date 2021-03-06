#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

if [ "${root%%:*}" = "block" ]; then
    {
        printf 'KERNEL=="%s", SYMLINK+="root"\n' \
            ${root#block:/dev/}
        printf 'SYMLINK=="%s", SYMLINK+="root"\n' \
            ${root#block:/dev/}
    } >> /etc/udev/rules.d/99-root.rules

    printf '[ -e "%s" ] && { ln -s "%s" /dev/root 2>/dev/null; rm "$job"; }\n' \
        "${root#block:}" "${root#block:}" > $hookdir/initqueue/settled/blocksymlink.sh

    # if [ -d /lib/systemd/system/ ]; then
    #     echo "${root#block:} $NEWROOT ${fstype:-auto} ${rflags:-defaults} 1 1" >> /etc/fstab
    #     {
    #        echo '[Unit]'
    #        echo 'Description=New Root File System'
    #        echo 'DefaultDependencies=no'
    #        echo 'Before=initrd-switch-root.service'
    #        echo '[Mount]'
    #        echo "What=${root#block:}"
    #        echo "Where=$NEWROOT"

    #    } >/lib/systemd/system/${NEWROOT#/}.mount

    #    mkdir -p /lib/systemd/system/initrd-switch-root.target.requires
    #    ln -s ../${NEWROOT#/}.mount /lib/systemd/system/initrd-switch-root.target.requires/${NEWROOT#/}.mount
    # fi

    wait_for_dev "${root#block:}"
fi

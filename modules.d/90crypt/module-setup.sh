#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

check() {
    local _rootdev
    # if cryptsetup is not installed, then we cannot support encrypted devices.
    type -P cryptsetup >/dev/null || return 1

    . $dracutfunctions

    check_crypt() {
        local dev=$1 fs=$2
        [[ $fs = "crypto_LUKS" ]] || return 1
        ID_FS_UUID=$(udevadm info --query=property --name=$dev \
            | while read line; do
                [[ ${line#ID_FS_UUID} = $line ]] && continue
                eval "$line"
                echo $ID_FS_UUID
                break
                done)
        [[ ${ID_FS_UUID} ]] || return 1
        if ! [[ $kernel_only ]]; then
            echo " rd.luks.uuid=luks-${ID_FS_UUID} " >> "${initdir}/etc/cmdline.d/90crypt.conf"
        fi
        return 0
    }

    [[ $hostonly ]] || [[ $mount_needs ]] && {
        for_each_host_dev_fs check_crypt || return 1
    }

    return 0
}

depends() {
    echo dm rootfs-block
    return 0
}

installkernel() {
    instmods dm_crypt =crypto
}

install() {
    dracut_install cryptsetup rmdir readlink umount
    inst "$moddir"/cryptroot-ask.sh /sbin/cryptroot-ask
    inst "$moddir"/probe-keydev.sh /sbin/probe-keydev
    inst_hook cmdline 10 "$moddir/parse-keydev.sh"
    inst_hook cmdline 30 "$moddir/parse-crypt.sh"
    inst_hook pre-pivot-cleanup 30 "$moddir/crypt-cleanup.sh"
    inst_simple /etc/crypttab
    inst "$moddir/crypt-lib.sh" "/lib/dracut-crypt-lib.sh"
}


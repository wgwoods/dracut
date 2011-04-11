#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh
do_fipskernel()
{
    boot=$(getarg boot=)
    newroot=$NEWROOT

    if [ -n "$boot" ]; then
        KERNEL=$(uname -r)
        case "$boot" in
        LABEL=*)
            boot="$(echo $boot | sed 's,/,\\x2f,g')"
            boot="/dev/disk/by-label/${boot#LABEL=}"
            ;;
        UUID=*)
            boot="/dev/disk/by-uuid/${boot#UUID=}"
            ;;
        /dev/*)
            ;;
        *)
            die "You have to specify boot=<boot device> as a boot option for fips=1" ;;
        esac

        if ! [ -e "$boot" ]; then
            udevadm trigger --action=add >/dev/null 2>&1
            [ -z "$UDEVVERSION" ] && UDEVVERSION=$(udevadm --version)
            
            if [ $UDEVVERSION -ge 143 ]; then
                udevadm settle --exit-if-exists=$boot
            else
                udevadm settle --timeout=30
            fi
        fi

        [ -e "$boot" ]
        
        mkdir /boot
        info "Mounting $boot as /boot"
        mount -oro "$boot" /boot
        unset newroot
    fi

    info "Checking integrity of kernel"

    if ! [ -e "$newroot/boot/.vmlinuz-${KERNEL}.hmac" ]; then
        warn "$newroot/boot/.vmlinuz-${KERNEL}.hmac does not exist"
        return 1
    fi

    sha512hmac -c "$newroot/boot/.vmlinuz-${KERNEL}.hmac" || return 1

    if [ -z "$newroot" ]; then
        info "Umounting /boot"
        umount /boot
    fi
}

do_fips()
{
    do_fipskernel || return 1

    FIPSMODULES=$(cat /etc/fipsmodules)
    
    info "Loading and integrity checking all crypto modules"
    for module in $FIPSMODULES; do
        if [ "$module" != "tcrypt" ]; then
            modprobe ${module} || return 1
        fi
    done
    info "Self testing crypto algorithms"
    modprobe tcrypt || return 1
    rmmod tcrypt
    info "All initrd crypto checks done"  

    return 0
}

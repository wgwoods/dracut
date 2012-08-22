#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

# Don't continue if we don't need network
if [ -z "$netroot" ] && [ ! -e "/tmp/net.ifaces" ] && ! getargbool 0 rd.neednet >/dev/null; then
    return
fi

command -v fix_bootif >/dev/null || . /lib/net-lib.sh

# Write udev rules
{
    # bridge: attempt only the defined interface
    if [ -e /tmp/bridge.info ]; then
        . /tmp/bridge.info
        IFACES+=" ${ethnames%% *}"
    fi

    # bond: attempt only the defined interface (override bridge defines)
    if [ -e /tmp/bond.info ]; then
        . /tmp/bond.info
        # It is enough to fire up only one
        IFACES+=" ${bondslaves%% *}"
    fi

    if [ -e /tmp/vlan.info ]; then
        . /tmp/vlan.info
        IFACES+=" $phydevice"
    fi

    ifup='/sbin/ifup $env{INTERFACE}'
    [ -z "$netroot" ] && ifup="$ifup -m"
    runcmd="RUN+=\"/sbin/initqueue --onetime $ifup\""

    # We have some specific interfaces to handle
    if [ -n "$IFACES" ]; then
        echo 'SUBSYSTEM!="net", GOTO="net_end"'
        echo 'ACTION=="remove", GOTO="net_end"'
        for iface in $IFACES; do
            case "$iface" in
                ??:??:??:??:??:??)  # MAC address
                    cond="ATTR{address}==\"$iface\"" ;;
                ??-??-??-??-??-??)  # MAC address in BOOTIF form
                    cond="ATTR{address}==\"$(fix_bootif $iface)\"" ;;
                *)                  # an interface name
                    cond="ENV{INTERFACE}==\"$iface\"" ;;
            esac
            # The GOTO prevents us from trying to ifup the same device twice
            echo "$cond, $runcmd, GOTO=\"net_end\""
        done
        echo 'LABEL="net_end"'

    # Default: We don't know the interface to use, handle all
    else
        cond='ACTION=="add|change", SUBSYSTEM=="net"'
        echo "$cond, $runcmd" > /etc/udev/rules.d/91-default-net.rules
    fi

} > /etc/udev/rules.d/90-net.rules

#!/bin/sh

get_ip() {
    local iface="$1" ip=""
    ip=$(ip -o -f inet addr show $iface)
    ip=${ip%%/*}
    ip=${ip##* }
}

iface_for_remote_addr() {
    set -- $(ip -o route get to $1)
    echo $5
}

iface_for_mac() {
    local interface="" mac="$(echo $1 | sed 'y/ABCDEF/abcdef/')"
    for interface in /sys/class/net/*; do
        if [ $(cat $interface/address) = "$mac" ]; then
            echo ${interface##*/}
        fi
    done
}

iface_has_link() {
    local interface="$1" flags=""
    [ -n "$interface" ] || return 2
    interface="/sys/class/net/$interface"
    [ -d "$interface" ] || return 2
    flags=$(cat $interface/flags)
    echo $(($flags|0x41)) > $interface/flags # 0x41: IFF_UP|IFF_RUNNING
    [ "$(cat $interface/carrier)" = 1 ] || return 1
    # XXX Do we need to reset the flags here? anaconda never bothered..
}

all_ifaces_up() {
    local iface="" IFACES=""
    [ -e "/tmp/net.ifaces" ] && read IFACES < /tmp/net.ifaces
    for iface in $IFACES; do
        [ -e /tmp/net.$iface.up ] || return 1
    done
}

get_netroot_ip() {
    local prefix="" server="" rest=""
    splitsep "$1" ":" prefix server rest
    case $server in
        [0-9]*\.[0-9]*\.[0-9]*\.[0-9]*) echo "$server"; return 0 ;;
    esac
    return 1
}

ip_is_local() {
    strstr "$(ip route get $1 2>/dev/null)" " via "
}

ifdown() {
    local netif="$1"
    # ip down/flush ensures that routing info goes away as well
    ip link set $netif down
    ip addr flush dev $netif
    echo "#empty" > /etc/resolv.conf
    rm -f /tmp/net.$netif.did-setup
    # TODO: send "offline" uevent?
}

setup_net() {
    local netif="$1" f="" gw_ip="" netroot_ip="" iface="" IFACES=""
    [ -e /tmp/net.$netif.did-setup ] && return
    [ -e "/tmp/net.ifaces" ] && read IFACES < /tmp/net.ifaces
    [ -z "$IFACES" ] && IFACES="$netif"
    # run the scripts written by ifup
    [ -e /tmp/net.$netif.gw ]            && . /tmp/net.$netif.gw
    [ -e /tmp/net.$netif.hostname ]      && . /tmp/net.$netif.hostname
    [ -e /tmp/net.$netif.override ]      && . /tmp/net.$netif.override
    [ -e /tmp/dhclient.$netif.dhcpopts ] && . /tmp/dhclient.$netif.dhcpopts
    # set up resolv.conf
    [ -e /tmp/net.$netif.resolv.conf ] && \
        cp -f /tmp/net.$netif.resolv.conf /etc/resolv.conf

    # Handle STP Timeout: arping the default gateway.
    # (or the root server, if a) it's local or b) there's no gateway.)
    # Note: This assumes that if no router is present the
    # root server is on the same subnet.

    # Get DHCP-provided router IP, or the cmdline-provided "gw=" argument
    [ -n "$new_routers" ] && gw_ip=${new_routers%%,*}
    [ -n "$gw" ] && gw_ip=$gw

    # Get the "netroot" IP (if there's an IP address in there)
    netroot_ip=$(get_netroot_ip $netroot)

    # try netroot if it's local (or there's no gateway)
    if ip_is_local $netroot_ip || [ -z "$gw_ip" ]; then
        dest="$netroot_ip"
    else
        dest="$gw_ip"
    fi

    unset layer2
    if [ -f /sys/class/net/$netif/device/layer2 ]; then
        read layer2 < /sys/class/net/$netif/device/layer2
    fi

    if [ "$layer2" != "0" ] && [ -n "$dest" ] && ! arping -q -f -w 60 -I $netif $dest ; then
        info "Resolving $dest via ARP on $netif failed"
    fi
    unset layer2

    > /tmp/net.$netif.did-setup
}

save_netinfo() {
    local netif="$1" IFACES="" f="" i=""
    [ -e /tmp/net.ifaces ] && read IFACES < /tmp/net.ifaces
    # Add $netif to the front of IFACES (if it's not there already).
    set -- "$netif"
    for i in $IFACES; do [ "$i" != "$netif" ] && set -- "$@" "$i"; done
    IFACES="$*"
    for i in $IFACES; do
        for f in /tmp/dhclient.$i.*; do
            [ -f $f ] && cp -f $f /tmp/net.${f#/tmp/dhclient.}
        done
    done
    echo $IFACES > /tmp/.net.ifaces.new
    mv /tmp/.net.ifaces.new /tmp/net.ifaces
}

set_ifname() {
    local name="$1" mac="$2" num=0 n=""
    # if it's already set, return the existing name
    for n in $(getargs ifname=); do
        strstr "$n" "$mac" && echo ${n%%:*} && return
    done
    # otherwise, pick a new name and use that
    while [ -e /sys/class/$name$num ]; do num=$(($num+1)); done
    echo "ifname=$name$num:$mac" >> /etc/cmdline.d/45-ifname.conf
    echo "$name$num"
}

ibft_to_cmdline() {
    local iface="" mac="" dev=""
    local dhcp="" ip="" gw="" mask="" hostname=""
    modprobe -q iscsi_ibft
    (
        for iface in /sys/firmware/ibft/ethernet*; do
            [ -e ${iface}/mac ] || continue
            mac=$(read a < ${iface}/mac; echo $a)
            [ -z "$mac" ] && continue
            dev=$(set_ifname ibft $mac)
            dhcp=$(read a < ${iface}/dhcp; echo $a)
            if [ -n "$dhcp" ]; then
                echo "ip=$dev:dhcp"
            else
                ip=$(read a < ${iface}/ip-addr; echo $a)
                gw=$(read a < ${iface}/gateway; echo $a)
                mask=$(read a < ${iface}/subnet-mask; echo $a)
                hostname=$(read a < ${iface}/hostname; echo $a)
                echo "ip=$ip::$gw:$mask:$hostname:$dev:none"
            fi
        done
    ) >> /etc/cmdline.d/40-ibft.conf
    # reread cmdline
    unset CMDLINE
}

parse_iscsi_root()
{
    local v
    v=${1#iscsi:}

# extract authentication info
    case "$v" in
	*@*:*:*:*:*)
	    authinfo=${v%%@*}
	    v=${v#*@}
    # allow empty authinfo to allow having an @ in iscsi_target_name like this:
    # netroot=iscsi:@192.168.1.100::3260::iqn.2009-01.com.example:testdi@sk
	    if [ -n "$authinfo" ]; then
		OLDIFS="$IFS"
		IFS=:
		set $authinfo
		IFS="$OLDIFS"
		if [ $# -gt 4 ]; then
		    warn "Wrong authentication info in iscsi: parameter!"
		    return 1
		fi
		iscsi_username=$1
		iscsi_password=$2
		if [ $# -gt 2 ]; then
		    iscsi_in_username=$3
		    iscsi_in_password=$4
		fi
	    fi
	    ;;
    esac

# extract target ip
    case "$v" in
	[[]*[]]:*)
	    iscsi_target_ip=${v#[[]}
		iscsi_target_ip=${iscsi_target_ip%%[]]*}
	    v=${v#[[]$iscsi_target_ip[]]:}
	    ;;
	*)
	    iscsi_target_ip=${v%%[:]*}
	    v=${v#$iscsi_target_ip:}
	    ;;
    esac

# extract target name
    case "$v" in
	*:iqn.*)
	    iscsi_target_name=iqn.${v##*:iqn.}
	    v=${v%:iqn.*}:
	    ;;
	*:eui.*)
	    iscsi_target_name=iqn.${v##*:eui.}
	    v=${v%:iqn.*}:
	    ;;
	*:naa.*)
	    iscsi_target_name=iqn.${v##*:naa.}
	    v=${v%:iqn.*}:
	    ;;
	*)
	    warn "Invalid iscii target name, should begin with 'iqn.' or 'eui.' or 'naa.'"
	    return 1
	    ;;
    esac

# parse the rest
    OLDIFS="$IFS"
    IFS=:
    set $v
    IFS="$OLDIFS"

    iscsi_protocol=$1; shift # ignored
    iscsi_target_port=$1; shift
    if [ $# -eq 3 ]; then
	iscsi_iface_name=$1; shift
    fi
    if [ $# -eq 2 ]; then
	iscsi_netdev_name=$1; shift
    fi
    iscsi_lun=$1; shift
    if [ $# -ne 0 ]; then
	warn "Invalid parameter in iscsi: parameter!"
	return 1
    fi
}

ip_to_var() {
    local v=${1}:
    local i
    set --
    while [ -n "$v" ]; do
        if [ "${v#\[*:*:*\]:}" != "$v" ]; then
            # handle IPv6 address
            i="${v%%\]:*}"
            i="${i##\[}"
            set -- "$@" "$i"
            v=${v#\[$i\]:}
        else
            set -- "$@" "${v%%:*}"
            v=${v#*:}
        fi
    done

    unset ip srv gw mask hostname dev autoconf macaddr mtu
    case $# in
        0)  autoconf="error" ;;
        1)  autoconf=$1 ;;
        2)  dev=$1; autoconf=$2 ;;
        3)  dev=$1; autoconf=$2; mtu=$3 ;;
        4)  dev=$1; autoconf=$2; mtu=$3; macaddr=$4 ;;
        *)  ip=$1; srv=$2; gw=$3; mask=$4; hostname=$5; dev=$6; autoconf=$7; mtu=$8; macaddr=$9 ;;
    esac
    # anaconda-style argument cluster
    if strstr "$autoconf" "*.*.*.*"; then
        ip="$autoconf"
        gw=$(getarg gateway=)
        mask=$(getarg netmask=)
        hostname=$(getarg hostname=)
        dev=$(getarg ksdevice=)
        autoconf="none"
        mtu=$(getarg mtu=)
        case "$dev" in
            # ignore fancy values for ksdevice=XXX
            link|bootif|BOOTIF|ibft|*:*:*:*:*:*) dev="" ;;
        esac
    fi
}

parse_ifname_opts() {
    local IFS=:
    set $1

    case $# in
        7)
            ifname_if=$1
            # udev requires MAC addresses to be lower case
            ifname_mac=$(echo $2:$3:$4:$5:$6:$7 | sed 'y/ABCDEF/abcdef/')
            ;;
        *)
            die "Invalid arguments for ifname="
            ;;
    esac

    case $ifname_if in
        eth[0-9]|eth[0-9][0-9]|eth[0-9][0-9][0-9]|eth[0-9][0-9][0-9][0-9])
            warn "ifname=$ifname_if uses the kernel name space for interfaces"
            warn "This can fail for multiple network interfaces and is discouraged!"
            warn "Please use a custom name like \"netboot\" or \"bluesocket\""
            warn "or use biosdevname and no ifname= at all."
            ;;
    esac

}

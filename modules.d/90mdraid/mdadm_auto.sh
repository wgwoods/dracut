#!/bin/sh
. /lib/dracut-lib.sh

info "Autoassembling MD Raid"    
/sbin/mdadm -As --auto=yes 2>&1 | vinfo

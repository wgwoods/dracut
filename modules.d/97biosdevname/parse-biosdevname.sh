# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh
USE_BIOSDEVNAME=$(getarg biosdevname)
if [ "$USE_BIOSDEVNAME" != "1" ]; then
    udevproperty UDEV_BIOSDEVNAME=
    rm -f /etc/udev/rules.d/71-biosdevname.rules
else
    info "biosdevname=1: activating biosdevname network renaming"
    udevproperty UDEV_BIOSDEVNAME=1
fi


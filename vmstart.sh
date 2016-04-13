#!/bin/bash
  vmname=`basename $0`

  if egrep "^$vmname\$" ~/vmware/stale; then
    echo "$vmname is a stale vm. are you sure you want to use it? (y/n)"
    read response
    [ "$response" != "y" ] && exit
  fi

  export VMWARE_USE_SHIPPED_GTK=yes
  vmplayer ~/vmware/$vmname/$vmname.vmx &

  #rename the window. (why does this have to be so fucking elaborate?)
  sleep 1
  until wmctrl -r "$vmname - vmware player" -T $vmname; do
    sleep 0.2
  done
  sleep 1
  wmctrl -r "$vmname - vmware player" -T $vmname
  sleep 1
  wmctrl -r "$vmname - vmware player" -T $vmname
  sleep 1
  wmctrl -r "$vmname - vmware player" -T $vmname

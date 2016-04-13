#!/bin/bash

if [ `basename $0` == 'rename-vm.sh' ]; then
  cp_or_mv=mv
  copied_or_moved=moved
else
  cp_or_mv="cp -a"
  copied_or_moved=copied
fi

from=$1
to=$2

cd ~/vmware

if [ -e $from/*.lck ] || [ -e $from/vmmcores* ] ; then
  echo "cannot copy or rename vm while it is running or suspended" 1>&2
  exit 1
fi

if [ -d $to ]; then
  echo "cannot $cp_or_mv to $to: it already exists"
  exit 1
fi

[ "copied" == "$copied_or_moved" ] && echo "please wait (copying large files takes time)"
$cp_or_mv $from $to

cd $to
rename "s/^$from/$to/" $from*

perl -wpe "s/$from/$to/g" -i $to.v*

echo "done"
echo "once you start the new vm, vmware will ask you if you copied it or moved it. tell it you $copied_or_moved it."
echo "remember to change the hostname and possibly addresses when you first run it."

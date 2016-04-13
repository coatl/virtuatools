#!/bin/bash

vmwaredir="$HOME/vmware"

#assumptions:
#virtual hard drives are scsi
#vms are stored under $vmwaredir (defaults to ~/vmware/, changeable above)
#each vm has just one virtual drive, at scsi 0:0
#name of drive file(s) is same as name of vm, with .vmdk and -sNNN.vmdk extension
#source and target do not have the same name
#all these amount to assuming the usual vmware conventions/defaults

function panic() {
  code="$1"
  msg="$2"
  echo ERROR: "$msg" >/dev/stderr
  exit "$code"
}

if [ "$1" = --back ]; then
  back=true
  shift
fi

source="$1"
target="$2"

cd "$vmwaredir" || panic 1 "cd failed: $vmwaredir doesn't exist?"


if [ -n "$back" ] ; then
  [ -z "$target" ] || panic "give only one arg when specifying --back"  #$target (2nd argument) is ignored!

  to="`egrep '^scsi0:1\.fileName *= *' $source/$source.vmx |cut -d= -f2-999|cut -d'\"' -f2`"
  target="`basename $to .vmdk`"
fi

#check for source/target existence
[ -e "$source/$source.vmx" ] || panic 1 "source vm does not exist"
[ -e "$target/$target.vmx" ] || panic 1 "target vm does not exist"

#check for suspended VM
egrep '^checkpoint\.vmState *= *"?[^" ]' "$source/$source.vmx" && panic 1 "source vm is not shut down, merely suspended"
egrep '^checkpoint\.vmState *= *"?[^" ]' "$target/$target.vmx" && panic 1 "target vm is not shut down, merely suspended"

#check for running VM
[ -e "$source/$source.vmdk.lck" -o -e "$source/$source.vmx.lck" ] && panic 1 "source vm is running"
[ -e "$target/$target.vmdk.lck" -o -e "$target/$target.vmx.lck" ] && panic 1 "target vm is running"



function remove_dev_from_vmx() {
  vmx="$1"
  device="$2"

  egrep -v "^$device\.(present|fileName|redo) *= *"  < "$vmx"  > "$vmx.new"
  mv "$vmx"{.new,}
}



function hd_mv() {
  source="$1"
  sdevice="$2"
  target="$3"
  tdevice="$4"
  hd="$5"

  #check for $hd or $tdevice already present in $target
  [ -e "$target/$hd.vmdk" ] && panic 1 "target vm already has a $hd.vmdk"
  egrep "^$tdevice\.fileName *= *" "$target/$target.vmx" && panic 1 "target vm already has $tdevice allocated"

  remove_dev_from_vmx "$target/$target.vmx" "$tdevice"

  mv "$source/$hd.vmdk" "$source/$hd"-s[0-9][0-9][0-9].vmdk "$target/"

  echo "$tdevice.present = \"TRUE\"" >>"$target/$target.vmx"
  echo "$tdevice.fileName = \"$hd.vmdk\"" >>"$target/$target.vmx"
  echo "$tdevice.redo = \"\"" >>"$target/$target.vmx" #what's this do?

  remove_dev_from_vmx "$source/$source.vmx" "$sdevice"
}



if [ -z "$back" ]; then
  hd_mv "$source" scsi0:0 "$target" scsi0:1 "$source"

  echo computing sha256 of moved hard drive
  cd "$target"
  sha256sum "$source.vmdk" "$source"-s[0-9][0-9][0-9].vmdk >"../$source/$source.vmdk.sha256sum"

  echo the virtual hard drive of this vm has been temporarily moved to the vm "$target" >readme.about.vmdk
  echo to move it back, please run: mv-hd-mv.sh --back \""$target"\"

else
  hd_mv "$source" scsi0:1 "$target" scsi0:0 "$target"

  echo checking sha256 of moved hard drive
  cd "$target"
  sha256sum --check <"$target".vmdk.sha256sum

  rm readme.about.vmdk
fi


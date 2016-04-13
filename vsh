#!/bin/bash
#connect terminal session to serial port of a vmware vm.
#via unix socket which should be attached to serial port /dev/ttyS1 on the vm
#result: a shell to the vm that bypasses vmware user-interface.
#you must set up the serial port in vmware and arrange for command line on it within the vm.
#validate checks the vm setup. see config example at eof.

function panic(){
  msg="$1"
  echo "$msg" 1>&2
  exit 5
}

function validate(){
  TARGET="$1"

  cd ~/vmware/"$TARGET"

  [ -e ~/vmware/"$TARGET"/shell.socket ] || panic "shell.socket device/unixsocket not configured on $TARGET"
  #these lines should be present in the virtual machine's .vmx file
  #if this script is to work
  vmx="$TARGET".vmx
  egrep -q '^serial1\.present = "TRUE"$'           "$vmx" || panic "shell.socket not set up in vmx"
  egrep -q '^serial1\.fileType = "pipe"$'          "$vmx" || panic "shell.socket not set up in vmx"
  egrep -q '^serial1\.fileName = "shell\.socket"$' "$vmx" || panic "shell.socket not set up in vmx"
  expected_serial1_lines=3
  if egrep -q '^serial1\.tryNoRxLoss = "TRUE"$'    "$vmx" ; then
    (( expected_serial1_lines+=1 ))
  fi
  [ "$expected_serial1_lines" == `egrep -c '^serial1\.' "$vmx"` ] || panic "shell.socket not set up in vmx"
}

function new_window(){
  verb="$1"
  TARGET="$2"

  if [ -e ~/.kde/share/apps/konsole/VM.profile ]; then
    konsole --profile VM --title "$TARGET console" -e bash -c "GREET=' ' vsh '$verb' '$TARGET'"
  else #fallback to working in current window
    "$verb" "$TARGET"
  fi

}


function to_vmshell(){
  TARGET="$1"

  cd ~/vmware/"$TARGET"

  #get lock on shell.socket and connect to it
  exec 9>shell.socket.lock
  flock -w 4 -n 9 || panic "shell.socket on $TARGET is already in use"
  trap 'kill "$COPROC_PID"; rm shell.socket.lock' EXIT #lock release, close connection to vm com2:
  coproc socat -d -d UNIX-CONNECT:shell.socket PTY: 2>&1 #why redirect stderr?

  #scrape socat output for pty name
  pty=unknown
  while [ "unknown" == "$pty" ] ; do
    read -u "${COPROC[0]}" line
    if echo "$line"|fgrep "PTY is "; then
      pty=`echo "$line"|perl -wpe 's/^.* ([^ ]+)$/$1/'`
    fi
    echo "$line"
  done

  if [ -z "$GREET" ]; then
    GREET='esc char is Ctrl-y. to exit, type: Ctrl-y y y\r\n'
  fi
  ( sleep 0.1; echo -n -e "$pty - $GREET" 1>&2 ) &
  screen -U -S "$TARGET".`hostname` -t "$TARGET" "$pty"

  #or: minicom -p "$pty"

  exit
}

function vmshell_execute(){
  TARGET="$1"; cmd="$2"
  if [ 0 != `echo -n "$cmd" | wc -l` ] ; then
    cmd="function cmd(){$cmd}; cmd"
    #newlines in cmd should be ok now
  fi

  cd ~/vmware/"$TARGET"

  #get lock on shell.socket
  exec 9>shell.socket.lock
  flock -w 4 -n 9 || panic "shell.socket on $TARGET is already in use"
  trap 'rm shell.socket.lock' EXIT #lock release

  nonce=$( echo "vsh nonce: `hostname` $$ $TARGET `date` $cmd"|sha256sum|tr -d ' -' )

  echo " $cmd ; echo '$nonce'" | \
    socat UNIX-CONNECT:shell.socket STDIO,cool-write | \
    #tee /tmp/shell.output | \
    perl -wne "
      s/ \r(?!\n)//g;     #weird cr in middle of line (w space yet...)
      s/\r//g;            #remove carriage returns,
      /^$nonce$/ && exit; #stop reading after nonce (by itself)
      print if \$go;
      \$go=1 if /echo '$nonce'$/;  #skip until end of echoed cmd postfix
    "
  #echo '------------unreconstructed (except for \r) output:'
  #tr $'\r' 'R' </tmp/shell.output 1>&2
  #why does socat eat up a full 1/2s of time every time here?
  #nc instead of socat doesn't work here, dunno why

  exit
}

#todo:
#change tab/window title
#v err exit on vsh to already running session
#v -c cmdline flag to run a batch-mode command
#v locking during operation to prevent races
#specify right number of lines and columns with stty
#put all vsh tabs in one window
#comports other than com2
#check permissions of serial port inside vm once connected?
#auto-launch in vm-startup.sh

if [ "to_vmshell" == "$1" ] ; then
  validate "$2"
  to_vmshell "$2"
elif [ "minimal_execute" == "$1" ] ; then
  #validate "$2"
  minimal_execute
elif [ "-c" == "$2" ] ; then
  validate "$1"
  vmshell_execute "$1" "$3"
else
  validate "$1"
  new_window to_vmshell "$1"
fi


false <<E




#ttyS1 must be set up as a getty console within the vm as well.
#this in /etc/init/ttyS1 should do it in upstart systems.
#(copied and simplified from the tty0 entry.)
start on stopped rc RUNLEVEL=[2345]
stop on runlevel [!2345]

respawn
exec /sbin/getty -8 115200 ttyS1

E

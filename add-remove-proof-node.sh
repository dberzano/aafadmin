#!/bin/bash

#
# add-remove-proof-node.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Adds or removes a PROOF node from the dynamic PROOF configuration file, i.e.
# proof.conf. Hostname to add/remove is read from SSH standard variables, while
# number of cores is read from stdin.
#

# Maximum number of seconds to wait for a lock
export LockLimit=15

# Lock/Wait function to regulate access to a certain file
function LockWait() {

  local LockDir="$1.lock"
  local LockSuccess=1
  local LockCount=0

  while ! mkdir "$LockDir" 2> /dev/null ; do
    if [ $LockCount == $LockLimit ] ; then
      LockSuccess=0
      break
    fi
    sleep 1
    let LockCount++
  done

  # At this point we've given up waiting
  if [ $LockSuccess == 0 ] ; then
    echo "Given up waiting to acquire lock over $1" >&2
    return 1
  fi

  # Remove lock in case of exit/abort/etc. (only sigkill is uninterruptible)
  trap "Unlock $1" 0

  return 0
}

# Removes lock for a certain file
function Unlock() {
  rmdir "$1.lock" 2> /dev/null
  trap '' 0  # unset EXIT traps
}

# Main function
function Main() {

  local NCores Action ProofConf

  # Immediately read the number of cores and action on stdin
  read NCores
  read Action

  # Is it a valid number?
  let NCores+=0
  if [ $NCores == 0 ] ; then
    echo "Invalid number of cores: $NCores" >&2
    exit 1
  fi

  # Valid action?
  if [ "$Action" != 'add' ] && [ "$Action" != 'remove' ] ; then
    echo "Invalid action: $Action" >&2
    exit 1
  fi

  # Source environment variables
  source /etc/aafrc 2> /dev/null
  if [ $? != 0 ] ; then
    echo 'Can not find configuration file /etc/aafrc.' >&2
    exit 1
  fi

  # PROOF "dynamic" configuration file for nodes
  ProofConf="$AF_PREFIX/etc/proof/proof.conf"

  # Get hostname from SSH environment
  if [ "$SSH_CLIENT" == '' ] ; then
    echo 'No SSH_CLIENT in environment!'
    exit 1
  fi

  # Get caller's IP address from the SSH variable
  export Ip=$(echo $SSH_CLIENT | awk '{ print $1 }')

  # Get hostname from the IP address
  export Host=$(getent hosts $Ip 2> /dev/null | awk '{ print $2 }')

  # Check if we really have the host name
  if [ "$Host" == '' ] ; then
    echo 'No hostname can be retrieved!'
    exit 1
  fi

  # Lock and process
  LockWait "$ProofConf" || exit 1

  # Always removes host
  grep -v " $Host" "$ProofConf" > "$ProofConf.0" && \
    rm -f "$ProofConf" && \
    mv "$ProofConf.0" "$ProofConf" || exit 1

  # Add, if requested
  if [ "$Action" == 'add' ] ; then
    for i in `seq 1 $NCores` ; do
      echo "worker $Host" >> "$ProofConf"
    done
  fi

  # Lock is removed automatically

}

#
# Entry point
#

Main "$@"

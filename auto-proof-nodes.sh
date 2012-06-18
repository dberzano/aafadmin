#!/bin/bash

#
# auto-proof-nodes.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Adds or removes one or more PROOF nodes to or from the dynamic PROOF
# configuration file, i.e. proof.conf.
#
# It works by taking parameters from the command line, or remotely by guessing
# the caller host via SSH standard variables.
#

# Load AF configuration
source /etc/aafrc || exit 1

# Maximum number of seconds to wait for a lock
export LockLimit=15

# The proof.conf
export ProofConf="$AF_PREFIX/etc/proof/proof-dummy.conf"

# TCP Ports to check (usually, ssh, xrootd, proof)
export CheckPorts=( 22 1093 1094 )

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

# List hosts and workers
function ListWorkers() {
  echo 'List of host / num. of workers:'
  grep ^worker "$ProofConf" | sort | uniq -c | \
    perl -ne '/([0-9]+)\s+worker\s+([^\s]+)/ and print " * $2 / $1\n"'
}

# Add hosts and workers. Each argument has the format host.domain/nwrk
function AddHosts() {

  local HostNcores Host Ncores

  LockWait "$ProofConf" || return 1

  while [ "$#" -ge 1 ] ; do
    HostNcores="$1"

    Host=${HostNcores%/*}
    Ncores=${HostNcores##*/}

    # Was Ncores given, and is it a number?
    [ "$Ncores" == "$HostNcores" ] && Ncores=1
    let Ncores+=0 2> /dev/null
    [ $? != 0 ] || [ $Ncores == 0 ] && Ncores=1

    # Always removes host
    grep -v "worker $Host" "$ProofConf" > "$ProofConf.0" && \
      rm -f "$ProofConf" && \
      mv "$ProofConf.0" "$ProofConf" || return 1

    # Compute number of workers to assing starting from a config variable and
    # the given number of cores
    Nwrk=`echo "a=$Ncores*$AF_PROOF_WORKERS_PER_CORE+0.5;scale=0;a/=1;a" | bc`

    ### WE COMPUTE NWRK ###

    # Add Nwrk times
    for i in `seq 1 $Nwrk` ; do
      echo "worker $Host" >> "$ProofConf"
    done

    echo "Host $Host added with $Nwrk worker(s)"

   shift 1
  done

  Unlock "$ProofConf"

}

# Remove hosts: takes hosts as arguments
function RemoveHosts() {

  local GrepStr

  LockWait "$ProofConf" || return 1

  while [ "$#" -ge 1 ] ; do
    [ "$GrepStr" == '' ] && \
      GrepStr="worker $1\$" || \
      GrepStr="$GrepStr|worker $1\$"
    shift 1
  done

  cat "$ProofConf" | \
    egrep -v "$GrepStr" > "$ProofConf".0 && \
    rm -f "$ProofConf" && \
    mv "$ProofConf".0 "$ProofConf"

  Unlock "$ProofConf"

}

# List hosts and workers
function CleanupWorkers() {
  local P Host Ok ToRemove Tmp

  Tmp=`mktemp /tmp/auto-proof-XXXXX`

  echo 'Cleaning up inactive workers:'

  grep ^worker "$ProofConf" | sort | uniq -c | \
    perl -ne '/[0-9]+\s+worker\s+([^\s]+)/ and print "$1\n"' > $Tmp

  while read Host ; do
    Ok=0
    for P in ${CheckPorts[@]} ; do
      nc -z $Host $P &> /dev/null
      if [ $? == 0 ] ; then
        Ok=1
        break
      fi
    done

    if [ $Ok == 0 ] ; then
      echo " * $Host: unreachable!"
      ToRemove="$ToRemove $Host"
    else
      echo " * $Host: active"
    fi

  done < $Tmp
  rm -f $Tmp

  eval "RemoveHosts $ToRemove" || return $?

}

# Accepts commands from a remote host
function RemoteMode() {

  local Ip Host Nwrk Command

  # Get hostname from SSH environment
  if [ "$SSH_CLIENT" == '' ] ; then
    echo 'No SSH_CLIENT in environment!' >&2
    return 1
  fi

  # Get caller's IP address from the SSH variable
  Ip=$(echo $SSH_CLIENT | awk '{ print $1 }')

  # Get hostname from the IP address
  Host=$(getent hosts $Ip 2> /dev/null | awk '{ print $2 }')

  # Check if we really have the host name
  if [ "$Host" == '' ] ; then
    echo 'Hostname cannot be retrieved!' >&2
    return 1
  fi

  # Get the command
  read Command
  case $Command in
    add*)
      echo "i have to add"
      Nwrk=${Command##* }
      AddHosts "$Host/$Nwrk" || return $?
    ;;
    delete)
      RemoveHosts "$Host" || return $?
    ;;
  esac

}

# The main function
function Main() {

  local Prog Args Remote AddHostWorkers DeleteHost List

  Prog=$(basename "$0")

  Args=$(getopt -o 'radlc' \
    --long 'remote,add,delete,list,cleanup' -n"$Prog" -- "$@")
  [ $? != 0 ] && exit 1

  eval set -- "$Args"

  while [ "$1" != "--" ] ; do

    case "$1" in

      --remote|-r)
        Mode='remote'
        shift 1
      ;;

      --add|-a)
        Mode='add'
        shift 1
      ;;

      --delete|-d)
        Mode='delete'
        shift 1
      ;;

      --list|-l)
        Mode='list'
        shift 1
      ;;

      --cleanup|-c)
        Mode='cleanup'
        shift 1
      ;;

      *)
        # Should never happen
        echo "Ignoring unknown option: $1" >&2
        shift 1
      ;;

    esac

  done

  shift # --

  case "$Mode" in

    remote)
      RemoteMode
    ;;

    add)
      AddHosts "$@"
    ;;

    delete)
      RemoveHosts "$@"
    ;;

    list)
      ListWorkers
    ;;

    cleanup)
      CleanupWorkers
    ;;

  esac || echo 'A fatal error occured, aborting.' >&2

}

#
# Entry point
#

Main "$@"

#!/bin/bash

#
# push-puppet.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Pushes current PROOF configuration to Puppet, which will deploy it to other
# hosts.
#

# Files to copy (wrt/ AF_PREFIX)
Files=(
  '/etc/proof/XrdSecgsiGMAPFunLDAP.cf'
#  '/etc/proof/proof.conf'
  '/etc/proof/grid-mapfile'
  '/etc/proof/groups.alice.cf'
  '/etc/proof/prf-main.cf'
  '/etc/init.d/proof'
)

# Main function
function Main() {

  local TmpDir

  # Source environment variables
  source /etc/aafrc 2> /dev/null
  if [ $? != 0 ]; then
    echo 'Can not find configuration file /etc/aafrc.' >&2
    exit 1
  fi

  # Temporary directory for configuration
  TmpDir=`mktemp -d /tmp/push-puppet-XXXX`

  # Stage needed files into temporary directory
  echo 'Staging needed files into a temporary directory:' >&2
  for F in "${Files[@]}" ; do
    mkdir -p `dirname "$TmpDir/$F"`
    cp -pv "$AF_PREFIX/$F" "$TmpDir/$F"
  done

  # Add global configuration file there
  cp -pv /etc/aafrc "$TmpDir/etc/"

  # Send files to remote host via rsync
  echo 'Sending files via rsync:' >&2
  rsync -vrlt --delete "$TmpDir/" "$AF_DEPLOY_DEST"

  # Clean up
  rm -rf "$TmpDir"

}

#
# Entry point
#

Main "$@"

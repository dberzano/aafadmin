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
  '/etc/proof/proof.conf'
  '/etc/proof/grid-mapfile'
  '/etc/proof/groups.alice.cf'
  '/etc/proof/prf-main.cf'
  '/etc/init.d/proof'
)

# Main function
function Main() {

  local List

  # Source environment variables
  source /etc/aafrc 2> /dev/null
  if [ $? != 0 ]; then
    echo 'Can not find configuration file /etc/aafrc.' >&2
    exit 1
  fi

  # Prepares a file list
  List=`mktemp /tmp/push-puppet-XXXX`

  for F in "${Files[@]}" ; do
    echo "$F" >> $List
  done

  # Rsync only those files to destination
  rsync -a --files-from=$List "$AF_PREFIX"/ "$AF_DEPLOY_DEST"

  # Clean up
  rm -f $List

}

#
# Entry point
#

Main "$@"

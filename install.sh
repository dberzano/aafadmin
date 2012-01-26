#!/bin/bash

#
# install.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Creates a skeleton on the destination directory and installs all the scripts
# to manage an analysis facility.
#

# Error codes
ErrMkdir=1
ErrMissingRc=2
ErrCp=3

# Directories to create
Skel=(
  'bin'
  'var/proof'
  'var/log'
  'etc/proof'
  'etc/init.d'
  'etc/grid-security'
)

# Files to copy in bin
FilesBin=(
  'create-deps.rb'
  'gen-proof-cfg.sh'
)

# Files to copy in etc/proof (don't overwrite)
FilesEtcProof=(
  'conf/prf-main.tmpl'
  'conf/proof.conf'
)

# Files to copy in etc/proof (don't overwrite)
FilesEtcInitd=(
  'init.d/proof'
)

# Function that copies overwriting
function Copy {
  local Dest="$2"
  local File
  local Keep
  [ "$1" == '-o' ] && Keep=0 || Keep=1
  shift 2

  echo "Copying files in $Dest (overwrite):"
  while [ $# -gt 0 ] ; do
    File="$AF_PREFIX/$Dest/`basename "$1"`"

    if [ "$Keep" == 1 ] && [ -e "$File" ]; then
      echo "keeping \`$File'"
    else
      cp -pv "$1" "$File"
      if [ $? != 0 ]; then
        echo 'Error copying: aborting'
        return $ErrCp
      fi
    fi

    shift
  done
}

# The main function
function Main {

  # Source environment variables
  source /etc/aafrc 2> /dev/null
  if [ $? != 0 ]; then
    echo 'Can not find configuration file /etc/aafrc.' >&2
    echo 'Please put it in place, configure it to your needs and try again.' >&2
    return $ErrMissingRc
  fi

  # Run from installer's directory
  cd `dirname "$0"`

  # Try to create the destination directory
  mkdir -p "$AF_PREFIX"
  if [ $? != 0 ]; then
    echo "Can not create directory $AF_PREFIX: as root, do:"
    echo "  mkdir -p '$AF_PREFIX'"
    echo "  chown $AF_USER '$AF_PREFIX'"
    return $ErrMkdir
  fi

  # Create skeleton
  echo -n 'Creating directory structure:'
  for S in "${Skel[@]}" ; do
    echo -n " $AF_PREFIX/$S"
    mkdir -p "$AF_PREFIX/$S"
    if [ $? != 0 ]; then
      echo 'Error creating directory: aborting.' >&2
      exit $ErrMkdir
    fi
  done
  echo ''

  # Install files (-o: overwrite, -k: keep)
  Copy -o 'bin' "${FilesBin[@]}" || exit $?
  Copy -k 'etc/proof' "${FilesEtcProof[@]}" || exit $?
  Copy -o 'etc/init.d' "${FilesEtcInitd[@]}" || exit $?

}

#
# Entry point
#

Main "$@"
exit $?

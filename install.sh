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
ErrRootVer=4
ErrRootSymlink=5

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
  'conf/XrdSecgsiGMAPFunLDAP.cf'
  'conf/grid-mapfile'
  'conf/groups.alice.cf'
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

  echo -n "Copying files in $Dest "
  [ "$Keep" == 1 ] && echo "(won't overwrite):" || echo "(overwrite):"

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

  # Parse command line options
  local Prog=$(basename "$BASH_SOURCE")
  local Args
  local Keep='-k'
  local RootPath=''

  Args=$(getopt -o 'or:' --long 'overwrite,root:' -n"$Prog" -- "$@")
  [ $? == 0 ] || return $ErrArgs

  eval set -- "$Args"

  while [ "$1" != "--" ] ; do

    case "$1" in

      --overwrite|-o)
        Keep='-o'
        shift
      ;;

      --root|-r)
        RootPath="$2"
        shift 2
      ;;

      *)
        # Should never happen
        echo "Skipping unknown option: $1"
        shift 1
      ;;

    esac

  done

  shift # --

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
  Copy -o    'bin' "${FilesBin[@]}" || exit $?
  Copy $Keep 'etc/proof' "${FilesEtcProof[@]}" || exit $?
  Copy -o    'etc/init.d' "${FilesEtcInitd[@]}" || exit $?

  # Link ROOT version
  local RootSymlink="$AF_PREFIX/var/proof/root_current"
  if [ ! -L "$RootSymlink" ]; then
    if [ ! -d "$RootPath" ]; then
      echo "You need to specify the full path to PROOF's ROOT version with --root"
      exit $ErrRootVer
    else
      echo "Symlinking ROOT version to $RootSymlink:"
      ln -nfsv "$RootPath" "$RootSymlink" || exit $ErrRootSymlink
    fi
  fi

}

#
# Entry point
#

Main "$@"
exit $?

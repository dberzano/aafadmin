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
#  'var/proof'
#  'var/log'
  'etc/proof'
  'etc/init.d'
)

# Files to copy in bin
FilesBin=(
  'create-deps.rb'
  'gen-proof-cfg.sh'
  'gen-afdsmgrd-cfg.sh'
  'push-puppet.sh'
  'add-remove-proof-node.sh'
)

# Files to copy in etc/proof (don't overwrite)
FilesEtcProof=(
  'conf/prf-main.tmpl'
  'conf/afdsmgrd.tmpl'
  'conf/afdsmgrd_env.tmpl'
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

      #--root|-r)
      #  RootPath="$2"
      #  shift 2
      #;;

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
    echo "  chown $AF_USER:$AF_GROUP '$AF_PREFIX'"
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

  # Generates configuration using the installed utility
  echo 'Invoking utility to generate PROOF configuration from template:'
  "$AF_PREFIX/bin/gen-proof-cfg.sh" || exit $?

  # Generates configuration using the installed utility
  echo 'Invoking utility to generate afdsmgrd configuration from template:'
  "$AF_PREFIX/bin/gen-afdsmgrd-cfg.sh" || exit $?


  # proof.conf file is generated with current hostname as master only
  if [ ! -e "$AF_PREFIX/etc/proof/proof.conf" ] || [ "$Keep" == '-o' ]; then
    echo 'Generating proof.conf with current master name'
    echo '# Do not mess with this file: it is automatically generated' \
      > "$AF_PREFIX/etc/proof/proof.conf"
    echo "master `hostname -f`" >> "$AF_PREFIX/etc/proof/proof.conf"
  fi

  # Linking afdsmgrd startup script
  echo 'Linking startup script of afdsmgrd'
  ln -nfsv "$AF_ROOT_PROOF/etc/proof/init.d/afdsmgrd" "$AF_PREFIX/etc/init.d/afdsmgrd"

}

#
# Entry point
#

Main "$@"
exit $?

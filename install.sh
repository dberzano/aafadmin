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
ErrHelp=42

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
  'create-deps-real.rb'
  'create-deps.sh'
  'gen-proof-cfg.sh'
  'gen-afdsmgrd-cfg.sh'
  'push-puppet.sh'
  'add-remove-proof-node.sh'
  'afdsutil.sh'
  'af-xrddm-verify.sh'
  'afdsutil.C'
  'proof-packages.sh'
  'xrddm-wrapper.sh'
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

# Files to copy in etc
FilesEtc=(
  'env-alice.sh'
  'af-alien-lib.sh'
)

# xrddm source and destination
export XrddmUrl='http://xrootd-dm.googlecode.com/svn/trunk'
export XrddmTmp='/tmp/xrddm-trunk'

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

# Prints help
function PrintHelp {

  local Prog
  Prog=`basename "$0"`

  echo "$Prog -- by Dario Berzano <dario.berzano@cern.ch>" >&2
  echo 'Installs AF related stuff. File /etc/aafrc must be preinstalled' >&2
  echo '' >&2
  echo "Usage: $Prog [options]" >&2
  echo '  -o, --overwrite                  overwrites template files' >&2
  echo '  -n, --no-config                  do not regenerate configs' >&2
  echo '      --force-xrddm                force reinstallation of xrddm' >&2

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

  Args=$(getopt -o 'onh' --long 'overwrite,no-config,force-xrddm,help' \
    -n"$Prog" -- "$@")
  [ $? == 0 ] || return $ErrArgs

  eval set -- "$Args"

  while [ "$1" != "--" ] ; do

    case "$1" in

      --overwrite|-o)
        Keep='-o'
        shift
      ;;

      --no-config|-n)
        NoConfig=1
        shift
      ;;

      --force-xrddm)
        ForceXrddm=1
        shift
      ;;

      --help)
        PrintHelp
        exit $ErrHelp
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
  Copy -o    'etc' "${FilesEtc[@]}" || exit $?

  # xrddm: download and compile if forced or if unpresent
  if [ ! -x "$AF_PREFIX"/bin/xrddm ] || [ "$ForceXrddm" == 1 ]; then
    echo 'Downloading and compiling xrddm...' >&2
    (
      export XRDDMSYS="$AF_PREFIX"
      export XROOTD_DIR="$AF_ALIEN_DIR/api"
      export ALIEN_DIR="$AF_ALIEN_DIR"

      source "$AF_PREFIX"/etc/env-alice.sh --root current --verbose && \
      rm -rvf "$XrddmTmp"/build && \
      mkdir -vp "$XrddmTmp"/build && \
      svn co "$XrddmUrl" "$XrddmTmp" && \
      cd "$XrddmTmp"/build && \
      cmake "$XrddmTmp" && \
        make && make install

      exit $?
    ) || exit $?
  else
    echo 'xrddm already present: skipping' >&2
  fi

  # With an option we can avoid regeneration of configuration files
  if [ "$NoConfig" != 1 ]; then

    # Generates configuration using the installed utility
    echo 'Invoking utility to generate PROOF configuration from template:'
    "$AF_PREFIX/bin/gen-proof-cfg.sh" || exit $?

    # Generates configuration using the installed utility
    echo 'Invoking utility to generate afdsmgrd configuration from template:'
    "$AF_PREFIX/bin/gen-afdsmgrd-cfg.sh" || exit $?

  else
    echo 'Skipping generation of configuration files from templates' >&2
  fi

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

  # Copying afdsmgrd macro to a writable directory
  Copy -o "var/proof" "$AF_ROOT_PROOF/etc/proof/utils/afdsmgrd/afdsutil.C"

}

#
# Entry point
#

Main "$@"
exit $?

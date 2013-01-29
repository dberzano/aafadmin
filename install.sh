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
  'libexec'
  'etc/proof'
  'etc/xrootd'
  'etc/init.d'
  'var/run'
  'var/proof'
  'lib/perl-apmon'
)

# Files to copy in bin
FilesBin=(
  'push-puppet.sh'
  'af-proof-nodes.sh'
  'af-dsutil.sh'
  'af-xrddm-verify.sh'
  'af-proof-packages.sh'
  'af-monalisa.pl'
  'af-packman-lite.sh'
  'af-sync'
)

# Files to copy in libexec (i.e. binaries not in path)
FilesLibexec=(
  'af-create-deps.rb'
  'afdsutil.C'
)

# Files to copy in etc/proof
FilesEtcProof=(
  'conf/prf-main.tmpl'
  'conf/afdsmgrd.tmpl'
  'conf/afdsmgrd_env.tmpl'
  'conf/XrdSecgsiGMAPFunLDAP.cf'
  'conf/groups.alice.cf'
)

# Files to copy in etc/init.d
FilesEtcInitd=(
  'init.d/proof'
  'init.d/xrootd'
)

# Files to copy in etc
FilesEtc=(
  'env-alice.sh'
  'af-alien-lib.sh'
  'conf/monalisa-conf.tmpl'
  'AliRoot_PAR_SETUP.C'
)

# Files to copy in etc/xrootd
FilesEtcXrootd=(
  'conf/xrootd.cf'
  'conf/xrootd-startup.cf'
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

  pecho -n "Copying files in $Dest "
  [ "$Keep" == 1 ] && pecho "(won't overwrite):" || pecho "(overwrite):"

  while [ $# -gt 0 ] ; do
    File="$AF_PREFIX/$Dest/`basename "$1"`"

    if [ "$Keep" == 1 ] && [ -e "$File" ]; then
      pecho "keeping \`$File'"
    else
      cp -pv "$1" "$File"
      if [ $? != 0 ]; then
        pecho 'Error copying: aborting'
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

  pecho "$Prog -- by Dario Berzano <dario.berzano@cern.ch>"
  pecho 'Installs AF related stuff. File /etc/aafrc must be preinstalled'
  pecho ''
  pecho "Usage: $Prog [options]"
  pecho '  -o, --overwrite                  overwrites template files'
  pecho '  -n, --no-config                  do not regenerate configs'
  pecho '      --force-xrddm                force reinstallation of xrddm'

}

# Bright echo on stderr
function pecho() {
  local NewLine=''
  if [ "$1" == -n ]; then
    NewLine='-n'
    shift
  fi
  echo -e $NewLine "\033[1m$1\033[m" >&2
}

# The main function
function Main {

  # Source environment variables
  source /etc/aafrc 2> /dev/null
  if [ $? != 0 ]; then
    pecho 'Can not find configuration file /etc/aafrc.'
    pecho 'Please put it in place, configure it to your needs and try again.'
    return $ErrMissingRc
  fi

  # Run from installer's directory
  cd `dirname "$0"`

  # Parse command line options
  local Prog=$(basename "$BASH_SOURCE")
  local Args
  local Keep='-k'
  local RootPath=''

  Args=$(getopt -o 'onh' \
    --long 'overwrite,no-config,force-xrddm,help' \
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

  # Custom afdsmgrd defined in aafrc
  if [ "$AF_CUSTOM_AFDSMGRD" != '' ]; then
    CustomAfdsmgrd=`readlink -m "$AF_CUSTOM_AFDSMGRD"`
  fi

  # Try to create the destination directory
  mkdir -p "$AF_PREFIX"
  if [ $? != 0 ]; then
    pecho "Can not create directory $AF_PREFIX: as root, do:"
    pecho "  mkdir -p '$AF_PREFIX'"
    pecho "  chown $AF_USER:$AF_GROUP '$AF_PREFIX'"
    return $ErrMkdir
  fi

  # Create skeleton
  pecho -n 'Creating directory structure:'
  for S in "${Skel[@]}" ; do
    pecho -n " $AF_PREFIX/$S"
    mkdir -p "$AF_PREFIX/$S"
    if [ $? != 0 ]; then
      pecho 'Error creating directory: aborting.'
      exit $ErrMkdir
    fi
  done
  echo ''

  # Create datasets cache
  pecho 'Creating cache directory for AliEn datasets:' 
  mkdir -pv "$AF_DATASETS_CACHE"
  chmod -v 0777 "$AF_DATASETS_CACHE"

  # Install files (-o: overwrite, -k: keep)
  Copy -o 'bin' "${FilesBin[@]}" || exit $?
  Copy -o 'libexec' "${FilesLibexec[@]}" || exit $?
  Copy -o 'etc/proof' "${FilesEtcProof[@]}" || exit $?
  Copy -o 'etc/xrootd' "${FilesEtcXrootd[@]}" || exit $?
  Copy -o 'etc/init.d' "${FilesEtcInitd[@]}" || exit $?
  Copy -o 'etc' "${FilesEtc[@]}" || exit $?

  # Generate dependencies
  "$AF_PREFIX"/libexec/af-create-deps.rb

  # Perl ApMon library
  pecho 'Installing Perl ApMon library...'
  cp -vpr 'perl-apmon/' "$AF_PREFIX/lib/" || exit $?

  # xrddm: download and compile if forced or if unpresent
  if [ ! -x "$AF_PREFIX"/bin/xrddm ] || [ "$ForceXrddm" == 1 ]; then
    pecho 'Downloading and compiling xrddm...'
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
    pecho 'xrddm already present: skipping'
  fi

  # With an option we can avoid regeneration of configuration files
  if [ "$NoConfig" != 1 ]; then

    # Generates PROOF configuration
    pecho 'Generating PROOF configuration...'
    (
      # Path prefix for ROOT packages
      export TPL_ROOT_PREFIX=$AF_PACK_DIR/VO_ALICE/ROOT

      # PROOF master, without domain
      export TPL_MASTER_SHORT=${AF_MASTER%%.*}

      export TPL_VAR="$AF_PREFIX/var/proof"
      export TPL_ETC="$AF_PREFIX/etc/proof"

      export TPL_GRID_SECURITY='/etc/grid-security'
      export TPL_PACKAGES="$TPL_VAR/proofbox/$AF_USER/packages"
      export TPL_PROOFPORT='1093'
      export TPL_XRDPORT='1094'

      export TPL_MONA_HOST="$AF_MONA_HOST"

      # ROOT versions available, separated by a pipe
      export TPL_ROOT_VER=$(
        cd "$TPL_ROOT_PREFIX" ;
        ls -1d */ | cut -d/ -f1 | \
        while read RootVer ; do
          echo -n "$RootVer|"
        done)

      cd "$AF_PREFIX"/etc/proof || exit 1
      cheetah fill --env --nobackup --oext cf prf-main.tmpl
      exit $?
    ) || exit $?

    # Generates afdsmgrd configuration
    (

      if [ "$CustomAfdsmgrd" != '' ]; then
        # Using custom afdsmgrd
        pecho 'Generating afdsmgrd (custom) configuration...'
        export TPL_DIR_BIN="$CustomAfdsmgrd"/bin
        export TPL_DIR_LIBEXEC="$CustomAfdsmgrd"/libexec
        export TPL_DIR_LIB="$CustomAfdsmgrd"/lib
        export Initd="$CustomAfdsmgrd"/etc/init.d/afdsmgrd
        export Afdsutil="$CustomAfdsmgrd"/share/afdsutil.C
      else
        # Using afdsmgrd provided with current version of ROOT
        pecho 'Generating afdsmgrd (from ROOT) configuration...'
        export TPL_DIR_BIN="$AF_ROOT_PROOF"/bin
        export TPL_DIR_LIBEXEC="$AF_ROOT_PROOF"/etc/proof
        export TPL_DIR_LIB="$AF_ROOT_PROOF"/etc/proof/lib
        export Initd="$AF_ROOT_PROOF"/etc/proof/init.d/afdsmgrd
        export Afdsutil="$AF_ROOT_PROOF"/etc/proof/utils/afdsmgrd/afdsutil.C
      fi

      cd "$AF_PREFIX"/etc/proof || exit 1

      cheetah fill --env --nobackup --oext conf afdsmgrd.tmpl    # config
      cheetah fill --env --nobackup --oext sh afdsmgrd_env.tmpl  # sysconfig

      # Linking afdsmgrd startup script
      pecho 'Linking startup script of afdsmgrd'
      ln -nfsv "$Initd" "$AF_PREFIX/etc/init.d/afdsmgrd"

      # Copying afdsmgrd macro to a writable directory
      Copy -o "var/proof" "$Afdsutil"

      exit $?
    ) || exit $?

    # Generates grid-security file to map local AF user to machine's subject
    pecho 'Generating grid-mapfile from current host certificate...'
    (
      export HostSubject=$( openssl x509 -in /etc/grid-security/hostcert.pem \
      -noout -subject | sed -e 's/subject= \+//' )
      [ "$HostSubject" == '' ] && exit 1
      echo "Certificate subject is: $HostSubject"
      echo \"$HostSubject\" $AF_USER > "$AF_PREFIX"/etc/proof/grid-mapfile
    ) || exit $?

  else
    pecho 'Skipping generation of configuration files from templates'
  fi

  # proof.conf file is generated with current hostname as master only
  if [ ! -e "$AF_PREFIX/etc/proof/proof.conf" ] || [ "$Keep" == '-o' ]; then
    pecho 'Generating proof.conf with current master name'
    echo '# Do not mess with this file: it is automatically generated' \
      > "$AF_PREFIX/etc/proof/proof.conf"
    echo "master `hostname -f`" >> "$AF_PREFIX/etc/proof/proof.conf"
  fi

  # Generates MonALISA configuration
  pecho 'Generating MonALISA configuration...'
  (
    cd "$AF_PREFIX/etc" || exit 1
    cheetah fill --env --nobackup --oext pl monalisa-conf.tmpl || exit 1

    echo "* * * * * $AF_USER \"$AF_PREFIX/bin/af-monalisa.pl\"" \
      "> /dev/null 2> /dev/null" > "$AF_PREFIX"/etc/af-monalisa.cron

  ) || exit $?

  # Remove template files
  pecho 'Removing Cheetah configuration templates and backups...'
  rm -vf "$AF_PREFIX"/etc/proof/*.{tmpl,bak} "$AF_PREFIX"/etc/*.{tmpl,bak}

}

#
# Entry point
#

Main "$@"
exit $?

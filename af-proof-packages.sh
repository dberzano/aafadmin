#!/bin/bash

#
# af-proof-packages.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Creates PROOF packages for the existing AliRoot versions. It is meant to be
# run on the master only (synchronization happens elsewhere, i.e. via Puppet).
#

source /etc/aafrc || exit 1

# Program name
Prog=`basename "$0"`

# Colored echo on stderr
function pecho() {
  local NewLine=''
  if [ "$1" == -n ]; then
    NewLine='-n'
    shift
  fi
  echo -e $NewLine "\033[1m$1\033[m" >&2
}

# Prints help
function PrintHelp {

  local Prog
  Prog=`basename "$0"`

  pecho "$Prog -- by Dario Berzano <dario.berzano@cern.ch>"
  pecho 'Creates PAR files that enable available AliRoot versions on PROOF.'
  pecho 'AliRoot dependency file must be up to date.'
  pecho ''
  pecho "Usage: $Prog [options]"
  pecho '      --clean PACKAGE              removes PACKAGE (or "old")'
  pecho '      --add PACKAGE                adds PACKAGE (or "new")'
  pecho '      --sync                       removes old and adds new packages'
  pecho '      --af-sync                    sends packages to all PROOF slaves'
  pecho '      --list,-l                    list all local PROOF packages'
  pecho '      --abort                      abort on error'
  pecho '      --update-list,-u             updates packages list from remote'
  pecho '      --dry-run                    dry run'
  pecho '      --help                       this help screen'

}

# Creates package for version $1 in the packages directory. No need to invoke
# PROOF or compile anything. Returns 0 on success, !0 on failure
function MakeAliPar() {

  local AliVer="$1"
  local DestDir="$2"
  local ParDir="$DestDir/$AliVer"
  local ParFile="$ParDir".par
  local PackDir="$AF_PREFIX/var/proof/proofbox/$AF_USER/packages"

  pecho "Creating parfile $ParFile..."

  # Creates package by copying template ROOT macro
  mkdir -p "$ParDir"/PROOF-INF
  cp -v "$AF_PREFIX"/libexec/AliRoot_PAR_SETUP.C "$ParDir"/PROOF-INF/SETUP.C

  # Compress package (must be gzipped)
  tar -C "$DestDir" --force-local \
    -czf "$DestDir/$AliVer.par" "$AliVer/" || return 1

  # Put packages in place
  mv -v "$ParDir" "$ParFile" "$PackDir" || return 1

  # Remove intermediate directory
  #rm -rf "$DestDir"

  return 0
}

# Cleans AliRoot PROOF packages
function CleanAliPack() {

  local AliPack="$1"
  local PackDir="$AF_PREFIX/var/proof/proofbox/$AF_USER/packages"

  if [ "$AliPack" == 'old' ] ; then

    pecho 'Cleaning obsoleted packages...'

    # Removes obsolete AliRoot packages (packages no longer in dependency file)
    ls -1d "$PackDir/"* | sed -e 's/\.par$//' | sort -u | \
    while read Pack ; do

      Pack=`basename "$Pack"`

      # Not present? Delete it
      grep -c "^$Pack|" "$AF_DEP_FILE" > /dev/null
      if [ $? != 0 ] ; then
        pecho "Removing obsoleted $Pack"
        $DryRunPrefix rm -rvf "$PackDir/$Pack" "$PackDir/$Pack.par"
      else
        pecho "Keeping $Pack"
      fi

    done

  elif [ "$AliPack" == 'all' ] ; then

    # Removes all packages
    pecho 'Cleaning all packages...'
    $DryRunPrefix rm -rvf "$PackDir/"*

  else

    # Removes a single package (not safe, beware)
    pecho "Removing package $AliPack..."
    $DryRunPrefix rm -rvf "$PackDir/$AliPack" "$PackDir/$AliPack.par"

  fi

}

# Adds PROOF packages for AliRoot
function AddAliPack() {

  local AliPack="$1"
  local PackDir="$AF_PREFIX/var/proof/proofbox/$AF_USER/packages"
  local TempDir

  local InstalledOk=`mktemp /tmp/af-par-ok-XXXXX`
  local InstalledErr=`mktemp /tmp/af-par-err-XXXXX`

  # Temporary working directory containing intermediate PAR files
  TempDir=`mktemp -d /tmp/af-par-XXXXX`

  if [ "$AliPack" == 'new' ] ; then

    pecho 'Installing new packages...'

    # Adds new packages not yet present
    cat "$AF_DEP_FILE" | awk -F \| '{ print $1 }' | \
    while read Pack ; do

      if [ -f "$PackDir/$Pack.par" ] && [ -d "$PackDir/$Pack" ] ; then
        pecho "Skipping installed $Pack"
      else

        # Installing a new package
        pecho "Installing package $Pack"

        rm -rvf "$PackDir/$Pack"*
        $DryRunPrefix MakeAliPar "$Pack" "$TempDir"

        if [ $? != 0 ] ; then
          pecho "Installation of package $Pack failed"
          rm -rvf "$PackDir/$Pack"*
          echo -n "$Pack " >> $InstalledErr
          if [ "$AbortOnError" == 1 ] ; then
            rm -f $InstalledErr $InstalledOk
            pecho "Temporary directory $TempDir left for inspection."
            pecho 'Aborting.'
            return 1
          fi
        else
          echo -n "$Pack " >> $InstalledOk
        fi

      fi

    done

    local ListOk ListErr
    ListOk=`cat $InstalledOk`
    ListErr=`cat $InstalledErr`
    rm -f $InstalledErr $InstalledOk

    [ "$ListOk" != '' ] && pecho "New packages installed correctly: $ListOk"
    [ "$ListErr" != '' ] && pecho "Installation failed for: $ListErr"

  else

    # Adds a single package
    pecho "Installing package $AliPack"
    rm -rvf "$PackDir/$AliPack"*
    $DryRunPrefix MakeAliPar "$AliPack" "$TempDir"

    if [ $? != 0 ] ; then
      pecho "Installation of package $AliPack failed"
      rm -rvf "$PackDir/$AliPack"*
      if [ "$AbortOnError" == 1 ] ; then
        pecho "Temporary directory $TempDir left for inspection."
        pecho 'Aborting.'
        return 1
      fi
    fi

  fi

  rm -rf "$TempDir"

}

# List all currently available PROOF packages
function ListAliPack() {
  local PackDir="$AF_PREFIX/var/proof/proofbox/$AF_USER/packages"
  pecho 'List of AliRoot PROOF packages:'
  ls -1 $PackDir 2> /dev/null | sed -e 's#.par$##' | sort -u | \
  while read Pack ; do
    pecho "  $Pack"
  done
}

#
# Entry point
#

Prog=$(basename "$0")

Args=$(getopt -o 'lu' \
  --long 'clean:,add:,abort,sync,list,update-list,dry-run,af-sync,help' \
  -n"$Prog" -- "$@")
[ $? != 0 ] && exit 1

eval set -- "$Args"

while [ "$1" != "--" ] ; do

  case "$1" in

    --clean)
      CleanPackage="$2"
      shift 2
    ;;

    --add)
      AddPackage="$2"
      shift 2
    ;;

    --sync)
      CleanPackage='old'
      AddPackage='new'
      shift 1
    ;;

    --list|-l)
      ListPackages=1
      shift 1
    ;;

    --update-list|-u)
      UpdateListDeps=1
      shift 1
    ;;

    --dry-run)
      DryRunPrefix="echo [Dry Run]"
      shift 1
    ;;

    --af-sync)
      AfSync=1
      shift 1
    ;;

    --help)
      PrintHelp
      exit 1
    ;;

    --abort)
      export AbortOnError=1
    ;;

    *)
      # Should never happen
      pecho "Ignoring unknown option: $1"
      shift 1
    ;;

  esac

done

shift # --

# Help screen if nothing to do
if [ "$AddPackage" == '' ] && [ "$CleanPackage" == '' ] &&
  [ "$ListPackages" != '1' ] ; then
  PrintHelp
  exit 1
fi

#
# Updates list of dependencies from remote
#

if [ "$UpdateListDeps" == 1 ] ; then
  "$AF_PREFIX"/libexec/af-create-deps.rb
  if [ $? != 0 ] ; then
    pecho 'Cannot create dependencies, aborting'
    exit 1
  fi
fi

#
# List packages. If doing so, do nothing else
#

if [ "$ListPackages" == 1 ] ; then
  ListAliPack
  exit $?
fi

#
# First action is to clean packages
#

if [ "$CleanPackage" != '' ] ; then
  CleanAliPack "$CleanPackage" || exit $?
fi

#
# Then we add the new ones
#

if [ "$AddPackage" != '' ] ; then
  AddAliPack "$AddPackage" || exit $?
fi

#
# Synchronize packages to all slaves
#

af-sync -p
exit $?

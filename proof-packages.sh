#!/bin/bash

#
# proof-packages.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Creates PROOF packages for the existing AliRoot versions. It is meant to be
# run on the master only (synchronization happens elsewhere, i.e. via Puppet).
#

source /etc/aafrc || exit 1

# Program name
Prog=`basename "$0"`

# AliRoot meta package (from AAF, by Martin Vala), in read-only
AliMeta=`ls -rtd1 "$AF_PACK_DIR/VO_ALICE/aaf-aliroot/"*/`
AliMeta="${AliMeta}/PROOF-INF/VO_ALICE@AliRoot"
AliMeta=`readlink -e "$AliMeta"`

# Check if it exists or not
if [ "$AliMeta" == '' ] ; then
  echo "$Prog: can't find AliRoot meta package" >&2
  exit 1
fi

# Creates package in a destination directory. Return value: 0=ok, !0=failure
function MakeAliPar() {

  local AliVer="$1"
  local DestDir="$2"
  local ParDir="$DestDir/$AliVer"

  echo "Creating parfile $DestDir/$AliVer.par..." >&2

  # Package directory
  mkdir -p "$ParDir"

  # rsync there
  rsync -a "$AliMeta/" "$ParDir" || return 1

  # Change file with sed
  sed \
    -e 's/cat %s\/deps\/aliroot_deps.txt/cat \\\"$AF_DEP_FILE\\\"/' \
    -i "$ParDir/PROOF-INF/SETUP.C" || return 1

  # Compress package (must be gzipped)
  tar -C "$DestDir" --force-local \
    -czf "$DestDir/$AliVer.par" "$AliVer/" || return 1

  # Remove directory
  rm -rf "$ParDir"

}

# Uploads package
function UpAliPar() {

  local ParFile="$1"
  local AliPackage=`basename "$ParFile"`
  AliPackage=${AliPackage%.*}

  # AliRoot version (plain), without VO_ALICE@AliRoot::
  local AliVer=`echo $AliPackage | awk -F :: '{ print $2 }'`
  [ "$AliVer" == '' ] && return 1

  # Directory containing macro to upload stuff
  local RootMacroDir
  RootMacroDir=`mktemp -d /tmp/af-root-macro-XXXXX`

  # PROOF sandbox
  local ProofSandbox RootSandbox
  ProofSandbox=`mktemp -d /tmp/af-proof-sandbox-XXXXX`
  RootSandbox=`mktemp -d /tmp/af-root-sandbox-XXXXX`

  (
    # Source AliRoot stuff, with correct dependencies
    source "$AF_PREFIX/etc/env-alice.sh" --aliroot $AliVer --verbose || return 1

    # Root version
    RootVer=`basename "$ROOTSYS"`

    # A ROOT macro to upload the package
    local RootMacro="$RootMacroDir/EnableUpload.C"
    cat > "$RootMacro" <<EOF
{
  gEnv->SetValue("Proof.Sandbox", "$ProofSandbox");
  gEnv->SetValue("XSec.GSI.DelegProxy", "2");

  TProof::Reset("$AF_USER@$AF_MASTER", 0);

  // Watch out: set ROOT version by *package name*!
  TProof::Mgr("$AF_USER@$AF_MASTER")->SetROOTVersion("VO_ALICE@ROOT::$RootVer");

  //if (!TProof::Open("$AF_USER@$AF_MASTER", "workers=1x")) gSystem->Exit(1);

  // Enable on master only: other workers are synced elsewhere
  if (!TProof::Open("$AF_USER@$AF_MASTER", "masteronly")) gSystem->Exit(1);

  if (gProof->UploadPackage("$ParFile")) {
    gProof->Close();  // be kind and avoid "maximum sessions reached" problem
    gSystem->Exit(2);
  }

  // ALIROOT mode is *mandatory* to avoid the libOADB problem (not present in
  // every AliRoot version, apparently)
  TList *listOpts = new TList();
  listOpts->Add( new TNamed("ALIROOT_MODE", "ALIROOT") );

  if (gProof->EnablePackage("$ParFile", listOpts)) {
    gProof->Close();
    gSystem->Exit(3);
  }

  gProof->Close();
}
EOF

    # Execute it
    TmpLog=`mktemp /tmp/af-root-log-XXXXX`
    cd "$RootSandbox"
    root -l -b -q "$RootMacro" > $TmpLog 2>&1
    ExitCode=$?
    cd -

    # Remove garbage locks
    find /tmp -name 'proof-package-lock-*af-proof-sandbox*' -exec rm -vf '{}' \;

    [ $ExitCode != 0 ] && cat $TmpLog
    rm -f $TmpLog

    # Propagate exitcode
    return $ExitCode

  )

  # Inherit exitcode
  ExitCode=$?

  # Cleanup
  rm -rf "$ProofSandbox" "$RootMacroDir" "$RootSandbox"

  return $ExitCode

}

# Cleans AliRoot PROOF packages
function CleanAliPack() {

  local AliPack="$1"
  local PackDir="$AF_PREFIX/var/proof/proofbox/$AF_USER/packages"

  if [ "$AliPack" == 'old' ] ; then

    echo 'Cleaning obsoleted packages...' >&2

    # Removes obsolete AliRoot packages (packages no longer in dependency file)
    ls -1d "$PackDir/"* | sed -e 's/\.par$//' | sort -u | \
    while read Pack ; do

      Pack=`basename "$Pack"`

      # Not present? Delete it
      grep -c "^$Pack|" "$AF_DEP_FILE" > /dev/null
      if [ $? != 0 ] ; then
        echo "Removing obsoleted $Pack"
        rm -rvf "$PackDir/$Pack" "$PackDir/$Pack.par"
      else
        echo "Keeping $Pack"
      fi

    done

  elif [ "$AliPack" == 'all' ] ; then

    # Removes all packages
    echo 'Cleaning all packages...' >&2
    rm -rvf "$PackDir/"*

  else

    # Removes a single package (not safe, beware)
    echo "Removing package $AliPack..." >&2
    rm -rvf "$PackDir/$AliPack" "$PackDir/$AliPack.par"

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

    echo 'Installing new packages...'

    # Adds new packages not yet present
    cat "$AF_DEP_FILE" | awk -F \| '{ print $1 }' | \
    while read Pack ; do

      if [ -f "$PackDir/$Pack.par" ] && [ -d "$PackDir/$Pack" ] ; then
        echo "Skipping installed $Pack" >&2
      else

        # Installing a new package
        echo "Installing package $Pack"

        rm -rvf "$PackDir/$Pack"*
        MakeAliPar "$Pack" "$TempDir" && UpAliPar "$TempDir/$Pack.par"

        if [ $? != 0 ] ; then
          echo "Installation of package $Pack failed" >&2
          rm -rvf "$PackDir/$Pack"*
          echo -n "$Pack " >> $InstalledErr
          if [ "$AbortOnError" == 1 ] ; then
            rm -f $InstalledErr $InstalledOk
            echo "Temporary directory $TempDir left for inspection." >&2
            echo 'Aborting.' >&2
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

    [ "$ListOk" != '' ] && echo "New packages installed correctly: $ListOk"
    [ "$ListErr" != '' ] && echo "Installation failed for: $ListErr"

  else

    # Adds a single package
    echo "Installing package $AliPack"
    rm -rvf "$PackDir/$AliPack"*
    MakeAliPar "$AliPack" "$TempDir" && UpAliPar "$TempDir/$AliPack.par"

    if [ $? != 0 ] ; then
      echo "Installation of package $AliPack failed" >&2
      rm -rvf "$PackDir/$AliPack"*
      if [ "$AbortOnError" == 1 ] ; then
        echo "Temporary directory $TempDir left for inspection." >&2
        echo 'Aborting.' >&2
        return 1
      fi
    fi

  fi

  rm -rf "$TempDir"

}

#
# Entry point
#

Prog=$(basename "$0")

Args=$(getopt -o '' --long 'clean:,add:,abort,sync' -n"$Prog" -- "$@")
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

    --abort)
      export AbortOnError=1
    ;;

    *)
      # Should never happen
      echo "Skipping unknown option: $1"
      shift 1
    ;;

  esac

done

shift # --

#
# First action is to clean packages
#

if [ "$CleanPackage" != '' ] ; then
  CleanAliPack "$CleanPackage" || exit $?
fi

#
# Then we add new ones
#

if [ "$AddPackage" != '' ] ; then
  AddAliPack "$AddPackage" || exit $?
fi